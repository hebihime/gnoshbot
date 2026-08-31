import Foundation

/// Build-setting / Info.plist control-plane origin. Debug vs Release/TestFlight differ.
public struct ControlPlaneSettings: Equatable, Sendable {
    public var baseURL: URL
    public var overtureRelease: String
    /// Demo TestFlight: skip I16 funding gates. Not a funded CDP Smart Account.
    public var isDemo: Bool
    public var shopBaseURL: URL?
    /// Must equal shop `accepts[0].network`. Default sepolia so TestFlight cannot silently pay Base.
    public var x402Network: X402Network

    public init(
        baseURL: URL,
        overtureRelease: String = "2026-08-19.0",
        isDemo: Bool = false,
        shopBaseURL: URL? = nil,
        x402Network: X402Network = .baseSepolia
    ) {
        self.baseURL = baseURL
        self.overtureRelease = overtureRelease
        self.isDemo = isDemo
        self.shopBaseURL = shopBaseURL
        self.x402Network = x402Network
    }

    public static let pinnedOvertureRelease = "2026-08-19.0"

    public static func fromAppBundle(_ bundle: Bundle = .main) -> ControlPlaneSettings {
        let info = bundle.infoDictionary ?? [:]
        let rawBase = (info["GNOSHBOT_API_BASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = URL(string: rawBase ?? "") ?? URL(string: "http://127.0.0.1:8080")!
        let release = (info["GNOSHBOT_OVERTURE_RELEASE"] as? String).flatMap {
            $0.isEmpty ? nil : $0
        } ?? pinnedOvertureRelease
        let shopRaw = (info["GNOSHBOT_SHOP_BASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shop = (shopRaw?.isEmpty == false) ? URL(string: shopRaw!) : nil
        let plistDemo = (info["GNOSHBOT_DEMO"] as? Bool) ?? (info["GNOSHBOT_DEMO"] as? String == "YES")
        #if GNOSHBOT_DEMO
        let demo = true
        #else
        let demo = plistDemo
        #endif
        let networkRaw = (info["GNOSHBOT_X402_NETWORK"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let network = networkRaw.flatMap(X402Network.parse) ?? .baseSepolia
        return ControlPlaneSettings(
            baseURL: base,
            overtureRelease: release,
            isDemo: demo,
            shopBaseURL: shop,
            x402Network: network
        )
    }
}

public enum BrooklynDemoAddress {
    public static let label = "Home"
    public static let line1 = "14 Pine Street"
    public static let city = "Brooklyn"
    public static let region = "NY"
    public static let postalCode = "11201"
    public static let country = "US"
    public static let latitude = 40.6944
    public static let longitude = -73.9903
    public static let geohash5 = "dr5rs"
}
