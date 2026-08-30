# Gnoshbot control plane (backend) — atomic execution plan

Status: execution slice. Not source of truth. `GROK.md` wins.

Repo surface: `gnoshbot-backend/` + `database/`. Cheap AWS (Neon + Function URL + async ingest Invoke) lives in `infra/` — see `plans/infrastructure.md`. This plane does not need RDS, ALB, or SQS.

## Progress (2026-08-31)

| Atom | State | Notes |
| --- | --- | --- |
| B0 | **done** | Production rejects documented secrets; `us-west-2`; pin `OVERTURE_RELEASE`. Demo/`GNOSHBOT_INGEST=0` sets `ingestEnabled=false`. |
| B1 | **done** | `{ error, code }`, `X-Request-Id`, no SQL in 500s. |
| B2 | **done** | Required `Idempotency-Key`; finite bbox; `reason`. |
| B3 | **done** | Tile machine + PostGIS concurrent-ensure test. |
| B4 | **done** | Payable prefixes only; `/_sandbox/` excluded. |
| B5 | **done** | Literal `bbox.*`, dual-read categories, pinned glob. |
| B6 | **done** | NATIVE/PROXY_WRAPPED not overwritten from Overture. |
| B7 | **done (cheap)** | HTTP enqueues via async `lambda:Invoke` (`enqueue.ts`, `worker.ts`). Unset `INGEST_LAMBDA_FUNCTION_NAME` is a no-op. **Not** SQS. Demo never enqueues. Live Invoke still needs apply + ECR push. |
| B8 | TBD | `user_locations` table exists; no public route until a GROK one-liner (`POST /devices/location`). |
| B9 | **done** | HMAC `user_id_hash`; no street/wallet; 404 unknown POI. |
| B10 | **done** | UUID + token upsert. |
| B11 | TBD | GROK one-liner + subscriber table; APNs is N10. |
| B12 | TBD | Skip aggregates, no outreach. |
| B13 | TBD | Encrypted PROXY_WRAPPED menu write. Helpers in `menu-schema.ts`. |
| B14 | **code** | SQL function + EventBridge `{action:purge}`. Far-away UNSUPPORTED fixture test TBD. |
| B15 | TBD | STAC rollover dry-run. |
| B16 | **done** | `bun test` in CI with compose PostGIS. |
| B17 | **code** | `assertPayToMatchesSnapshot` / `centsToUsdcAtomic` exist; dedicated unit file TBD. |
| Shop overlay | other repo | `~/Repos/web3-restaurant-api`. |

This plane is **never** on the Siri path. No lunch-path dependency (`GROK.md`).

Shop fulfillment overlay is **not** this repo. File `DECISIONS.md` in `~/Repos/web3-restaurant-api` and implement there. Backend atoms that mention fulfillment mean: consume shop `Location` / GET only from iOS, or optional later poller in B12.

Do not: auto SMS/Fax/email Overture contacts; store skip-log street addresses or raw user ids; overwrite `NATIVE`/`PROXY_WRAPPED` metadata from Overture; run DuckDB without literal `bbox.*` predicates; glob `release/` without a pinned date.

Commit each atom with Conventional Commits. Body is why.

---

## B0 — Config without fake production secrets

**Depends on:** none  
**Files:** `src/config.ts`  
**Do:** fail boot if `SKIP_LOG_HMAC_SECRET` or `MENU_WRAP_KEY_HEX` are the documented dev defaults **when** `NODE_ENV=production` (or `GNOSHBOT_ENV=production`). Keep local defaults for `bun run dev`. Pin `OVERTURE_RELEASE` (default `2026-08-19.0`). `AWS_REGION` must be `us-west-2` in production.  
**Done when:** production boot without secrets exits nonzero; dev still starts.

---

## B1 — Request IDs + structured errors

**Depends on:** B0  
**Files:** `src/app.ts`  
**Do:** JSON errors `{ error, code }`. 400 validation vs 500 unexpected. Do not leak SQL.  
**Done when:** invalid bbox still 400; thrown `query` error is 500 without query text.

---

## B2 — `Idempotency-Key` on `POST /regions/ensure`

**Depends on:** B1  
**Files:** `src/app.ts`, `src/regions.ts`  
**Do:** require header `Idempotency-Key` grain `{opaqueUser}:{geohash5}:{release}` (`SCALABILITY.md` S3). Parse JSON `min_lon, min_lat, max_lon, max_lat, reason` in `onboarding | significant_location | saved_address`. Reject non-finite coords.  
**Done when:** missing key → 400; same key concurrent → one worker.

---

## B3 — Tile state machine exactly

**Depends on:** B2  
**Files:** `src/regions.ts`  
**Do:** `SELECT EXISTS (geohash5, release, status IN ('ready','running'))`. ready → **200** `{ status, restaurants }`. running → **202** `{ status: "running" }`. missing → insert `running` + `ST_MakeEnvelope`, enqueue worker, **202**. failed → allow retry (insert/update running) or 409 documented; pick retry.  
**Done when:** integration test against PostGIS: second ensure while running is 202 without second DuckDB extract (mock extract).

---

## B4 — `GET /regions/:geohash5`

**Depends on:** B3  
**Files:** `src/regions.ts`  
**Do:** tile status + payable prefixes (`NATIVE`/`PROXY_WRAPPED` only) with `shop_origin_host`, `shop_location_id`, `x402_version`, `overture_id`, `name`. Exclude sandbox prefixes.  
**Done when:** fixture tile ready returns those fields; UNSUPPORTED not in `payablePrefixes`.

---

## B5 — DuckDB extract correctness

**Depends on:** none (exists; harden)  
**Files:** `src/ingest/overture.ts`  
**Do:** keep `SET s3_region='us-west-2'`; `bbox.xmin/ymin` **before** any `ST_Intersects`; dual-read taxonomy + deprecated categories until Sep 2026; drop `permanently_closed`; project only needed columns. Pin glob to `release/<RELEASE>/theme=places/type=place/*`.  
**Do not:** `categories.main`; full theme scan.  
**Done when:** recorded EXPLAIN or unit with mocked parquet proves bbox predicates present; release id comes from config.

---

## B6 — Persist + protect payable rows

**Depends on:** B5, `database/init.sql`  
**Files:** `src/ingest/overture.ts`  
**Do:** `INSERT … ON CONFLICT` restaurant update **only** if capability `UNSUPPORTED`. `INSERT x402_capabilities … DO NOTHING`. Transaction per batch or COPY.  
**Done when:** Postgres test: NATIVE row name unchanged after second ingest of same overture_id.

---

## B7 — Ingest worker out of the HTTP process

**Depends on:** B3, B6, cheap infra (Function URL + ingest Lambda) — **not** N8 SQS  
**Files:** `src/ingest/worker.ts`, `src/ingest/enqueue.ts`, `src/regions.ts`  
**Do:** HTTP inserts `running` and enqueues. Cheap shape: async `lambda:Invoke` (`InvocationType=Event`). Worker runs DuckDB, upserts, `MARK_READY` with count, or `failed` + error. Lambda timeout 900 s; container image; 2048 MB; `/tmp` spill.  
**Do not:** block `POST /regions/ensure` on S3; add SQS because the expensive plan listed N8.  
**Done when:** HTTP returns 202 in &lt; 100 ms with extract stubbed; worker completion flips tile to ready. Cheap code is in tree; live Invoke needs apply + ECR.

---

## B8 — `user_locations` upsert

**Depends on:** B2  
**Files:** `src/travel.ts` (new), route `POST /devices/location` **or** extend ensure body  
**Do:** GROK allows `user_locations(user_id, last_known, last_ingest_center, last_seen_at)`. If no dedicated route exists in GROK, implement upsert inside ensure when `reason=significant_location` **and** document the extra JSON fields (`user_id`, `last_known_lat/lon`) in this atom’s PR **or** add `POST /devices/location` and list it in a GROK supersession — **stop and ask** before inventing a public route. Preferred: extend ensure payload with optional `device` object only if GROK is updated. Until then, implement SQL upsert used by a new `POST /devices/location` and file GROK control-plane list update in the same PR (docs atom).  
**Done when:** GROK control-plane list and code match; last_seen_at updates; not used as drop-off.

---

## B9 — `POST /skips`

**Depends on:** B0  
**Files:** `src/app.ts`, `src/crypto/menu-schema.ts`  
**Do:** HMAC `user_id` → `user_id_hash` bytea. Fields: `overture_id`, `estimated_lost_revenue_usdc`, `city_geohash`. No wallet, no street. FK to restaurants (404 if unknown POI).  
**Done when:** DB row has 32-byte hash; raw user_id not stored; integration test.

---

## B10 — `POST /devices/push-token`

**Depends on:** B0  
**Files:** `src/app.ts`  
**Do:** `user_id` UUID + APNs token; upsert `updated_at`.  
**Done when:** unique (user_id, token); second post updates timestamp.

---

## B11 — Silent push `region-ready:{geohash5}`

**Depends on:** B7, B10, infrastructure APNs  
**Files:** `src/push.ts`  
**Do:** when tile → ready, notify devices that requested that geohash (store ensure’s user in `region_tile_subscribers` **new table** — not in GROK today). **Stop and ask** if adding `region_tile_subscribers` or push only to users who called ensure with that geohash5 via a column on a new table. Minimal GROK-compatible approach: persist `{user_id, geohash5, release}` on ensure (new table `region_ensure_log` without street addresses) and push those tokens. Same PR: one sentence in `GROK.md` control-plane section.  
**Done when:** ready flip sends one silent push per subscriber; no delivery address in payload.

---

## B12 — Operator skip aggregates (no outreach)

**Depends on:** B9  
**Files:** `src/ops/skips.ts` or SQL view  
**Do:** per geohash5 daily: skip_count, skip_usdc_sum (`SCALABILITY.md` §7.5). Export query only.  
**Do not:** email/SMS/fax.  
**Done when:** SQL or bun script prints aggregates from fixtures.

---

## B13 — Encrypted `PROXY_WRAPPED` menu write path

**Depends on:** B0  
**Files:** `src/crypto/menu-schema.ts`, `src/wraps.ts`  
**Do:** AES-GCM 12-byte nonce; `menu_schema_wrapped_key` is key id, not raw DEK in DB. Only PROXY_WRAPPED. Native menus stay on shop GET.  
**Done when:** round-trip decrypt; CHECK constraint in `init.sql` still holds.

---

## B14 — `purge_stale_unsupported_pois` job

**Depends on:** `database/init.sql`, infrastructure schedule  
**Files:** `src/ingest/purge.ts`  
**Do:** call existing SQL function daily us-west-2 quiet hours. Geography 8046.72 m. Protect NATIVE/PROXY_WRAPPED. Do not delete `user_locations`. Skip log 90 days. Empty ready tiles.  
**Done when:** fixture: UNSUPPORTED far from all delivery_locations and stale users deleted; payable survives.

---

## B15 — Monthly release rollover

**Depends on:** B7  
**Files:** `src/ingest/stac.ts`  
**Do:** watch STAC; pin new `<RELEASE>`; re-queue tiles with saved delivery or engaged device within 5 miles / 30 days last_seen. Do not re-ingest planet. Do not point at releases older than ~60 days.  
**Done when:** dry-run lists tile keys only for those geohash5s.

---

## B16 — HTTP tests

**Depends on:** B3–B10  
**Files:** `src/*.test.ts`  
**Do:** bun test: bbox 400; skips HMAC; ensure 200/202; GET 404 unknown tile. Use Testcontainers PostGIS or docker compose db.  
**Done when:** `bun test` in CI besides smokes.

---

## B17 — x402 helpers stay client-side honest

**Depends on:** none  
**Files:** `src/crypto/x402.ts`  
**Do:** keep `assertPayToMatchesSnapshot`, `centsToUsdcAtomic`, v1 header encode. This is **not** the shop facilitator.  
**Done when:** unit tests for atomic conversion and payTo mismatch throw.

---

## Shop-host overlay (other repo; listed so backend/iOS do not stall blindly)

Implement in `web3-restaurant-api` after `DECISIONS.md`:

1. Place 201 `Location` + require `delivery` snapshot (400 if missing).  
2. Confirm settle mints fulfillment, 201 `Location` …/fulfillment; replay 200.  
3. `GET …/orders/{id}` and `…/fulfillment` + `X-Customer-Id`.  
4. Overlay statuses only; no new kitchen `OrderStatus` SETTLED.  
5. `POST …/kitchen/orders/{id}/dispatch` `{ eta_minutes, tracking_token, courier_phone? }`.  
6. Keep `X-PAYMENT` JSON 402.  

Until 1–3 exist, iOS I18 is blocked. Gnoshbot-backend must not reimplement the shop.

---

## Order

B0 → B1 → B2 → B3 → B4  
B5 → B6 → B7 (cheap: async Lambda invoke; SQS not required)  
B9, B10, B16, B17 anytime after B0  
B8/B11 require GROK one-line additions in the same PR  
B12–B15 after data exists  

Next on this plane: B8 or B11 (GROK line), B12, B13, B17 tests, B14 fixture, B15. Do not wait for RDS/ALB.  
