# Gnoshbot Scalability

## Why this exists

Gnoshbot must not hire a data team every time a user lands in a new city, and it must not host 70 million POIs "just in case." Coverage is a side effect of **saved delivery addresses** and of where engaged devices actually stand. This file is the engineer-free provisioning loop, the purge that keeps the index equal to the living user set, and the B2B skip flywheel that turns a missing x402 node into a wrap lead — with legal brakes.

---

## 1. Principles

1. **Users are the crawlers.** Saving a delivery address, onboarding, and significant location change each submit a bounding box. If that box is empty of rows, a worker fills it from Overture. If it is not empty, the request is a no-op. Lunch-time kitchen search uses the **confirmed address** box, not GPS.
2. **Compute sits on the data.** Overture's catalog is `us-west-2`. Ingest runs in `us-west-2`. Cross-region S3 reads are a bill, not a strategy ([Overture cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/), [S3 pricing — Data transfer](https://aws.amazon.com/s3/pricing/)).
3. **Payable nodes are forever; raw POIs are not.** `NATIVE` and `PROXY_WRAPPED` rows survive purge. `UNSUPPORTED` rows that no engaged user has been near in 90 days do not.
4. **The shop host is not a registry.** Production identity of a kitchen remains origin host + location id on `web3-restaurant-api`. Gnoshbot's restaurant table is a **discovery index** that *points at* those prefixes. We do not KYC a JPEG into production ([shop PRODUCT.md](https://github.com/hebihime/web3-restaurant-api/blob/main/PRODUCT.md)).

---

## 2. Overture as the global gazetteer

### 2.1 Canonical URI

```
s3://overturemaps-us-west-2/release/<RELEASE>/theme=places/type=place/*
```

`<RELEASE>` is `yyyy-mm-dd.x`. Pin it in config. The Overture DuckDB guide's current example is `2026-08-19.0` ([DuckDB](https://docs.overturemaps.org/getting-data/duckdb/)). STAC is the machine index of "latest": [https://stac.overturemaps.org/catalog.json](https://stac.overturemaps.org/catalog.json).

Azure twin, if AWS is on fire:

```
https://overturemapswestus2.blob.core.windows.net/release/<RELEASE>/theme=places/type=place/
```

AWS Registry of Open Data: bucket `overturemaps-us-west-2`, region **us-west-2**, anonymous `aws s3 ls --no-sign-request` ([registry.opendata.aws/overture](https://registry.opendata.aws/overture/)).

### 2.2 Schema facts that ingest must respect

- Theme `places`, type `place` ([cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/)).
- Stable id is GERS (`id`). Use it as `overture_id` primary key.
- `names.primary`, `websites[]`, `phones[]`, `emails[]`, `addresses[].freeform`, `geometry`, `bbox`.
- `categories.primary` / `categories.alternate` **deprecated, removed September 2026**. Dual-read `basic_category` + `taxonomy.hierarchy` ([Places overview](https://docs.overturemaps.org/guides/places/), [taxonomy](https://docs.overturemaps.org/guides/places/taxonomy/)).
- `operating_status`: `open | permanently_closed | temporarily_closed`. **Not hours of operation** ([place schema](https://docs.overturemaps.org/schema/reference/places/place/)). Drop `permanently_closed` at ingest.
- No menus. No x402 URL. No live "open now."

Food-and-drink counts are millions, not the whole places theme (~60–70 M). Filter in DuckDB; do not download the theme.

### 2.3 DuckDB pruning

httpfs range-reads Parquet ([DuckDB HTTP(S)](https://duckdb.org/docs/current/core_extensions/httpfs/https.html)). Spatial `ST_Intersects` alone does **not** prune row groups; **literal `bbox.*` predicates do** (Overture's own queries, and [Dunnington on DuckDB GeoParquet pruning](https://dewey.dunnington.ca/post/2025/lazy-geoparquet-reading-in-sedonadb-duckdb-geopandas-and-gdal/)). Always write:

```sql
WHERE bbox.xmin BETWEEN :min_lon AND :max_lon
  AND bbox.ymin BETWEEN :min_lat AND :max_lat
  AND operating_status IS DISTINCT FROM 'permanently_closed'
  AND (
        list_contains(taxonomy.hierarchy, 'food_and_drink')
     OR basic_category IN ('restaurant','cafe','bar','meal_takeaway','meal_delivery','bakery','food_truck')
     OR categories.primary ILIKE '%restaurant%'   -- until Sep 2026
  )
```

Anonymous S3:

```sql
CREATE SECRET overture (TYPE s3, PROVIDER config, REGION 'us-west-2');
-- or: SET s3_region='us-west-2';  and unsigned requests
```

Worker region: **us-west-2**. Same-region S3 → Lambda/ECS is $0 transfer; GET request charges still apply.

Lambda ceiling 900 s, 10 GB memory, `/tmp` up to 10 GB ([Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)). Prefer a container image with DuckDB + spatial preinstalled so `INSTALL` is not on the clock. If a 5-mile box ever approaches the timeout (dense megacity, unfiltered theme), split the box into a 2×2 grid and run four jobs with the same idempotency key namespace.

---

## 3. Idempotent ingest

### 3.1 Client triggers

**A. Saving a delivery location (wizard Band A, or later Addresses editor)**  
5-mile (8046.72 m) geodesic box around the **saved coordinates**, `POST /regions/ensure`. This is the box lunch will search.

**B. Onboarding (Phase 3 ENGAGE SYSTEM)**  
Same call for each already-saved address. Do not ingest a GPS ping the user did not save.

**C. Travel (pre-warm only)**  
`CLLocationManager.startMonitoringSignificantLocationChanges()` ([Apple](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges())). Cellular/Wi-Fi, not GPS. If the app was terminated, iOS **relaunches it into the background** on a new event. Requires **Always** authorization and a precise `NSLocationAlwaysAndWhenInUseUsageDescription`. Distance is "significant," classically cell-tower handoff (~500 m–2+ km), **not** a 5-mile fence. Gnoshbot therefore:

1. on event, haversine against `user_locations.last_ingest_center`;
2. if displacement < 5 miles, update `last_known` only;
3. if ≥ 5 miles, compute a new box and `POST /regions/ensure`.

That tile is a **cache**, so a later "add this hotel as an address" is instant. It is **not** a license to deliver to the hotel. Do not run GPS `startUpdatingLocation` in the background for this. Visits (`startMonitoringVisits()`) is a reasonable v2 complement for "arrived at an airport" — still followed by Save + Siri confirm before food moves.

### 3.2 API

```
POST /regions/ensure
Idempotency-Key: {userId}:{geohash5}:{release}
{
  "min_lon": -74.08, "min_lat": 40.68,
  "max_lon": -73.93, "max_lat": 40.79,
  "reason": "onboarding" | "significant_location"
}
```

`geohash5` (~4.9 km) is the idempotency grain so two users in the same neighborhood share work.

Server:

```sql
SELECT EXISTS (
  SELECT 1 FROM region_tiles
  WHERE geohash5 = $1 AND release = $2 AND status IN ('ready','running')
);
```

- `ready`: 200 `{ "status": "ready", "restaurants": N }`
- `running`: 202 `{ "status": "running" }`
- missing: insert `running`, enqueue worker, 202

Worker, after DuckDB:

```sql
INSERT INTO restaurants (overture_id, name, website_url, phone_number, email_address,
                         street_address, coordinates, cuisine_tags, release)
VALUES ($1,$2,$3,$4,$5,$6, ST_SetSRID(ST_MakePoint($lon,$lat),4326), $7, $release)
ON CONFLICT (overture_id) DO UPDATE
  SET name = EXCLUDED.name,
      website_url = EXCLUDED.website_url,
      phone_number = EXCLUDED.phone_number,
      email_address = EXCLUDED.email_address,
      street_address = EXCLUDED.street_address,
      coordinates = EXCLUDED.coordinates,
      cuisine_tags = EXCLUDED.cuisine_tags,
      release = EXCLUDED.release
  WHERE restaurants.integration_status = 'UNSUPPORTED';
-- never overwrite name/coords for NATIVE/PROXY_WRAPPED from Overture if operators have curated them

INSERT INTO x402_capabilities (overture_id, integration_status)
VALUES ($1, 'UNSUPPORTED')
ON CONFLICT (overture_id) DO NOTHING;
```

Protected rows (`NATIVE`, `PROXY_WRAPPED`) keep their `native_x402_url` / `proxy_wallet_address` / `wrapped_menu` through monthly release churn. Only `UNSUPPORTED` metadata refreshes.

`user_locations` upsert: `last_known_coordinates`, `last_ingest_center`, `last_seen_at`.

### 3.3 Device cache hydration

202 does not mean the phone has menus. Control plane, when the tile flips `ready`, sends a silent push `region-ready:{geohash5}`. The app pulls a compact JSON of payable prefixes + UNSUPPORTED counts for that tile into `RestaurantCache`. Menus for payable prefixes are fetched from the shop host, not from Overture.

Wizard copy while 202: "Mapping kitchens nearby." ENGAGE is still allowed; the first Siri lunch may hit "No payable kitchen in range" if the user is faster than DuckDB. That is preferable to blocking ENGAGE on S3.

---

## 4. Monthly release rollover

A cron (or EventBridge) watches STAC. When `<RELEASE>` changes:

1. Pin the new id in config.
2. Re-queue **all tiles that currently have a saved delivery address or an engaged device within 5 miles** (`delivery_locations` plus `user_locations.last_seen_at` within 30 days). Do not re-ingest the planet.
3. After success, tiles with no engaged user stay on the old release until purge deletes their UNSUPPORTED rows.

Overture retains roughly two monthly releases on the public bucket (GDAL tutorial note: ~60 days). Do not point production at a release older than that.

---

## 5. Purge

Daily, us-west-2, after ingest quiet hours.

```sql
-- 1. Drop UNSUPPORTED POIs not near any saved delivery address
--    or any recently-seen engaged device.
DELETE FROM restaurants r
USING x402_capabilities c
WHERE r.overture_id = c.overture_id
  AND c.integration_status = 'UNSUPPORTED'
  AND NOT EXISTS (
    SELECT 1 FROM delivery_locations d
    WHERE ST_DWithin(r.coordinates, d.coordinates, 8046.72)
  )
  AND NOT EXISTS (
    SELECT 1 FROM user_locations u
    WHERE u.last_seen_at > now() - interval '90 days'
      AND ST_DWithin(r.coordinates, u.last_known_coordinates, 8046.72)
  );

-- 2. Capabilities cascade (FK ON DELETE CASCADE) or explicit:
DELETE FROM x402_capabilities c
WHERE NOT EXISTS (SELECT 1 FROM restaurants r WHERE r.overture_id = c.overture_id);

-- 3. Skip log retention
DELETE FROM skipped_merchant_logs
WHERE skipped_at < now() - interval '90 days';

-- 4. Empty tiles
DELETE FROM region_tiles t
WHERE t.status = 'ready'
  AND NOT EXISTS (
    SELECT 1 FROM restaurants r
    WHERE ST_Intersects(r.coordinates, t.geom)
  );
```

**Protected:** any `integration_status IN ('NATIVE','PROXY_WRAPPED')`, even if every user leaves town. Those rows are the network.

**Also protect:** `user_locations` itself. Do not delete users. `last_seen_at` aging is what makes purge work.

Indexes: GIST on `restaurants.coordinates`, GIST on `user_locations.last_known_coordinates`, btree on `x402_capabilities.integration_status`, btree on `user_locations.last_seen_at`.

---

## 6. Mapping Overture → payable node

```
restaurants.overture_id
    └── x402_capabilities
            integration_status: UNSUPPORTED | NATIVE | PROXY_WRAPPED
            native_x402_url          -- v1 or v2 endpoint
            shop_origin_host         -- web3-restaurant-api prefix host
            shop_location_id
            proxy_wallet_address     -- only if we operate a wrap
            wrapped_menu_json        -- only if we host the Menu Pull
```

A **NATIVE** node is a merchant who already speaks x402 (v1 or v2) on a URL we did not mint.

A **PROXY_WRAPPED** node is Gnoshbot (or the shop host) wrapping a Menu Pull **the proxy hosts**. That wrap is a production origin on `web3-restaurant-api` (`/{proxyHost}/{locationId}/`), `payTo` asserted by **that** GET, not by a form. This is compatible with the shop host's "we do not KYC" rule: the origin is a URL we operate, the till is a wallet we created for the merchant and put on that GET. Custody of that till is a **separate, explicit product** (see §7.4).

`UNSUPPORTED` is the default at ingest.

---

## 7. B2B growth engine

### 7.1 Skip log

When the picker would have chosen a restaurant but `integration_status = 'UNSUPPORTED'`:

```sql
INSERT INTO skipped_merchant_logs
  (overture_id, skipped_at, estimated_lost_revenue_usdc, user_id_hash, city_geohash)
VALUES ($1, now(), $2, $3, $4);
```

`user_id_hash` is an HMAC, not a raw user id, not a wallet. Estimated revenue is the **would-have** item price, not a promise.

The picker then takes the next payable candidate. If none, launch aborts "No payable kitchen in range." Skips still flush.

### 7.2 Notification — legal, then technical

Automated Email/SMS/Fax the same day, from harvested Overture phones/emails, claiming "an AI missed an $18.50 purchase," collides with:

- **US SMS:** TCPA. Autodialed marketing to a phone requires prior express consent. An Overture `phones[]` value is not consent. Transactional "you missed a sale" to a number we have never been given by the business is a fact-specific risk; treat SMS as **off** until counsel says otherwise. Official starting point: [47 USC § 227](https://www.law.cornell.edu/uscode/text/47/227) / FCC TCPA pages.
- **US email:** CAN-SPAM. Commercial email is legal without prior consent if it is truthful, identified as an ad, has a valid physical postal address, and a working unsubscribe ([FTC CAN-SPAM](https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business)). Harvested `emails[]` from a map dataset may not be the right inbox and may not be a commercial-email relationship. First versions: **manual** or **form-on-our-site** only.
- **Fax:** junk-fax rules are also TCPA. Off by default.
- **Truth in advertising:** "Estimated Revenue Passed Over: $18.50" is a modeled counterfactual. If we send it, it must be labeled as an estimate and must not imply a completed checkout we prevented them from taking.

**v1 shipping policy (closed):** do not auto-SMS, auto-fax, or auto-email Overture-harvested contacts. Write the skip log. Weekly, an operator (or a later, counsel-approved drip) exports aggregates: restaurant, skip count, sum of estimates, website. Outreach is to the **website contact form** or a clearly identified commercial email the merchant published for business inquiries, with CAN-SPAM headers, after a human or a policy engine has confirmed the address.

**v2 (not closed):** if counsel signs off, a CAN-SPAM-compliant email to `emails[]` with unsubscribe, once per restaurant per 30 days, cap 1/day/address, suppress forever on bounce or opt-out.

### 7.3 Copy (when sending is allowed)

Subject: `AI orders skipped your kitchen (estimate)`

Body must include: who we are, that this is commercial, a postal address, unsubscribe, the **estimate** framing, a date, a geohash-level location (not the user's home), and a link to wrap docs. Do not include the user's name, device, allergies, or wallet.

### 7.4 Onboarding a wrap (compatible with the shop host)

The shop host will not take a photo and call it a restaurant. Gnoshbot's wrap path must end in a **Menu Pull GET** the wrap origin hosts:

1. Merchant (or our operator) supplies a public menu URL or an upload into a **staging** tool.
2. Structured extract (Gemini Flash, `ingest.schema.json`) → human confirm (price edit / drop row, no add) — same rules as the shop sandbox.
3. Staging **graduates** only by publishing a Menu Pull GET on a host we control (`menus.gnoshbot.com/{locationId}`) with `store.payTo` set to a wallet the merchant controls (they paste a 0x they own) **or** a CDP Smart Account whose owner is the merchant's email.
4. `POST /pulls` on `web3-restaurant-api` with that base URL + location id. The shop host fetches, Zod-validates, requires `payTo`, mints `/{originHost}/{locationId}/`.
5. Gnoshbot sets `x402_capabilities` to `PROXY_WRAPPED` with `shop_origin_host` / `shop_location_id`.

There is **no** "promote sandbox" on the shop host. We never ask it to. We publish a GET and wrap that GET.

Till custody: preferred = merchant's own 0x on the GET. If we create a CDP account for them, that is custody-adjacent and needs its own TOS. Do not put Gnoshbot's operator demo till on a production wrap.

Proxy lifecycle after wrap: Gnoshbot agent places and confirms on the shop prefix like any other origin, including the confirmed `delivery` snapshot. Kitchen is the shop board until the merchant connects a webhook. Order injection into "their Toast" is explicitly later; v1 is the board + email of the ticket. A protocol-translation micro-fee, if any, is deducted by the proxy **after** the shop 402 settles to `payTo` and must be disclosed in the wrap TOS — it is not a second 402 on the agent.

### 7.5 Metrics that drive the flywheel

Per geohash5, daily:

- skip_count
- skip_usdc_sum
- payable_order_count
- payable_usdc_sum
- wrap_conversion (skips → PROXY_WRAPPED)

These are internal. They may appear in an operator dashboard. They are not user-facing.

---

## 8. Scale numbers (order of magnitude)

| Object | Growth |
| --- | --- |
| `region_tiles` | O(engaged cities), not O(planet) |
| `restaurants` UNSUPPORTED | O(users × 5-mile food POIs), 90-day cap |
| `restaurants` payable | monotonic, small |
| device `RestaurantCache` | one city + maybe last city |
| DuckDB workers | burst on first user in a city, then idle |
| shop host | scales with payable orders, which is the point |

A million users who never leave ten metro areas cost ten metros of POIs, not a global build.

---

## 9. Closed decisions

| ID | Decision |
| --- | --- |
| S1 | Ingest compute in **us-west-2** against `s3://overturemaps-us-west-2`. |
| S2 | Pin `<RELEASE>`; dual-read taxonomy + deprecated categories until Sep 2026. |
| S3 | Idempotency grain = `geohash5 + release`. |
| S4 | Ingest bbox is the saved delivery address. Significant-change + 5-mile hysteresis pre-warms travel cities only. Always location. GPS is never the drop-off. |
| S5 | Purge UNSUPPORTED not within 5 miles of any saved delivery address or any device seen in 90 days. Protect payable rows forever. |
| S6 | No auto SMS/Fax/email in v1. Skip log only. |
| S7 | Wraps are Menu Pull origins we host, then `POST /pulls`. No sandbox promotion. |
| S8 | DuckDB is a worker, never the Siri path, never on-device. |
