import Foundation
import SwiftData
import Testing
@testable import GnoshbotData

@Suite("GnoshbotStore")
@MainActor
struct GnoshbotStoreTests {
    @Test("latestOrder returns the inserted ActiveOrderCache without HTTP")
    func latestOrderReturnsInsertedRow() throws {
        let container = try GnoshbotPersistence.makeInMemoryContainer()
        let store = GnoshbotStore(container: container)
        let context = try store.modelContext

        let home = DeliveryLocation(
            label: "Home",
            line1: "14 Pine Street",
            line2: "Apt 4",
            city: "Brooklyn",
            region: "NY",
            postalCode: "11201",
            country: "US",
            latitude: 40.6944,
            longitude: -73.9903,
            isDefault: true
        )
        context.insert(home)

        let order = ActiveOrderCache(
            orderId: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
            idempotencyKey: "550e8400-e29b-41d4-a716-446655440000",
            shopPrefix: "/pos.example.com/downtown",
            delivery: home
        )
        context.insert(order)
        try context.save()

        let latest = try store.latestOrder()
        #expect(latest?.orderId == order.orderId)
        #expect(latest?.deliveryLocationId == home.id)
        #expect(latest?.status == .launching)

        let defaults = try store.defaultDeliveryLocation()
        #expect(defaults?.id == home.id)
        #expect(try store.deliveryLocations().count == 1)
    }

    @Test("priorLunch skips the current row even when demo stays launching")
    func priorAndDelete() throws {
        let container = try GnoshbotPersistence.makeInMemoryContainer()
        let store = GnoshbotStore(container: container)
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

        let old = ActiveOrderCache(
            orderId: "old",
            idempotencyKey: "k-old",
            shopPrefix: "/demo",
            delivery: home
        )
        old.itemName = "Lamb Kebab"
        old.merchantName = "Harbor Grill"
        old.menuItemId = "med-lamb"
        old.status = .settled
        old.timestamp = Date().addingTimeInterval(-60)
        context.insert(old)

        let launching = ActiveOrderCache(
            orderId: "new",
            idempotencyKey: "k-new",
            shopPrefix: "/demo",
            delivery: home
        )
        launching.status = .launching
        launching.timestamp = Date()
        context.insert(launching)
        try context.save()

        #expect(try store.priorLunch()?.menuItemId == "med-lamb")
        try store.deleteAllOrders()
        #expect(try store.latestOrder() == nil)
        #expect(try store.priorLunch() == nil)
        #expect(try store.deliveryLocations().count == 1)
    }

    @Test("priorLunch sees the previous demo lunch that never left launching")
    func priorDemoLaunching() throws {
        let container = try GnoshbotPersistence.makeInMemoryContainer()
        let store = GnoshbotStore(container: container)
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

        let old = ActiveOrderCache(
            orderId: "old",
            idempotencyKey: "k-old",
            shopPrefix: "/demo",
            delivery: home
        )
        old.itemName = "Pepperoni Pie"
        old.merchantName = "Pine Street Pasta"
        old.menuItemId = "it-pepperoni"
        old.status = .launching
        old.timestamp = Date().addingTimeInterval(-60)
        context.insert(old)

        let launching = ActiveOrderCache(
            orderId: "new",
            idempotencyKey: "k-new",
            shopPrefix: "/demo",
            delivery: home
        )
        launching.status = .launching
        launching.timestamp = Date()
        context.insert(launching)
        try context.save()

        #expect(try store.priorLunch()?.menuItemId == "it-pepperoni")
    }
}
