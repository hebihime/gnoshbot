import Foundation
import SwiftData
import Testing
@testable import GnoshbotData

@Suite("OrderLunchLaunch")
@MainActor
struct OrderLunchLaunchTests {
    private func makeStore() throws -> GnoshbotStore {
        let container = try GnoshbotPersistence.makeInMemoryContainer()
        let store = GnoshbotStore(container: container)
        store.fundedFlag = true
        store.remainingAllowanceUSDC = 25
        return store
    }

    @Test("zero saved addresses speaks the add-address line")
    func zeroAddresses() throws {
        let store = try makeStore()
        let deny = try OrderLunchLaunch.denyBeforeConfirmation(store: store)
        #expect(deny == .noSavedAddresses)
        #expect(try store.latestOrder() == nil)
    }

    @Test("declined confirmation does not insert ActiveOrderCache")
    func cancelConfirmInsertsNothing() throws {
        let store = try makeStore()
        let context = try store.modelContext
        let home = DeliveryLocation(
            label: "Home",
            line1: "14 Pine Street",
            city: "Brooklyn",
            region: "NY",
            postalCode: "11201",
            country: "US",
            latitude: 40.6944,
            longitude: -73.9903,
            isDefault: true
        )
        context.insert(home)
        try context.save()

        let copy = try OrderLunchLaunch.afterConfirmation(
            confirmed: false,
            delivery: home,
            store: store
        )
        #expect(copy == .spoken(.confirmationDeclined))
        if case .spoken(let line) = copy {
            #expect(line.spoken == "No order placed.")
        }
        #expect(try store.latestOrder() == nil)
    }

    @Test("empty payable box is spoken only after confirmation")
    func emptyBoxAfterYes() throws {
        let store = try makeStore()
        let context = try store.modelContext
        let home = DeliveryLocation(
            label: "Home",
            line1: "14 Pine Street",
            city: "Brooklyn",
            region: "NY",
            postalCode: "11201",
            country: "US",
            latitude: 40.6944,
            longitude: -73.9903,
            isDefault: true
        )
        context.insert(home)
        try context.save()

        #expect(try OrderLunchLaunch.denyBeforeConfirmation(store: store) == nil)
        let copy = try OrderLunchLaunch.afterConfirmation(
            confirmed: true,
            delivery: home,
            store: store
        )
        #expect(copy == .spoken(.emptyPayableBox))
        #expect(try store.latestOrder() == nil)
    }
}
