import Foundation
import SwiftData

/// Launch guards and post-confirm empty-pool check. No `POST /orders`. GPS is not consulted.
@MainActor
public enum OrderLunchLaunch {
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
    public static func afterConfirmation(
        confirmed: Bool,
        delivery: DeliveryLocation,
        store: GnoshbotStore
    ) throws -> AfterConfirm {
        guard confirmed else {
            return .spoken(.confirmationDeclined)
        }
        if try !store.hasPayableKitchen(near: delivery) {
            return .spoken(.emptyPayableBox)
        }
        return .awaitingPick
    }

    public enum AfterConfirm: Equatable, Sendable {
        case spoken(LaunchCopy)
        /// Payable kitchen exists. I13 inserts `launching` and speaks "On it."
        case awaitingPick
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
