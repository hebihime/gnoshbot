import Foundation

/// Fatal launch copy from `PRODUCT_DECISIONS.md` §1.5. No merchant, SKU, price, or minutes.
public enum LaunchCopy: String, CaseIterable, Sendable {
    case noSavedAddresses
    case confirmationDeclined
    case unknownLabel
    case allowanceZero
    case unfunded
    case emptyPayableBox
    case bioShieldEmptiesBox

    public var spoken: String {
        switch self {
        case .noSavedAddresses:
            "Add a delivery address in Gnoshbot first."
        case .confirmationDeclined:
            "No order placed."
        case .unknownLabel:
            "I don't have that address. Open Gnoshbot to add it."
        case .allowanceZero:
            "Order denied. Daily allowance exceeded."
        case .unfunded:
            "Launch aborted. Insufficient funds. Top up in Gnoshbot."
        case .emptyPayableBox:
            "No payable kitchen in range of that address."
        case .bioShieldEmptiesBox:
            "Every nearby menu collides with your Bio-Shield. I won't guess."
        }
    }
}
