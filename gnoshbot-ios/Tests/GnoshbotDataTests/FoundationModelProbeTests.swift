import Foundation
import Testing
@testable import GnoshbotData

@Suite("FoundationModelProbe")
struct FoundationModelProbeTests {
    @Test("timeout wins over a stuck operation")
    func timeout() async {
        await #expect(throws: AsyncTimeoutError.timedOut) {
            try await AsyncTimeout.firstCompleted(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "done"
            }
        }
    }

    @Test("fast operation beats the timeout")
    func completes() async throws {
        let value = try await AsyncTimeout.firstCompleted(seconds: 1) {
            "ok"
        }
        #expect(value == "ok")
    }

    @Test("in-flight row becomes abandoned after reconcile")
    func abandoned() {
        let suite = "gnoshbot.test.fm.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let snapshot = FoundationModelProbeSnapshot(
            startedAt: Date().addingTimeInterval(-30),
            finishedAt: nil,
            outcome: .inFlight,
            durationMs: nil,
            detail: "respond"
        )
        FoundationModelProbe.persist(snapshot, to: defaults)
        let abandoned = FoundationModelProbe.reconcileAbandonedInFlight(defaults: defaults)
        #expect(abandoned?.outcome == .abandonedInFlight)
        #expect(abandoned?.summaryLine.contains("never finished") == true)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("gate is single-flight")
    func gate() async {
        let gate = FoundationModelGate()
        #expect(await gate.tryBegin())
        #expect(await gate.tryBegin() == false)
        await gate.end()
        #expect(await gate.tryBegin())
        await gate.end()
    }

    @Test("model JSON keeps a legal id and reason")
    func parseReason() {
        let parsed = ModelPickJSON.parse(
            """
            here you go
            {"menuItemId":"med-lamb","reason":"You asked for mediterranean and medium spice."}
            """
        )
        #expect(parsed?.menuItemId == "med-lamb")
        #expect(parsed?.reason.contains("mediterranean") == true)
    }

    @Test("pasted legal-line menuItemId still resolves")
    func pastedLineId() {
        let blob = "id=it-pepperoni restaurant=Pine Street Pasta item=Pepperoni Pie cuising=italian,pizza spice=medium desc=tomato,mozzarella, pepperoni"
        #expect(
            ModelPickJSON.legalMenuItemId(blob, legal: ["med-lamb", "it-pepperoni"]) == "it-pepperoni"
        )
        #expect(ModelPickJSON.legalMenuItemId("it-pepperoni", legal: ["it-pepperoni"]) == "it-pepperoni")
        #expect(ModelPickJSON.legalMenuItemId("nope", legal: ["it-pepperoni"]) == nil)
    }

    @Test("one-word spice is not a usable reason")
    func stubReason() {
        #expect(ModelPickJSON.usableReason("mild") == nil)
        #expect(ModelPickJSON.usableReason("Thai") == nil)
        #expect(ModelPickJSON.usableReason("ok") == nil)
        #expect(
            ModelPickJSON.usableReason(
                "Lamb kebab from Harbor Grill fits mediterranean at medium spice."
            ) != nil
        )
    }
}
