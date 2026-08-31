import Foundation
import Security

/// Spender EOA material. Keychain ACL has **no** biometry (GROK invariant 5, T18).
/// P-256 `SecKey` matches the GROK template (I15). The secp256k1 blob is what EIP-3009 uses.
public enum SpenderKey {
    public static let tag = "com.gnoshbot.spender.ecdsa"
    public static let secp256k1Tag = "com.gnoshbot.spender.secp256k1"
    nonisolated(unsafe) public static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    /// Empty: no `.userPresence`, no `.biometryAny`.
    public static let accessControlFlags: SecAccessControlCreateFlags = []

    public static func generateIfNeeded() throws {
        try generateSecKeyIfNeeded()
        try generateSecp256k1IfNeeded()
    }

    public static var hasBiometryACL: Bool {
        accessControlFlags.contains(.biometryAny)
            || accessControlFlags.contains(.biometryCurrentSet)
            || accessControlFlags.contains(.userPresence)
    }

    public static func secp256k1PrivateKey() throws -> Data {
        try generateSecp256k1IfNeeded()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: secp256k1Tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            throw SpenderKeyError.missingSecp256k1
        }
        return data
    }

    public static func makeAccessControl() throws -> SecAccessControl {
        var err: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            accessibility,
            accessControlFlags,
            &err
        ) else {
            throw err!.takeRetainedValue() as Error
        }
        return access
    }

    public static func deleteAllForTests() {
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
        ] as CFDictionary)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: secp256k1Tag,
        ] as CFDictionary)
    }

    private static func generateSecKeyIfNeeded() throws {
        if secKeyExists() { return }
        let access = try makeAccessControl()
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(tag.utf8),
                kSecAttrAccessControl as String: access,
            ],
        ]
        var err: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attrs as CFDictionary, &err) != nil else {
            throw err!.takeRetainedValue() as Error
        }
    }

    private static func secKeyExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    private static func generateSecp256k1IfNeeded() throws {
        let exists: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: secp256k1Tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(exists as CFDictionary, &item) == errSecSuccess { return }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw SpenderKeyError.rngFailed }
        let data = Data(bytes)
        let access = try makeAccessControl()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: secp256k1Tag,
            kSecAttrAccessible as String: accessibility,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: data,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw SpenderKeyError.keychain(addStatus)
        }
    }
}

public enum SpenderKeyError: Error {
    case missingSecp256k1
    case rngFailed
    case keychain(OSStatus)
}
