import Foundation
import SwiftData

@Model
public final class RestaurantCache {
    @Attribute(.unique) public var overtureId: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// `unsupported` | `native` | `proxy_wrapped`
    public var integration: String
    public var nativeX402Url: String?
    public var shopOriginHost: String?
    public var shopLocationId: String?
    /// 1 (shop host) or 2 (native v2)
    public var x402Version: Int

    public init(
        overtureId: String,
        name: String,
        latitude: Double,
        longitude: Double,
        integration: String,
        nativeX402Url: String? = nil,
        shopOriginHost: String? = nil,
        shopLocationId: String? = nil,
        x402Version: Int
    ) {
        self.overtureId = overtureId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.integration = integration
        self.nativeX402Url = nativeX402Url
        self.shopOriginHost = shopOriginHost
        self.shopLocationId = shopLocationId
        self.x402Version = x402Version
    }
}
