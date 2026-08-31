import Foundation
import SwiftData

/// Place + 402 confirm + shop v1 `X-PAYMENT`. Delivery snapshot is mandatory. Minutes are not spoken here.
@MainActor
public struct SettlementWorker {
    public var http: any HTTPPerforming
    public var store: GnoshbotStore
    public var config: ShopRuntimeConfig
    public var signer: any X402ExactSigning
    public var notifier: any SettlementNotifying
    public var poller: FulfillmentPoller
    public var clock: @Sendable () -> Date

    public init(
        http: any HTTPPerforming,
        store: GnoshbotStore,
        config: ShopRuntimeConfig,
        signer: any X402ExactSigning,
        notifier: any SettlementNotifying,
        poller: FulfillmentPoller = .skip,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.http = http
        self.store = store
        self.config = config
        self.signer = signer
        self.notifier = notifier
        self.poller = poller
        self.clock = clock
    }

    public func run(pick: CachedPick?, delivery: DeliveryLocation) async throws -> SettlementOutcome {
        guard !delivery.line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SettlementError.missingDelivery
        }

        let row = try existingOrInsert(delivery: delivery, pick: pick)
        let resolvedPick: CachedPick
        if let pick {
            resolvedPick = pick
        } else {
            switch try store.pickCachedCandidate(near: delivery) {
            case .pick(let local):
                resolvedPick = local
                row.shopPrefix = local.shopPrefix
                row.merchantName = local.merchantName
                row.itemName = local.itemName
            default:
                try await abort(row, SettlementError.missingPick, .launchAborted(reason: "No payable kitchen"))
            }
        }

        let now = clock()
        let retriedPlace = row.status == .launching
            && row.trackingUrl == nil
            && now.timeIntervalSince(row.timestamp) >= config.staleLaunchingRetryAfter

        do {
            let placed = try await place(pick: resolvedPick, delivery: delivery, row: row)
            row.orderId = placed.orderId
            row.shopPrefix = resolvedPick.shopPrefix
            row.merchantName = resolvedPick.merchantName
            row.itemName = resolvedPick.itemName
            row.markPlaced()
            try store.persist()

            let payTo = placed.payTo.isEmpty ? resolvedPick.payTo : placed.payTo
            if !resolvedPick.payTo.isEmpty, !addressesEqual(payTo, resolvedPick.payTo) {
                try await abort(row, SettlementError.payToMismatch, .launchAborted(reason: "PayTo mismatch"))
            }

            let confirmURL = shopURL(prefix: resolvedPick.shopPrefix, path: "orders/\(placed.orderId)/confirm")
            let first = try await confirm(url: confirmURL, paymentHeader: nil, pick: resolvedPick)

            if first.status == 409 {
                try await abort(row, SettlementError.draftExpired, .holdExpired)
            }
            if (200...299).contains(first.status) {
                return try await finishPaid(row: row, response: first, pick: resolvedPick, retriedPlace: retriedPlace)
            }
            guard first.status == 402 else {
                try await abort(row, SettlementError.missing402, .launchAborted(reason: "Unexpected confirm"))
            }

            let challenge = try X402V1.parseChallenge(first.body)
            guard let accepts = challenge.accepts.first else {
                try await abort(row, SettlementError.noAccepts, .launchAborted(reason: "Payment rejected"))
            }

            do {
                try assertPayable(accepts: accepts, placePayTo: payTo)
            } catch let error as SettlementError {
                try await abort(row, error, .launchAborted(reason: "Payment rejected"))
            }

            let header = try signer.paymentHeader(accepts: accepts, now: clock())
            let paid = try await confirm(url: confirmURL, paymentHeader: header, pick: resolvedPick)

            if paid.status == 402 {
                let after = try? X402V1.parseChallenge(paid.body)
                try await abort(
                    row,
                    SettlementError.facilitatorRejected(after?.error ?? "Payment rejected"),
                    .launchAborted(reason: "Payment rejected")
                )
            }
            if paid.status == 409 {
                try await abort(row, SettlementError.draftExpired, .holdExpired)
            }
            guard (200...299).contains(paid.status) else {
                try await abort(row, SettlementError.facilitatorRejected("confirm \(paid.status)"), .launchAborted(reason: "Payment rejected"))
            }

            if let atomic = accepts.amountAtomic {
                row.costUsdc = UsdcWire.usdc(atomic: atomic)
            }
            return try await finishPaid(row: row, response: paid, pick: resolvedPick, retriedPlace: retriedPlace)
        } catch let error as SettlementError {
            throw error
        } catch {
            row.markFailed(PushCopy.launchAborted(reason: "Payment rejected").body)
            try? store.persist()
            await notifier.notify(.launchAborted(reason: "Payment rejected"))
            throw error
        }
    }

    private func finishPaid(
        row: ActiveOrderCache,
        response: RawHTTP,
        pick: CachedPick,
        retriedPlace: Bool
    ) async throws -> SettlementOutcome {
        let location = header(response.headers, "Location")
        let snapshot = try? FulfillmentSnapshot.parse(response.body)
        let tracking = location
            ?? snapshot?.locationUri
            ?? shopURL(prefix: pick.shopPrefix, path: "orders/\(row.orderId)/fulfillment").absoluteString
        row.markSettled(trackingUrl: tracking, settlementTxHash: snapshot?.paymentTxHash)
        try store.persist()
        await notifier.notify(.paidKitchenOnIt)

        if poller.enabled, let trackingURL = URL(string: tracking) {
            try await poll(row: row, fulfillmentURL: trackingURL)
        }

        return SettlementOutcome(
            status: row.status,
            trackingUrl: row.trackingUrl,
            etaMinutes: row.etaMinutes,
            settlementTxHash: row.settlementTxHash,
            retriedPlace: retriedPlace
        )
    }

    private func poll(row: ActiveOrderCache, fulfillmentURL: URL) async throws {
        let started = clock()
        var lastLogistics = ""
        var announcedEta = false
        while true {
            var request = URLRequest(url: fulfillmentURL)
            request.httpMethod = "GET"
            request.setValue(config.customerId, forHTTPHeaderField: "X-Customer-Id")
            let (data, response) = try await http.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                let snap = try FulfillmentSnapshot.parse(data)
                lastLogistics = snap.logisticsStatus
                let firstEta = row.etaMinutes == nil && snap.etaMinutes != nil
                row.applyFulfillment(
                    logisticsStatus: snap.logisticsStatus,
                    etaMinutes: snap.etaMinutes,
                    trackingToken: snap.trackingToken,
                    trackingUrl: snap.locationUri
                )
                if snap.logisticsStatus == "failed" {
                    row.markFailed(PushCopy.kitchenDeclinedRefundStarted.body)
                    try store.persist()
                    await notifier.notify(.kitchenDeclinedRefundStarted)
                    throw SettlementError.kitchenFailed
                }
                try store.persist()
                if firstEta, let eta = snap.etaMinutes {
                    announcedEta = true
                    await notifier.notify(.arriving(minutes: eta))
                } else if announcedEta, snap.logisticsStatus == "dispatched", let eta = snap.etaMinutes {
                    await notifier.notify(.onTheWay(minutes: eta))
                }
                if FulfillmentPollSchedule.isTerminal(logisticsStatus: snap.logisticsStatus) {
                    return
                }
            }

            let elapsed = clock().timeIntervalSince(started)
            let delay = FulfillmentPollSchedule.delaySeconds(
                elapsed: elapsed,
                etaKnown: row.etaMinutes != nil,
                terminal: FulfillmentPollSchedule.isTerminal(logisticsStatus: lastLogistics),
                cap: poller.capSeconds
            )
            guard let delay else {
                if row.etaMinutes == nil {
                    row.awaitingKitchenTime = true
                    try store.persist()
                }
                return
            }
            try await poller.sleep(delay)
        }
    }

    private func assertPayable(accepts: X402V1.Accepts, placePayTo: String) throws {
        guard addressesEqual(accepts.payTo, placePayTo) else {
            throw SettlementError.payToMismatch
        }
        guard let challengeNet = X402Network.parse(accepts.network) else {
            throw SettlementError.networkMismatch(shop: config.x402Network.rawValue, challenge: accepts.network)
        }
        guard challengeNet == config.x402Network else {
            throw SettlementError.networkMismatch(shop: config.x402Network.rawValue, challenge: accepts.network)
        }
        guard let atomic = accepts.amountAtomic else {
            throw SettlementError.amountExceedsAllowance
        }
        if atomic > config.remainingAllowanceAtomic {
            throw SettlementError.amountExceedsAllowance
        }
        if atomic > config.shopMaxOrderAtomic {
            throw SettlementError.amountExceedsShopCap
        }
    }

    private func place(pick: CachedPick, delivery: DeliveryLocation, row: ActiveOrderCache) async throws -> PlaceResult {
        var request = URLRequest(url: shopURL(prefix: pick.shopPrefix, path: "orders"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.customerId, forHTTPHeaderField: "X-Customer-Id")
        request.setValue(row.idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try PlaceBody.encode(pick: pick, delivery: delivery)
        let (data, response) = try await http.data(for: request)
        let http = try requireHTTP(response)
        guard (200...299).contains(http.statusCode) else {
            throw SettlementError.badResponse
        }
        return try PlaceResult.parse(data: data, headers: headerMap(http))
    }

    private func confirm(url: URL, paymentHeader: String?, pick: CachedPick) async throws -> RawHTTP {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.customerId, forHTTPHeaderField: "X-Customer-Id")
        if let paymentHeader {
            request.setValue(paymentHeader, forHTTPHeaderField: X402V1.paymentHeaderField(for: pick))
        }
        let (data, response) = try await http.data(for: request)
        let http = try requireHTTP(response)
        return RawHTTP(status: http.statusCode, headers: headerMap(http), body: data)
    }

    private func existingOrInsert(delivery: DeliveryLocation, pick: CachedPick?) throws -> ActiveOrderCache {
        if let latest = try store.latestOrder(),
           latest.deliveryLocationId == delivery.id,
           latest.status == .launching,
           latest.trackingUrl == nil
        {
            return latest
        }
        return try store.insertLaunching(pick: pick, delivery: delivery)
    }

    private func abort(_ row: ActiveOrderCache, _ error: SettlementError, _ push: PushCopy) async throws -> Never {
        row.markFailed(push.body)
        try store.persist()
        await notifier.notify(push)
        throw error
    }

    private func shopURL(prefix: String, path: String) -> URL {
        let base = config.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let p = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rest = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/\(p)/\(rest)")!
    }

    private func requireHTTP(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw SettlementError.badResponse }
        return http
    }
}

private func addressesEqual(_ a: String, _ b: String) -> Bool {
    a.lowercased() == b.lowercased()
}

private func header(_ headers: [String: String], _ name: String) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
}

private func headerMap(_ response: HTTPURLResponse) -> [String: String] {
    var result: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
        if let k = key as? String, let v = value as? String {
            result[k] = v
        }
    }
    return result
}

private struct RawHTTP {
    var status: Int
    var headers: [String: String]
    var body: Data
}

private struct PlaceResult {
    var orderId: String
    var payTo: String

    static func parse(data: Data, headers: [String: String]) throws -> PlaceResult {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettlementError.badResponse
        }
        let id = (obj["orderId"] as? String)
            ?? (obj["order_id"] as? String)
            ?? header(headers, "Location").flatMap { URL(string: $0)?.lastPathComponent }
        let payTo = (obj["payTo"] as? String) ?? (obj["pay_to"] as? String) ?? ""
        guard let id, !id.isEmpty else { throw SettlementError.badResponse }
        return PlaceResult(orderId: id, payTo: payTo)
    }
}

enum PlaceBody {
    static func encode(pick: CachedPick, delivery: DeliveryLocation) throws -> Data {
        var deliveryObj: [String: Any] = [
            "label": delivery.label,
            "line1": delivery.line1,
            "city": delivery.city,
            "region": delivery.region,
            "postalCode": delivery.postalCode,
            "country": delivery.country,
            "lat": delivery.latitude,
            "lon": delivery.longitude,
        ]
        if let line2 = delivery.line2 {
            deliveryObj["line2"] = line2
        }
        let body: [String: Any] = [
            "lines": [
                [
                    "menuItemId": pick.menuItemId,
                    "quantity": pick.quantity,
                    "modifierIds": pick.modifierIds,
                ],
            ],
            "delivery": deliveryObj,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }
}
