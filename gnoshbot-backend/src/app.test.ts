import { expect, test } from "bun:test";
import { hmacUserId } from "./crypto/menu-schema.js";
import { createApp } from "./app.js";
import { PINNED_OVERTURE_RELEASE } from "./config.js";
import { getRegion } from "./regions.js";
import type { QueryFn } from "./db.js";

const json = async (res: Response) => (await res.json()) as Record<string, unknown>;

const unusedQuery: QueryFn = async () => {
  throw new Error("unused");
};

test("invalid bbox is 400 with error and code", async () => {
  const app = createApp();
  const res = await app.request("/regions/ensure", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "Idempotency-Key": `dev:zzzzz:${PINNED_OVERTURE_RELEASE}`,
    },
    body: JSON.stringify({ min_lon: "west", reason: "onboarding" }),
  });
  expect(res.status).toBe(400);
  expect(res.headers.get("X-Request-Id")).toBeTruthy();
  const body = await json(res);
  expect(body.code).toBe("invalid_bbox");
  expect(body.error).toBe("bbox fields must be finite numbers");
  expect(JSON.stringify(body)).not.toMatch(/SELECT /i);
});

test("non-finite bbox coords are 400", async () => {
  const app = createApp();
  const res = await app.request("/regions/ensure", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "Idempotency-Key": `dev:zzzzz:${PINNED_OVERTURE_RELEASE}`,
    },
    body: '{"min_lon":-74,"min_lat":40,"max_lon":1e999,"max_lat":41,"reason":"onboarding"}',
  });
  expect(res.status).toBe(400);
  expect((await json(res)).code).toBe("invalid_bbox");
});

test("missing Idempotency-Key is 400", async () => {
  const app = createApp();
  const res = await app.request("/regions/ensure", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      min_lon: -74.08,
      min_lat: 40.68,
      max_lon: -73.93,
      max_lat: 40.79,
      reason: "onboarding",
    }),
  });
  expect(res.status).toBe(400);
  const body = await json(res);
  expect(body.code).toBe("missing_idempotency_key");
});

test("thrown query error is 500 without query text", async () => {
  const app = createApp({
    ensureRegion: async () => {
      throw new Error(
        'syntax error at or near "region_tiles": SELECT * FROM region_tiles WHERE geohash5 = $1'
      );
    },
    getRegion,
    query: unusedQuery,
  });
  const res = await app.request("/regions/ensure", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "Idempotency-Key": `usr1:dr5re:${PINNED_OVERTURE_RELEASE}`,
      "X-Request-Id": "req-test-500",
    },
    body: JSON.stringify({
      min_lon: -74.08,
      min_lat: 40.68,
      max_lon: -73.93,
      max_lat: 40.79,
      reason: "onboarding",
    }),
  });
  expect(res.status).toBe(500);
  expect(res.headers.get("X-Request-Id")).toBe("req-test-500");
  const body = await json(res);
  expect(body).toEqual({ error: "internal error", code: "internal_error" });
  expect(JSON.stringify(body)).not.toContain("SELECT");
  expect(JSON.stringify(body)).not.toContain("region_tiles");
});

test("GET unknown tile is 404 without SQL in the body", async () => {
  const app = createApp({
    ensureRegion: async () => ({ status: "running" }),
    getRegion: async () => ({ tile: null, payablePrefixes: [] as const }),
    query: unusedQuery,
  });
  const res = await app.request("/regions/zzzzz");
  expect(res.status).toBe(404);
  const body = await json(res);
  expect(body.code).toBe("unknown_tile");
  expect(JSON.stringify(body)).not.toMatch(/SELECT /i);
});

test("ensure 202 does not wait on DuckDB when ensureRegion is stubbed", async () => {
  const app = createApp({
    ensureRegion: async () => ({ status: "running" }),
    getRegion,
    query: unusedQuery,
  });
  const started = performance.now();
  const res = await app.request("/regions/ensure", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "Idempotency-Key": `usr1:dr5re:${PINNED_OVERTURE_RELEASE}`,
    },
    body: JSON.stringify({
      min_lon: -74.08,
      min_lat: 40.68,
      max_lon: -73.93,
      max_lat: 40.79,
      reason: "onboarding",
    }),
  });
  expect(performance.now() - started).toBeLessThan(100);
  expect(res.status).toBe(202);
  expect(await json(res)).toEqual({ status: "running" });
});

test("POST /skips HMAC-hashes user_id and rejects streets", async () => {
  const inserted: unknown[][] = [];
  const app = createApp({
    ensureRegion: async () => ({ status: "running" }),
    getRegion,
    query: (async (text: string, params?: unknown[]) => {
      if (String(text).includes("FROM restaurants")) {
        return { rowCount: 1, rows: [{ "?column?": 1 }] };
      }
      inserted.push(params ?? []);
      return { rowCount: 1, rows: [] };
    }) as unknown as QueryFn,
  });

  const street = await app.request("/skips", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      overture_id: "poi-1",
      user_id: "user-1",
      city_geohash: "dr5re",
      estimated_lost_revenue_usdc: 12.5,
      street_address: "14 Pine Street",
    }),
  });
  expect(street.status).toBe(400);
  expect((await json(street)).code).toBe("skip_must_not_include_address");

  const ok = await app.request("/skips", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      overture_id: "poi-1",
      user_id: "user-1",
      city_geohash: "dr5re",
      estimated_lost_revenue_usdc: 12.5,
    }),
  });
  expect(ok.status).toBe(201);
  const hash = inserted[0]?.[2] as Buffer;
  expect(Buffer.isBuffer(hash)).toBe(true);
  expect(hash.length).toBe(32);
  expect(hash.equals(hmacUserId("user-1"))).toBe(true);
  expect(JSON.stringify(inserted)).not.toContain("user-1");
  expect(JSON.stringify(inserted)).not.toContain("Pine");
});

test("POST /skips is 404 for unknown POI", async () => {
  const app = createApp({
    ensureRegion: async () => ({ status: "running" }),
    getRegion,
    query: (async (text: string) => {
      if (String(text).includes("FROM restaurants")) {
        return { rowCount: 0, rows: [] };
      }
      throw new Error("should not insert");
    }) as unknown as QueryFn,
  });
  const res = await app.request("/skips", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      overture_id: "missing",
      user_id: "user-1",
      city_geohash: "dr5re",
      estimated_lost_revenue_usdc: 1,
    }),
  });
  expect(res.status).toBe(404);
  expect((await json(res)).code).toBe("unknown_poi");
});

test("POST /devices/push-token rejects non-UUID user_id", async () => {
  const app = createApp({
    ensureRegion: async () => ({ status: "running" }),
    getRegion,
    query: unusedQuery,
  });
  const res = await app.request("/devices/push-token", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ user_id: "not-a-uuid", token: "tok" }),
  });
  expect(res.status).toBe(400);
  expect((await json(res)).code).toBe("invalid_push_token");
});
