import Foundation
import SwiftData
import Testing
@testable import GnoshbotData

@Suite("Address save")
@MainActor
struct AddressSaveTests {
    @Test("unique label is enforced and geocode failure refuses save")
    func uniqueAndGeocode() async throws {
        let container = try GnoshbotPersistence.makeInMemoryContainer()
        let store = GnoshbotStore(container: container)
        let draft = AddressDraft.brooklynHome
        let geocoder = CoordinateGeocoder(
            latitude: BrooklynDemoAddress.latitude,
            longitude: BrooklynDemoAddress.longitude
        )
        let coords = try await geocoder.geocode(draft)
        let saved = try store.saveAddress(draft: draft, latitude: coords.latitude, longitude: coords.longitude)
        #expect(saved.latitude == BrooklynDemoAddress.latitude)
        #expect(saved.longitude == BrooklynDemoAddress.longitude)
        #expect(saved.isDefault)

        do {
            _ = try store.saveAddress(
                draft: draft,
                latitude: coords.latitude,
                longitude: coords.longitude
            )
            Issue.record("expected duplicate label")
        } catch let error as AddressSaveError {
            #expect(error == .duplicateLabel)
        }

        let failing = CoordinateGeocoder(latitude: 0, longitude: 0, shouldFail: true)
        do {
            _ = try await failing.geocode(draft)
            Issue.record("expected geocode fail")
        } catch let error as AddressSaveError {
            #expect(error == .geocodeFailed)
        }
        #expect(try store.deliveryLocations().count == 1)
        #expect(AddressCopy.emptyState == "Gnoshbot will always ask before sending food. Add Home to start.")
    }
}
