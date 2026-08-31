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

    @Test("empty payable box after yes still On it then push")
    func emptyBoxAfterYes() async throws {
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
        #expect(copy == .onIt)
        #expect(try store.latestOrder()?.status == .launching)
        let box = CapturingNotifier.Box()
        let outcome = try await LaunchFollowThrough.run(
            store: store,
            delivery: home,
            notifier: CapturingNotifier(box: box)
        )
        #expect(outcome == .failed(.emptyPayableBox))
        #expect(try store.latestOrder()?.status == .failed)
        #expect(box.copies == [.emptyPayableBox])
    }

    @Test("yes with payable cache inserts launching and speaks On it without X-PAYMENT")
    func yesInsertsLaunching() async throws {
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
        context.insert(
            RestaurantCache(
                overtureId: "demo.place.brooklyn.wrap",
                name: "Demo Kitchen (wrap)",
                latitude: 40.6944,
                longitude: -73.9903,
                integration: "proxy_wrapped",
                shopOriginHost: ShopPrefix.demoHost,
                shopLocationId: ShopPrefix.demoLocation,
                x402Version: 1
            )
        )
        let json = MenuDocument.bundledDemoJSON()
        context.insert(
            MenuCache(
                shopPrefix: ShopPrefix.demo,
                json: json,
                sha256: MenuDocument.sha256Hex(json)
            )
        )
        try context.save()

        let result = try OrderLunchLaunch.afterConfirmation(
            confirmed: true,
            delivery: home,
            store: store
        )
        #expect(result == .onIt)
        #expect(OrderLunchLaunch.onIt == "On it.")
        let order = try store.latestOrder()
        #expect(order?.status == .launching)
        #expect(order?.deliveryLocationId == home.id)
        #expect(order?.itemName == "")
        let box = CapturingNotifier.Box()
        let outcome = try await LaunchFollowThrough.run(
            store: store,
            delivery: home,
            notifier: CapturingNotifier(box: box)
        )
        guard case .picked(let pick) = outcome else {
            Issue.record("expected pick")
            return
        }
        #expect(pick.itemName.isEmpty == false)
        #expect(try store.latestOrder()?.itemName == pick.itemName)
        #expect(box.copies.isEmpty)
    }

    @Test("pick slower than 400ms still inserts launching with deferred pick")
    func deferPickStillOnIt() async throws {
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
        context.insert(
            RestaurantCache(
                overtureId: "demo.place.brooklyn.wrap",
                name: "Demo Kitchen (wrap)",
                latitude: 40.6944,
                longitude: -73.9903,
                integration: "proxy_wrapped",
                shopOriginHost: ShopPrefix.demoHost,
                shopLocationId: ShopPrefix.demoLocation,
                x402Version: 1
            )
        )
        try context.save()

        let result = try await OrderLunchLaunch.afterConfirmationWithBudget(
            confirmed: true,
            delivery: home,
            store: store,
            budgetNanoseconds: 50_000_000,
            pick: {
                Thread.sleep(forTimeInterval: 0.2)
                return .pick(
                    CachedPick(
                        overtureId: "demo.place.brooklyn.wrap",
                        shopPrefix: ShopPrefix.demo,
                        menuItemId: "x",
                        merchantName: "should not wait",
                        itemName: "deferred",
                        costUsdcGuess: 1
                    )
                )
            }
        )
        #expect(result == .onIt)
        #expect(try store.latestOrder()?.shopPrefix == "")
        #expect(try store.latestOrder()?.itemName == "")
        #expect(try store.latestOrder()?.status == .launching)
    }

    @Test("Bio-Shield empty after yes is a push not a spoken abort")
    func bioShieldAfterYes() async throws {
        let store = try makeStore()
        store.profile = ProfileEnvelope(allergens: ["peanut", "dairy", "wheat / gluten", "fish", "sesame"])
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
        context.insert(
            RestaurantCache(
                overtureId: "demo.place.brooklyn.wrap",
                name: "Demo Kitchen (wrap)",
                latitude: 40.6944,
                longitude: -73.9903,
                integration: "proxy_wrapped",
                shopOriginHost: ShopPrefix.demoHost,
                shopLocationId: ShopPrefix.demoLocation,
                x402Version: 1
            )
        )
        let json = MenuDocument.bundledDemoJSON()
        context.insert(
            MenuCache(
                shopPrefix: ShopPrefix.demo,
                json: json,
                sha256: MenuDocument.sha256Hex(json)
            )
        )
        try context.save()
        _ = try OrderLunchLaunch.afterConfirmation(confirmed: true, delivery: home, store: store)
        let box = CapturingNotifier.Box()
        let outcome = try await LaunchFollowThrough.run(
            store: store,
            delivery: home,
            notifier: CapturingNotifier(box: box)
        )
        #expect(outcome == .failed(.bioShieldEmptiesBox))
        #expect(try store.latestOrder()?.status == .failed)
        #expect(box.copies == [.bioShieldEmptiesBox])
    }
}
