import Foundation

public enum ShopPrefix {
    public static let demoHost = "demo-shop.gnoshbot.com"
    public static let demoLocation = "testflight"
    public static let demo = "\(demoHost)/\(demoLocation)"

    public static func make(originHost: String?, locationId: String?) -> String? {
        guard let originHost, !originHost.isEmpty, let locationId, !locationId.isEmpty else {
            return nil
        }
        return "\(originHost)/\(locationId)"
    }

    public static func isSandbox(_ prefix: String) -> Bool {
        prefix.contains("/_sandbox/")
    }

    public static func isDemoFixture(_ prefix: String) -> Bool {
        prefix == demo || prefix.hasSuffix("/\(demo)") || prefix.contains(demoHost)
    }
}
