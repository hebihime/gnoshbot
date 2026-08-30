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
        switch try OrderLunchLaunch.afterConfirmation(
            confirmed: ok,
            delivery: proposedRow,
            store: store
        ) {
        case .spoken(let copy):
            return .result(dialog: IntentDialog(stringLiteral: copy.spoken))
        case .awaitingPick:
            // I13 inserts `launching` and is the contract for this dialog.
            return .result(dialog: IntentDialog(stringLiteral: "On it."))
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
