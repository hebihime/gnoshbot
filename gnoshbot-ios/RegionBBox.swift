import Foundation

public struct RegionBBox: Equatable, Sendable {
    public var minLon: Double
    public var minLat: Double
    public var maxLon: Double
    public var maxLat: Double

    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }

    /// Symmetric degree box whose arithmetic center is the saved point (I7 / backend geohash grain).
    public static func fiveMilesAround(latitude: Double, longitude: Double) -> RegionBBox {
        let meters = LunchRange.meters
        let latDelta = meters / 111_320.0
        let cosLat = cos(latitude * .pi / 180)
        let lonDelta = meters / (111_320.0 * max(cosLat, 0.000_001))
        return RegionBBox(
            minLon: longitude - lonDelta,
            minLat: latitude - latDelta,
            maxLon: longitude + lonDelta,
            maxLat: latitude + latDelta
        )
    }

    public var centerLatitude: Double { (minLat + maxLat) / 2 }
    public var centerLongitude: Double { (minLon + maxLon) / 2 }

    public var geohash5: String {
        GeoHash5.encode(latitude: centerLatitude, longitude: centerLongitude)
    }

    public var jsonBody: [String: Any] {
        [
            "min_lon": minLon,
            "min_lat": minLat,
            "max_lon": maxLon,
            "max_lat": maxLat,
        ]
    }
}

public enum EnsureReason: String, Sendable {
    case savedAddress = "saved_address"
    case onboarding
    case significantLocation = "significant_location"
}

public enum IdempotencyKey {
    /// Grain `{opaqueUser}:{geohash5}:{release}` (`SCALABILITY.md` S3).
    public static func make(opaqueUser: String, geohash5: String, release: String) -> String {
        "\(opaqueUser):\(geohash5):\(release)"
    }
}
