import { beforeAll, expect, test } from "bun:test";
import { createApp } from "./app.js";
import { hmacUserId } from "./crypto/menu-schema.js";
import { PINNED_OVERTURE_RELEASE } from "./config.js";
import { query } from "./db.js";
import { persistPlaces, type OverturePlaceRow } from "./ingest/overture.js";
import { runIngestJob } from "./ingest/worker.js";
import {
  ensureRegion,
  geohash5ForBBox,
  getRegion,
} from "./regions.js";

const NYC_BBOX = {
  min_lon: -74.08,
  min_lat: 40.68,
  max_lon: -73.93,
  max_lat: 40.79,
};

const NYC_GEOHASH = geohash5ForBBox({
  minLon: NYC_BBOX.min_lon,
  minLat: NYC_BBOX.min_lat,
  maxLon: NYC_BBOX.max_lon,
  maxLat: NYC_BBOX.max_lat,
});

const NYC = {
  ...NYC_BBOX,
  reason: "onboarding" as const,
  idempotency_key: `dev:${NYC_GEOHASH}:${PINNED_OVERTURE_RELEASE}`,
};

const waitForPg = async (): Promise<void> => {
  const deadline = Date.now() + 30_000;
  let last: unknown;
  while (Date.now() < deadline) {
    try {
      await query("SELECT 1");
      return;
    } catch (err) {
      last = err;
      await Bun.sleep(500);
    }
  }
  throw last;
};

beforeAll(async () => {
  await waitForPg();
});

const truncateTiles = async () => {
  await query(
    "TRUNCATE region_tiles, skipped_merchant_logs, device_push_tokens, restaurants CASCADE"
  );
};

test("ensure returns 202 without running extract; worker later marks ready", async () => {
  await truncateTiles();
  let extracts = 0;
  const ingest = async () => {
    extracts += 1;
    await Bun.sleep(500);
    return 3;
  };
  const enqueues: unknown[] = [];

  const started = performance.now();
  const first = await ensureRegion(NYC, async (job) => {
    enqueues.push(job);
  });
  if (!process.env.DATABASE_URL?.includes("neon.tech")) {
    expect(performance.now() - started).toBeLessThan(100);
  }
  expect(first).toEqual({ status: "running" });
  expect(extracts).toBe(0);
  expect(enqueues).toHaveLength(1);
  expect(enqueues[0]).toMatchObject({
    geohash5: NYC_GEOHASH,
    release: PINNED_OVERTURE_RELEASE,
    idempotency_key: NYC.idempotency_key,
    min_lon: NYC.min_lon,
    min_lat: NYC.min_lat,
    max_lon: NYC.max_lon,
    max_lat: NYC.max_lat,
  });

  const second = await ensureRegion(NYC, async () => {
    throw new Error("must not enqueue twice");
  });
  expect(second).toEqual({ status: "running" });
  expect(extracts).toBe(0);

  await runIngestJob(
    {
      geohash5: NYC_GEOHASH,
      release: PINNED_OVERTURE_RELEASE,
      bbox: { ...NYC_BBOX },
      min_lon: NYC.min_lon,
      min_lat: NYC.min_lat,
      max_lon: NYC.max_lon,
      max_lat: NYC.max_lat,
      idempotency_key: NYC.idempotency_key,
    },
    ingest
  );
  expect(extracts).toBe(1);
  expect(await ensureRegion(NYC, async () => {})).toEqual({
    status: "ready",
    restaurants: 3,
  });
});

test("second ensure while running is 202 without a second enqueue", async () => {
  await truncateTiles();
  let enqueues = 0;
  const enqueue = async () => {
    enqueues += 1;
  };

  const [a, b] = await Promise.all([
    ensureRegion(NYC, enqueue),
    ensureRegion(NYC, enqueue),
  ]);
  expect(a).toEqual({ status: "running" });
  expect(b).toEqual({ status: "running" });
  expect(enqueues).toBe(1);
});

test("GET /regions/:geohash5 returns payable prefixes and omits UNSUPPORTED and sandbox", async () => {
  await truncateTiles();
  await query(
    `
    INSERT INTO region_tiles (geohash5, release, status, geom, restaurant_count, ready_at)
    VALUES (
      $1, $2, 'ready',
      ST_MakeEnvelope($3, $4, $5, $6, 4326),
      4, now()
    )
    `,
    [
      NYC_GEOHASH,
      PINNED_OVERTURE_RELEASE,
      NYC.min_lon,
      NYC.min_lat,
      NYC.max_lon,
      NYC.max_lat,
    ]
  );

  const insertPoi = async (
    id: string,
    name: string,
    status: "UNSUPPORTED" | "NATIVE" | "PROXY_WRAPPED",
    extras: {
      nativeUrl?: string;
      origin?: string;
      location?: string;
    } = {}
  ) => {
    await query(
      `
      INSERT INTO restaurants (overture_id, name, coordinates, release)
      VALUES ($1, $2, ST_SetSRID(ST_MakePoint($3, $4), 4326), $5)
      `,
      [id, name, -74.005, 40.735, PINNED_OVERTURE_RELEASE]
    );
    await query(
      `
      INSERT INTO x402_capabilities (
        overture_id, integration_status, native_x402_url, shop_origin_host, shop_location_id, x402_version
      )
      VALUES ($1, $2, $3, $4, $5, 1)
      `,
      [
        id,
        status,
        extras.nativeUrl ?? null,
        extras.origin ?? null,
        extras.location ?? null,
      ]
    );
  };

  await insertPoi("poi-native", "Native Kitchen", "NATIVE", {
    nativeUrl: "https://pay.example/x402",
  });
  await insertPoi("poi-wrap", "Wrapped Deli", "PROXY_WRAPPED", {
    origin: "pos.example.com",
    location: "downtown",
  });
  await insertPoi("poi-unsup", "Cash Only", "UNSUPPORTED");
  await insertPoi("poi-sandbox", "TTL Shop", "PROXY_WRAPPED", {
    origin: "shop.example",
    location: "/_sandbox/abc",
  });

  const result = await getRegion(NYC_GEOHASH);
  expect(result.tile).toEqual({ status: "ready", restaurants: 4 });
  const ids = result.payablePrefixes.map((p) => p.overture_id).sort();
  expect(ids).toEqual(["poi-native", "poi-wrap"]);
  const wrapped = result.payablePrefixes.find((p) => p.overture_id === "poi-wrap");
  expect(wrapped).toMatchObject({
    name: "Wrapped Deli",
    shop_origin_host: "pos.example.com",
    shop_location_id: "downtown",
    x402_version: 1,
  });
});

test("second ingest does not overwrite NATIVE or PROXY_WRAPPED restaurant names", async () => {
  await truncateTiles();
  await query(
    `
    INSERT INTO restaurants (overture_id, name, coordinates, release)
    VALUES
      ('poi-curated', 'Curated Name', ST_SetSRID(ST_MakePoint(-74.005, 40.735), 4326), $1),
      ('poi-wrap', 'Wrapped Name', ST_SetSRID(ST_MakePoint(-74.006, 40.736), 4326), $1)
    `,
    [PINNED_OVERTURE_RELEASE]
  );
  await query(
    `
    INSERT INTO x402_capabilities (overture_id, integration_status, native_x402_url)
    VALUES ('poi-curated', 'NATIVE', 'https://pay.example/x402')
    `
  );
  await query(
    `
    INSERT INTO x402_capabilities (overture_id, integration_status, shop_origin_host, shop_location_id)
    VALUES ('poi-wrap', 'PROXY_WRAPPED', 'pos.example.com', 'downtown')
    `
  );

  const rows: OverturePlaceRow[] = [
    {
      overture_id: "poi-curated",
      name: "Overture Overwrite",
      website_url: null,
      phone_number: null,
      email_address: null,
      street_address: "should not apply",
      lon: -74.005,
      lat: 40.735,
    },
    {
      overture_id: "poi-wrap",
      name: "Also Overwrite",
      website_url: null,
      phone_number: null,
      email_address: null,
      street_address: "nope",
      lon: -74.006,
      lat: 40.736,
    },
  ];
  await persistPlaces(rows);

  const got = await query(
    "SELECT overture_id, name, street_address FROM restaurants WHERE overture_id IN ('poi-curated','poi-wrap') ORDER BY overture_id"
  );
  expect(got.rows).toEqual([
    { overture_id: "poi-curated", name: "Curated Name", street_address: null },
    { overture_id: "poi-wrap", name: "Wrapped Name", street_address: null },
  ]);
});

test("POST /skips stores HMAC user_id_hash and POST /devices/push-token upserts", async () => {
  await truncateTiles();
  await query(
    `
    INSERT INTO restaurants (overture_id, name, coordinates, release)
    VALUES ('poi-skip', 'Skip Kitchen', ST_SetSRID(ST_MakePoint(-74.005, 40.735), 4326), $1)
    `,
    [PINNED_OVERTURE_RELEASE]
  );
  const app = createApp();
  const skip = await app.request("/skips", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      overture_id: "poi-skip",
      user_id: "opaque-user-42",
      city_geohash: NYC_GEOHASH,
      estimated_lost_revenue_usdc: 8.25,
    }),
  });
  expect(skip.status).toBe(201);
  const log = await query(
    "SELECT user_id_hash, estimated_lost_revenue_usdc::text AS usdc FROM skipped_merchant_logs WHERE overture_id = $1",
    ["poi-skip"]
  );
  const hash = log.rows[0]?.user_id_hash as Buffer;
  expect(hash.equals(hmacUserId("opaque-user-42"))).toBe(true);
  expect(String(log.rows[0]?.usdc)).toBe("8.25");
  const dumped = JSON.stringify(log.rows);
  expect(dumped).not.toContain("opaque-user-42");
  expect(dumped).not.toContain("Pine");

  const user = "11111111-1111-1111-1111-111111111111";
  const first = await app.request("/devices/push-token", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ user_id: user, token: "apns-token-1" }),
  });
  expect(first.status).toBe(200);
  await query(
    "UPDATE device_push_tokens SET updated_at = now() - interval '1 minute' WHERE user_id = $1 AND token = $2",
    [user, "apns-token-1"]
  );
  const before = await query(
    "SELECT updated_at FROM device_push_tokens WHERE user_id = $1 AND token = $2",
    [user, "apns-token-1"]
  );
  const second = await app.request("/devices/push-token", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ user_id: user, token: "apns-token-1" }),
  });
  expect(second.status).toBe(200);
  const after = await query(
    "SELECT updated_at FROM device_push_tokens WHERE user_id = $1 AND token = $2",
    [user, "apns-token-1"]
  );
  expect(new Date(String(after.rows[0]?.updated_at)).getTime()).toBeGreaterThan(
    new Date(String(before.rows[0]?.updated_at)).getTime()
  );
  const count = await query("SELECT count(*)::int AS n FROM device_push_tokens");
  expect(count.rows[0]?.n).toBe(1);
});
