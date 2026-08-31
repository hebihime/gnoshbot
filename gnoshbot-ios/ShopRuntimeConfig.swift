import Foundation

/// Shop host + x402 network. `x402Network` must equal `accepts[0].network` or we refuse to sign.
public struct ShopRuntimeConfig: Sendable, Equatable {
    public var baseURL: URL
    public var x402Network: X402Network
    public var customerId: String
    public var remainingAllowanceAtomic: UInt64
    public var shopMaxOrderAtomic: UInt64
    public var acceptanceTimeoutSeconds: TimeInterval
    public var extraPollCapSeconds: TimeInterval
    public var staleLaunchingRetryAfter: TimeInterval

    public init(
        baseURL: URL,
        x402Network: X402Network,
        customerId: String,
        remainingAllowanceAtomic: UInt64,
        shopMaxOrderAtomic: UInt64 = UsdcWire.atomic(cents: 20_000),
        acceptanceTimeoutSeconds: TimeInterval = 600,
        extraPollCapSeconds: TimeInterval = 45 * 60,
        staleLaunchingRetryAfter: TimeInterval = 15
    ) {
        self.baseURL = baseURL
        self.x402Network = x402Network
        self.customerId = customerId
        self.remainingAllowanceAtomic = remainingAllowanceAtomic
        self.shopMaxOrderAtomic = shopMaxOrderAtomic
        self.acceptanceTimeoutSeconds = acceptanceTimeoutSeconds
        self.extraPollCapSeconds = extraPollCapSeconds
        self.staleLaunchingRetryAfter = staleLaunchingRetryAfter
    }

    public static func from(
        settings: ControlPlaneSettings,
        customerId: String,
        remainingAllowanceAtomic: UInt64
    ) -> ShopRuntimeConfig? {
        guard let baseURL = settings.shopBaseURL else { return nil }
        return ShopRuntimeConfig(
            baseURL: baseURL,
            x402Network: settings.x402Network,
            customerId: customerId,
            remainingAllowanceAtomic: remainingAllowanceAtomic
        )
    }

    public var pollCapSeconds: TimeInterval {
        acceptanceTimeoutSeconds + extraPollCapSeconds
    }
}
