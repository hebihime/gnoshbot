import Foundation
import Testing
@testable import GnoshbotData

@Suite("RegionEnsureClient")
struct RegionEnsureClientTests {
    @Test("saving Home posts ensure with finite bbox and idempotency grain")
    func ensureKeyAndBBox() async throws {
        let settings = ControlPlaneSettings(
            baseURL: URL(string: "https://demo.example")!,
            overtureRelease: "2026-08-19.0",
            isDemo: true
        )
        let user = "usr-test"
        let capture = RequestCapture()
        let http = ScriptedHTTP { request in
            capture.request = request
            return try TestHTTP.json(
                ["status": "ready", "restaurants": 2],
                status: 200,
                url: request.url!
            )
        }
        let client = RegionEnsureClient(settings: settings, http: http, opaqueUser: user)
        let result = try await client.ensureSavedAddress(
            latitude: BrooklynDemoAddress.latitude,
            longitude: BrooklynDemoAddress.longitude
        )
        #expect(result.status == .ready)
        #expect(result.restaurants == 2)
        let request = try #require(capture.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path.hasSuffix("/regions/ensure") == true)
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "usr-test:dr5rs:2026-08-19.0")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        #expect(body?["reason"] as? String == "saved_address")
        #expect(body?["min_lat"] is Double)
        #expect((body?["min_lat"] as? Double)?.isFinite == true)
        #expect((body?["max_lon"] as? Double)?.isFinite == true)
    }
}
