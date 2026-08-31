# GROK.md — Gnoshbot engineering blueprint

Enforcement layer for **this** repo. When this file and any other Gnoshbot file disagree, **this file wins** unless the other file is a newer dated supersession in `PRODUCT_DECISIONS.md`.

The ordering host at `~/Repos/web3-restaurant-api` has its **own** `GROK.md`. That file still wins inside that tree. Do not edit `TransitionTo`, wrap x402 in `ChargeAsync`, promote sandboxes, or invent kitchen tuples from here. File a `DECISIONS.md` entry there for the fulfillment overlay specified below, then implement it there.

Official product name: **Gnoshbot**.

---

## Source of Truth Register

Every architectural assertion Gnoshbot is allowed to depend on, paired with the official page that attests or **corrects** it.

| ID | Decision / fact | Verdict | Official source |
| --- | --- | --- | --- |
| T01 | Overture GeoParquet catalog lives in AWS region **us-west-2**, bucket `overturemaps-us-west-2`. | **Correct.** Not us-east-1. | [Overture cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/) |
| T02 | Places path: `s3://overturemaps-us-west-2/release/<RELEASE>/theme=places/type=place/*.parquet` with `<RELEASE>` = `yyyy-mm-dd.x`. | **Correct.** Current worked example `2026-08-19.0`. | [Overture DuckDB](https://docs.overturemaps.org/getting-data/duckdb/), [cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/) |
| T03 | Azure twin is `overturemapswestus2` in West US 2, not a substitute for AWS region colocation. | **Correct.** | [cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/) |
| T04 | S3 → any AWS service **in the same Region** is $0 data transfer (GET request charges still apply). Cross-region is billed (Oregon → N. Virginia example $0.02/GB). | **Correct.** Therefore ingest Lambda/ECS **must** be us-west-2. | [Amazon S3 pricing — Data transfer](https://aws.amazon.com/s3/pricing/) |
| T05 | Registry of Open Data lists the same bucket, region us-west-2, anonymous list. | **Correct.** | [registry.opendata.aws/overture](https://registry.opendata.aws/overture/) |
| T06 | `categories` on places is deprecated, removal **September 2026**. Use `basic_category` + `taxonomy`. | **Correct.** Dual-read until then. There is no `categories.main`. | [Places overview](https://docs.overturemaps.org/guides/places/) |
| T07 | `operating_status` is not opening hours. | **Correct.** | [Place schema](https://docs.overturemaps.org/schema/reference/places/place/) |
| T08 | DuckDB `httpfs` range-reads Parquet over HTTP(S)/S3. | **Correct.** | [DuckDB HTTP(S)](https://duckdb.org/docs/current/core_extensions/httpfs/https.html), [S3 API](https://duckdb.org/docs/current/core_extensions/httpfs/s3api.html) |
| T09 | Efficient bbox extract requires **literal `bbox.*` predicates**. `ST_Intersects` alone does not prune GeoParquet row groups in DuckDB. | **Correct.** | [Overture DuckDB](https://docs.overturemaps.org/getting-data/duckdb/), [Dunnington 2025](https://dewey.dunnington.ca/post/2025/lazy-geoparquet-reading-in-sedonadb-duckdb-geopandas-and-gdal/) |
| T10 | Lambda: max timeout **900 s**, memory 128–10240 MB, `/tmp` 512–10240 MB, sync payload 6 MB. | **Correct.** Ingest is a worker, not a 200 ms API. | [Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html) |
| T11 | App Intents have **30 seconds** of CPU on iOS. Siri may impose a shorter wait for a spoken result. macOS: no fixed limit. | **Correct.** | [Forums 832257 (Frameworks Engineer)](https://developer.apple.com/forums/thread/832257), [WWDC26 345](https://developer.apple.com/videos/play/wwdc2026/345/), [Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent) |
| T12 | `LongRunningIntent` + `performBackgroundTask` extends past 30 s and presents a **system Live Activity**. Pair with `CancellableIntent`. | **Correct.** Do **not** use for silent launch. | [Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent), [WWDC26 345](https://developer.apple.com/videos/play/wwdc2026/345/) |
| T13 | `BGAppRefreshTask`: up to **30 seconds**, system-scheduled, **not guaranteed**. | **Correct.** | [Choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app), [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask) |
| T14 | `beginBackgroundTask` grants a **limited** continuation; expiration handler must end the assertion or the app is killed. | **Correct.** | [Extending background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time) |
| T15 | There is no general-purpose "run forever in the background." Force-quit disables refresh. | **Correct.** `Task.detached` is not a scheduler. | [iOS background execution limits](https://developer.apple.com/forums/thread/685525) |
| T16 | `supportedModes` can request `.background`. | **Correct.** Prefer background; run in the **app** process. | [supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes-5zhmb) |
| T17 | Significant-change location uses cell/Wi-Fi, relaunches a terminated app on new events. | **Correct.** Not a 5-mile GPS fence. | [startMonitoringSignificantLocationChanges()](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges()), [Getting the current location](https://developer.apple.com/documentation/corelocation/getting-the-current-location-of-a-device) |
| T18 | Keychain items with `.userPresence` / `.biometryAny` prompt Face ID/Touch ID/passcode on access. | **Correct.** | [Accessing Keychain items with Face ID or Touch ID](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id), [Restricting keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility) |
| T19 | Secure Enclave holds **keys**, not SwiftData rows. Default CryptoKit SE key is after-first-unlock, empty flags. | **Correct.** Wrap Bio-Shield with an SE key; do not claim SwiftData is the Enclave. | [Apple Platform Security — Secure Enclave](https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web), [CryptoKit SecureEnclave](https://developer.apple.com/documentation/cryptokit/secureenclave) |
| T20 | ERC-4337: `UserOperation` → bundler → `EntryPoint.handleOps`. Account validates via `validateUserOp`. | **Correct.** Foundation for the CDP Smart Account. | [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) |
| T21 | ERC-7710 is a **draft** `redeemDelegations` interface. Compatible with 4337, does not require it. **No iOS/biometric language.** | **Correct.** Cannot by itself exempt Face ID. | [ERC-7710](https://eips.ethereum.org/EIPS/eip-7710) |
| T22 | ERC-7715 is the wallet permission-request companion (JSON-RPC), also draft. | **Correct.** Optional later; not v1. | [ERC-7715](https://eips.ethereum.org/EIPS/eip-7715) |
| T23 | Biconomy/Rhinestone Smart Sessions: ERC-7579 module, on-chain policy on a session signer. | **Correct.** Not an iOS API. | [Biconomy Smart Sessions](https://docs.biconomy.io/sdk-reference/sessions), [smartsessions](https://github.com/erc7579/smartsessions) |
| T24 | CDP Spend Permissions: on-chain allowance (token, period, amount) to a spender. Production path for autonomous USDC. Manager `0xf85210B21cC50302F477BA56686d2019dC9b67Ad`. | **Correct. This is what we ship.** Period is elapsed seconds, not civil midnight. | [CDP Spend Permissions](https://docs.cdp.coinbase.com/wallets/using-wallets/spend-permissions) |
| T25 | CDP Swift SDK: iOS 16+, Smart Accounts, Keychain session, `sendUserOperation`, paymaster. | **Correct.** | [CDP Swift Quickstart](https://docs.cdp.coinbase.com/wallets/client-side-development/swift) |
| T26 | CDP session tokens: 15 min access, 7 day refresh. This is **auth**, not a chain session key. | **Correct.** | [CDP session management](https://docs.cdp.coinbase.com/embedded-wallets/session-management) |
| T27 | x402 **v2** headers: `PAYMENT-REQUIRED`, `PAYMENT-SIGNATURE`, `PAYMENT-RESPONSE` (Base64 JSON). | **Correct for v2.** | [x402 HTTP 402](https://docs.x402.org/core-concepts/http-402), [spec v2](https://github.com/x402-foundation/x402/blob/main/specs/x402-specification-v2.md) |
| T28 | x402 **v1** (legacy, **what the shop host speaks**): JSON 402 body `accepts[]` + client header `X-PAYMENT` (Base64), optional `X-PAYMENT-RESPONSE`. | **Correct.** Dual-stack: v1 to this host, v2 to native v2 nodes. | Shop host `MerchantEndpoints.cs`, `ConfirmOrder.cs`; [x402-foundation core README v1 table](https://github.com/x402-foundation/x402/tree/main/typescript/packages/core) |
| T29 | HTTP 402 is reserved by HTTP Semantics; x402 gives it a payment challenge. | **Correct.** | [RFC 9110 §15.5.3](https://www.rfc-editor.org/rfc/rfc9110.html#status.402), [RFC 7231 §6.5.2](https://datatracker.ietf.org/doc/html/rfc7231#section-6.5.2) |
| T30 | HTTP 201 Created **should** carry `Location` of the new resource. | **Correct.** Shop place currently returns 201 **without** Location. | [RFC 9110 §15.3.2](https://www.rfc-editor.org/rfc/rfc9110.html#status.201), [§10.2.2 Location](https://www.rfc-editor.org/rfc/rfc9110.html#field.location) |
| T31 | x402 `exact` on EVM is EIP-3009 `TransferWithAuthorization`. | **Correct.** Shop `X402ExactSigner` already builds this. | [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009) |
| T32 | Shop host: place free, **only confirm is 402**, server is the price, payer = `verify()` wallet, reject = new outbound transfer. | **Correct.** Do not change. | Local `~/Repos/web3-restaurant-api/GROK.md` |
| T33 | Shop order SM: draft→paid→accepted→preparing→ready→completed (+ reject/refund/cancel/expire). No SETTLED/DISPATCHED enum. | **Correct.** Overlay, don't rewrite. | `OrderStateMachine.cs` |
| T34 | CAG beats RAG on latency for a bounded working set. | **Use as the lunch-path doctrine.** | [arXiv:2412.15605](https://arxiv.org/abs/2412.15605) |
| T35 | Auto SMS/fax to harvested numbers is TCPA-adjacent; commercial email must satisfy CAN-SPAM. | **v1: no auto SMS/fax/email.** | [47 USC § 227](https://www.law.cornell.edu/uscode/text/47/227), [FTC CAN-SPAM](https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business) |
| T36 | `requestConfirmation(for:dialog:)` on an `IntentParameter` returns whether the user confirmed; cancel throws; no side effect if they refuse. | **Correct. Mandatory for delivery location every launch.** | [parameter requestConfirmation](https://developer.apple.com/documentation/appintents/intentparameter/requestconfirmation(for:dialog:)), [AppIntent.requestConfirmation](https://developer.apple.com/documentation/appintents/appintent/requestconfirmation(conditions:actionname:dialog:)), [Forums 832267](https://developer.apple.com/forums/thread/832267) |
| T37 | Food ships only to a saved delivery location confirmed on that turn. GPS is not a destination. Place body carries an immutable `delivery` snapshot. | **Invariant.** | `PRODUCT_DECISIONS.md` P2–P3, P12; `ARCHITECTURE.md` §3, §4.5, §8.2 |

---

## What Gnoshbot is

A voice-first iOS agent that:

1. Requires ≥1 saved delivery location, and **asks the user to confirm that address every launch**.
2. Filters payable kitchens in a 5-mile box around the **confirmed** address against an on-device Bio-Shield and Flavor Fingerprint.
3. Places and confirms on an x402 merchant (v1 shop wrap or v2 native), with the confirmed address on the place body.
4. Speaks **"On it."** in < 500 ms after yes.
5. Settles USDC on Base in the background under a CDP Spend Permission.
6. Tracks fulfillment via HTTP `Location` + GET, not via the kitchen SignalR board.
7. Discovers POIs from Overture on demand in us-west-2.

It is not a restaurant registry, not a POS, not a conversational menu reader. It does not send food to device GPS.

---

## Hard invariants

1. Launch dialog contains no merchant, SKU, price, or minutes. The only extra voice turn is delivery-location confirmation.
2. Minutes are spoken or pushed only after `eta_minutes != null` on the fulfillment resource.
3. **No place(), no payment, no food** unless `requestConfirmation` returned true for a saved `DeliveryLocation` on that turn. GPS is never the destination. The place `delivery` snapshot is that row.
4. Bio-Shield ciphertext is SE-wrapped. Fail closed on unknown ingredients when any allergen is set.
5. Spender Keychain ACL has **no** biometry flag. Owner/passkey does.
6. Voice path: no network except optionally a measured < 150 ms picker. Default picker is local.
7. `Task.detached` is never the background strategy.
8. DuckDB/Overture never runs in `perform()` or on-device.
9. Ingest compute is us-west-2.
10. Dual-stack x402: v1 `X-PAYMENT` to the shop host; v2 headers to native v2 nodes.
11. Do not invent shop `OrderStatus` tuples. Fulfillment is an overlay.
12. Sandbox TTL shops are not in the live pool.
13. No auto SMS/Fax/email in v1.
14. `payTo` on the 402 `accepts[]` must equal the place-time snapshot.
15. Money on the shop wire is cents (`long`) and USDC atomic (`cents × 10_000`). Never decimals.

---

## Shop-host overlay (implement in `web3-restaurant-api`)

File `DECISIONS.md` first. Then:

1. `Results.Created(location, body)` on **place** (already 201). Require and snapshot `delivery` (label, postal lines, lat/lon). 400 if missing.
2. Mint `order_fulfillment` at successful confirm; return **201** + `Location: …/orders/{id}/fulfillment`. Replay: 200 + same Location. Overlay copies the delivery snapshot.
3. `GET /{originHost}/{locationId}/orders/{id}` and `…/fulfillment` gated by `X-Customer-Id`.
4. Overlay statuses: `awaiting_kitchen | accepted | preparing | ready_for_dispatch | dispatched | delivered | failed`.
5. `POST …/kitchen/orders/{id}/dispatch` `{ eta_minutes, tracking_token, courier_phone? }` writes overlay, does not need a new `OrderStatus` if `ready` is enough; adding `dispatch` as overlay-only is preferred.
6. Projector copies overlay onto the read model. Optional SignalR group `order:{id}`. Polling remains the contract.
7. Keep `X-PAYMENT` / JSON 402 body. Do not migrate this host to v2 in the same PR.

Full narrative: `ARCHITECTURE.md` §8.

---

## Control-plane API (Gnoshbot backend)

```
POST /regions/ensure          Idempotency-Key, bbox → 200 ready | 202 running
GET  /regions/{geohash5}      tile status + payable prefixes
POST /skips                   skip log (from device worker)
POST /devices/push-token
```

No lunch-path dependency.

---

## Code templates

### Swift — App Intent (launch)

```swift
import AppIntents
import BackgroundTasks
import UIKit

struct OrderLunchIntent: AppIntent {
    static var title: LocalizedStringResource = "Order lunch"
    static var description = IntentDescription("Hands-free lunch. Gnoshbot picks and pays.")
    static var openAppWhenRun: Bool { false }
    static var supportedModes: IntentModes = [.background]

    @Parameter(title: "Delivery location")
    var deliveryLocation: DeliveryLocationEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = GnoshbotStore.shared
        let allowance = try store.remainingAllowanceUSDC()
        guard allowance > 0 else {
            return .result(dialog: IntentDialog("Order denied. Daily allowance exceeded."))
        }
        guard store.fundedFlag else {
            return .result(dialog: IntentDialog("Launch aborted. Insufficient funds. Top up in Gnoshbot."))
        }

        let saved = try store.deliveryLocations()
        guard !saved.isEmpty else {
            return .result(dialog: IntentDialog("Add a delivery address in Gnoshbot first."))
        }

        let proposed = deliveryLocation ?? store.defaultDeliveryLocation()!
        let ok = try await $deliveryLocation.requestConfirmation(
            for: proposed,
            dialog: IntentDialog("Deliver to \(proposed.spokenLine)?")
        )
        guard ok else {
            return .result(dialog: IntentDialog("No order placed."))
        }

        let pick = store.pickCachedCandidate(near: proposed) // local CAG; bbox of proposed
        try store.insertLaunching(pick: pick, delivery: proposed)
        GnoshbotBackground.shared.enqueueSettlement(pick: pick, delivery: proposed)
        return .result(dialog: IntentDialog("On it."))
    }
}

struct DeliveryLocationEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Delivery location")
    static var defaultQuery = DeliveryLocationQuery()

    var id: UUID
    var spokenLine: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: spokenLine))
    }
}

struct GnoshbotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OrderLunchIntent(),
            phrases: [
                "Tell \(.applicationName) I'm hungry",
                "Ask \(.applicationName) to order lunch",
                "Order lunch with \(.applicationName)"
            ],
            shortTitle: "Order lunch",
            systemImageName: "fork.knife.circle.fill"
        )
    }
}
```

### Swift — background assertion + URLSession

```swift
import Foundation
import UIKit

final class GnoshbotBackground: NSObject, URLSessionTaskDelegate {
    static let shared = GnoshbotBackground()
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.gnoshbot.settlement")
        cfg.sessionSendsLaunchEvents = true
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    func enqueueSettlement(pick: CachedPick?, delivery: DeliveryLocationEntity) {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "gnoshbot.settle") { [weak self] in
            self?.endBg()
        }
        Task {
            defer { endBg() }
            do {
                try await SettlementWorker(session: session).run(pick: pick, delivery: delivery)
            } catch {
                await Push.localFail(error)
            }
        }
    }

    private func endBg() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }
}
```

`SettlementWorker.run` performs, in order: refuse to run if `delivery` is missing; optional local pick if `pick == nil` using the confirmed address bbox; `POST /orders` (v1) **with `delivery` snapshot**; `POST /confirm` without payment; parse 402 JSON `accepts[0]`; assert `payTo` and `maxAmountRequired` ≤ remaining; EIP-3009 sign with spender EOA; `POST /confirm` + `X-PAYMENT`; read `Location`; persist `settled`; start fulfillment polling on the same session.

### Swift — SwiftData cache

```swift
import Foundation
import SwiftData

enum SpokenStatus: String, Codable {
    case launching, placed, settled, processingLogistics, dispatched, delivered, failed
}

@Model
final class DeliveryLocation {
    @Attribute(.unique) var id: UUID
    var label: String
    var line1: String
    var line2: String?
    var city: String
    var region: String
    var postalCode: String
    var country: String
    var latitude: Double
    var longitude: Double
    var isDefault: Bool
    var lastConfirmedAt: Date?
}

@Model
final class ActiveOrderCache {
    @Attribute(.unique) var orderId: String
    var timestamp: Date
    var status: SpokenStatus
    var trackingUrl: String?
    var shopPrefix: String
    var merchantName: String
    var itemName: String
    var costUsdc: Decimal
    var etaMinutes: Int?
    var trackingToken: String?
    var settlementTxHash: String?
    var errorMessage: String?
    var idempotencyKey: String
    var deliveryLocationId: UUID
    var deliverySpokenLine: String

    init(orderId: String, idempotencyKey: String, shopPrefix: String, delivery: DeliveryLocation) {
        self.orderId = orderId
        self.idempotencyKey = idempotencyKey
        self.shopPrefix = shopPrefix
        self.timestamp = Date()
        self.status = .launching
        self.merchantName = ""
        self.itemName = ""
        self.costUsdc = 0
        self.deliveryLocationId = delivery.id
        self.deliverySpokenLine = "\(delivery.label), \(delivery.line1)"
    }
}

@Model
final class RestaurantCache {
    @Attribute(.unique) var overtureId: String
    var name: String
    var latitude: Double
    var longitude: Double
    var integration: String          // unsupported | native | proxy_wrapped
    var nativeX402Url: String?
    var shopOriginHost: String?
    var shopLocationId: String?
    var x402Version: Int             // 1 or 2
}

@Model
final class MenuCache {
    @Attribute(.unique) var shopPrefix: String
    var json: Data
    var sha256: String
    var fetchedAt: Date
}

@Model
final class ProfileBlob {
    var ciphertext: Data
    var nonce: Data
    var wrappedKey: Data
}
```

### Swift — Inquiry

```swift
import AppIntents
import SwiftData

struct CheckOrderStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check order status"
    static var openAppWhenRun: Bool { false }
    static var supportedModes: IntentModes = [.background]

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let row = try GnoshbotStore.shared.latestOrder()
        guard let row else {
            return .result(dialog: IntentDialog("No active lunch orders."))
        }
        switch row.status {
        case .launching, .placed:
            return .result(dialog: IntentDialog("Still placing it."))
        case .settled, .processingLogistics:
            if let eta = row.etaMinutes {
                return .result(dialog: IntentDialog("In the kitchen. About \(eta) minutes."))
            }
            return .result(dialog: IntentDialog("Payment settled. They're organizing a courier."))
        case .dispatched:
            let remaining = max(0, (row.etaMinutes ?? 0) - minutesSince(row.timestamp))
            if remaining == 0 {
                return .result(dialog: IntentDialog("It should be at the door."))
            }
            return .result(dialog: IntentDialog("On the way. \(remaining) minutes."))
        case .delivered:
            return .result(dialog: IntentDialog("It should be at the door."))
        case .failed:
            return .result(dialog: IntentDialog(row.errorMessage ?? "The order failed."))
        }
    }
}
```

### Swift — spender key (no Face ID)

```swift
import Security
import Foundation

enum SpenderKey {
    static let tag = "com.gnoshbot.spender.ecdsa"

    static func generateIfNeeded() throws {
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [],    // no .userPresence, no .biometryAny
            nil
        )!
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: access
            ]
        ]
        var err: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attrs as CFDictionary, &err) != nil else {
            throw err!.takeRetainedValue() as Error
        }
    }
}
```

### x402 v1 payment header (JSON before Base64)

```json
{
  "x402Version": 1,
  "scheme": "exact",
  "network": "base",
  "payload": {
    "signature": "0x…",
    "authorization": {
      "from": "0xSpenderOrPayer",
      "to": "0xPayToFromAccepts",
      "value": "2000000",
      "validAfter": "0",
      "validBefore": "1770000000",
      "nonce": "0x…"
    }
  }
}
```

Send as `X-PAYMENT: base64(utf8(json))`. `value` is USDC atomic. `to` == `accepts[0].payTo` == place snapshot.

### x402 v2 (native nodes only)

```http
POST /order HTTP/1.1
PAYMENT-SIGNATURE: eyJ4NDAyVmVyc2lvbiI6Mi… 
```

Challenge:

```http
HTTP/1.1 402 Payment Required
PAYMENT-REQUIRED: eyJ4NDAyVmVyc2lvbiI6Mi…
```

### Place (existing shop) + overlay (new)

Place request:

```http
POST /{originHost}/{locationId}/orders HTTP/1.1
X-Customer-Id: device-stable-opaque
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json

{
  "lines": [
    { "menuItemId": "3fa85f64-5717-4562-b3fc-2c963f66afa6", "quantity": 1, "modifierIds": [] }
  ],
  "delivery": {
    "label": "Home",
    "line1": "14 Pine Street",
    "line2": "Apt 4",
    "city": "Brooklyn",
    "region": "NY",
    "postalCode": "11201",
    "country": "US",
    "lat": 40.6944,
    "lon": -73.9903
  }
}
```

Place response **after overlay PR**:

```http
HTTP/1.1 201 Created
Location: https://shop.example/pos.example.com/downtown/orders/7c9e6679-7425-40de-944b-e07fc1f90ae7
```

Confirm success **after overlay PR**:

```http
HTTP/1.1 201 Created
Location: https://shop.example/pos.example.com/downtown/orders/7c9e6679-7425-40de-944b-e07fc1f90ae7/fulfillment
Content-Type: application/json

{
  "order_id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "settlement_status": "paid",
  "logistics_status": "awaiting_kitchen",
  "eta_minutes": null,
  "tracking_token": null,
  "payment_tx_hash": "0xabc…"
}
```

Fulfillment GET (later):

```json
{
  "order_id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "settlement_status": "paid",
  "logistics_status": "dispatched",
  "eta_minutes": 22,
  "eta_source": "courier",
  "tracking_token": "tok_881a",
  "courier_phone": null,
  "updated_at": "2026-08-30T16:04:11Z"
}
```

Kitchen SM alongside that payload remains `"status": "ready"` (or `completed`). Client spoken class maps overlay → `dispatched`.

### Tool schemas (picker output)

```json
[
  {
    "name": "select_and_order_native_node",
    "description": "Best payable (NATIVE or PROXY_WRAPPED) option.",
    "parameters": {
      "type": "object",
      "required": ["overture_id", "shop_prefix", "menu_item_id", "quantity"],
      "properties": {
        "overture_id": { "type": "string" },
        "shop_prefix": { "type": "string", "description": "/{originHost}/{locationId}" },
        "menu_item_id": { "type": "string", "format": "uuid" },
        "quantity": { "type": "integer", "minimum": 1, "maximum": 50 },
        "modifier_ids": { "type": "array", "items": { "type": "string", "format": "uuid" } }
      }
    }
  },
  {
    "name": "log_skipped_legacy_merchant",
    "description": "Culinary winner is UNSUPPORTED. Log and continue.",
    "parameters": {
      "type": "object",
      "required": ["overture_id", "restaurant_name", "estimated_lost_revenue_usdc"],
      "properties": {
        "overture_id": { "type": "string" },
        "restaurant_name": { "type": "string" },
        "estimated_lost_revenue_usdc": { "type": "number" }
      }
    }
  }
]
```

The worker **ignores** any `cost_usdc` the model invents. Server price is law.

### Postgres (control plane)

Control-plane tables:

- `overture_id` PK
- `coordinates geometry(Point,4326)`
- `x402_capabilities.integration_status` in `UNSUPPORTED|NATIVE|PROXY_WRAPPED`
- add `shop_origin_host`, `shop_location_id`, `x402_version`
- add `region_tiles(geohash5, release, status, geom)`
- add `user_locations(user_id, last_known_coordinates, last_ingest_center, last_seen_at)` — device travel, not drop-off
- add `delivery_locations(user_id, label, address fields, coordinates)` — the only legal drop-off set
- skip log **without** raw user ids or delivery street addresses

Purge SQL: `SCALABILITY.md` §5.

### DuckDB ingest (us-west-2)

```sql
INSTALL spatial; LOAD spatial;
INSTALL httpfs;  LOAD httpfs;
SET s3_region = 'us-west-2';

SELECT
  id AS overture_id,
  names.primary AS name,
  websites[1] AS website_url,
  phones[1] AS phone_number,
  emails[1] AS email_address,
  addresses[1].freeform AS street_address,
  categories.primary AS category_deprecated,
  basic_category,
  taxonomy,
  bbox.xmin AS lon,
  bbox.ymin AS lat
FROM read_parquet(
  's3://overturemaps-us-west-2/release/2026-08-19.0/theme=places/type=place/*',
  filename = true,
  hive_partitioning = 1
)
WHERE bbox.xmin BETWEEN $min_lon AND $max_lon
  AND bbox.ymin BETWEEN $min_lat AND $max_lat
  AND operating_status IS DISTINCT FROM 'permanently_closed'
  AND (
        list_contains(taxonomy.hierarchy, 'food_and_drink')
     OR basic_category IN ('restaurant','cafe','bar','meal_takeaway','meal_delivery','bakery','food_truck')
     OR categories.primary ILIKE '%restaurant%'
  );
```

---

## Document map

| File | Role |
| --- | --- |
| `ARCHITECTURE.md` | Asymmetric lifecycle, location confirmation, iOS process model, wallet, x402 dual-stack, shop overlay including `delivery` on place |
| `PRODUCT_DECISIONS.md` | Zero-disclosure VUI except mandatory address confirm, 3-phase wizard with addresses, closed product calls |
| `PERFORMANCE_CONSIDERATIONS.md` | 500 ms prompt + 500 ms "On it.", CAG around confirmed address, background handoff |
| `SCALABILITY.md` | us-west-2 ingest keyed on saved addresses, significant-change pre-warm, purge, skip flywheel |
| `GROK.md` | This file: register, invariants, templates, commit/README language |
| `README.md` | Public handshake for humans and LinkedIn drafts. **Not** an enforcement layer. |

These five markdown files (`ARCHITECTURE.md` through `GROK.md`) are the only documentation source of truth in this repository. `README.md` must not contradict them.

---

## Commit messages (required)

The operator does not write `feat:` / `fix:` / `perf:` by habit. **You must**, when you create the commit, because github-to-linkedin-drafts scores those prefixes. Do not ask the user to rephrase. Pick the type from the actual diff, then write a normal first line after it.

Cursor User Rules still apply: commit only when asked; the **body** is 1–2 sentences on **why**, not a file list; pass the message via HEREDOC.

Format (Conventional Commits):

```
<type>: <imperative summary, ≥20 characters, no trailing period>

Optional body. Why this change exists. If the change is worth a LinkedIn draft,
write 80+ characters explaining what shipped and why — not a file list.
```

Types — use the first that is true:

| Type | When | Effect on the scorer |
| --- | --- | --- |
| `feat` | New user-visible capability or API | +12, tiny diffs still allowed |
| `fix` | Bug, incorrect behavior, security hole | +8, tiny diffs still allowed |
| `perf` | Faster, cheaper, less memory, lower latency | +10, tiny diffs still allowed |
| `feat!` / `fix!` | Breaking change. Also add a `BREAKING CHANGE:` footer | type bonus **plus** +18 |
| `refactor` | Same behavior, different structure | +4 |
| `chore` `docs` `ci` `test` `style` `build` `deps` `bump` | That is *all* the commit is | **Dropped before scoring.** Correct. Do not disguise these as `feat`. |

Examples:

```
feat: persist launching ActiveOrderCache after address confirmation
fix: refuse place() when requestConfirmation did not return true
perf: fetch latest ActiveOrderCache with timestamp prefix(1)
ci: run bun typecheck and DuckDB spatial smoke on pull requests
chore: pin bun packageManager to the machine that passed ingest gate

feat!: drop JSON 402 body for native v2 nodes

BREAKING CHANGE: native merchants must send PAYMENT-SIGNATURE; shop host stays v1.
```

Not these:

```
Push
phase 2: bun switch
update
wip
feat: tweak comments          ← not a feat
feat: add github actions      ← that is ci:
```

Do not prefix every commit `feat` to game the scorer. False types pollute drafts. A lockfile bump is `chore` or `deps` and should stay invisible to LinkedIn.

---

## README (public handshake)

github-to-linkedin-drafts fetches the README **after scoring** and uses it only as generation context. Scoring never reads it. New-repo drafts must lead with **why this repo exists**. The README is that spine.

Rules:

1. **Why first.** Gnoshbot is a voice-first lunch agent: confirm a saved delivery address, say "On it.", settle USDC on Base in the background. That thesis belongs in the first screen. Do not open with a folder tree or a protocol lecture.
2. **Not a generic explainer.** Do not mash nearby keywords into "x402 is for micropayments" / "agents replace apps." Write this product's claim. If README and GROK disagree, GROK wins; fix the README.
3. **Not a changelog and not the five source-of-truth files.** Mechanisms, endpoints, and first ships are evidence under the why. They do not replace it. Do not copy `ARCHITECTURE.md` into README.
4. **Keep the launch contract honest.** No spoken minutes until fulfillment `eta_minutes`. GPS is not the destination. Menu, price, and kitchen stay off the launch utterance.
5. **Handshake, not enforcement.** Humans and LinkedIn drafts read README. Agents encode invariants in this file and in tests.

---

## User profile envelope (SE-wrapped JSON)

```json
{
  "user_id": "usr_9921a8x3",
  "bio_shield": {
    "medical_allergies": ["PEANUTS", "SHELLFISH"],
    "dietary_frameworks": ["NONE"]
  },
  "flavor_fingerprint": {
    "spice_tolerance": "HIGH",
    "disliked_ingredients": ["CILANTRO", "OLIVES"],
    "preferred_cuisines": ["MEXICAN", "THAI", "MEDITERRANEAN"],
    "preferred_meal_types": ["BURRITOS", "NOODLES", "BOWLS"]
  },
  "financial_guardrails": {
    "max_single_order_usdc": 25.00,
    "daily_allowance_limit_usdc": 35.00,
    "current_daily_spent_usdc": 14.50,
    "session_key_expiration": "2026-08-30T23:59:59Z"
  }
}
```

Delivery locations are **not** in this blob. They are first-class SwiftData rows (`DeliveryLocation`) so App Intents can resolve `AppEntity` values without decrypting medical data.

---

## KPIs

| KPI | Target |
| --- | --- |
| Time to location prompt | p95 < 500 ms |
| Time from yes to "On it." | p95 < 500 ms |
| Time to `settled` cache write | p95 < 8 s on Base happy path |
| Voice completions vs app-open completions | maximize voice share |
| On-chain confirm success (402 retry that settles) | track; alert on drops |
| Orders with unconfirmed destination | **0** |

---

## Stop and ask

- Anything that speaks minutes before fulfillment `eta_minutes` is set.
- Anything that puts `.biometryAny` on the spender key.
- Anything that runs DuckDB or Overture inside an App Intent.
- Auto SMS/Fax/email to harvested Overture contacts.
- Promote-from-sandbox, billing, or shop tokens on the wrap host.
- Replacing shop `X-PAYMENT` with v2 headers in the same change as the fulfillment overlay.
- Inventing `SETTLED` as an `OrderStatus` tuple.
- Claiming ERC-7710 as an iOS biometric exemption.
- Shipping food to GPS, "last known," or a default address without `requestConfirmation` on that turn.
- Geocoding a street the user spoke into a new destination from Siri.
