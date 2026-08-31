import Foundation
import SwiftData
import Testing
@testable import GnoshbotData

@Suite("CacheHydrator")
@MainActor
struct CacheHydratorTests {
    @Test("fixture menu lands in MenuCache and sandbox prefixes are rejected")
    func fixtureAndSandbox() async throws {
        let container = try GnoshbotPersistence.makeInMemoryContainer()
        let store = GnoshbotStore(container: container)
        let settings = ControlPlaneSettings(
            baseURL: URL(string: "https://demo.example")!,
            isDemo: true
        )
        let regionData = try JSONSerialization.data(withJSONObject: [
            "tile": ["status": "ready", "restaurants": 2],
            "payablePrefixes": [
                [
                    "overture_id": "demo.place.brooklyn.wrap",
                    "name": "Demo Kitchen (wrap)",
                    "shop_origin_host": "demo-shop.gnoshbot.com",
                    "shop_location_id": "testflight",
                    "x402_version": 1,
                ],
                [
                    "overture_id": "sandbox.poi",
                    "name": "TTL Shop",
                    "shop_origin_host": "shop.example",
                    "shop_location_id": "/_sandbox/abc",
                    "x402_version": 1,
                ],
            ],
        ] as [String: Any])
        let http = ScriptedHTTP { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (regionData, response)
        }
        let hydrator = CacheHydrator(settings: settings, http: http)
        try await hydrator.hydrate(geohash5: "dr5rs", into: store)

        let context = try store.modelContext
        let restaurants = try context.fetch(FetchDescriptor<RestaurantCache>())
        #expect(restaurants.map(\.overtureId) == ["demo.place.brooklyn.wrap"])
        #expect(restaurants.first?.integration == "proxy_wrapped")
        let menus = try context.fetch(FetchDescriptor<MenuCache>())
        #expect(menus.count == 1)
        #expect(menus.first?.shopPrefix == ShopPrefix.demo)
        let parsed = try MenuDocument.parse(json: menus.first!.json)
        #expect(parsed.items.count <= 10)
        #expect(parsed.items.contains { $0.name == "Garden Bowl" })
        #expect(!ShopPrefix.isSandbox(ShopPrefix.demo))
        #expect(ShopPrefix.isSandbox("shop.example/_sandbox/abc"))
    }
}
