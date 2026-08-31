import Foundation
import SwiftData

/// Launch guards, post-confirm pick, launching row. No `POST /orders`. No `X-PAYMENT`. GPS is not consulted.
@MainActor
public enum OrderLunchLaunch {
    public static let onIt = "On it."
    public static let pickBudgetNanoseconds: UInt64 = 400_000_000

    public static func denyBeforeConfirmation(store: GnoshbotStore) throws -> LaunchCopy? {
        if store.remainingAllowanceUSDC <= 0 {
            return .allowanceZero
        }
        if !store.fundedFlag {
            return .unfunded
        }
        if try store.deliveryLocations().isEmpty {
            return .noSavedAddresses
        }
        return nil
    }

    /// `confirmed` is the `requestConfirmation` result. Never call this before that returns.
    /// A yes always inserts `launching` and returns `.onIt` (P16). Pick and empty-box live in `LaunchFollowThrough`.
    public static func afterConfirmation(
        confirmed: Bool,
        delivery: DeliveryLocation,
        store: GnoshbotStore,
        pick: (() throws -> LunchScoreOutcome)? = nil
    ) throws -> AfterConfirm {
        _ = pick
        guard confirmed else {
            return .spoken(.confirmationDeclined)
        }
        _ = try store.insertLaunching(pick: nil, delivery: delivery)
        return .onIt
    }

    /// Same as `afterConfirmation`. Pick budget is unused on the voice path (P16).
    public static func afterConfirmationWithBudget(
        confirmed: Bool,
        delivery: DeliveryLocation,
        store: GnoshbotStore,
        budgetNanoseconds: UInt64 = pickBudgetNanoseconds,
        pick: @escaping @Sendable () throws -> LunchScoreOutcome
    ) async throws -> AfterConfirm {
        _ = budgetNanoseconds
        _ = pick
        return try afterConfirmation(confirmed: confirmed, delivery: delivery, store: store)
    }

    public enum AfterConfirm: Equatable, Sendable {
        case spoken(LaunchCopy)
        case onIt
    }
}

extension GnoshbotStore {
    public func hasPayableKitchen(near location: DeliveryLocation) throws -> Bool {
        let context = try modelContext
        let kitchens = try context.fetch(FetchDescriptor<RestaurantCache>())
        return kitchens.contains { kitchen in
            let payable = kitchen.integration == "native" || kitchen.integration == "proxy_wrapped"
            return payable && LunchRange.isWithinFiveMiles(
                latitude: kitchen.latitude,
                longitude: kitchen.longitude,
                of: location
            )
        }
    }
}
