import Foundation
import SwiftData
import Testing
@testable import GnoshbotData

@Suite("SettlementWorker")
@MainActor
struct SettlementWorkerTests {
    private let payTo = "0x1111111111111111111111111111111111111111"
    private let orderId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
    private let itemId = "3fa85f64-5717-4562-b3fc-2c963f66afa6"

    @Test("place includes delivery snapshot, pays with X-PAYMENT, settles with eta still null")
    func placeConfirmPaySettles() async throws {
        let env = try makeEnv()
        let http = StepHTTP()
        http.enqueue { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "X-Customer-Id") == "cust-1")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") != nil)
            #expect(request.value(forHTTPHeaderField: "X-PAYMENT") == nil)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let delivery = body["delivery"] as! [String: Any]
            #expect(delivery["line1"] as? String == "14 Pine Street")
            #expect((delivery["lat"] as? NSNumber)?.doubleValue == 40.6944)
            #expect(body["cost"] == nil)
            #expect(body["total"] == nil)
            return try TestHTTP.json(
                ["orderId": self.orderId, "payTo": self.payTo, "status": "draft"],
                status: 201,
                url: request.url!,
                headers: ["Location": "http://shop.test/\(ShopPrefix.demo)/orders/\(self.orderId)"]
            )
        }
        http.enqueue { request in
            #expect(request.value(forHTTPHeaderField: "X-PAYMENT") == nil)
            return try TestHTTP.json(self.challengeJSON(), status: 402, url: request.url!)
        }
        http.enqueue { request in
            #expect(request.value(forHTTPHeaderField: "X-PAYMENT") != nil)
            #expect(request.value(forHTTPHeaderField: "PAYMENT-SIGNATURE") == nil)
            let header = request.value(forHTTPHeaderField: "X-PAYMENT")!
            let json = String(data: Data(base64Encoded: header)!, encoding: .utf8)!
            #expect(json.contains("base-sepolia"))
            return try TestHTTP.json(
                [
                    "orderId": self.orderId,
                    "settlementStatus": "paid",
                    "logisticsStatus": "awaiting_kitchen",
                    "etaMinutes": NSNull(),
                    "paymentTxHash": "0xabc",
                ],
                status: 201,
                url: request.url!,
                headers: ["Location": "http://shop.test/\(ShopPrefix.demo)/orders/\(self.orderId)/fulfillment"]
            )
        }
        let outcome = try await env.worker(http: http).run(pick: env.pick, delivery: env.home)
        #expect(outcome.status == .settled)
        #expect(outcome.etaMinutes == nil)
        #expect(outcome.trackingUrl?.contains("/fulfillment") == true)
        #expect(try env.store.latestOrder()?.status == .settled)
        #expect(try env.store.latestOrder()?.etaMinutes == nil)
        #expect(env.notes.box.copies == [.paidKitchenOnIt])
    }

    @Test("refuses an empty delivery line")
    func missingDelivery() async throws {
        let env = try makeEnv()
        env.home.line1 = "   "
        await #expect(throws: SettlementError.missingDelivery) {
            try await env.worker(http: StepHTTP()).run(pick: env.pick, delivery: env.home)
        }
    }

    @Test("refuses Base mainnet challenge when the shop is sepolia")
    func networkMustMatchShop() async throws {
        let env = try makeEnv()
        let http = happyPlaceThen(env) { request in
            var body = self.challengeJSON()
            var accepts = (body["accepts"] as! [[String: Any]])[0]
            accepts["network"] = "base"
            body["accepts"] = [accepts]
            return try TestHTTP.json(body, status: 402, url: request.url!)
        }
        await #expect(throws: SettlementError.networkMismatch(shop: "base-sepolia", challenge: "base")) {
            try await env.worker(http: http).run(pick: env.pick, delivery: env.home)
        }
        #expect(try env.store.latestOrder()?.status == .failed)
    }

    @Test("402 after sign does not auto-resign")
    func facilitatorRejectAfterSign() async throws {
        let env = try makeEnv()
        let http = happyPlaceThen(env) { request in
            try TestHTTP.json(self.challengeJSON(), status: 402, url: request.url!)
        }
        http.enqueue { request in
            #expect(request.value(forHTTPHeaderField: "X-PAYMENT") != nil)
            return try TestHTTP.json(
                ["x402Version": 1, "error": "verification_failed", "accepts": []],
                status: 402,
                url: request.url!
            )
        }
        await #expect(throws: SettlementError.self) {
            try await env.worker(http: http).run(pick: env.pick, delivery: env.home)
        }
        #expect(env.notes.box.copies.last == .launchAborted(reason: "Payment rejected"))
        #expect(http.requests.filter { $0.value(forHTTPHeaderField: "X-PAYMENT") != nil }.count == 1)
    }

    @Test("draft TTL 409 uses hold-expired copy")
    func draftExpired() async throws {
        let env = try makeEnv()
        let http = happyPlaceThen(env) { request in
            try TestHTTP.json(["title": "Conflict", "detail": "expired"], status: 409, url: request.url!)
        }
        await #expect(throws: SettlementError.draftExpired) {
            try await env.worker(http: http).run(pick: env.pick, delivery: env.home)
        }
        #expect(env.notes.box.copies.last == .holdExpired)
    }

    @Test("stale launching retries place with the same Idempotency-Key")
    func staleLaunchingRetriesPlace() async throws {
        let env = try makeEnv()
        let row = try env.store.insertLaunching(pick: env.pick, delivery: env.home)
        let key = row.idempotencyKey
        row.timestamp = Date().addingTimeInterval(-20)
        try env.store.persist()
        let http = StepHTTP()
        http.enqueue { request in
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == key)
            return try TestHTTP.json(
                ["orderId": self.orderId, "payTo": self.payTo],
                status: 201,
                url: request.url!
            )
        }
        http.enqueue { request in
            try TestHTTP.json(self.challengeJSON(), status: 402, url: request.url!)
        }
        http.enqueue { request in
            try TestHTTP.json(
                ["orderId": self.orderId, "settlementStatus": "paid", "logisticsStatus": "awaiting_kitchen"],
                status: 201,
                url: request.url!,
                headers: ["Location": "http://shop.test/fulfillment"]
            )
        }
        let outcome = try await env.worker(http: http).run(pick: env.pick, delivery: env.home)
        #expect(outcome.retriedPlace)
    }

    @Test("fulfillment GET with eta 22 writes cache and arriving push")
    func pollEta() async throws {
        let env = try makeEnv()
        let http = happyPathToPaid(env)
        http.enqueue { request in
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "X-Customer-Id") == "cust-1")
            return try TestHTTP.json(
                [
                    "orderId": self.orderId,
                    "settlementStatus": "paid",
                    "logisticsStatus": "dispatched",
                    "etaMinutes": 22,
                    "trackingToken": "tok_881a",
                ],
                status: 200,
                url: request.url!
            )
        }
        let poller = FulfillmentPoller(enabled: true, capSeconds: 0, sleep: { _ in }, now: Date.init)
        let outcome = try await env.worker(http: http, poller: poller).run(pick: env.pick, delivery: env.home)
        #expect(outcome.etaMinutes == 22)
        #expect(try env.store.latestOrder()?.status == .dispatched)
        #expect(env.notes.box.copies.contains(.arriving(minutes: 22)))
        #expect(env.notes.box.copies.contains(.paidKitchenOnIt))
    }

    @Test("kitchen overlay failed posts declined copy")
    func kitchenReject() async throws {
        let env = try makeEnv()
        let http = happyPathToPaid(env)
        http.enqueue { request in
            try TestHTTP.json(
                ["logisticsStatus": "failed", "settlementStatus": "paid"],
                status: 200,
                url: request.url!
            )
        }
        let poller = FulfillmentPoller(enabled: true, capSeconds: 1, sleep: { _ in }, now: Date.init)
        await #expect(throws: SettlementError.kitchenFailed) {
            try await env.worker(http: http, poller: poller).run(pick: env.pick, delivery: env.home)
        }
        #expect(env.notes.box.copies.last == .kitchenDeclinedRefundStarted)
        #expect(try env.store.latestOrder()?.status == .failed)
    }

    @Test("poll cap without eta never invents minutes")
    func pollCap() async throws {
        let env = try makeEnv()
        let http = happyPathToPaid(env)
        http.enqueue { request in
            try TestHTTP.json(
                ["logisticsStatus": "awaiting_kitchen", "etaMinutes": NSNull()],
                status: 200,
                url: request.url!
            )
        }
        let poller = FulfillmentPoller(enabled: true, capSeconds: 0, sleep: { _ in }, now: Date.init)
        let outcome = try await env.worker(http: http, poller: poller).run(pick: env.pick, delivery: env.home)
        #expect(outcome.etaMinutes == nil)
        #expect(try env.store.latestOrder()?.awaitingKitchenTime == true)
        let spoken = InquirySpeech.status(try #require(try env.store.latestOrder()))
        #expect(spoken == InquirySpeech.waitingOnKitchenTime)
        #expect(!spoken.contains("22"))
    }

    private func makeEnv() throws -> Env {
        let container = try GnoshbotPersistence.makeInMemoryContainer()
        let store = GnoshbotStore(container: container)
        store.fundedFlag = true
        store.remainingAllowanceUSDC = 25
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
        try context.save()
        let pick = CachedPick(
            overtureId: "ovr-1",
            shopPrefix: ShopPrefix.demo,
            menuItemId: itemId,
            merchantName: "Wrap Shop",
            itemName: "Burrito",
            costUsdcGuess: 14.5,
            payTo: payTo,
            x402Version: 1
        )
        let notes = CapturingNotifier()
        return Env(store: store, home: home, pick: pick, notes: notes)
    }

    private func challengeJSON() -> [String: Any] {
        [
            "x402Version": 1,
            "error": "X-PAYMENT header is required",
            "accepts": [[
                "scheme": "exact",
                "network": "base-sepolia",
                "maxAmountRequired": "14500000",
                "payTo": payTo,
                "asset": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
                "maxTimeoutSeconds": 300,
                "extra": ["name": "USDC", "version": "2"],
            ]],
        ]
    }

    private func happyPlaceThen(_ env: Env, confirm: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)) -> StepHTTP {
        let http = StepHTTP()
        http.enqueue { request in
            try TestHTTP.json(
                ["orderId": self.orderId, "payTo": self.payTo],
                status: 201,
                url: request.url!
            )
        }
        http.enqueue(confirm)
        return http
    }

    private func happyPathToPaid(_ env: Env) -> StepHTTP {
        let http = happyPlaceThen(env) { request in
            try TestHTTP.json(self.challengeJSON(), status: 402, url: request.url!)
        }
        http.enqueue { request in
            try TestHTTP.json(
                ["orderId": self.orderId, "settlementStatus": "paid", "logisticsStatus": "awaiting_kitchen"],
                status: 201,
                url: request.url!,
                headers: ["Location": "http://shop.test/\(ShopPrefix.demo)/orders/\(self.orderId)/fulfillment"]
            )
        }
        return http
    }
}

@MainActor
private struct Env {
    var store: GnoshbotStore
    var home: DeliveryLocation
    var pick: CachedPick
    var notes: CapturingNotifier

    func worker(http: StepHTTP, poller: FulfillmentPoller = .skip) -> SettlementWorker {
        SettlementWorker(
            http: http,
            store: store,
            config: ShopRuntimeConfig(
                baseURL: URL(string: "http://shop.test")!,
                x402Network: .baseSepolia,
                customerId: "cust-1",
                remainingAllowanceAtomic: UsdcWire.atomic(usdc: 25)
            ),
            signer: FixtureExactSigner(),
            notifier: notes,
            poller: poller
        )
    }
}

private final class StepHTTP: HTTPPerforming, @unchecked Sendable {
    var steps: [(URLRequest) throws -> (Data, HTTPURLResponse)] = []
    var requests: [URLRequest] = []

    func enqueue(_ step: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)) {
        steps.append(step)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !steps.isEmpty else { throw SettlementError.unexpectedRequest }
        let step = steps.removeFirst()
        let (data, response) = try step(request)
        return (data, response)
    }
}
