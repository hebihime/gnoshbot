import Foundation
import SwiftData
import Testing
@testable import GnoshbotData

@Suite("DeliveryLocationEntity")
@MainActor
struct DeliveryLocationEntityTests {
    @Test("query resolves a saved row and returns empty for an unknown id")
    func queryResolvesSavedAndIgnoresUnknown() async throws {
        let container = try GnoshbotPersistence.makeInMemoryContainer()
        GnoshbotStore.shared.attach(container)
        let store = GnoshbotStore.shared
        let context = try store.modelContext

        let home = DeliveryLocation(
            label: "Home",
            line1: "14 Pine Street",
            line2: "apartment 4",
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

        let query = DeliveryLocationQuery()
        let found = try await query.entities(for: [home.id])
        #expect(found.count == 1)
        #expect(found.first?.spokenLine == "Home, 14 Pine Street, apartment 4, Brooklyn")

        let unknown = try await query.entities(for: [UUID()])
        #expect(unknown.isEmpty)
    }
}
