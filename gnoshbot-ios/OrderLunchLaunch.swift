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
    public static func afterConfirmation(
        confirmed: Bool,
        delivery: DeliveryLocation,
        store: GnoshbotStore,
        pick: (() throws -> LunchScoreOutcome)? = nil
    ) throws -> AfterConfirm {
        guard confirmed else {
            return .spoken(.confirmationDeclined)
        }
        if try !store.hasPayableKitchen(near: delivery) {
            return .spoken(.emptyPayableBox)
        }
        let outcome: LunchScoreOutcome
        if let pick {
            outcome = try pick()
        } else {
            outcome = try store.pickCachedCandidate(near: delivery)
        }
        switch outcome {
        case .emptyPayable:
            return .spoken(.emptyPayableBox)
        case .bioShieldEmpty:
            return .spoken(.bioShieldEmptiesBox)
        case .pick(let cached):
            _ = try store.insertLaunching(pick: cached, delivery: delivery)
            return .onIt
        }
    }

    /// Race the local picker against 400 ms. Timeout still inserts `launching` (deferred pick) and speaks "On it."
    public static func afterConfirmationWithBudget(
        confirmed: Bool,
        delivery: DeliveryLocation,
        store: GnoshbotStore,
        budgetNanoseconds: UInt64 = pickBudgetNanoseconds,
        pick: @escaping @Sendable () throws -> LunchScoreOutcome
    ) async throws -> AfterConfirm {
        guard confirmed else {
            return .spoken(.confirmationDeclined)
        }
        if try !store.hasPayableKitchen(near: delivery) {
            return .spoken(.emptyPayableBox)
        }
        let outcome = await racePick(budgetNanoseconds: budgetNanoseconds, pick: pick)
        switch outcome {
        case .timedOut:
            _ = try store.insertLaunching(pick: nil, delivery: delivery)
            return .onIt
        case .finished(.emptyPayable):
            return .spoken(.emptyPayableBox)
        case .finished(.bioShieldEmpty):
            return .spoken(.bioShieldEmptiesBox)
        case .finished(.pick(let cached)):
            _ = try store.insertLaunching(pick: cached, delivery: delivery)
            return .onIt
        }
    }

    private static func racePick(
        budgetNanoseconds: UInt64,
        pick: @escaping @Sendable () throws -> LunchScoreOutcome
    ) async -> PickRace {
        await withTaskGroup(of: PickRace.self) { group in
            group.addTask {
                do {
                    return .finished(try pick())
                } catch {
                    return .timedOut
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: budgetNanoseconds)
                return .timedOut
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }

    public enum AfterConfirm: Equatable, Sendable {
        case spoken(LaunchCopy)
        case onIt
    }

    private enum PickRace: Sendable {
        case finished(LunchScoreOutcome)
        case timedOut
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
