import Foundation

/// Prototype-only plaintext profile. MVP/I10 still SE-wraps `ProfileBlob`.
public enum PrototypeProfileStore {
    public static let profileKey = "gnoshbot.prototype.profile"
    public static let onboardedKey = "gnoshbot.prototype.onboarded"

    public static func defaults() -> UserDefaults {
        UserDefaults(suiteName: GnoshbotPersistence.appGroupId) ?? .standard
    }

    public static func load() -> ProfileEnvelope {
        guard let data = defaults().data(forKey: profileKey),
              let profile = try? JSONDecoder().decode(ProfileEnvelope.self, from: data)
        else {
            return .empty
        }
        return profile
    }

    public static func save(_ profile: ProfileEnvelope) {
        if let data = try? JSONEncoder().encode(profile) {
            defaults().set(data, forKey: profileKey)
        }
    }

    public static var hasCompletedOnboarding: Bool {
        get { defaults().bool(forKey: onboardedKey) }
        set { defaults().set(newValue, forKey: onboardedKey) }
    }
}
