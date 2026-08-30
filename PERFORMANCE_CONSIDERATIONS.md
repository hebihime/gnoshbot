# Gnoshbot Performance Considerations

## Why this exists

Siri will not wait for a vector database, a facilitator, or Base. Apple gives an App Intent 30 seconds of CPU and may cut the spoken result much earlier ([Forums 832257](https://developer.apple.com/forums/thread/832257), [WWDC26 345](https://developer.apple.com/videos/play/wwdc2026/345/)). The product target is two snappy voice turns: a **sub-500 ms** location confirmation prompt, then after yes a **sub-500 ms** "On it." Everything that is not a local guard, a saved-address read, or a local pick runs after that return.

`requestConfirmation` is a Siri turn, not network. It does not count against the 500 ms pick budget; it **is** the wait we owe the user.

This file is the latency budget, the Cache-Augmented Generation design that makes the pick local, and the background-handoff machinery that keeps the OS from killing the payment.

---

## 1. Latency budget

| Stage | Budget | Where | Notes |
| --- | --- | --- | --- |
| Intent process start | 0–80 ms | OS | Cold App Intent in a terminated app can exceed this. Mitigate: keep the app resident via significant-location and a daily BG refresh so the process is warm at lunch. |
| SwiftData guard reads | 10–30 ms | device | Allowance, funded flag, saved `DeliveryLocation` rows. **Hard cap to first spoken prompt: 500 ms.** |
| Location confirmation | user turn | Siri | `requestConfirmation`. No network. No GPS fix. |
| After yes: CAG pick | 50–300 ms | device | Menus already cached for that address's geohash. v1 prefers local scorer. |
| Persist `launching` row | 10–20 ms | device | Includes `deliveryLocationId`. |
| `beginBackgroundTask` + enqueue URLSession | 10–20 ms | device | |
| `return .result("On it.")` | — | — | **Hard cap: 500 ms from the yes.** |
| Place + 402 + settle | 1–8 s | background | Facilitator + chain. Not on the voice clock. Place body includes the confirmed `delivery` snapshot. |
| First fulfillment GET with eta | 30 s–10 min | background | Kitchen time. APNs when it lands. |

If, **after yes**, `perform()` is still running at 400 ms with no pick, it returns "On it." anyway and the worker runs the pick. The user never waits on a model. The user **does** wait on their own yes.

### 1.1 What is forbidden on the voice clock

- `GET` menu over the network
- DuckDB / Overture
- LLM HTTP if p95 > 150 ms
- `X-PAYMENT` construction
- `sendUserOperation`
- Geocoding a new street the user just spoke
- Fresh GPS as a destination
- Photo / vision

### 1.2 Warmth

A lunch-hour cold start of a terminated process will blow 500 ms before `perform()` even runs. Mitigations, in order:

1. Significant-location relaunches (travel) keep the process plausible.
2. `BGAppRefreshTask` requested with `earliestBeginDate` around the user's historical lunch window (from `order_history_metrics`). The system may ignore this ([Choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app): up to 30 s, not guaranteed).
3. After the first successful lunch, the OS's own heuristics favor apps the user actually uses. The first week is the dangerous week: onboarding should leave the app in memory (user is still in the wizard) and pre-warm the region cache **before** they first talk to Siri.

Do not buy provisioned-concurrency Lambda for the voice path. The voice path does not call Lambda.

---

## 2. Cache-Augmented Generation

### 2.1 Why not RAG at lunch

Retrieval-augmented generation adds an embedding query, a vector round trip, and chunk assembly to the critical path. That is the opposite of a Siri budget. Cache-Augmented Generation (CAG) preloads the working set into the model's context (or into a local scorer that occupies the same architectural slot) so generation does not retrieve.

Reference: "Don't Do RAG: When Cache-Augmented Generation is All You Need for Knowledge Tasks" (arXiv:2412.15605) — [https://arxiv.org/abs/2412.15605](https://arxiv.org/abs/2412.15605). The result that matters here is empirical: for a **bounded, stable** knowledge set, preloading beats retrieve-then-read on latency at equal quality.

Gnoshbot's working set is bounded by construction:

- 1 user profile envelope (decrypted Bio-Shield + Flavor Fingerprint + remaining allowance)
- 1 confirmed `DeliveryLocation`
- ≤ 10 payable restaurants in the 5-mile box **around that address**
- ≤ 5 candidate items per restaurant after local filters
- 2 tools (`select_and_order_native_node`, `log_skipped_legacy_merchant`)

That is a few tens of kilobytes of JSON, not a corpus.

### 2.2 What is cached, where, when

| Object | Store | Written | Read |
| --- | --- | --- | --- |
| Region restaurants + x402 status | device SwiftData `RestaurantCache` | onboarding, significant-location, silent push from control plane | CAG assembly |
| Menu JSON for NATIVE / PROXY_WRAPPED | device SwiftData `MenuCache` | when status becomes payable; refreshed on BG refresh | CAG assembly |
| Profile envelope | SE-wrapped blob | wizard | decrypt in `perform()` |
| Tool schemas | bundled constant | ship | every pick |
| Skip log (outbox) | SwiftData | tool path B | flushed by background worker |

Control plane may hold the same restaurant index for ingest/purge. The **voice path does not consult it**.

### 2.3 Assembly (every launch)

```
context = {
  profile: decrypt(bioShield + fingerprint + remainingUsdc),
  now: ISO8601,
  delivery: confirmedLocation,              // saved row, just confirmed
  candidates: MenuCache
                .filter(distance ≤ 5 mi from confirmedLocation)
                .filter(integration in {native, proxy_wrapped})
                .filter(bioShieldPass)
                .filter(neverIngredientsPass)
                .sorted(flavorScore desc)
                .prefix(10)
}
```

No GPS during `perform()`. A fresh CLLocation can take seconds and is the wrong destination besides ([Getting the current location](https://developer.apple.com/documentation/corelocation/getting-the-current-location-of-a-device)). Lunch uses the confirmed saved address. Speaking "On it." toward a GPS ping the user did not confirm is a product defect.

### 2.4 Picker implementation

v1 ships a **deterministic scorer** as the CAG occupant (same inputs, same outputs, no token variance, sub-20 ms). An on-device or near-device LLM is allowed to replace it when:

- p95 complete-to-tool-call < 200 ms on a warm A-series device, and
- structured tool-call only (no free text orders), and
- the runtime still applies the Bio-Shield veto after the call.

Until those gates are measured in a device lab, the scorer **is** the picker. The tool schema remains so a model swap does not change the worker.

Scorer:

```
best = argmax_item flavorScore(item)
require item.costUsdc <= remainingAllowance
require item.shop.integration in {native, proxy_wrapped}
emit select_and_order_native_node(...)
for each UNSUPPORTED restaurant with flavorScore > best.score:
    emit log_skipped_legacy_merchant(...)   // async, not on the voice clock
```

Skipped merchants are queued for the worker. They do not block "On it."

### 2.5 Menu cache freshness

Menus are living on the shop host (re-GET every `PullPollSeconds=300` plus ping). Device `MenuCache`:

- TTL 15 minutes for the active region.
- BG refresh / significant-location / post-lunch worker: `GET /{origin}/{loc}/menu` for each cached payable prefix, replace on 200, keep last-good on failure (same fail-closed idea as the shop).
- Hash the JSON; skip SwiftData write if unchanged.

Stale prices: the shop **reprices at place** and locks the snapshot. If the agent's guessed `cost_usdc` disagrees with `OrderDto.Total`, the worker still pays the **server** total if it is ≤ remaining allowance and ≤ slider; otherwise it aborts and APNs "Price moved past your allowance." The agent never injects a price on place (`PlaceOrderHttpRequest` has menu item ids and quantities only).

### 2.6 Memory

Ten menus of a few hundred items is fine in RAM. Do not load Overture's global places file onto the phone. Do not embed DuckDB in the iOS app. DuckDB stays in us-west-2.

---

## 3. Sub-500 ms confirmation vs background work

### 3.1 The wrong pattern

```swift
Task.detached(priority: .high) {
    try await agent.processBackgroundM2MOrder() // uses GPS, no address confirm
}
return .result(dialog: "Your meal will arrive in \(predictiveETA) minutes.")
```

Three defects: (1) `Task.detached` is not a background assertion — when the intent process suspends, the task is frozen or killed ([iOS background execution limits](https://developer.apple.com/forums/thread/685525)); (2) the dialog asserts minutes that do not exist yet; (3) no delivery-location confirmation, so food can leave toward a coordinate the user did not accept.

### 3.2 The right pattern

1. Work that must complete in `perform()`: guards, pick (or defer pick), insert `launching` row, **create a background assertion**, schedule a `URLSession` background request (or a chain of them).
2. Return "On it."
3. Session delegate, running in the app's background relaunch, performs place → confirm 402 → sign → confirm pay → GET fulfillment. Each HTTP call is a `URLSession` task so the system can continue it.
4. On each terminal or interesting state, write SwiftData and send a local/remote push.

`beginBackgroundTask(withName:expirationHandler:)` covers the common case where the app is already running and lunch takes < ~30 s of network ([Extending your app’s background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)). Pair it with background `URLSession` so a longer facilitator delay does not depend on that assertion.

`LongRunningIntent` is available on iOS 26+ and lifts the 30 s cap with a system Live Activity ([Creating your first app intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent), [WWDC26 345](https://developer.apple.com/videos/play/wwdc2026/345/)). **Do not use it for launch.** A Live Activity is a UI confession that the missile is still on the rail. Use it, if ever, for an explicit "track my order" intent the user asked to watch.

### 3.3 Signing cost

EIP-3009 typed-data sign on a software Keychain EOA is milliseconds. A CDP `sendUserOperation` is a network round trip and must not run in `perform()`. If the spender path needs a UserOp (USDC sitting on the Smart Account), that UserOp is background.

### 3.4 APNs vs local notifications

Local notifications work if the process is alive. If the OS killed us after URLSession completed in the system daemon, the session's completion relaunch can post a local notification. For kitchen-driven ETA updates minutes later, the **shop host** (or Gnoshbot control plane polling the shop) must send a **remote** silent or alerting push. Budget: one alerting push per state class (settled, eta-available, dispatched, failed). Do not push every poll.

---

## 4. On-device database performance

- `ActiveOrderCache`: one hot row. Index on `timestamp` descending. Inquiry fetches `prefix(1)`.
- `RestaurantCache`: GERS id primary key, spatial prefilter is "haversine in Swift against last location," not PostGIS on device. 5-mile box around a city is thousands of rows, not millions. Linear scan is fine; if not, store a geohash7 and filter equality.
- `MenuCache`: blob JSON + hash. Do not normalize extras into relational rows on device unless profiling says so.
- Encrypting the profile is one AES-GCM decrypt per launch (~1 ms). Do not decrypt on every Inquiry.

SwiftData + App Intents: use an app-group container so the intent (main app process) and any extension share the store. Prefer running the intent in the **application** process (`ExecutionTargets`) to avoid opening the store from two processes.

---

## 5. Control-plane performance (not voice)

Overture bbox extract is a worker with a 900 s Lambda ceiling ([Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)). It must:

- `SET s3_region='us-west-2'`
- filter `bbox.xmin/ymin` (and `xmax/ymax` if not a point) **before** `ST_Intersects`
- project only `id, names.primary, websites, phones, addresses, categories/taxonomy, geometry`
- write Postgres with `ON CONFLICT (overture_id) DO NOTHING`

DuckDB httpfs range reads Parquet footers and the row groups the bbox stats admit ([HTTP(S) Support](https://duckdb.org/docs/current/core_extensions/httpfs/https.html), [Overture DuckDB](https://docs.overturemaps.org/getting-data/duckdb/)). A 5-mile box is small. The failure mode is forgetting the bbox filter and scanning the theme. That will time out and run up S3 GET counts (S3 GET is billed even when transfer to Lambda in-region is free — [S3 pricing](https://aws.amazon.com/s3/pricing/)).

Pin a release id (`2026-08-19.0` or newer). Do not glob `release/theme=places` without a date; that is not a valid layout.

`/tmp` on Lambda is 512 MB by default, raisable to 10 GB. DuckDB spill belongs there. Memory: start at 2048 MB (about one vCPU); raise if EXPLAIN ANALYZE says so.

Cold start: accept seconds. This job is triggered by saving an address, onboarding, and travel, never by Siri. Optionally keep one provisioned concurrent worker during the first week in a new city if ingest latency is user-visible in the address editor; the editor should say "Mapping kitchens nearby…" and not block Save.

---

## 6. SLOs

| Metric | SLO | Measurement |
| --- | --- | --- |
| Voice: location prompt | p95 < 500 ms to first spoken address | os_signpost until `requestConfirmation` |
| Voice: "On it." after yes | p95 < 500 ms, p99 < 900 ms | os_signpost from yes to return |
| False-start: food toward unconfirmed dest | **0** | invariant test |
| Time to `settled` cache write | p95 < 8 s on Base mainnet happy path | worker timestamps |
| Time to first non-null eta | not an SLO (kitchen) | — |
| Inquiry intent | p95 < 50 ms | os_signpost |
| Region ingest for a 5-mile box | p95 < 30 s after first trigger | worker |
| False-start rate (said "On it." then failed pay) | < 2 % | APNs fail / launch |

False-starts are the cost of the architecture. Drive them down with a better funded-flag (refresh USDC balance on BG refresh, not at lunch) and by refusing to launch when remaining Spend Permission allowance is below the region's p20 item price.

---

## 7. Anti-patterns

- Vector DB on the lunch path.
- `openAppWhenRun = true`.
- `LongRunningIntent` for the silent launch.
- Predictive minutes in the launch dialog.
- Fresh GPS as a destination in `perform()`.
- Skipping `requestConfirmation` when only one address is saved.
- DuckDB in-process on iOS.
- Waiting for `getUserOperation` receipt before returning to Siri.
- Loading more than 10 menus into the picker context "for quality."
