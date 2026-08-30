import Foundation
import SwiftData

/// Spoken classes on device. These are not kitchen `OrderStatus` tuples (GROK.md T33).
public enum SpokenStatus: String, Codable, Sendable {
    case launching
    case placed
    case settled
    case processingLogistics
    case dispatched
    case delivered
    case failed
}

/// Saved drop-off. Food ships only to a row confirmed on that Siri turn.
@Model
public final class DeliveryLocation {
    @Attribute(.unique) public var id: UUID
    public var label: String
    public var line1: String
    public var line2: String?
    public var city: String
    public var region: String
    public var postalCode: String
    public var country: String
    public var latitude: Double
    public var longitude: Double
    public var isDefault: Bool
    public var lastConfirmedAt: Date?

    public init(
        id: UUID = UUID(),
        label: String,
        line1: String,
        line2: String? = nil,
        city: String,
        region: String,
        postalCode: String,
        country: String,
        latitude: Double,
        longitude: Double,
        isDefault: Bool,
        lastConfirmedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.region = region
        self.postalCode = postalCode
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.isDefault = isDefault
        self.lastConfirmedAt = lastConfirmedAt
    }

    public var spokenLine: String {
        var parts = [label, line1]
        if let line2, !line2.isEmpty {
            parts.append(line2)
        }
        parts.append(city)
        return parts.joined(separator: ", ")
    }
}

/// Hot row for Inquiry Intents. Sub-10 ms `FetchDescriptor` prefix(1) on `timestamp`.
@Model
public final class ActiveOrderCache {
    @Attribute(.unique) public var orderId: String
    public var timestamp: Date
    public var status: SpokenStatus
    public var trackingUrl: String?
    public var shopPrefix: String
    public var merchantName: String
    public var itemName: String
    public var costUsdc: Decimal
    public var etaMinutes: Int?
    public var trackingToken: String?
    public var settlementTxHash: String?
    public var errorMessage: String?
    public var idempotencyKey: String
    public var deliveryLocationId: UUID
    public var deliverySpokenLine: String

    public init(
        orderId: String,
        idempotencyKey: String,
        shopPrefix: String,
        delivery: DeliveryLocation
    ) {
        self.orderId = orderId
        self.idempotencyKey = idempotencyKey
        self.shopPrefix = shopPrefix
        self.timestamp = Date()
        self.status = .launching
        self.merchantName = ""
        self.itemName = ""
        self.costUsdc = 0
        self.deliveryLocationId = delivery.id
        self.deliverySpokenLine = "\(delivery.label), \(delivery.line1)"
    }

    public func markPlaced() {
        status = .placed
        timestamp = Date()
    }

    public func markSettled(trackingUrl: String, settlementTxHash: String?) {
        self.trackingUrl = trackingUrl
        self.settlementTxHash = settlementTxHash
        status = .settled
        timestamp = Date()
    }

    public func applyFulfillment(
        logisticsStatus: String,
        etaMinutes: Int?,
        trackingToken: String?,
        trackingUrl: String?
    ) {
        if let trackingUrl {
            self.trackingUrl = trackingUrl
        }
        if let trackingToken {
            self.trackingToken = trackingToken
        }
        if let etaMinutes {
            self.etaMinutes = etaMinutes
        }
        switch logisticsStatus {
        case "awaiting_kitchen", "accepted", "preparing":
            status = .processingLogistics
        case "ready_for_dispatch", "dispatched":
            status = .dispatched
        case "delivered":
            status = .delivered
        case "failed":
            status = .failed
        default:
            break
        }
        timestamp = Date()
    }

    public func markFailed(_ message: String) {
        status = .failed
        errorMessage = message
        timestamp = Date()
    }
}

public enum ActiveOrderInquiry {
    /// Single-row fetch used by Inquiry Intents. Must not hit the network.
    public static func latestDescriptor() -> FetchDescriptor<ActiveOrderCache> {
        var descriptor = FetchDescriptor<ActiveOrderCache>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    public static func latest(in context: ModelContext) throws -> ActiveOrderCache? {
        try context.fetch(latestDescriptor()).first
    }
}

public enum GnoshbotSchema {
    public static let models: [any PersistentModel.Type] = [
        DeliveryLocation.self,
        ActiveOrderCache.self,
    ]
}
