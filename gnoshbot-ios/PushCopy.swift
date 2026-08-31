import Foundation

/// PRODUCT_DECISIONS.md §1.6 plus ARCHITECTURE.md §12 hold-expiry line.
public enum PushCopy: Equatable, Sendable {
    case paidKitchenOnIt
    case arriving(minutes: Int)
    case onTheWay(minutes: Int)
    case launchAborted(reason: String)
    case kitchenDeclinedRefundStarted
    case holdExpired
    case emptyPayableBox
    case bioShieldEmptiesBox

    public var body: String {
        switch self {
        case .paidKitchenOnIt:
            "Paid. Kitchen is on it."
        case .arriving(let n):
            "Arriving in \(n) minutes."
        case .onTheWay(let n):
            "On the way. \(n) minutes."
        case .launchAborted(let reason):
            "Launch aborted. \(reason). Tap to retry."
        case .kitchenDeclinedRefundStarted:
            "Kitchen declined. Refund started."
        case .holdExpired:
            "The hold expired. Say the word and I'll retry."
        case .emptyPayableBox:
            LaunchCopy.emptyPayableBox.spoken
        case .bioShieldEmptiesBox:
            LaunchCopy.bioShieldEmptiesBox.spoken
        }
    }
}

public protocol SettlementNotifying: Sendable {
    func notify(_ copy: PushCopy) async
}

public struct CapturingNotifier: SettlementNotifying {
    public final class Box: @unchecked Sendable {
        public var copies: [PushCopy] = []
        public init() {}
    }

    public let box: Box

    public init(box: Box = Box()) {
        self.box = box
    }

    public func notify(_ copy: PushCopy) async {
        box.copies.append(copy)
    }
}
