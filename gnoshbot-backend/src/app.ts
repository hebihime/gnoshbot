import { Hono } from "hono";
import { hmacUserId } from "./crypto/menu-schema.js";
import { query } from "./db.js";
import { ensureRegion, getRegion, type EnsureBody } from "./regions.js";

export const app = new Hono();

app.post("/regions/ensure", async (c) => {
  const body = (await c.req.json()) as EnsureBody;
  if (
    [body.min_lon, body.min_lat, body.max_lon, body.max_lat].some(
      (n) => typeof n !== "number" || Number.isNaN(n)
    )
  ) {
    return c.json({ error: "bbox fields must be numbers" }, 400);
  }
  const result = await ensureRegion(body);
  const status = result.status === "ready" ? 200 : 202;
  return c.json(result, status);
});

app.get("/regions/:geohash5", async (c) => {
  const geohash5 = c.req.param("geohash5");
  const result = await getRegion(geohash5);
  if (!result.tile) {
    return c.json({ error: "unknown tile" }, 404);
  }
  return c.json(result);
});

app.post("/skips", async (c) => {
  const body = (await c.req.json()) as {
    overture_id: string;
    estimated_lost_revenue_usdc: number;
    user_id: string;
    city_geohash: string;
  };
  if (!body.overture_id || !body.user_id || !body.city_geohash) {
    return c.json({ error: "overture_id, user_id, city_geohash required" }, 400);
  }
  await query(
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
  const body = (await c.req.json()) as { user_id: string; token: string };
  if (!body.user_id || !body.token) {
    return c.json({ error: "user_id and token required" }, 400);
  }
  await query(
    `
    INSERT INTO device_push_tokens (user_id, token)
    VALUES ($1, $2)
    ON CONFLICT (user_id, token) DO UPDATE SET updated_at = now()
    `,
    [body.user_id, body.token]
  );
  return c.json({ ok: true });
});
