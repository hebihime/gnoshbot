import Foundation
import SwiftData

/// Bundled Brooklyn neighborhood for prototype. Not Overture. Not the MVP control plane.
public enum PrototypeCatalog {
    public static func data() -> Data {
        if let url = Bundle.module.url(forResource: "prototype-catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url)
        {
            return data
        }
        return Data()
    }

    public static func load() throws -> (geohash5: String, kitchens: [Kitchen]) {
        let data = data()
        guard !data.isEmpty,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CacheHydratorError.invalidJSON
        }
        let geohash5 = (root["geohash5"] as? String) ?? BrooklynDemoAddress.geohash5
        let raw = root["kitchens"] as? [[String: Any]] ?? []
        let kitchens = raw.compactMap(Kitchen.init(json:))
        return (geohash5, kitchens)
    }

    public struct Kitchen: Equatable, Sendable {
        public var overtureId: String
        public var name: String
        public var shopOriginHost: String
        public var shopLocationId: String
        public var latitude: Double
        public var longitude: Double
        public var cuisineTags: [String]
        public var items: [MenuItemDocument]

        public var shopPrefix: String {
            ShopPrefix.make(originHost: shopOriginHost, locationId: shopLocationId) ?? ""
        }

        public var asPrefix: PayablePrefix {
            PayablePrefix(
                overtureId: overtureId,
                name: name,
                shopOriginHost: shopOriginHost,
                shopLocationId: shopLocationId,
                x402Version: 1,
                latitude: latitude,
                longitude: longitude,
                integration: "proxy_wrapped"
            )
        }

        public var menuJSON: Data {
            let payload: [String: Any] = [
                "name": name,
                "cuisineTags": cuisineTags,
                "items": items.map { item -> [String: Any] in
                    var row: [String: Any] = [
                        "id": item.id,
                        "name": item.name,
                        "description": item.description,
                        "price": item.priceCents,
                        "mealTypes": item.mealTypes,
                    ]
                    if let spice = item.spice {
                        row["spice"] = spice
                    }
                    return row
                },
            ]
            return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        }

        init?(json: [String: Any]) {
            guard let overtureId = json["overture_id"] as? String,
                  let name = json["name"] as? String,
                  let host = json["shop_origin_host"] as? String,
                  let loc = json["shop_location_id"] as? String,
                  let latitude = json["latitude"] as? Double,
                  let longitude = json["longitude"] as? Double
            else { return nil }
            self.overtureId = overtureId
            self.name = name
            self.shopOriginHost = host
            self.shopLocationId = loc
            self.latitude = latitude
            self.longitude = longitude
            self.cuisineTags = (json["cuisineTags"] as? [String]) ?? []
            let cuisine = cuisineTags
            let rawItems = json["items"] as? [[String: Any]] ?? []
            self.items = rawItems.compactMap { raw in
                let itemName = raw["name"] as? String ?? ""
                guard !itemName.isEmpty else { return nil }
                return MenuItemDocument(
                    id: (raw["id"] as? String) ?? UUID().uuidString,
                    name: itemName,
                    description: (raw["description"] as? String) ?? "",
                    extraNames: [],
                    priceCents: (raw["price"] as? Int) ?? 0,
                    spice: raw["spice"] as? String,
                    mealTypes: (raw["mealTypes"] as? [String]) ?? [],
                    cuisineTags: cuisine
                )
            }
        }
    }

    @MainActor
    public static func hydrate(into store: GnoshbotStore) async throws {
        let loaded = try load()
        let hydrator = CacheHydrator(
            settings: ControlPlaneSettings(
                baseURL: URL(string: "https://prototype.invalid")!,
                isDemo: true
            ),
            http: OfflineHTTP()
        )
        let prefixes = loaded.kitchens.map(\.asPrefix)
        let menus = Dictionary(uniqueKeysWithValues: loaded.kitchens.map { ($0.shopPrefix, $0.menuJSON) })
        try await hydrator.hydratePayload(
            RegionPayload(geohash5: loaded.geohash5, payablePrefixes: prefixes),
            menusByPrefix: menus,
            into: store
        )
    }
}

struct OfflineHTTP: HTTPPerforming {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw CacheHydratorError.invalidJSON
    }
}
