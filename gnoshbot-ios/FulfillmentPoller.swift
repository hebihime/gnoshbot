import Foundation

public enum FulfillmentPollSchedule {
    public static func delaySeconds(
        elapsed: TimeInterval,
        etaKnown: Bool,
        terminal: Bool,
        cap: TimeInterval
    ) -> TimeInterval? {
        if terminal { return nil }
        if elapsed >= cap { return nil }
        if elapsed < 60 { return 5 }
        if !etaKnown { return 15 }
        return 60
    }

    public static func isTerminal(logisticsStatus: String) -> Bool {
        logisticsStatus == "delivered" || logisticsStatus == "failed"
    }
}

public struct FulfillmentSnapshot: Equatable, Sendable {
    public var orderId: String?
    public var logisticsStatus: String
    public var settlementStatus: String?
    public var etaMinutes: Int?
    public var trackingToken: String?
    public var paymentTxHash: String?
    public var locationUri: String?

    public init(
        orderId: String? = nil,
        logisticsStatus: String,
        settlementStatus: String? = nil,
        etaMinutes: Int? = nil,
        trackingToken: String? = nil,
        paymentTxHash: String? = nil,
        locationUri: String? = nil
    ) {
        self.orderId = orderId
        self.logisticsStatus = logisticsStatus
        self.settlementStatus = settlementStatus
        self.etaMinutes = etaMinutes
        self.trackingToken = trackingToken
        self.paymentTxHash = paymentTxHash
        self.locationUri = locationUri
    }

    public static func parse(_ data: Data) throws -> FulfillmentSnapshot {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettlementError.malformedFulfillment
        }
        let logistics = string(obj, "logisticsStatus") ?? string(obj, "logistics_status") ?? ""
        let eta = int(obj, "etaMinutes") ?? int(obj, "eta_minutes")
        return FulfillmentSnapshot(
            orderId: string(obj, "orderId") ?? string(obj, "order_id"),
            logisticsStatus: logistics,
            settlementStatus: string(obj, "settlementStatus") ?? string(obj, "settlement_status"),
            etaMinutes: eta,
            trackingToken: string(obj, "trackingToken") ?? string(obj, "tracking_token"),
            paymentTxHash: string(obj, "paymentTxHash") ?? string(obj, "payment_tx_hash"),
            locationUri: string(obj, "locationUri") ?? string(obj, "location_uri")
        )
    }
}

private func string(_ obj: [String: Any], _ key: String) -> String? {
    obj[key] as? String
}

private func int(_ obj: [String: Any], _ key: String) -> Int? {
    if let i = obj[key] as? Int { return i }
    if let n = obj[key] as? NSNumber { return n.intValue }
    return nil
}

public struct FulfillmentPoller: Sendable {
    public var enabled: Bool
    public var capSeconds: TimeInterval
    public var sleep: @Sendable (TimeInterval) async throws -> Void
    public var now: @Sendable () -> Date

    public init(
        enabled: Bool = true,
        capSeconds: TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { ns in
            try await Task.sleep(nanoseconds: UInt64(ns * 1_000_000_000))
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.enabled = enabled
        self.capSeconds = capSeconds
        self.sleep = sleep
        self.now = now
    }

    public static var skip: FulfillmentPoller {
        FulfillmentPoller(enabled: false, capSeconds: 0, sleep: { _ in }, now: Date.init)
    }
}
