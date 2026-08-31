# Gnoshbot iOS (frontend) — atomic execution plan

Status: execution slice. Not source of truth. If this file disagrees with `GROK.md` or a dated supersession in `PRODUCT_DECISIONS.md`, stop and fix this file.

Repo surface: `gnoshbot-ios/`. Today: `Package.swift` + `ActiveOrderCache.swift` (SwiftData models only). There is no Xcode app, no App Intent, no wallet, no settlement worker.

Shop overlay (`delivery` on place, `Location`, `GET …/fulfillment`) lives in `~/Repos/web3-restaurant-api`. Settlement and ETA steps below are blocked until that overlay exists. Do not invent kitchen `OrderStatus` tuples here.

Do not: `openAppWhenRun = true`; `LongRunningIntent` for launch; `Task.detached` as the background strategy; DuckDB/Overture in `perform()`; `.userPresence` / `.biometryAny` on the spender key; spoken minutes before fulfillment `eta_minutes`; GPS as destination; skip `requestConfirmation` when only one address is saved.

Commit each atom with Conventional Commits (`GROK.md`). Body is why.

---

## I0 — Xcode application target

**Depends on:** none  
**Files:** new `gnoshbot-ios/Gnoshbot.xcodeproj` (or `Project.swift` if Tuist later; default: Xcode), `GnoshbotApp.swift`, `Info.plist` keys  
**Do:** iOS 17+ app, bundle id `com.gnoshbot`, run App Intents in the **application** process (`ExecutionTargets` → application), not a widget extension. App group `group.com.gnoshbot` for SwiftData. `NSLocationAlwaysAndWhenInUseUsageDescription` names travel ingest, not “we send food wherever you are.” Background modes: `fetch`, `remote-notification`, `processing` only as later atoms need them.  
**Do not:** widget-extension intents; putting the store only in the extension container.  
**Done when:** empty app launches on simulator; Swift package `GnoshbotData` is a target dependency; app group entitlement present.

---

## I1 — SwiftData container + `GnoshbotStore`

**Depends on:** I0  
**Files:** `ActiveOrderCache.swift` (existing), new `RestaurantCache` / `MenuCache` / `ProfileBlob` as in `GROK.md`; `GnoshbotStore.swift`  
**Do:** `ModelContainer` in the app group. `GnoshbotStore.shared` with `deliveryLocations()`, `defaultDeliveryLocation()` (`isDefault` else `lastConfirmedAt`), `latestOrder()` via `ActiveOrderInquiry.latestDescriptor()` (`fetchLimit = 1`, `timestamp` reverse).  
**Do not:** network in store reads used by Inquiry.  
**Done when:** unit test inserts `DeliveryLocation` + `ActiveOrderCache` and `latestOrder()` returns that row in-process without HTTP.

---

## I2 — `DeliveryLocationEntity` + query

**Depends on:** I1  
**Files:** `DeliveryLocationEntity.swift`, `DeliveryLocationQuery.swift`  
**Do:** `AppEntity` matching `GROK.md` (`id`, `spokenLine`). `spokenLine` format: `{label}, {line1}{, line2}?, {city}?` (`PRODUCT_DECISIONS.md` §4.6). Query reads SwiftData only.  
**Done when:** entity resolves for a saved row; unknown id returns empty, not a geocoded street.

---

## I3 — Fatal local copy (no network)

**Depends on:** I2  
**Files:** `LaunchCopy.swift`  
**Do:** exact strings from `PRODUCT_DECISIONS.md` §1.5: no addresses; declined confirm; unknown label; allowance 0; `funded == false`; no payable kitchen in 5-mile box of **confirmed** address; Bio-Shield empties the box.  
**Done when:** table-driven tests assert those strings; no interpolation of merchant/SKU/price/minutes.

---

## I4 — `OrderLunchIntent` guards + confirmation only

**Depends on:** I3  
**Files:** `OrderLunchIntent.swift`  
**Do:** `openAppWhenRun = false`, `supportedModes = [.background]`. Guards: allowance, `fundedFlag`, ≥1 `DeliveryLocation`. Then `$deliveryLocation.requestConfirmation(for: proposed, dialog:)` **every launch**. Cancel/false → `"No order placed."` No `POST /orders`. No pick yet: if no payable cache, speak the empty-pool line **after** yes only if the box is empty; before yes never.  
**Do not:** return “On it.” before confirmation; use GPS; geocode a spoken street.  
**Done when:** UI test or App Intent test: zero addresses → add-address line; cancel confirm → no `ActiveOrderCache` row.

---

## I5 — `GnoshbotShortcuts`

**Depends on:** I4  
**Files:** `GnoshbotShortcuts.swift`  
**Do:** phrases exactly: “Tell \(\.applicationName) I'm hungry”, “Ask \(\.applicationName) to order lunch”, “Order lunch with \(\.applicationName)”.  
**Done when:** shortcuts appear in the Shortcuts app for the debug build.

---

## I6 — Addresses editor (Band A)

**Depends on:** I1  
**Files:** `AddressesView.swift`, `AddressEditorView.swift`  
**Do:** list label, one-line address, Default badge. Add: MapKit search + pin + Contacts. Fields: unique label, line1, optional line2, city, region, postal, country. Geocode at save; refuse save if geocode fails. “Use current location” only here, on a visible map, then Save. Caption: Siri reads this back; GPS is not drop-off. Empty: “Gnoshbot will always ask before sending food. Add Home to start.” Exactly one `isDefault`. Delete last address disables Siri ordering (store flag).  
**Do not:** Siri creating addresses.  
**Done when:** save persists lat/lon immutable until edit; unique label constraint enforced.

---

## I7 — `POST /regions/ensure` on save (not in `perform()`)

**Depends on:** I6, backend `B3`  
**Files:** `RegionEnsureClient.swift`  
**Do:** 5-mile (8046.72 m) geodesic bbox around **saved** coordinates. `Idempotency-Key: {userId}:{geohash5}:{release}`. `reason: "saved_address"` (or `"onboarding"` at engage). 200 ready / 202 running. Wizard copy while 202: “Mapping kitchens nearby.”  
**Do not:** call from `OrderLunchIntent.perform()`.  
**Done when:** saving Home hits ensure with finite lat/lon; intent path has zero `URLSession` to the control plane.

---

## I8 — Phase 1 Bio-Shield UI

**Depends on:** I0  
**Files:** `BioShieldView.swift`  
**Do:** `PRODUCT_DECISIONS.md` §2: 44×44 cards, allergens + frameworks slugs lowercase, custom exclusions NFC-normalized. Footer fail-closed copy. No iCloud allergy backup.  
**Done when:** selecting Peanut sets slug `"peanut"` in the in-memory draft; Reduce Motion has no bounce.

---

## I9 — Phase 2 Flavor Fingerprint UI

**Depends on:** I8  
**Files:** `FlavorView.swift`  
**Do:** crave chips, never-order chips + text field, spice Mild/Medium/High default Medium. Scoring constants live in I12, not this view.  
**Done when:** draft JSON matches §3.3 shape.

---

## I10 — `ProfileBlob` SE wrap

**Depends on:** I8, I9  
**Files:** `ProfileSeal.swift`  
**Do:** `SecureEnclave.P256` key agreement, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, **no** `.userPresence`. AES-GCM `{ ciphertext, nonce, wrappedKey }` in SwiftData. Envelope includes Bio-Shield + flavor + slider remaining (not delivery addresses). Decrypt in `perform()` for CAG; wipe plaintext. Locked-since-boot: “Unlock your iPhone and ask again.”  
**Do not:** plaintext allergen columns; Face ID to read allergies at lunch.  
**Done when:** test encrypt/decrypt round-trip; Inquiry intents do not decrypt.

---

## I11 — `RestaurantCache` + `MenuCache` hydration

**Depends on:** I7, backend `B4`  
**Files:** `CacheHydrator.swift`  
**Do:** on `region-ready:{geohash5}` silent push or 200 from ensure, pull payable prefixes into `RestaurantCache`. `GET /{origin}/{loc}/menu` for each payable prefix (shop host, not Overture). TTL 15 min. Hash JSON; skip write if unchanged. Keep last-good on failure. `integration` in `{unsupported, native, proxy_wrapped}`. Sandbox `/_sandbox/` prefixes **not** in live pool.  
**Done when:** fixture menu JSON lands in `MenuCache`; sandbox prefix rejected.

---

## I12 — Deterministic CAG scorer (v1 picker)

**Depends on:** I10, I11  
**Files:** `LunchScorer.swift`, `BioShieldMatcher.swift`  
**Do:** working set ≤10 restaurants, ≤5 items each, 5-mile of **confirmed** `DeliveryLocation`. Bio-Shield fail-closed on name/description (+ synonym table). `neverIngredients` drop. Score: +3 cuisine ∩ preferred, +1 meal type, +1 spice, −2 missing cuisine, −100 never → drop. `costUsdc` local guess ≤ remaining allowance. Emit `select_and_order_native_node` or abort empty payable. Queue `log_skipped_legacy_merchant` for UNSUPPORTED culinary winners **off** the voice clock. Ignore model-invented prices later. No LLM until p95 tool-call &lt; 200 ms measured in lab.  
**Do not:** RAG; load more than 10 menus “for quality.”  
**Done when:** fixture menus + peanut shield drops peanut items; empty payable → exact copy from I3.

---

## I13 — Insert `launching` + “On it.” after yes

**Depends on:** I4, I12  
**Files:** `OrderLunchIntent.swift`, `GnoshbotStore.swift`  
**Do:** after confirm, pick (or defer pick if clock &gt; 400 ms). `insertLaunching` with `deliveryLocationId` + `deliverySpokenLine`. Return `"On it."` p95 &lt; 500 ms from yes. No minutes, merchant, SKU, USDC in that dialog.  
**Done when:** signpost test or documented manual: yes → launching row → dialog; no `X-PAYMENT` in that stack.

---

## I14 — `beginBackgroundTask` + background `URLSession`

**Depends on:** I13  
**Files:** `GnoshbotBackground.swift` as `GROK.md`  
**Do:** identifier `com.gnoshbot.settlement`, `sessionSendsLaunchEvents = true`, `waitsForConnectivity = true`. Expiration handler `endBackgroundTask`.  
**Do not:** `Task.detached` as the assertion; `LongRunningIntent` for launch.  
**Done when:** killing the intent process still leaves a system background session (manual: Charles/Proxyman sees later POSTs).

---

## I15 — Spender EOA Keychain (no biometry)

**Depends on:** I0  
**Files:** `SpenderKey.swift` as `GROK.md`  
**Do:** tag `com.gnoshbot.spender.ecdsa`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, empty flags.  
**Done when:** unit test: key exists; access control has no `.userPresence` / `.biometryAny`.

---

## I16 — CDP Smart Account + Spend Permission (ENGAGE)

**Depends on:** I15, I6  
**Files:** `EngageSystem.swift`, CDP Swift package  
**Do:** Base `EthereumConfig(createOnLogin: .smart)`, `useCdpPaymaster: true`. Slider $10–$50 USDC default $25, `periodInDays: 1`, allowance atomic 6 decimals. Copy says “every 24 hours,” not “midnight.” ENGAGE disabled until ≥1 address AND Smart Account AND spend-permission user-op submitted AND Siri auth requested. Funding may be $0.  
**Do not:** Face ID per lunch.  
**Done when:** engage persists `engaged = true`; spender exists; slider in sealed envelope.

---

## I17 — Funded flag + remaining allowance (not at lunch over network)

**Depends on:** I16  
**Files:** `BalanceRefresh.swift`  
**Do:** refresh USDC + remaining Spend Permission on BG refresh, not in `perform()`. `fundedFlag` cached. Remaining 0 → launch deny copy.  
**Done when:** `perform()` reads only local flags.

---

## I18 — `SettlementWorker` place + confirm 402 + pay (shop v1)

**Depends on:** I14, I15, shop overlay in `web3-restaurant-api`  
**Files:** `SettlementWorker.swift`, `X402V1.swift`  
**Do:** refuse without `delivery`. `POST /{origin}/{loc}/orders` with `Idempotency-Key`, `X-Customer-Id` (opaque device-stable, not wallet), `delivery` snapshot. `POST confirm` without payment → JSON 402 `accepts[]`. Assert `payTo` == place snapshot. `maxAmountRequired` ≤ remaining slider and ≤ shop guardrails. Sign EIP-3009 with spender. `X-PAYMENT` base64 JSON v1. Money: cents / USDC atomic (`cents × 10_000`). Dual-stack: v1 to shop host; v2 headers only if `x402_version == 2` and not shop. On 2xx: `trackingUrl` = `Location`, status `settled`, `settlementTxHash`. APNs: “Paid. Kitchen is on it.”  
**Do not:** inject price on place; speak minutes here.  
**Done when:** integration test against shop fixture: 201 Location, cache `settled`, eta still null.

---

## I19 — Fulfillment poll

**Depends on:** I18  
**Files:** `FulfillmentPoller.swift`  
**Do:** `GET …/fulfillment` with `X-Customer-Id`. 5 s first 60 s, 15 s until `eta_minutes != null`, 60 s until terminal. Cap `AcceptanceTimeoutSeconds + 45 min`. Map overlay → spoken class (`GROK.md` / `ARCHITECTURE.md` §8.4). First non-null eta → APNs “Arriving in {n} minutes.” Never invent minutes.  
**Done when:** fixture GET with `eta_minutes: 22` writes cache and would post that copy.

---

## I20 — Inquiry intents (local only)

**Depends on:** I1, I19 mapping  
**Files:** `CheckOrderStatusIntent.swift`, `WhereIsItGoingIntent.swift`, `WhatDidYouOrderIntent.swift`, `WhatDidItCostIntent.swift`  
**Do:** SwiftData only. Copy from `GROK.md` / `PRODUCT_DECISIONS.md` §1.3. Dispatched remaining minutes from `etaMinutes` and `timestamp`, never a predictive model.  
**Done when:** no `URLSession` in these types; p95 fetch path is a single `FetchDescriptor`.

---

## I21 — `CancelLunchIntent`

**Depends on:** I18  
**Files:** `CancelLunchIntent.swift`  
**Do:** speak “Cancelling.” Worker POSTs shop cancel/refund path.  
**Done when:** draft cancel hits shop; paid path follows shop refund overlay, not a invented reverse-settle.

---

## I22 — Failure matrix after voice close

**Depends on:** I18  
**Files:** `SettlementWorker.swift`  
**Do:** `ARCHITECTURE.md` §12: 402 after sign, facilitator reject, draft TTL 409, kitchen reject overlay `failed`, poll cap with no eta, `launching` older than 15 s without `trackingUrl` → retry place same Idempotency-Key.  
**Done when:** each case writes `failed` or retries as specified; APNs copy from §1.6.

---

## I23 — Significant-change pre-warm (not drop-off)

**Depends on:** I16, I7  
**Files:** `TravelIngest.swift`  
**Do:** `startMonitoringSignificantLocationChanges()` after ENGAGE. Haversine vs `last_ingest_center`; if ≥ 5 miles, `POST /regions/ensure` `reason: "significant_location"` and upsert travel center on control plane (`user_locations`).  
**Do not:** `startUpdatingLocation` in background; deliver to last_known.  
**Done when:** displacement &lt; 5 miles updates last_known only (client + `POST` only if API exists for that; otherwise local until backend `B8`).

---

## I24 — `BGAppRefreshTask` lunch-window warmth

**Depends on:** I17, I11  
**Files:** `RefreshScheduler.swift`  
**Do:** `earliestBeginDate` near historical lunch; 30 s budget; not guaranteed. Refresh menus + funded flag. Force-quit: no refresh (Apple).  
**Done when:** registered identifier; handler ends task.

---

## I25 — Post-engage chrome

**Depends on:** I16, I19  
**Files:** `HomeView.swift`  
**Do:** `PRODUCT_DECISIONS.md` §5: order card, addresses, remaining allowance, fund/revoke, Bio-Shield/flavor editors, revoke autonomous ordering. SKU behind explicit tap. No restaurant feed, cart, tip, stars, “send to wherever I am.”  
**Done when:** last address deleted disables launch; revoke deletes spender + on-chain revoke.

---

## I26 — Invariant tests

**Depends on:** I4, I13, I18  
**Files:** `GnoshbotTests/`  
**Do:** false-start food toward unconfirmed dest = **0**; launch dialog has no minutes/merchant/SKU/price; spender ACL has no biometry; no DuckDB import in app target.  
**Done when:** CI `xcodebuild test` green on those cases.

---

## Order (critical path)

I0 → I1 → I2 → I3 → I4 → I5 → I13 (pick stub ok) → I14  
I6 → I7 → I11 → I12 before production pick  
I8 → I9 → I10 before Bio-Shield-true pick  
I15 → I16 → I17 → I18 (blocked on shop overlay) → I19 → I20  
I21–I26 parallel to taste once I18 exists.

**Externally blocked:** I18–I19, I21 paid-path, I22 kitchen-reject until `web3-restaurant-api` overlay PR.
