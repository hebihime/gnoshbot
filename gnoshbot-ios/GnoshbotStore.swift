import Foundation
import SwiftData

/// Local SwiftData facade. Inquiry and launch guards must not hit the network through this type.
@MainActor
public final class GnoshbotStore {
    public static let shared = GnoshbotStore()

    private var container: ModelContainer?
    private var cachedContext: ModelContext?

    public init() {}

    public init(container: ModelContainer) {
        self.container = container
        self.cachedContext = ModelContext(container)
    }

    /// Cached locally (I17 refreshes off the voice path). Fail closed until set.
    public var fundedFlag: Bool = false
    public var remainingAllowanceUSDC: Decimal = 0
    public var remainingAllowanceAtomic: UInt64 { UsdcWire.atomic(usdc: remainingAllowanceUSDC) }
    /// In-memory until I10 SE-wraps ProfileBlob. Empty shield = no allergen filter.
    public var profile: ProfileEnvelope = .empty
    public var lastEnsureCopy: String?

    public func attach(_ container: ModelContainer) {
        self.container = container
        self.cachedContext = ModelContext(container)
    }

    public var modelContext: ModelContext {
        get throws {
            if let cachedContext {
                return cachedContext
            }
            guard let container else {
                throw GnoshbotStoreError.containerNotAttached
            }
            let context = ModelContext(container)
            cachedContext = context
            return context
        }
    }

    public func persist() throws {
        try modelContext.save()
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

    /// Most recent lunch that is not the current in-flight row. Demo orders stay
    /// `.launching`, so we cannot skip every launching status.
    public func priorLunch() throws -> PriorLunch? {
        let context = try modelContext
        let descriptor = FetchDescriptor<ActiveOrderCache>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let rows = try context.fetch(descriptor)
        guard let currentId = rows.first?.orderId else { return nil }
        for row in rows {
            if row.orderId == currentId { continue }
            guard !row.itemName.isEmpty else { continue }
            return PriorLunch(
                menuItemId: row.menuItemId ?? "",
                itemName: row.itemName,
                merchantName: row.merchantName,
                pickReason: row.pickReason ?? ""
            )
        }
        return nil
    }

    public func deleteAllOrders() throws {
        let context = try modelContext
        for row in try context.fetch(FetchDescriptor<ActiveOrderCache>()) {
            context.delete(row)
        }
        try context.save()
    }

    /// One-shot: wipe lunches after the Lamb Kebab demo loop. Addresses stay.
    public func wipeOrdersOnce() throws {
        let defaults = FoundationModelProbe.defaults()
        let key = "gnoshbot.orders.wipe.2026-08-31.3"
        guard defaults.string(forKey: key) != "done" else { return }
        try deleteAllOrders()
        defaults.set("done", forKey: key)
        defaults.synchronize()
    }

    public func applyDemoFundingIfNeeded(_ settings: ControlPlaneSettings) {
        guard settings.isDemo else { return }
        fundedFlag = true
        if remainingAllowanceUSDC <= 0 {
            remainingAllowanceUSDC = 25
        }
        profile = PrototypeProfileStore.load()
    }

    public func seedPrototypeHomeIfNeeded() throws {
        if try !deliveryLocations().isEmpty { return }
        _ = try saveAddress(
            draft: .brooklynHome,
            latitude: BrooklynDemoAddress.latitude,
            longitude: BrooklynDemoAddress.longitude
        )
    }

    public func persistProfile(_ envelope: ProfileEnvelope) {
        profile = envelope
        PrototypeProfileStore.save(envelope)
    }

    public func applyLaunchingPick(_ pick: CachedPick) throws {
        guard let row = try latestOrder(), row.status == .launching else { return }
        row.merchantName = pick.merchantName
        row.itemName = pick.itemName
        row.costUsdc = pick.costUsdcGuess
        row.shopPrefix = pick.shopPrefix
        row.pickSource = pick.pickSource
        row.pickReason = pick.pickReason
        row.menuItemId = pick.menuItemId
        try persist()
    }

    public func failLatestLaunch(_ push: PushCopy) throws {
        guard let row = try latestOrder(), row.status == .launching else { return }
        row.markFailed(push.body)
        try persist()
    }

    public func siriOrderingEnabled() throws -> Bool {
        try !deliveryLocations().isEmpty
    }

    public func saveAddress(
        draft: AddressDraft,
        latitude: Double,
        longitude: Double,
        replacing id: UUID? = nil
    ) throws -> DeliveryLocation {
        let context = try modelContext
        let existing = try context.fetch(
            FetchDescriptor<DeliveryLocation>(sortBy: [SortDescriptor(\.label)])
        )
        let labelKey = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !labelKey.isEmpty else { throw AddressSaveError.emptyLabel }
        guard !draft.line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AddressSaveError.emptyLine1
        }
        if existing.contains(where: { $0.label.caseInsensitiveCompare(labelKey) == .orderedSame && $0.id != id }) {
            throw AddressSaveError.duplicateLabel
        }
        let makeDefault = draft.isDefault || existing.isEmpty
        if makeDefault {
            for row in existing { row.isDefault = false }
        }
        let row: DeliveryLocation
        if let id, let found = existing.first(where: { $0.id == id }) {
            found.label = labelKey
            found.line1 = draft.line1
            found.line2 = draft.line2
            found.city = draft.city
            found.region = draft.region
            found.postalCode = draft.postalCode
            found.country = draft.country
            found.latitude = latitude
            found.longitude = longitude
            found.isDefault = makeDefault
            row = found
        } else {
            row = DeliveryLocation(
                label: labelKey,
                line1: draft.line1,
                line2: draft.line2,
                city: draft.city,
                region: draft.region,
                postalCode: draft.postalCode,
                country: draft.country,
                latitude: latitude,
                longitude: longitude,
                isDefault: makeDefault
            )
            context.insert(row)
        }
        try context.save()
        return row
    }

    public func deleteAddress(id: UUID) throws {
        let context = try modelContext
        let rows = try context.fetch(FetchDescriptor<DeliveryLocation>())
        guard let row = rows.first(where: { $0.id == id }) else { return }
        context.delete(row)
        let leftover = try context.fetch(
            FetchDescriptor<DeliveryLocation>(sortBy: [SortDescriptor(\.label)])
        )
        if leftover.count == 1 {
            leftover[0].isDefault = true
        }
        try context.save()
    }

    public func insertLaunching(pick: CachedPick?, delivery: DeliveryLocation) throws -> ActiveOrderCache {
        let context = try modelContext
        let deliveryId = delivery.id
        var descriptor = FetchDescriptor<DeliveryLocation>(
            predicate: #Predicate { $0.id == deliveryId }
        )
        descriptor.fetchLimit = 1
        let persisted = try context.fetch(descriptor).first ?? delivery
        persisted.lastConfirmedAt = Date()
        let row = ActiveOrderCache(
            orderId: UUID().uuidString,
            idempotencyKey: UUID().uuidString,
            shopPrefix: pick?.shopPrefix ?? "",
            delivery: persisted
        )
        row.deliverySpokenLine = persisted.spokenLine
        if let pick {
            row.merchantName = pick.merchantName
            row.itemName = pick.itemName
            row.costUsdc = pick.costUsdcGuess
            row.shopPrefix = pick.shopPrefix
            row.pickSource = pick.pickSource
            row.pickReason = pick.pickReason
            row.menuItemId = pick.menuItemId
        }
        context.insert(row)
        try context.save()
        return row
    }

    public func restaurantSnapshots() throws -> [RestaurantSnapshot] {
        let context = try modelContext
        let kitchens = try context.fetch(FetchDescriptor<RestaurantCache>())
        let menus = try menuDocuments()
        return kitchens.map { kitchen in
            let prefix = ShopPrefix.make(
                originHost: kitchen.shopOriginHost,
                locationId: kitchen.shopLocationId
            ) ?? kitchen.nativeX402Url ?? ""
            return RestaurantSnapshot(
                overtureId: kitchen.overtureId,
                name: kitchen.name,
                latitude: kitchen.latitude,
                longitude: kitchen.longitude,
                integration: kitchen.integration,
                shopPrefix: prefix,
                cuisineTags: menus[prefix]?.cuisineTags ?? []
            )
        }
    }

    public func menuDocuments() throws -> [String: MenuDocument] {
        let context = try modelContext
        let rows = try context.fetch(FetchDescriptor<MenuCache>())
        var map: [String: MenuDocument] = [:]
        for row in rows {
            if let parsed = try? MenuDocument.parse(json: row.json) {
                map[row.shopPrefix] = parsed
            }
        }
        return map
    }

    public func pickCachedCandidate(near delivery: DeliveryLocation) throws -> LunchScoreOutcome {
        try LunchScorer.pick(
            restaurants: restaurantSnapshots(),
            menus: menuDocuments(),
            near: delivery,
            profile: profile,
            remainingAllowanceUSDC: remainingAllowanceUSDC
        )
    }
}

public enum GnoshbotStoreError: Error {
    case containerNotAttached
}

public enum GnoshbotPersistence {
    public static let appGroupId = "group.com.gnoshbot"
    public static let schema = Schema(GnoshbotSchema.models)

    public static func appGroupStoreURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent("Gnoshbot.store")
    }

    public static func makeAppContainer() throws -> ModelContainer {
        let url = appGroupStoreURL()
        do {
            return try openContainer(url: url)
        } catch {
            if let url {
                destroyStore(at: url)
                return try openContainer(url: url)
            }
            throw error
        }
    }

    private static func openContainer(url: URL?) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func destroyStore(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = URL(fileURLWithPath: url.path + suffix)
            try? fm.removeItem(at: path)
        }
    }

    public static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
