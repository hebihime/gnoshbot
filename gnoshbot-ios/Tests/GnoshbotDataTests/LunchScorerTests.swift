import Foundation
import Testing
@testable import GnoshbotData

@Suite("LunchScorer")
struct LunchScorerTests {
    private func home() -> DeliveryLocation {
        DeliveryLocation(
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
    }

    private func kitchen() -> RestaurantSnapshot {
        RestaurantSnapshot(
            overtureId: "demo.place.brooklyn.wrap",
            name: "Demo Kitchen (wrap)",
            latitude: 40.6944,
            longitude: -73.9903,
            integration: "proxy_wrapped",
            shopPrefix: ShopPrefix.demo,
            cuisineTags: ["american"]
        )
    }

    @Test("empty shield does not allergen-filter; peanut shield drops satay")
    func peanutAndEmpty() throws {
        let json = MenuDocument.bundledDemoJSON()
        let menu = try MenuDocument.parse(json: json)
        let delivery = home()
        let empty = LunchScorer.pick(
            restaurants: [kitchen()],
            menus: [ShopPrefix.demo: menu],
            near: delivery,
            profile: .empty,
            remainingAllowanceUSDC: 25
        )
        guard case .pick(let first) = empty else {
            Issue.record("expected pick, got \(empty)")
            return
        }
        #expect(first.itemName != "")
        #expect(first.shopPrefix == ShopPrefix.demo)

        let peanut = LunchScorer.pick(
            restaurants: [kitchen()],
            menus: [ShopPrefix.demo: menu],
            near: delivery,
            profile: ProfileEnvelope(allergens: ["peanut"]),
            remainingAllowanceUSDC: 25
        )
        guard case .pick(let second) = peanut else {
            Issue.record("expected pick after dropping satay")
            return
        }
        #expect(second.itemName != "Peanut Satay")

        let harsh = LunchScorer.pick(
            restaurants: [kitchen()],
            menus: [ShopPrefix.demo: menu],
            near: delivery,
            profile: ProfileEnvelope(allergens: ["peanut", "dairy", "wheat / gluten", "fish", "sesame"]),
            remainingAllowanceUSDC: 25
        )
        #expect(harsh == .bioShieldEmpty)
        #expect(LaunchCopy.bioShieldEmptiesBox.spoken == "Every nearby menu collides with your Bio-Shield. I won't guess.")
    }

    @Test("unknown ingredients fail closed when any allergen is set")
    func failClosedUnknown() {
        let item = MenuItemDocument(
            id: "mystery",
            name: "Chef special",
            description: "",
            priceCents: 1000
        )
        let menu = MenuDocument(merchantName: "X", items: [item])
        let result = LunchScorer.pick(
            restaurants: [kitchen()],
            menus: [ShopPrefix.demo: menu],
            near: home(),
            profile: ProfileEnvelope(allergens: ["peanut"]),
            remainingAllowanceUSDC: 25
        )
        #expect(result == .bioShieldEmpty)
    }
}
