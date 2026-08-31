import Foundation

/// Post-yes work. Must not run inside `OrderLunchIntent.perform()` after confirmation (P16).
public enum LaunchFollowThrough {
    public enum Outcome: Equatable, Sendable {
        case failed(PushCopy)
        case picked(CachedPick)
    }

    @MainActor
    public static func run(
        store: GnoshbotStore,
        delivery: DeliveryLocation,
        notifier: any SettlementNotifying
    ) async throws -> Outcome {
        let restaurants = try store.restaurantSnapshots()
        let menus = try store.menuDocuments()
        let assembled = LunchScorer.workingSet(
            restaurants: restaurants,
            menus: menus,
            latitude: delivery.latitude,
            longitude: delivery.longitude,
            profile: store.profile,
            remainingAllowanceUSDC: store.remainingAllowanceUSDC
        )
        switch assembled {
        case .emptyPayable:
            let push = PushCopy.emptyPayableBox
            try store.failLatestLaunch(push)
            await notifier.notify(push)
            return .failed(push)
        case .bioShieldEmpty:
            let push = PushCopy.bioShieldEmptiesBox
            try store.failLatestLaunch(push)
            await notifier.notify(push)
            return .failed(push)
        case .items(let survivors):
            let prior = try store.priorLunch()
            let pool = LunchScorer.withoutImmediateRepeat(survivors, prior: prior)
            let pick = LunchScorer.cachedPick(from: LunchScorer.argmax(pool), profile: store.profile)
            return .picked(pick)
        }
    }
}
