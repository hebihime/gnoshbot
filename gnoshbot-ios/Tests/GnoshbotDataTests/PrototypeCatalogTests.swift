import Foundation
import SwiftData
import Testing
@testable import GnoshbotData

@Suite("PrototypeCatalog")
@MainActor
struct PrototypeCatalogTests {
    @Test("bundled neighborhood has multiple kitchens and hydrate needs no HTTP")
    func catalogHydrates() async throws {
        let loaded = try PrototypeCatalog.load()
        #expect(loaded.geohash5 == "dr5rs")
        #expect(loaded.kitchens.count >= 6)

        let container = try GnoshbotPersistence.makeInMemoryContainer()
        let store = GnoshbotStore(container: container)
        try await PrototypeCatalog.hydrate(into: store)
        let kitchens = try store.restaurantSnapshots()
        #expect(kitchens.count >= 6)
        #expect(kitchens.contains { $0.overtureId == "demo.place.brooklyn.wrap" })
        let menus = try store.menuDocuments()
        #expect(menus.count >= 6)
    }

    @Test("illegal model ids are rejected")
    func illegalId() throws {
        let json = MenuDocument.bundledDemoJSON()
        let menu = try MenuDocument.parse(json: json)
        let kitchen = RestaurantSnapshot(
            overtureId: "demo.place.brooklyn.wrap",
            name: "Demo Kitchen (wrap)",
            latitude: 40.6944,
            longitude: -73.9903,
            integration: "proxy_wrapped",
            shopPrefix: ShopPrefix.demo,
            cuisineTags: ["american"]
        )
        let set = LunchScorer.workingSet(
            restaurants: [kitchen],
            menus: [ShopPrefix.demo: menu],
            latitude: 40.6944,
            longitude: -73.9903,
            profile: .empty,
            remainingAllowanceUSDC: 25
        )
        guard case .items(let survivors) = set else {
            Issue.record("expected survivors")
            return
        }
        #expect(LunchScorer.pickIfLegal(itemId: "not-a-real-id", from: survivors) == nil)
        #expect(LunchScorer.pickIfLegal(itemId: survivors[0].item.id, from: survivors) != nil)
    }
}
