import { Hono } from "hono";
import { hmacUserId } from "./crypto/menu-schema.js";
import { query, type QueryFn } from "./db.js";
import { ApiError, errorBody, publicInternalError } from "./errors.js";
import {
  ensureRegion as defaultEnsureRegion,
  getRegion as defaultGetRegion,
  parseEnsureBody,
  parseIdempotencyKey,
  type EnsureResult,
} from "./regions.js";
import type { EnsureBody } from "./regions.js";

export type AppDeps = {
  ensureRegion: (body: EnsureBody) => Promise<EnsureResult>;
  getRegion: typeof defaultGetRegion;
  query: QueryFn;
};

const USER_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const SKIP_FORBIDDEN_KEYS = [
  "street_address",
  "line1",
  "line2",
  "wallet",
  "wallet_address",
  "address",
] as const;

const isFiniteNumber = (n: unknown): n is number =>
  typeof n === "number" && Number.isFinite(n);

export const createApp = (
  deps: AppDeps = {
    ensureRegion: defaultEnsureRegion,
    getRegion: defaultGetRegion,
    query,
  }
): Hono => {
  const app = new Hono();

  app.use("*", async (c, next) => {
    const requestId = c.req.header("x-request-id")?.trim() || crypto.randomUUID();
    c.header("X-Request-Id", requestId);
    await next();
  });

  app.onError((err, c) => {
    if (err instanceof ApiError) {
      return c.json(errorBody(err.message, err.code), err.status);
    }
    return c.json(publicInternalError(), 500);
  });

  app.post("/regions/ensure", async (c) => {
    const idempotencyKey = c.req.header("Idempotency-Key")?.trim();
    if (!idempotencyKey) {
      return c.json(
        errorBody("Idempotency-Key header is required", "missing_idempotency_key"),
        400
      );
    }
    const parsedKey = parseIdempotencyKey(idempotencyKey);
    if (!parsedKey) {
      return c.json(
        errorBody(
          "Idempotency-Key must be {opaqueUser}:{geohash5}:{release}",
          "invalid_idempotency_key"
        ),
        400
      );
    }

    let raw: unknown;
    try {
      raw = await c.req.json();
    } catch {
      return c.json(errorBody("body must be JSON", "invalid_json"), 400);
    }

    const body = parseEnsureBody(raw, parsedKey);
    const result = await deps.ensureRegion(body);
    const status = result.status === "ready" ? 200 : 202;
    return c.json(result, status);
  });

  app.get("/regions/:geohash5", async (c) => {
    const geohash5 = c.req.param("geohash5");
    const result = await deps.getRegion(geohash5);
    if (!result.tile) {
      return c.json(errorBody("unknown tile", "unknown_tile"), 404);
    }
    return c.json(result);
  });

  app.post("/skips", async (c) => {
    let raw: unknown;
    try {
      raw = await c.req.json();
    } catch {
      return c.json(errorBody("body must be JSON", "invalid_json"), 400);
    }
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
      throw new ApiError(400, "invalid_json", "body must be a JSON object");
    }
    const body = raw as Record<string, unknown>;
    for (const key of SKIP_FORBIDDEN_KEYS) {
      if (key in body) {
        throw new ApiError(
          400,
          "skip_must_not_include_address",
          "skip log must not include street addresses or wallets"
        );
      }
    }
    if (
      typeof body.overture_id !== "string" ||
      !body.overture_id ||
      typeof body.user_id !== "string" ||
      !body.user_id ||
      typeof body.city_geohash !== "string" ||
      !body.city_geohash
    ) {
      throw new ApiError(
        400,
        "invalid_skip",
        "overture_id, user_id, city_geohash required"
      );
    }
    if (
      !isFiniteNumber(body.estimated_lost_revenue_usdc) ||
      body.estimated_lost_revenue_usdc < 0
    ) {
      throw new ApiError(
        400,
        "invalid_skip",
        "estimated_lost_revenue_usdc must be a non-negative finite number"
      );
    }

    const known = await deps.query(
      "SELECT 1 FROM restaurants WHERE overture_id = $1",
      [body.overture_id]
    );
    if ((known.rowCount ?? 0) === 0) {
      throw new ApiError(404, "unknown_poi", "overture_id is not a known restaurant");
    }

    await deps.query(
      `
    INSERT INTO skipped_merchant_logs
      (overture_id, estimated_lost_revenue_usdc, user_id_hash, city_geohash)
    VALUES ($1, $2, $3, $4)
    `,
      [
        body.overture_id,
        body.estimated_lost_revenue_usdc,
        hmacUserId(body.user_id),
        body.city_geohash,
      ]
    );
    return c.json({ ok: true }, 201);
  });

  app.post("/devices/push-token", async (c) => {
    let raw: unknown;
    try {
      raw = await c.req.json();
    } catch {
      return c.json(errorBody("body must be JSON", "invalid_json"), 400);
    }
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
      throw new ApiError(400, "invalid_json", "body must be a JSON object");
    }
    const body = raw as Record<string, unknown>;
    if (typeof body.user_id !== "string" || !USER_UUID.test(body.user_id)) {
      throw new ApiError(400, "invalid_push_token", "user_id must be a UUID");
    }
    if (typeof body.token !== "string" || !body.token) {
      throw new ApiError(400, "invalid_push_token", "user_id and token required");
    }
    await deps.query(
      `
    INSERT INTO device_push_tokens (user_id, token)
    VALUES ($1, $2)
    ON CONFLICT (user_id, token) DO UPDATE SET updated_at = now()
    `,
      [body.user_id, body.token]
    );
    return c.json({ ok: true });
  });

  return app;
};

export const app = createApp();

/** Fetch handler for Lambda Function URL runtimes that speak Web Fetch. Bun.serve is local. */
export const fetch: typeof app.fetch = app.fetch.bind(app);
