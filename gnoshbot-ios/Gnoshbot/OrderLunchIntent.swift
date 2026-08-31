import AppIntents
import GnoshbotData

struct OrderLunchIntent: AppIntent {
    static let title: LocalizedStringResource = "Order lunch"
    static let description = IntentDescription("Hands-free lunch. Gnoshbot picks and pays.")
    static var openAppWhenRun: Bool { false }
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Delivery location")
    var deliveryLocation: DeliveryLocationEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = GnoshbotStore.shared
        if let deny = try OrderLunchLaunch.denyBeforeConfirmation(store: store) {
            return .result(dialog: IntentDialog(stringLiteral: deny.spoken))
        }

        let saved = try store.deliveryLocations()
        let proposedRow = row(matching: deliveryLocation, in: saved) ?? storeDefault(saved)
        let proposed = proposedRow.asEntity()
        let ok = try await $deliveryLocation.requestConfirmation(
            for: proposed,
            dialog: IntentDialog("Deliver to \(proposed.spokenLine)?")
        )
        let restaurants = try store.restaurantSnapshots()
        let menus = try store.menuDocuments()
        let profile = store.profile
        let remaining = store.remainingAllowanceUSDC
        let lat = proposedRow.latitude
        let lon = proposedRow.longitude
        let result = try await OrderLunchLaunch.afterConfirmationWithBudget(
            confirmed: ok,
            delivery: proposedRow,
            store: store,
            pick: {
                LunchScorer.pick(
                    restaurants: restaurants,
                    menus: menus,
                    latitude: lat,
                    longitude: lon,
                    profile: profile,
                    remainingAllowanceUSDC: remaining
                )
            }
        )
        switch result {
        case .spoken(let copy):
            return .result(dialog: IntentDialog(stringLiteral: copy.spoken))
        case .onIt:
            GnoshbotBackground.shared.enqueueSettlement(pick: nil, delivery: proposedRow)
            return .result(dialog: IntentDialog(stringLiteral: OrderLunchLaunch.onIt))
        }
    }

    private func row(matching entity: DeliveryLocationEntity?, in saved: [DeliveryLocation]) -> DeliveryLocation? {
        guard let entity else { return nil }
        return saved.first(where: { $0.id == entity.id })
    }

    private func storeDefault(_ saved: [DeliveryLocation]) -> DeliveryLocation {
        saved.first(where: \.isDefault)
            ?? saved.max { lhs, rhs in
                (lhs.lastConfirmedAt ?? .distantPast) < (rhs.lastConfirmedAt ?? .distantPast)
            }
            ?? saved[0]
    }
}
