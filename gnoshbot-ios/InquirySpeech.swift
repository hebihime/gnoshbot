import Foundation

/// Inquiry copy. SwiftData only — no `URLSession`. Minutes only when `etaMinutes` is set (or remaining from it).
public enum InquirySpeech {
    public static let noActiveOrder = "No active lunch orders."
    public static let stillPlacing = "Still placing it."
    public static let organizingCourier = "Payment settled. They're organizing a courier."
    public static let waitingOnKitchenTime = "Paid. Still waiting on the kitchen for a time."
    public static let atTheDoor = "It should be at the door."
    public static let orderFailed = "The order failed."

    public static func status(_ row: ActiveOrderCache, now: Date = Date()) -> String {
        if row.awaitingKitchenTime, row.etaMinutes == nil {
            return waitingOnKitchenTime
        }
        switch row.status {
        case .launching, .placed:
            return stillPlacing
        case .settled, .processingLogistics:
            if let eta = row.etaMinutes {
                return "In the kitchen. About \(eta) minutes."
            }
            return organizingCourier
        case .dispatched:
            let remaining = remainingMinutes(row: row, now: now)
            if remaining == 0 {
                return atTheDoor
            }
            return "On the way. \(remaining) minutes."
        case .delivered:
            return atTheDoor
        case .failed:
            return row.errorMessage ?? orderFailed
        }
    }

    public static func destination(_ row: ActiveOrderCache) -> String {
        row.deliverySpokenLine
    }

    public static func ordered(_ row: ActiveOrderCache) -> String {
        if row.itemName.isEmpty || row.merchantName.isEmpty {
            return stillPlacing
        }
        return "\(row.itemName) from \(row.merchantName)."
    }

    public static func cost(_ row: ActiveOrderCache) -> String {
        if row.status == .launching || row.status == .placed, row.costUsdc == 0 {
            return stillPlacing
        }
        return "\(formatUSDC(row.costUsdc)) USDC"
    }

    public static func remainingMinutes(row: ActiveOrderCache, now: Date) -> Int {
        let eta = row.etaMinutes ?? 0
        let elapsed = max(0, Int(now.timeIntervalSince(row.timestamp) / 60))
        return max(0, eta - elapsed)
    }

    public static func formatUSDC(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: number) ?? "\(value)"
    }
}
