import Foundation

/// Shop v1 payment header: JSON then Base64, sent as `X-PAYMENT`.
public enum X402V1 {
    public static let paymentHeaderName = "X-PAYMENT"
    public static let paymentRequiredHeaderName = "PAYMENT-REQUIRED"
    public static let paymentSignatureHeaderName = "PAYMENT-SIGNATURE"

    public struct Accepts: Equatable, Sendable {
        public var scheme: String
        public var network: String
        public var maxAmountRequired: String
        public var payTo: String
        public var asset: String
        public var maxTimeoutSeconds: Int
        public var extraName: String
        public var extraVersion: String

        public init(
            scheme: String,
            network: String,
            maxAmountRequired: String,
            payTo: String,
            asset: String,
            maxTimeoutSeconds: Int,
            extraName: String = "USDC",
            extraVersion: String = "2"
        ) {
            self.scheme = scheme
            self.network = network
            self.maxAmountRequired = maxAmountRequired
            self.payTo = payTo
            self.asset = asset
            self.maxTimeoutSeconds = maxTimeoutSeconds
            self.extraName = extraName
            self.extraVersion = extraVersion
        }

        public var amountAtomic: UInt64? {
            UInt64(maxAmountRequired)
        }
    }

    public struct Challenge: Equatable, Sendable {
        public var x402Version: Int
        public var error: String?
        public var accepts: [Accepts]
    }

    public struct Authorization: Equatable, Sendable {
        public var from: String
        public var to: String
        public var value: String
        public var validAfter: String
        public var validBefore: String
        public var nonce: String
    }

    public static func parseChallenge(_ data: Data) throws -> Challenge {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let obj else { throw X402V1Error.malformedChallenge }
        let version = obj["x402Version"] as? Int ?? 1
        let error = obj["error"] as? String
        let acceptsRaw = obj["accepts"] as? [[String: Any]] ?? []
        let accepts = acceptsRaw.compactMap(parseAccepts)
        return Challenge(x402Version: version, error: error, accepts: accepts)
    }

    public static func encodeHeader(
        network: String,
        signature: String,
        authorization: Authorization
    ) throws -> String {
        let payload: [String: Any] = [
            "x402Version": 1,
            "scheme": "exact",
            "network": network,
            "payload": [
                "signature": signature,
                "authorization": [
                    "from": authorization.from,
                    "to": authorization.to,
                    "value": authorization.value,
                    "validAfter": authorization.validAfter,
                    "validBefore": authorization.validBefore,
                    "nonce": authorization.nonce,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return data.base64EncodedString()
    }

    public static func paymentHeaderField(for pick: CachedPick) -> String {
        pick.usesShopV1 ? paymentHeaderName : paymentSignatureHeaderName
    }

    private static func parseAccepts(_ obj: [String: Any]) -> Accepts? {
        guard
            let scheme = obj["scheme"] as? String,
            let network = obj["network"] as? String,
            let maxAmountRequired = stringValue(obj["maxAmountRequired"]),
            let payTo = obj["payTo"] as? String,
            let asset = obj["asset"] as? String
        else { return nil }
        let timeout = obj["maxTimeoutSeconds"] as? Int ?? 300
        let extra = obj["extra"] as? [String: Any]
        return Accepts(
            scheme: scheme,
            network: network,
            maxAmountRequired: maxAmountRequired,
            payTo: payTo,
            asset: asset,
            maxTimeoutSeconds: timeout,
            extraName: extra?["name"] as? String ?? "USDC",
            extraVersion: extra?["version"] as? String ?? "2"
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
}

public enum X402V1Error: Error {
    case malformedChallenge
}

public protocol X402ExactSigning: Sendable {
    var payerAddress: String { get }
    func paymentHeader(accepts: X402V1.Accepts, now: Date) throws -> String
}

/// Test / fixture signer. Emits a well-formed v1 header; signature is not chain-valid unless injected.
public struct FixtureExactSigner: X402ExactSigning {
    public var payerAddress: String
    public var signature: String

    public init(payerAddress: String = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf", signature: String = "0x" + String(repeating: "ab", count: 65)) {
        self.payerAddress = payerAddress
        self.signature = signature
    }

    public func paymentHeader(accepts: X402V1.Accepts, now: Date) throws -> String {
        let validBefore = Int64(now.timeIntervalSince1970) + Int64(max(1, accepts.maxTimeoutSeconds))
        let nonce = "0x" + String(repeating: "01", count: 32)
        let auth = X402V1.Authorization(
            from: payerAddress,
            to: accepts.payTo,
            value: accepts.maxAmountRequired,
            validAfter: "0",
            validBefore: String(validBefore),
            nonce: nonce
        )
        return try X402V1.encodeHeader(network: accepts.network, signature: signature, authorization: auth)
    }
}
