import Foundation
import Testing
@testable import GnoshbotData

@Suite("SpenderKey")
struct SpenderKeyTests {
    @Test("ACL flags include neither biometry nor userPresence")
    func noBiometryFlags() {
        #expect(SpenderKey.accessControlFlags.isEmpty)
        #expect(!SpenderKey.hasBiometryACL)
        #expect(SpenderKey.tag == "com.gnoshbot.spender.ecdsa")
        #expect(SpenderKey.accessibility == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    @Test("generateIfNeeded creates a keychain item without throwing")
    func generateExists() throws {
        SpenderKey.deleteAllForTests()
        do {
            try SpenderKey.generateIfNeeded()
            try SpenderKey.generateIfNeeded()
            let blob = try SpenderKey.secp256k1PrivateKey()
            #expect(blob.count == 32)
        } catch {
            let ns = error as NSError
            // swift test on macOS has no Keychain entitlement (errSecMissingEntitlement).
            if ns.domain == NSOSStatusErrorDomain, ns.code == -34018 {
                return
            }
            throw error
        }
    }
}

@Suite("SettlementSession")
struct SettlementSessionTests {
    @Test("background configuration matches GROK I14")
    func backgroundConfig() {
        #expect(SettlementSession.identifier == "com.gnoshbot.settlement")
        let cfg = SettlementSession.makeBackgroundConfiguration()
        #expect(cfg.sessionSendsLaunchEvents)
        #expect(cfg.waitsForConnectivity)
        #expect(cfg.identifier == SettlementSession.identifier)
    }
}

@Suite("UsdcWire")
struct UsdcWireTests {
    @Test("cents times 10_000 is USDC atomic")
    func centsToAtomic() {
        #expect(UsdcWire.atomic(cents: 1450) == 14_500_000)
        #expect(UsdcWire.atomic(usdc: 14.5) == 14_500_000)
    }
}

@Suite("X402V1")
struct X402V1Tests {
    @Test("parses shop camelCase 402 accepts")
    func parseChallenge() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "x402Version": 1,
            "error": "X-PAYMENT header is required",
            "accepts": [[
                "scheme": "exact",
                "network": "base-sepolia",
                "maxAmountRequired": "14500000",
                "payTo": "0x1111111111111111111111111111111111111111",
                "asset": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
                "maxTimeoutSeconds": 300,
                "extra": ["name": "USDC", "version": "2"],
            ]],
        ])
        let challenge = try X402V1.parseChallenge(data)
        #expect(challenge.accepts[0].network == "base-sepolia")
        #expect(challenge.accepts[0].amountAtomic == 14_500_000)
    }

    @Test("header is v1 exact JSON inside Base64")
    func encodeHeader() throws {
        let header = try X402V1.encodeHeader(
            network: "base-sepolia",
            signature: "0xab",
            authorization: .init(
                from: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
                to: "0x1111111111111111111111111111111111111111",
                value: "14500000",
                validAfter: "0",
                validBefore: "1800000300",
                nonce: "0x" + String(repeating: "01", count: 32)
            )
        )
        let json = try #require(String(data: Data(base64Encoded: header)!, encoding: .utf8))
        #expect(json.contains("\"x402Version\":1") || json.contains("\"x402Version\": 1"))
        #expect(json.contains("base-sepolia"))
        #expect(json.contains("14500000"))
    }
}
