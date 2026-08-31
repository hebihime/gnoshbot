import Foundation

public enum DeviceIdentity {
    public static let defaultsKey = "com.gnoshbot.opaqueUser"

    public static func opaqueUser(defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: defaultsKey)
        return created
    }

    public static func appGroupDefaults() -> UserDefaults {
        UserDefaults(suiteName: GnoshbotPersistence.appGroupId) ?? .standard
    }
}
