import Foundation
import SwiftData

/// Local SwiftData facade. Inquiry and launch guards must not hit the network through this type.
@MainActor
public final class GnoshbotStore {
    public static let shared = GnoshbotStore()

    private var container: ModelContainer?

    public init() {}

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Cached locally (I17 refreshes off the voice path). Fail closed until set.
    public var fundedFlag: Bool = false
    public var remainingAllowanceUSDC: Decimal = 0

    public func attach(_ container: ModelContainer) {
        self.container = container
    }

    public var modelContext: ModelContext {
        get throws {
            guard let container else {
                throw GnoshbotStoreError.containerNotAttached
            }
            return ModelContext(container)
        }
    }

    public func deliveryLocations() throws -> [DeliveryLocation] {
        let context = try modelContext
        let descriptor = FetchDescriptor<DeliveryLocation>(
            sortBy: [SortDescriptor(\.label)]
        )
        return try context.fetch(descriptor)
    }

    /// Prefer `isDefault`, else most recent `lastConfirmedAt`.
    public func defaultDeliveryLocation() throws -> DeliveryLocation? {
        let saved = try deliveryLocations()
        if let marked = saved.first(where: \.isDefault) {
            return marked
        }
        return saved.max { lhs, rhs in
            (lhs.lastConfirmedAt ?? .distantPast) < (rhs.lastConfirmedAt ?? .distantPast)
        }
    }

    public func latestOrder() throws -> ActiveOrderCache? {
        let context = try modelContext
        return try context.fetch(ActiveOrderInquiry.latestDescriptor()).first
    }
}

public enum GnoshbotStoreError: Error {
    case containerNotAttached
}

public enum GnoshbotPersistence {
    public static let appGroupId = "group.bot.gnosh"
    public static let schema = Schema(GnoshbotSchema.models)

    public static func appGroupStoreURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("Gnoshbot.store")
    }

    public static func makeAppContainer() throws -> ModelContainer {
        let url = appGroupStoreURL()
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
