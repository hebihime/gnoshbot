import Foundation

/// x402 `network` on the shop wire. TestFlight must match the shop, not assume Base mainnet.
public enum X402Network: String, Sendable, Equatable {
    case base = "base"
    case baseSepolia = "base-sepolia"

    public var chainId: UInt64 {
        switch self {
        case .base: 8453
        case .baseSepolia: 84532
        }
    }

    public static func parse(_ raw: String) -> X402Network? {
        X402Network(rawValue: raw.lowercased())
    }
}

public enum UsdcWire {
    public static let atomicPerCent: UInt64 = 10_000
    public static let atomicPerUsdc: UInt64 = 1_000_000

    public static func atomic(cents: UInt64) -> UInt64 {
        cents * atomicPerCent
    }

    public static func atomic(usdc: Decimal) -> UInt64 {
        var scaled = usdc * Decimal(atomicPerUsdc)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        return NSDecimalNumber(decimal: rounded).uint64Value
    }

    public static func usdc(atomic: UInt64) -> Decimal {
        Decimal(atomic) / Decimal(atomicPerUsdc)
    }
}
