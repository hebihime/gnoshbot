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
}
