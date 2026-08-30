# Gnoshbot Architecture

## Why this exists

Mealtime is a high-frequency, low-delight decision. The user already knows they are hungry. They do not want a menu read aloud, a price recitation, or a checkout confirmation. They do want to hear the delivery address and say yes. Gnoshbot is a voice-first agent that treats lunch as a logistics problem: confirm where the food goes, pick a payable kitchen in range of that address, settle USDC on Base, then track fulfillment until the meal is at that door.

The ordering surface is not a marketplace Gnoshbot owns. Production kitchens are origin-keyed wraps of a Menu Pull GET, paid over HTTP 402, implemented today by the sibling host at `~/Repos/web3-restaurant-api`. That host already moves money. It does not yet expose an agent-facing fulfillment pointer, and its place body has no delivery address. This document is the system architecture for the iOS agent **and** the protocol overlay that host must grow so a confirmed delivery address rides on place and an ETA can arrive after settlement.

Food never ships to device GPS. Food ships to a **saved delivery location the user confirmed on that turn**.

---

## 1. Load-bearing facts

These values are attested in `GROK.md`. Use them; do not substitute folklore.

| Topic | Fact |
| --- | --- |
| Overture catalog | `s3://overturemaps-us-west-2/release/<RELEASE>/`. Places: `theme=places/type=place/*.parquet`. Compute that reads it runs in **us-west-2**. |
| App Intent CPU | **30 seconds** on iOS. Siri may return earlier. Detached Swift tasks die with the process. Background work requires `beginBackgroundTask`, `URLSession` background, `BGAppRefreshTask` (~30 s, not guaranteed), or `LongRunningIntent`. |
| Voice confirmation | `requestConfirmation` from `perform()`. Delivery-location confirmation is mandatory every launch. GPS is never the destination. |
| Autonomous USDC | CDP Spend Permissions + a software spender EOA **without** `.userPresence` / `.biometryAny`. ERC-7710 is a draft on-chain interface and does not talk to iOS. |
| x402 on the shop host | **v1**: JSON 402 body `accepts[]` + client header `X-PAYMENT`. v2 headers (`PAYMENT-REQUIRED`, `PAYMENT-SIGNATURE`) are for native v2 nodes. |
| DuckDB / GeoParquet | Range-reads Parquet over HTTP. Spatial predicates do **not** auto-prune; `bbox.*` filters do. Cold `INSTALL spatial; LOAD httpfs` will miss 200 ms. Ingest is an async worker, not the Siri path. |

Official sources for every row: [Overture cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/), [Overture DuckDB](https://docs.overturemaps.org/getting-data/duckdb/), [AWS S3 data transfer](https://aws.amazon.com/s3/pricing/), [Apple App Intent first-run](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent), [requestConfirmation](https://developer.apple.com/documentation/appintents/appintent/requestconfirmation(conditions:actionname:dialog:)), [parameter requestConfirmation](https://developer.apple.com/documentation/appintents/intentparameter/requestconfirmation(for:dialog:)), [Apple Forums 832257](https://developer.apple.com/forums/thread/832257), [WWDC26 session 345](https://developer.apple.com/videos/play/wwdc2026/345/), [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask), [Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html), [x402 HTTP 402](https://docs.x402.org/core-concepts/http-402), [ERC-7710](https://eips.ethereum.org/EIPS/eip-7710), [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337), [CDP Spend Permissions](https://docs.cdp.coinbase.com/wallets/using-wallets/spend-permissions), [DuckDB HTTP(S)](https://duckdb.org/docs/current/core_extensions/httpfs/https.html).

---

## 2. System context

Gnoshbot is three cooperating planes. Money, discovery, and voice never share a blocking call stack.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ iPhone                                                                   │
│  Siri / App Intents  →  confirm saved address  →  CAG pick  → "On it."   │
│                           │                                              │
│                           ▼                                              │
│              BG execution assertion + URLSession (background)            │
│              SwiftData: DeliveryLocation + ActiveOrderCache              │
│              CDP Smart Account + Spend Permission spender                │
└───────────────┬──────────────────────────────┬───────────────────────────┘
                │ HTTPS                        │ x402 v1 (this host)
                │                              │ x402 v2 (native nodes)
                ▼                              ▼
┌─────────────────────────────┐   ┌────────────────────────────────────────┐
│ Gnoshbot control plane      │   │ Agent-payable shop                     │
│ (us-west-2)                 │   │ ~/Repos/web3-restaurant-api            │
│                             │   │                                        │
│ POST /regions/ensure        │   │ GET  /{origin}/{loc}/menu              │
│   DuckDB → Overture S3      │   │ POST /{origin}/{loc}/orders     201    │
│ POST /skips                 │   │ POST /{origin}/{loc}/orders/{id}/      │
│ nightly purge               │   │      confirm  402 then 200/201         │
│                             │   │ GET  /{origin}/{loc}/orders/{id}  NEW  │
└─────────────┬───────────────┘   │ GET  /{origin}/{loc}/orders/{id}/      │
              │                   │      fulfillment                  NEW  │
              ▼                   └────────────────────────────────────────┘
     s3://overturemaps-us-west-2/release/<RELEASE>/theme=places/type=place/
```

**Identity of a production kitchen** is the origin host + location id of a Menu Pull GET, not a GUID Gnoshbot mints. That is already law in the shop host ([PRODUCT.md](https://github.com/hebihime/web3-restaurant-api/blob/main/PRODUCT.md), local tree `~/Repos/web3-restaurant-api/PRODUCT.md`).

**Identity of a payer** is the wallet address `verify()` returns, not `X-Customer-Id`. `X-Customer-Id` is an idempotency/customer correlation header the shop requires; it is not the chain identity.

---

## 3. Asymmetric lifecycle

The voice loop and the money loop share an `orderId` and a **confirmed delivery location id**. Siri is not allowed to wait on Base, a facilitator, or a kitchen. Siri **is** required to wait on an explicit yes to the delivery address.

### 3.1 Sequence

```
User: "Siri, tell Gnoshbot I need lunch."

T+0 ms      App Intent perform() starts (30 s CPU budget; Siri may cut earlier)
T+0–40      Local guards: allowance, funded flag, ≥1 saved DeliveryLocation
            If none: "Add a delivery address in Gnoshbot first."  STOP
T+40–150    Propose default saved location (isDefault, else lastConfirmed)
            NEVER skip this step. NEVER use raw GPS as the destination.
T+150       requestConfirmation(for: location,
              dialog: "Deliver to Home, 14 Pine Street, apartment 4?")
            User: "Yes" | "No" | names another saved label
            No → requestDisambiguation among saved locations, or abort
                 "Open Gnoshbot to add an address."
            Cancel / timeout → no place(), no payment, no food.

               ── destination is now a user-confirmed saved location ──

T+confirm   Kitchen radius is 5 miles of that address (not device GPS)
            CAG: score ≤10 preloaded native/proxy menus for that bbox
            persist ActiveOrderCache(status: launching, deliveryLocationId, eta: nil)
            beginBackgroundTask + URLSession background
            return .result(dialog: "On it.")     ← Siri disconnects

               ── voice channel closed ──

Background worker:
  1. POST place (free, 201, Idempotency-Key, delivery address in body)
  2. POST confirm without payment → 402 + accepts[]
  3. sign EIP-3009 TransferWithAuthorization via spend-permission spender
  4. POST confirm with X-PAYMENT → facilitator verify/settle
  5. on 2xx: read Location (fulfillment URI)
  6. write cache status = settled, trackingUrl = Location
  7. APNs: "Paid. Kitchen is on it."
  8. poll GET fulfillment until eta_minutes is non-null or terminal
  9. APNs: "Arriving in 22 minutes."  (first time a number is spoken)
```

Spoken **minutes** are forbidden until the fulfillment resource has a non-null `eta_minutes`. A distance-based guess from the confirmed address is an internal ranking feature, not a user-facing promise. If settlement later fails, the user has only heard "On it." — not that a meal is coming. That is the point of the split.

Fatal interruptions that **are** allowed on the voice channel, because they are local:

| Guard | Spoken |
| --- | --- |
| No saved delivery location | "Add a delivery address in Gnoshbot first." |
| User declines every saved location | "No order placed." |
| Daily allowance exhausted | "Order denied. Daily allowance exceeded." |
| Cached `funded == false` | "Launch aborted. Insufficient funds." |
| No native/proxy node in the 5-mile box around the **confirmed** address | "No payable kitchen in range of that address." |
| Intent watchdog after confirmation (clock > 400 ms with no pick) | "On it." anyway; worker continues or fails via APNs |

Network timeout, 402 reject, facilitator revert, kitchen reject: **push notification + Inquiry Intent**, never a Siri retry of the original turn. Location confirmation is the only extra voice turn. Menu, price, and kitchen stay undisclosed on launch.

### 3.2 Why the split is mandatory

Apple's App Intents engineer: intents have 30 seconds of CPU; Siri may impose a tighter wait for a spoken result ([Forums 832257](https://developer.apple.com/forums/thread/832257), [WWDC26 345](https://developer.apple.com/videos/play/wwdc2026/345/)). x402 `exact` settlement is a facilitator round trip plus an on-chain `TransferWithAuthorization` ([x402 HTTP 402](https://docs.x402.org/core-concepts/http-402), [EIP-3009](https://eips.ethereum.org/EIPS/eip-3009)). Those two clocks do not compose. The architecture therefore uses two state machines:

1. **Voice machine** — `idle | confirming_location | launching | settled_spoken | failed_spoken`. Location confirmation is a blocking turn. After yes, "On it." returns in < 500 ms.
2. **Order machine** — owned by the shop host, copied from the reference merchant, **not rewritten**.
3. **Fulfillment overlay** — new, agent-facing, the only place `eta_minutes` lives.

---

## 4. iOS process model (no mythology)

### 4.1 What actually runs after Siri hangs up

| Mechanism | Official window | Usable for |
| --- | --- | --- |
| `AppIntent.perform()` | 30 s CPU on iOS; Siri may return earlier. macOS has no fixed limit. | Local guards, **location confirmation**, CAG, enqueue, spoken result. |
| `Task.detached` | Lifetime of the process. Not a background assertion. | Work **inside** an already-asserted background task. Never the assertion itself. |
| `UIApplication.beginBackgroundTask` | "Limited"; expiration handler fires; historically ~30 s on modern iOS. App is killed if you do not `endBackgroundTask`. | Bridging the few seconds of place + confirm. |
| `URLSessionConfiguration.background` | System-owned transfers; app may be relaunched on completion. | The HTTP 402 retry and subsequent GETs. |
| `BGAppRefreshTask` | Up to **30 seconds**, scheduled by the system, **not guaranteed**, skipped after user force-quit. | Opportunistic fulfillment poll, not the payment. |
| `BGProcessingTask` | Minutes, discretionary, usually overnight / charging. | Overture region ingest acknowledgements, cache compaction. |
| `LongRunningIntent` + `performBackgroundTask` (iOS 26+) | Extends past 30 s; system Live Activity; pair with `CancellableIntent`. | Visible long work. **Wrong** for a silent fire-and-forget lunch — it puts a Live Activity on the Lock Screen, which breaks the product's "missile already flew" contract. Reserve it for explicit "track this order" if we ever show progress. |

Sources: [Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent), [Choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app), [Extending background execution](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time), [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask), [iOS background execution limits](https://developer.apple.com/forums/thread/685525).

### 4.2 Required App Intent configuration

```swift
static var supportedModes: IntentModes = [.background]
static var openAppWhenRun: Bool { false }
```

Run in the main app process (`ExecutionTargets` → application), not a widget extension. Widget-process App Intents cannot hold a Keychain session or a `URLSession` background identifier reliably. See [supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes-5zhmb).

### 4.3 Inquiry intents are local

`CheckOrderStatusIntent`, `WhatDidYouOrderIntent`, `WhatDidItCostIntent`, and `WhereIsItGoingIntent` read SwiftData only. They must not hit the network. Sub-10 ms is realistic for a single `FetchDescriptor`. That is the only path that can honestly advertise "instant Siri follow-up."

### 4.4 Location confirmation API

Call from `perform()`, before any `POST /orders`:

```swift
let confirmed = try await $deliveryLocation.requestConfirmation(
    for: proposed,
    dialog: IntentDialog("Deliver to \(proposed.spokenLine)?")
)
guard confirmed else { return .result(dialog: IntentDialog("No order placed.")) }
```

Official: [IntentParameter.requestConfirmation(for:dialog:)](https://developer.apple.com/documentation/appintents/intentparameter/requestconfirmation(for:dialog:)), [AppIntent.requestConfirmation(conditions:actionName:dialog:)](https://developer.apple.com/documentation/appintents/appintent/requestconfirmation(conditions:actionname:dialog:)), [requestDisambiguation](https://developer.apple.com/documentation/appintents/intentparameter/requestdisambiguation(among:dialog:)). If the user cancels, the method throws and **no place() runs**.

Do not use `LongRunningIntent` for this prompt. It is a short Siri turn, not a Live Activity.

---

### 4.5 Delivery locations (data)

Saved in SwiftData, **not** SE-wrapped (they are not medical). Fields:

| Field | Rule |
| --- | --- |
| `id` | UUID |
| `label` | User-facing, unique per user: Home, Work, Gym, … |
| `line1`, `line2`, `city`, `region`, `postalCode`, `country` | Postal address as confirmed in the app |
| `latitude`, `longitude` | Geocoded at save time. Immutable until the user edits the address. |
| `isDefault` | Exactly one true |
| `lastConfirmedAt` | Updated on every successful voice yes |

Creation happens only in the app (search, pin, Contacts, "use current location" **on a map the user sees and saves**). Siri never geocodes a new address into existence. A "Current location" saved row is still a saved row: the voice prompt reads the reverse-geocoded street, and the user must say yes.

The 5-mile kitchen box, skip-log geography, and place `delivery` payload all use this row. Device GPS is used only to (a) help the user drop a pin in the editor and (b) trigger region ingest when they travel. GPS is not a destination.

---

## 5. Wallet, session keys, and Face ID

### 5.1 Accounts

Onboarding creates a CDP **EVM Smart Account** on Base (`EthereumConfig(createOnLogin: .smart)`), iOS 16+, Swift package `https://github.com/coinbase/cdp-swift` ([CDP Swift Quickstart](https://docs.cdp.coinbase.com/wallets/client-side-development/swift)). The Smart Account is an ERC-4337 sender: it validates a `UserOperation` at an `EntryPoint` ([ERC-4337](https://eips.ethereum.org/EIPS/eip-4337)). Gas on the happy path is sponsored (`useCdpPaymaster: true`).

USDC asset addresses the shop host already pins:

| Network | Chain ID | USDC |
| --- | --- | --- |
| Base | 8453 | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Base Sepolia | 84532 | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |

(Sepolia asset is the live value in `~/Repos/web3-restaurant-api/src/AgentPayable.Api/appsettings.json`.)

### 5.2 How automated spend actually works

Three different objects people conflate. Gnoshbot ships only the third as the allowance primitive.

1. **ERC-7710** — draft interface `redeemDelegations` on a Delegation Manager. Compatible with ERC-4337; does not require it. Says nothing about biometrics ([ERC-7710](https://eips.ethereum.org/EIPS/eip-7710)).
2. **Biconomy / Rhinestone Smart Sessions** — ERC-7579 module that validates a session signer against policies. On-chain, not iOS.
3. **CDP Spend Permissions** — production CDP API. Owner signs **once** to designate a spender, token, allowance, and period. The spender then calls `useSpendPermission` within those bounds ([Spend Permissions](https://docs.cdp.coinbase.com/wallets/using-wallets/spend-permissions)). Manager contract: `0xf85210B21cC50302F477BA56686d2019dC9b67Ad` on Base.

Gnoshbot ships **CDP Spend Permissions** as the allowance primitive:

- Token: USDC on Base.
- Allowance: the Phase-3 daily slider (10–50 USDC, default 25), encoded as 6-decimal atomic units.
- `periodInDays: 1` (rolling 86400 s, not "midnight local" — CDP periods are on-chain elapsed time, not tz-aware midnights).
- Spender: a dedicated local EOA generated at ENGAGE SYSTEM, stored in the Keychain **without** `SecAccessControl` biometric flags.

### 5.3 Face ID is an Apple ACL, not an ERC

[Accessing Keychain items with Face ID](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id) and [Restricting keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility): a key created with `.userPresence` or `.biometryAny` **will** prompt. CryptoKit's default Secure Enclave key uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and empty flags — no prompt after first unlock, but the private key never leaves the SE and is the **owner** key, not the session key.

Rules:

| Key | Storage | ACL | Used for | Prompts Face ID? |
| --- | --- | --- | --- | --- |
| CDP owner / passkey | CDP + Keychain session (15 min access / 7 day refresh) | vendor | Creating the Spend Permission, recovery | Yes, on create / re-auth |
| Spender EOA | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, **no** `.userPresence` | none | EIP-3009 `TransferWithAuthorization` and/or 4337 UserOp as spender | **No** |
| Bio-Shield wrapping key | `SecureEnclave.P256.Signing.PrivateKey` | after first unlock, no biometry | Encrypt allergy ciphertext | No, after first unlock |

A background App Intent **can** sign with the spender EOA without Face ID. That is a deliberate security trade: the blast radius is the remaining daily USDC allowance, not the whole account. Revocation is `revokeSpendPermission` plus Keychain delete.

Do not put the spender key in the Secure Enclave with `.biometryCurrentSet`. That reintroduces a prompt and kills the voice loop.

x402 `exact` on EVM is EIP-3009 `TransferWithAuthorization` (the shop host's `X402ExactSigner` already builds this). The spender signs that authorization. The facilitator submits it. The user's Smart Account does not need a UserOp per lunch if the USDC sits on an address the spender can move; if USDC sits **on** the Smart Account, the spender uses the Spend Permission Manager to pull USDC, then signs the 3009 authorization from the pulled balance **or** the Smart Account itself is the `from` and the session key is an owner. Pick one at implementation time; the architecture prefers USDC on the Smart Account with Spend Permission pulls into a hot payer used only for 3009, so a compromised spender cannot drain ETH/gas policy, only USDC up to the remaining period allowance.

---

## 6. x402: dual-stack, because the shop is v1 and the spec is v2

### 6.1 What the shop host actually speaks

Confirm is the **only** 402-gated call. Place is free. Copied from the reference merchant, enforced in `~/Repos/web3-restaurant-api/GROK.md` invariant 4.

Unauthenticated confirm:

```http
POST /{originHost}/{locationId}/orders/{orderId}/confirm HTTP/1.1
X-Customer-Id: <opaque>
```

Response (HTTP 402), JSON body, **not** a `PAYMENT-REQUIRED` header:

```json
{
  "x402Version": 1,
  "error": "X-PAYMENT header is required",
  "accepts": [
    {
      "scheme": "exact",
      "network": "base-sepolia",
      "maxAmountRequired": "2000000",
      "resource": "https://host/{origin}/{loc}/orders/{id}/confirm",
      "description": "order {id}",
      "mimeType": "application/json",
      "payTo": "0x…",
      "maxTimeoutSeconds": 300,
      "asset": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      "extra": { "name": "USDC", "version": "2" }
    }
  ]
}
```

Retry:

```http
POST /{originHost}/{locationId}/orders/{orderId}/confirm HTTP/1.1
X-Customer-Id: <opaque>
X-PAYMENT: <base64 JSON of { x402Version, scheme, network, payload: { signature, authorization } }>
```

`maxAmountRequired` is USDC **atomic** (cents × 10_000 at 1:1). Money inside the shop domain is `long` cents. Do not send dollars.

Implementation pointers in the shop host:

- Header read: `MerchantEndpoints.ConfirmOrder` → `http.Request.Headers["X-PAYMENT"]`
- Challenge builder: `ConfirmOrderCommandHandler.BuildRequirements` / `Challenge`
- Signer: `AgentPayable.DemoPay.X402ExactSigner` (agents reimplement; the API never calls it)

### 6.2 What x402 v2 speaks

[HTTP 402 (x402)](https://docs.x402.org/core-concepts/http-402) and [x402-specification-v2](https://github.com/x402-foundation/x402/blob/main/specs/x402-specification-v2.md):

| Header | Direction | Body |
| --- | --- | --- |
| `PAYMENT-REQUIRED` | server → client | Base64 `PaymentRequired` (v2 schema, CAIP-2 network e.g. `eip155:8453`) |
| `PAYMENT-SIGNATURE` | client → server | Base64 `PaymentPayload` |
| `PAYMENT-RESPONSE` | server → client | Base64 `SettlementResponse` |

v1 legacy (same foundation repo): `X-PAYMENT` + `X-PAYMENT-RESPONSE`, requirements in the JSON body.

### 6.3 Client policy

```
if node.x402_version == 1 or node.is_agent_payable_shop:
    speak X-PAYMENT / JSON 402 body
else:
    speak PAYMENT-SIGNATURE / PAYMENT-REQUIRED header
```

Native x402 merchants Gnoshbot discovers later may be v2. The wrap host is v1 until that repo itself migrates. Do not "fix" the shop host onto v2 from this project; that is a shop-host decision and would break `x402-angular` protocol copy.

---

## 7. The shop host as it exists today

Inspected at `~/Repos/web3-restaurant-api`. Relevant surface:

| Method | Path | Auth | Status | Body |
| --- | --- | --- | --- | --- |
| GET | `/{originHost}/{locationId}/menu` | none | 200 | `ShopMenuDto` |
| GET | `/{originHost}/{locationId}/guardrails` | none | 200 | max order, daily cap, asset, network, payTo |
| POST | `/{originHost}/{locationId}/orders` | `X-Customer-Id`, `Idempotency-Key` | **201** | `OrderDto` — **no `Location` header** |
| POST | `/{originHost}/{locationId}/orders/{id}/confirm` | `X-Customer-Id`, optional `X-PAYMENT` | 402 or **200** | challenge or `OrderDto` |
| POST | `/{originHost}/{locationId}/orders/{id}/cancel` | `X-Customer-Id` | 200 | draft → cancelled |
| GET | `/kitchen/orders/{id}` | none (board) | 200/404 | `OrderDetailsDto` (Dapper projection; 404 if not yet projected) |
| GET | `/{originHost}/{locationId}/kitchen/orders/{id}` | none | 200 | same, shop-scoped |
| POST | `…/kitchen/orders/{id}/accept\|reject\|start-preparing\|mark-ready\|complete` | kitchen | 200 | state machine |
| SignalR | `/hubs/orders` | board | — | projection upserts |

**There is no agent-facing GET of an order.** Kitchen reads are a board, not a tracking pointer. Place already returns 201 but `ResultHttp.ToHttpResult` serializes JSON only — it never sets `Location` ([RFC 9110 §10.2.2](https://www.rfc-editor.org/rfc/rfc9110.html#name-201-created), [§10.2.2 Location](https://www.rfc-editor.org/rfc/rfc9110.html#field.location)).

### 7.1 State machine (do not invent tuples)

From `OrderStateMachine.cs`. Actor is part of the key.

```
(none) --customer--> draft
draft  --system----> paid          # facilitator-verified settlement
draft  --customer--> cancelled
draft  --system----> expired       # DraftTtlSeconds, default 300
paid   --restaurant|system--> rejected
paid   --restaurant--> accepted
accepted --restaurant--> preparing
preparing --restaurant--> ready
ready --restaurant--> completed
rejected --system--> refund_pending
refund_pending --system--> refunded | refund_failed
```

Defaults (`appsettings.json`): `DraftTtlSeconds=300`, `AcceptanceTimeoutSeconds=600`, `MaxOrderValueMinorUnits=20000` ($200), `DailySpendCapMinorUnits=50000` ($500, **payer-keyed, UTC day**, shop-side — distinct from the user's on-device slider).

Spoken classes `settled`, `processing_logistics`, `dispatched`, `failed` **do not exist** on this aggregate. Replacing `paid` with a new kitchen enum would violate shop-host GROK invariant 9 ("state machine is law… do not invent tuples") and the stop-and-ask rule against editing `TransitionTo`. Gnoshbot therefore **adds an overlay**, it does not rewrite the kitchen. Place also currently accepts only `lines` — no delivery address. That is the other additive hole.

### 7.2 What "no ETA lifecycle" means, concretely

- `OrderDto` / `OrderDetailsDto` have no `eta_minutes`, no `tracking_token`, no courier fields.
- Confirm success is `200 OK` + current snapshot (`status: "paid"`).
- Kitchen progress is SignalR to the **board**, not to the paying agent.
- Reject starts a new outbound USDC transfer (`IRefundRail`). Settlement does not reverse.

---

## 8. Required modifications to `web3-restaurant-api`

These changes belong in that repo, behind a `DECISIONS.md` entry, without touching `TransitionTo` tuples. They are additive.

### 8.1 Decision to file first

Title: **Agent fulfillment pointer (201 Location + overlay) and delivery address on place; kitchen SM unchanged.**

Why: Gnoshbot must (1) send a user-confirmed postal address on place so the kitchen does not invent a drop-off, and (2) poll logistics after `paid` without sitting on SignalR and without treating `paid` as "food is moving."

### 8.2 HTTP `Location` on create and on settle

**Place (already 201).** Set the header. `ResultHttp` cannot stay JSON-only for 201. Accept and snapshot a `delivery` object; reject 400 if it is missing or fails validation (country, lat/lon finite, line1 non-empty).

```
POST /{originHost}/{locationId}/orders
X-Customer-Id: …
Idempotency-Key: …
{
  "lines": [ { "menuItemId": "…", "quantity": 1, "modifierIds": [] } ],
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

HTTP/1.1 201 Created
Location: https://{shopHost}/{originHost}/{locationId}/orders/{orderId}
Content-Type: application/json

{ "orderId": "…", "status": "draft", "delivery": { … } }
```

The delivery snapshot is immutable after place, same rule as line items and `payTo`. A later GPS drift does not rewrite it.

`Location` is an absolute URI ([RFC 9110 §10.2.2](https://www.rfc-editor.org/rfc/rfc9110.html#field.location)). Path is origin-keyed, same prefix as menu/confirm. Do not mint a GUID host.

**Confirm, after settle.** Creating a *new* resource (the fulfillment projection) is a real 201. Do not relabel the confirm of an existing draft as 201 if no new resource is minted — that would be a lie. Mint `/orders/{id}/fulfillment` and return:

```
HTTP/1.1 201 Created
Location: https://{shopHost}/{originHost}/{locationId}/orders/{orderId}/fulfillment
X-PAYMENT-RESPONSE: <optional v1 receipt, if you already emit one>
Content-Type: application/json

{
  "order_id": "…",
  "settlement_status": "paid",
  "logistics_status": "awaiting_kitchen",
  "eta_minutes": null,
  "tracking_token": null,
  "payment_tx_hash": "0x…"
}
```

Replay of a already-paid confirm stays **200** with the same `Location`, matching current idempotent "return original success, never hit the facilitator again" behavior.

### 8.3 New agent-facing reads

```
GET /{originHost}/{locationId}/orders/{orderId}
    Header: X-Customer-Id
    200: OrderDetailsDto + fulfillment
    404: not found, wrong customer, or not yet projected

GET /{originHost}/{locationId}/orders/{orderId}/fulfillment
    Header: X-Customer-Id
    200: FulfillmentDto
    404: order exists but fulfillment not minted (unpaid draft) or wrong customer
```

Authorization: same `X-Customer-Id` as place/confirm. Payer address is recorded only after settle; until then customer-id is the correlator. After settle, optionally also accept a signed `X-PAYMENT` replay as proof, but do not require it for GET — agents will poll from a background session that should not re-sign.

Do **not** reuse `/kitchen/orders/{id}` for agents. The board is unauthenticated and enumerates a shop. That is a kitchen surface.

### 8.4 Fulfillment overlay (new table, new DTO)

```sql
CREATE TABLE order_fulfillment (
    order_id               uuid PRIMARY KEY REFERENCES orders(id),
    logistics_status       text NOT NULL,
    eta_minutes            integer NULL,
    eta_source             text NOT NULL DEFAULT 'none',  -- none|kitchen|courier|system
    tracking_token         text NULL,
    courier_phone          text NULL,
    delivery_label         text NOT NULL,
    delivery_line1         text NOT NULL,
    delivery_line2         text NULL,
    delivery_city          text NOT NULL,
    delivery_region        text NOT NULL,
    delivery_postal        text NOT NULL,
    delivery_country       text NOT NULL,
    delivery_lat           double precision NOT NULL,
    delivery_lon           double precision NOT NULL,
    location_uri           text NOT NULL,
    updated_at             timestamptz NOT NULL
);
```

Wire `logistics_status` (string enum, **not** `OrderStatus`):

| Overlay | When it is written | Kitchen `OrderStatus` still |
| --- | --- | --- |
| `awaiting_kitchen` | minted at settle | `paid` |
| `accepted` | kitchen accept | `accepted` |
| `preparing` | start-preparing | `preparing` |
| `ready_for_dispatch` | mark-ready | `ready` |
| `dispatched` | new kitchen (or courier) command | `ready` or `completed` |
| `delivered` | complete, or courier callback | `completed` |
| `failed` | reject / expire / refund_* | `rejected` / `expired` / `refund_*` |

Client cache maps for Siri:

| Overlay | Spoken class |
| --- | --- |
| `awaiting_kitchen`, `accepted`, `preparing` | PROCESSING_LOGISTICS |
| `ready_for_dispatch`, `dispatched` | DISPATCHED (eta required before we speak minutes) |
| `delivered` | arrived |
| `failed` | FAILED |
| settlement `paid` | SETTLED (Inquiry: "Payment settled. They are organizing a courier." when eta is null) |

`eta_minutes` stays `null` until a kitchen or courier writes it. The acceptance-timeout worker (`AcceptanceTimeoutSeconds=600`) already rejects unpaid-attention tickets; it should also stamp `logistics_status=failed` on the overlay.

### 8.5 New kitchen command: dispatch

Additive tuple, filed in DECISIONS.md:

```
(OrderStatus.Ready, OrderStatus.Completed, Actor.Restaurant)   -- already exists
-- NEW overlay-only command, does not have to change OrderStatus:
POST /{originHost}/{locationId}/kitchen/orders/{id}/dispatch
body: { "eta_minutes": 22, "tracking_token": "…", "courier_phone": null }
```

If the kitchen never learns a courier, `mark-ready` may include optional `eta_minutes` for pickup. Delivery products write `dispatch`.

Do not add `SETTLED` to `OrderStatus`. Settlement is already `paid`.

### 8.6 Projector / SignalR

The outbox projector already upserts the read model and notifies the shop group. Extend the payload with fulfillment fields. Agents **may** subscribe to a new group `order:{orderId}` using a short-lived ticket minted in the 201 body (`fulfillment_ws: /hubs/orders?ticket=…`). Polling GET remains mandatory: iOS background sockets are not a contract.

Recommended poll: 5 s for the first 60 s after settle, 15 s until `eta_minutes != null`, 60 s until terminal. Cap at `AcceptanceTimeoutSeconds + 45 min`.

### 8.7 `ResultHttp` change

201 success path must use `Results.Created(uri, body)` (or equivalent) so `Location` is set. Keep 402 as raw JSON of `X402Challenge` (not ProblemDetails) — already correct.

### 8.8 Guardrails

`GET /guardrails` already exposes shop-side daily cap (payer-keyed, UTC). Gnoshbot's user slider is **stricter** and local. The agent must satisfy **both**. Do not ask the shop to learn the user's slider.

### 8.9 Out of scope for the overlay (do not smuggle in)

- Promote-from-sandbox
- Billing, accounts, shop tokens
- Replacing `X-PAYMENT` with v2 headers
- Merging into `x402-angular`
- Letting Gemini publish production menus
- Scraping DoorDash consumer pages

---

## 9. Client order cache (SwiftData)

The device holds the only state Inquiry Intents may read. Schema is in `GROK.md`. Status values on device are the **spoken classes**, not the kitchen enum:

`launching | placed | settled | processing_logistics | dispatched | delivered | failed`

`trackingUrl` is the 201 `Location`. `etaMinutes` is optional. `settlementTxHash` is the facilitator tx. `shopPrefix` stores `/{originHost}/{locationId}` so we can rebuild URLs. `deliveryLocationId` + denormalized `deliverySpokenLine` are required on every `launching` row; the worker refuses to POST place without them.

Writes happen only on the background worker (or APNs handler). The voice intent writes `launching` **after** location confirmation, before it returns "On it."

---

## 10. Discovery plane (not on the Siri path)

Spatial ingest is a **control-plane** job in us-west-2. It is triggered when the user **saves a delivery location**, on onboarding, and by significant location change (to pre-warm a city they just entered). It is never called from `perform()`. The kitchen search at lunch uses the **confirmed address** bbox, not the phone's GPS.

Bucket and path ([Overture cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/), [DuckDB guide](https://docs.overturemaps.org/getting-data/duckdb/), latest release in that guide **2026-08-19.0**):

```
s3://overturemaps-us-west-2/release/2026-08-19.0/theme=places/type=place/*
```

Lambda / worker: **us-west-2**. Same-region S3 → AWS service transfer is free ([S3 pricing — Data transfer](https://aws.amazon.com/s3/pricing/): "Data transferred from an Amazon S3 bucket to any AWS service(s) within the same AWS Region as the S3 bucket"). Compute in any other region against this bucket is inter-region Data Transfer OUT (~$0.02/GB Oregon → N. Virginia in AWS's own example on that page).

Warm Lambda `/tmp` may cache a metro Parquet slice between invocations (512 MB default, up to 10 GB). That is a hint, not a contract: instances are recycled. Do not design correctness around `/tmp` surviving.

Commercial Places autocomplete is typically billed per thousand requests (Google's published Places tiers have sat in the tens of dollars per thousand). Overture + DuckDB bbox extract is GET-request + compute, with $0 same-region transfer. That is the economic reason ingest lives here instead of a vendor SDK.

Lambda hard limits that bound the worker ([Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)): timeout **900 s**, memory 128–10240 MB, `/tmp` 512–10240 MB, sync payload 6 MB. DuckDB + `spatial` + `httpfs` belongs in a **container image** function (10 GB image) or a Fargate worker, not a 50 MB zip. Cold `INSTALL spatial; LOAD httpfs` is a multi-second event. Provisioned concurrency is optional; the product does not need it because ingest is async.

Query shape that actually prunes (Overture's own pizza example):

```sql
SET s3_region='us-west-2';
SELECT id, names.primary AS name, websites, phones, addresses, categories.primary,
       bbox, geometry
FROM read_parquet(
  's3://overturemaps-us-west-2/release/2026-08-19.0/theme=places/type=place/*',
  filename=true, hive_partitioning=1)
WHERE bbox.xmin BETWEEN :min_lon AND :max_lon
  AND bbox.ymin BETWEEN :min_lat AND :max_lat
  AND (
        categories.primary ILIKE '%restaurant%'
     OR basic_category IN ('restaurant','cafe','bar','meal_takeaway')
     OR list_contains(taxonomy.hierarchy, 'food_and_drink')
  );
```

`categories` is **deprecated**, removal September 2026 ([Places overview](https://docs.overturemaps.org/guides/places/)). Prefer `basic_category` + `taxonomy`. There is no `categories.main` (the source Lambda snippet was wrong). There are **no opening hours**; `operating_status` is `open | permanently_closed | temporarily_closed` and is explicitly not hours of day ([place schema](https://docs.overturemaps.org/schema/reference/places/place/)). Hours come from the shop menu (`open_hours[]` in `ingest.schema.json`) for native/proxy nodes only.

Idempotency, purge, and the skip flywheel: `SCALABILITY.md`.

---

## 11. End-to-end settlement + fulfillment (shop v1)

```
Agent                         Shop                         Facilitator / Base
  |                             |                              |
  | POST /orders + delivery     |                              |
  | 201 Location                |                              |
  |<----------------------------|                              |
  | POST /confirm (no pay)      |                              |
  | 402 + accepts[]             |                              |
  |<----------------------------|                              |
  | sign EIP-3009 (spender)     |                              |
  | POST /confirm X-PAYMENT     |  POST /verify, /settle       |
  |                             |----------------------------->|
  |                             |<-----------------------------|
  | 201 Location: /fulfillment  |                              |
  |<----------------------------|                              |
  | GET /fulfillment  (eta null, logistics=awaiting_kitchen)   |
  |                             |  kitchen accept / dispatch   |
  | GET /fulfillment  (eta 22, dispatched)                     |
```

Money is done at the 201. ETA is a later GET. Siri is long gone.

---

## 12. Failure matrix after the voice channel closes

| Failure | Detection | User |
| --- | --- | --- |
| 402 after sign (price moved, but shop snapshots at place — should not happen) | confirm 402 with new accepts | APNs; do not auto-resign above remaining allowance |
| Facilitator `verify` invalid | 402 body `error` | APNs "Launch aborted: payment rejected." |
| Facilitator settle failed | 402 | APNs; draft still live until TTL |
| Draft TTL 300 s elapsed | confirm 409 | APNs "The hold expired. Say the word and I'll retry." |
| Kitchen reject | overlay `failed`, refund rail | APNs "Kitchen declined. Refund in flight." Inquiry reads `refund_pending` |
| Overlay never grows an ETA | poll cap | Inquiry: "Paid. Still waiting on the kitchen for a time." Never invent minutes |
| iOS killed the worker mid-402 | `launching` row older than 15 s with no `trackingUrl` | next Inquiry or next BG refresh retries **place** with the same Idempotency-Key (safe) then confirm |

Place is idempotent on `(customerId, Idempotency-Key)`. Confirm is idempotent on payment payload hash / order id. Retries are safe if the worker died after 201 and before local cache write.

---

## 13. Trust boundaries

- Allergy data never leaves the device (see `PRODUCT_DECISIONS.md`). The CAG prompt receives a **boolean mask** ("exclude peanuts") computed locally against menu text, not the medical record.
- Delivery addresses live on device and are sent to the shop host **only** after a voice yes, as the place `delivery` snapshot. They are not medical; they are still PII. Do not put them in skip logs or B2B outreach.
- `payTo` is origin-asserted. The agent refuses to sign an `accepts[].payTo` that does not match the menu's `payTo` snapshot from GET menu / place `OrderDto.payTo`.
- The shop's daily cap and the user's slider both bind. The spender's Spend Permission is the on-chain enforcement; the slider is the UX enforcement; the shop cap is the merchant enforcement.
- Sandbox shops (`/_sandbox/{id}/`) are not production. Gnoshbot's live pool is origin prefixes only, plus Gnoshbot-operated proxy wraps that **are** origin wraps of a Menu Pull the proxy itself hosts — not upload-sandbox TTLs.

---

## 14. What this document refuses to claim

- Sub-second on-chain settlement.
- Overture as a live "open now" oracle.
- `Task.detached` as a background scheduler.
- ERC-7710 as an iOS biometric exemption.
- A global restaurant registry Gnoshbot KYCs.
- Predictive ETAs as user-visible truth.
- Shipping food to device GPS, "last known location," or an unconfirmed default.
- Skipping location confirmation when the user has only one saved address.
