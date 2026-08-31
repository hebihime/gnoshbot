import Foundation

public enum SettlementError: Error, Equatable {
    case missingDelivery
    case missingPick
    case payToMismatch
    case networkMismatch(shop: String, challenge: String)
    case amountExceedsAllowance
    case amountExceedsShopCap
    case missing402
    case noAccepts
    case badResponse
    case malformedFulfillment
    case unexpectedRequest
    case facilitatorRejected(String)
    case draftExpired
    case kitchenFailed
    case v2UnsupportedOnShop
}

public struct SettlementOutcome: Equatable, Sendable {
    public var status: SpokenStatus
    public var trackingUrl: String?
    public var etaMinutes: Int?
    public var settlementTxHash: String?
    public var retriedPlace: Bool
}
