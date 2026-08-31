import Foundation
import SwiftData

public struct PayablePrefix: Equatable, Sendable {
    public var overtureId: String
    public var name: String
    public var shopOriginHost: String?
    public var shopLocationId: String?
    public var x402Version: Int
    public var latitude: Double?
    public var longitude: Double?
    public var integration: String?

    public init(
        overtureId: String,
        name: String,
        shopOriginHost: String? = nil,
        shopLocationId: String? = nil,
        x402Version: Int = 1,
        latitude: Double? = nil,
        longitude: Double? = nil,
        integration: String? = nil
    ) {
        self.overtureId = overtureId
        self.name = name
        self.shopOriginHost = shopOriginHost
        self.shopLocationId = shopLocationId
        self.x402Version = x402Version
        self.latitude = latitude
        self.longitude = longitude
        self.integration = integration
    }

    public var shopPrefix: String? {
        ShopPrefix.make(originHost: shopOriginHost, locationId: shopLocationId)
    }

    public var resolvedIntegration: String {
        if let integration { return integration.lowercased() }
        if shopOriginHost != nil { return "proxy_wrapped" }
        return "native"
    }
}

public struct RegionPayload: Equatable, Sendable {
    public var geohash5: String
    public var payablePrefixes: [PayablePrefix]

    public init(geohash5: String, payablePrefixes: [PayablePrefix]) {
        self.geohash5 = geohash5
        self.payablePrefixes = payablePrefixes
    }
}

public enum CacheHydratorError: Error {
    case invalidJSON
}

public struct CacheHydrator: Sendable {
    public static let menuTTL: TimeInterval = 15 * 60

    public var settings: ControlPlaneSettings
    public var http: any HTTPPerforming
    public var now: @Sendable () -> Date
    public var demoMenuJSON: Data

    public init(
        settings: ControlPlaneSettings,
        http: any HTTPPerforming,
        now: @escaping @Sendable () -> Date = Date.init,
        demoMenuJSON: Data = MenuDocument.bundledDemoJSON()
    ) {
        self.settings = settings
        self.http = http
        self.now = now
        self.demoMenuJSON = demoMenuJSON
    }

    public func fetchRegion(geohash5: String) async throws -> RegionPayload {
        var request = URLRequest(url: settings.baseURL.appending(path: "regions/\(geohash5)"))
        request.httpMethod = "GET"
        let (data, _) = try await http.data(for: request)
        return try Self.parseRegion(geohash5: geohash5, data: data)
    }

    public static func parseRegion(geohash5: String, data: Data) throws -> RegionPayload {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CacheHydratorError.invalidJSON
        }
        let raw = root["payablePrefixes"] as? [[String: Any]] ?? []
        let prefixes = raw.map { row in
            PayablePrefix(
                overtureId: row["overture_id"] as? String ?? "",
                name: row["name"] as? String ?? "",
                shopOriginHost: row["shop_origin_host"] as? String,
                shopLocationId: row["shop_location_id"] as? String,
                x402Version: (row["x402_version"] as? Int) ?? 1,
                latitude: row["latitude"] as? Double,
                longitude: row["longitude"] as? Double,
                integration: row["integration"] as? String
            )
        }
        return RegionPayload(geohash5: geohash5, payablePrefixes: prefixes)
    }

    public func livePoolPrefixes(from payload: RegionPayload) -> [PayablePrefix] {
        payload.payablePrefixes.filter { prefix in
            guard let shop = prefix.shopPrefix else { return true }
            return !ShopPrefix.isSandbox(shop)
        }
    }

    @MainActor
    public func hydrate(geohash5: String, into store: GnoshbotStore) async throws {
        let payload = try await fetchRegion(geohash5: geohash5)
        let live = livePoolPrefixes(from: payload)
        let context = try store.modelContext
        let center = GeoHash5.decodeCenter(geohash5)
        for prefix in live where !prefix.overtureId.isEmpty {
            let lat: Double
            let lon: Double
            if let latitude = prefix.latitude, let longitude = prefix.longitude {
                lat = latitude
                lon = longitude
            } else if prefix.overtureId == "demo.place.brooklyn.wrap" {
                lat = BrooklynDemoAddress.latitude
                lon = BrooklynDemoAddress.longitude
            } else {
                lat = center.latitude
                lon = center.longitude
            }
            try upsertRestaurant(
                prefix,
                latitude: lat,
                longitude: lon,
                context: context
            )
            if let shopPrefix = prefix.shopPrefix {
                try await upsertMenu(shopPrefix: shopPrefix, origin: prefix.shopOriginHost, location: prefix.shopLocationId, context: context)
            }
        }
        try context.save()
    }

    @MainActor
    private func upsertRestaurant(
        _ prefix: PayablePrefix,
        latitude: Double,
        longitude: Double,
        context: ModelContext
    ) throws {
        let id = prefix.overtureId
        var descriptor = FetchDescriptor<RestaurantCache>(predicate: #Predicate { $0.overtureId == id })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.name = prefix.name
            existing.latitude = latitude
            existing.longitude = longitude
            existing.integration = prefix.resolvedIntegration
            existing.shopOriginHost = prefix.shopOriginHost
            existing.shopLocationId = prefix.shopLocationId
            existing.x402Version = prefix.x402Version
        } else {
            context.insert(
                RestaurantCache(
                    overtureId: prefix.overtureId,
                    name: prefix.name,
                    latitude: latitude,
                    longitude: longitude,
                    integration: prefix.resolvedIntegration,
                    shopOriginHost: prefix.shopOriginHost,
                    shopLocationId: prefix.shopLocationId,
                    x402Version: prefix.x402Version
                )
            )
        }
    }

    @MainActor
    private func upsertMenu(
        shopPrefix: String,
        origin: String?,
        location: String?,
        context: ModelContext
    ) async throws {
        var descriptor = FetchDescriptor<MenuCache>(predicate: #Predicate { $0.shopPrefix == shopPrefix })
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor).first
        if let existing, now().timeIntervalSince(existing.fetchedAt) < Self.menuTTL {
            return
        }
        let json: Data
        do {
            json = try await loadMenuJSON(shopPrefix: shopPrefix, origin: origin, location: location)
        } catch {
            return
        }
        let digest = MenuDocument.sha256Hex(json)
        if let existing, existing.sha256 == digest {
            return
        }
        if let existing {
            existing.json = json
            existing.sha256 = digest
            existing.fetchedAt = now()
        } else {
            context.insert(MenuCache(shopPrefix: shopPrefix, json: json, sha256: digest, fetchedAt: now()))
        }
    }

    private func loadMenuJSON(shopPrefix: String, origin: String?, location: String?) async throws -> Data {
        if ShopPrefix.isDemoFixture(shopPrefix) {
            return demoMenuJSON
        }
        if let origin, let location, let shopBase = settings.shopBaseURL {
            var request = URLRequest(
                url: shopBase.appending(path: "\(origin)/\(location)/menu")
            )
            request.httpMethod = "GET"
            let (data, _) = try await http.data(for: request)
            return data
        }
        throw CacheHydratorError.invalidJSON
    }
}
