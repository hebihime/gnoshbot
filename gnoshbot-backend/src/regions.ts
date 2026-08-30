import ngeohash from "ngeohash";
import { config } from "./config.js";
import { query } from "./db.js";
import { ApiError } from "./errors.js";
import { enqueueIngestLambda, type EnqueueFn } from "./ingest/enqueue.js";
import type { IngestJob } from "./ingest/job.js";
import type { BBox } from "./ingest/overture.js";
import { MARK_FAILED } from "./ingest/tile-sql.js";

const REASONS = ["onboarding", "significant_location", "saved_address"] as const;
export type EnsureReason = (typeof REASONS)[number];

export type EnsureBody = {
  min_lon: number;
  min_lat: number;
  max_lon: number;
  max_lat: number;
  reason: EnsureReason;
  idempotency_key: string;
};

export type ParsedIdempotencyKey = {
  opaqueUser: string;
  geohash5: string;
  release: string;
  raw: string;
};

export type EnsureResult =
  | { status: "ready"; restaurants: number }
  | { status: "running" };

const GEOHASH5 = /^[0-9b-hjkmnp-z]{5}$/;

const TILE_SQL = `
SELECT status, restaurant_count
FROM region_tiles
WHERE geohash5 = $1 AND release = $2
`;

const TILE_EXISTS_READY_OR_RUNNING = `
SELECT EXISTS (
  SELECT 1 FROM region_tiles
  WHERE geohash5 = $1 AND release = $2 AND status IN ('ready','running')
) AS present
`;

const INSERT_RUNNING = `
INSERT INTO region_tiles (geohash5, release, status, geom)
VALUES (
  $1, $2, 'running',
  ST_MakeEnvelope($3, $4, $5, $6, 4326)
)
ON CONFLICT (geohash5, release) DO NOTHING
RETURNING geohash5
`;

const RETRY_FAILED = `
UPDATE region_tiles
SET status = 'running',
    error = NULL,
    started_at = now(),
    geom = ST_MakeEnvelope($3, $4, $5, $6, 4326)
WHERE geohash5 = $1 AND release = $2 AND status = 'failed'
RETURNING geohash5
`;

const PAYABLE_PREFIXES_SQL = `
SELECT r.overture_id, r.name, c.shop_origin_host, c.shop_location_id, c.x402_version
FROM restaurants r
JOIN x402_capabilities c ON c.overture_id = r.overture_id
JOIN region_tiles t ON t.geohash5 = $1 AND t.release = $2
WHERE ST_Intersects(r.coordinates, t.geom)
  AND c.integration_status IN ('NATIVE', 'PROXY_WRAPPED')
  AND COALESCE(c.native_x402_url, '') NOT LIKE '%/_sandbox/%'
  AND COALESCE(c.shop_origin_host, '') NOT LIKE '%/_sandbox/%'
  AND COALESCE(c.shop_location_id, '') NOT LIKE '%/_sandbox/%'
`;

const isFiniteNumber = (n: unknown): n is number =>
  typeof n === "number" && Number.isFinite(n);

export const parseIdempotencyKey = (
  header: string
): ParsedIdempotencyKey | null => {
  const last = header.lastIndexOf(":");
  if (last <= 0) {
    return null;
  }
  const release = header.slice(last + 1);
  const rest = header.slice(0, last);
  const mid = rest.lastIndexOf(":");
  if (mid <= 0) {
    return null;
  }
  const geohash5 = rest.slice(mid + 1);
  const opaqueUser = rest.slice(0, mid);
  if (!opaqueUser || !GEOHASH5.test(geohash5) || !release) {
    return null;
  }
  return { opaqueUser, geohash5, release, raw: header };
};

export const geohash5ForBBox = (bbox: BBox): string => {
  const lat = (bbox.minLat + bbox.maxLat) / 2;
  const lon = (bbox.minLon + bbox.maxLon) / 2;
  return ngeohash.encode(lat, lon, 5);
};

export const parseEnsureBody = (
  raw: unknown,
  key: ParsedIdempotencyKey
): EnsureBody => {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new ApiError(400, "invalid_json", "body must be a JSON object");
  }
  const body = raw as Record<string, unknown>;
  if (
    !isFiniteNumber(body.min_lon) ||
    !isFiniteNumber(body.min_lat) ||
    !isFiniteNumber(body.max_lon) ||
    !isFiniteNumber(body.max_lat)
  ) {
    throw new ApiError(400, "invalid_bbox", "bbox fields must be finite numbers");
  }
  if (body.min_lon >= body.max_lon || body.min_lat >= body.max_lat) {
    throw new ApiError(400, "invalid_bbox", "bbox min must be less than max");
  }
  if (
    typeof body.reason !== "string" ||
    !REASONS.includes(body.reason as EnsureReason)
  ) {
    throw new ApiError(
      400,
      "invalid_reason",
      "reason must be onboarding, significant_location, or saved_address"
    );
  }

  const bbox: BBox = {
    minLon: body.min_lon,
    minLat: body.min_lat,
    maxLon: body.max_lon,
    maxLat: body.max_lat,
  };
  const geohash5 = geohash5ForBBox(bbox);
  if (key.geohash5 !== geohash5) {
    throw new ApiError(
      400,
      "idempotency_geohash_mismatch",
      "Idempotency-Key geohash5 must match the bbox center"
    );
  }
  if (key.release !== config.overtureRelease) {
    throw new ApiError(
      400,
      "idempotency_release_mismatch",
      "Idempotency-Key release must match OVERTURE_RELEASE"
    );
  }

  return {
    min_lon: body.min_lon,
    min_lat: body.min_lat,
    max_lon: body.max_lon,
    max_lat: body.max_lat,
    reason: body.reason as EnsureReason,
    idempotency_key: key.raw,
  };
};

const readTile = async (geohash5: string): Promise<EnsureResult> => {
  const existing = await query(TILE_SQL, [geohash5, config.overtureRelease]);
  const row = existing.rows[0] as
    | { status: string; restaurant_count: number | null }
    | undefined;
  if (row?.status === "ready") {
    return { status: "ready", restaurants: row.restaurant_count ?? 0 };
  }
  return { status: "running" };
};

const jobFromBody = (body: EnsureBody, geohash5: string): IngestJob => {
  const bbox = {
    min_lon: body.min_lon,
    min_lat: body.min_lat,
    max_lon: body.max_lon,
    max_lat: body.max_lat,
  };
  return {
    geohash5,
    release: config.overtureRelease,
    bbox,
    min_lon: bbox.min_lon,
    min_lat: bbox.min_lat,
    max_lon: bbox.max_lon,
    max_lat: bbox.max_lat,
    idempotency_key: body.idempotency_key,
  };
};

export const ensureRegion = async (
  body: EnsureBody,
  enqueue: EnqueueFn = enqueueIngestLambda
): Promise<EnsureResult> => {
  const bbox: BBox = {
    minLon: body.min_lon,
    minLat: body.min_lat,
    maxLon: body.max_lon,
    maxLat: body.max_lat,
  };
  const geohash5 = geohash5ForBBox(bbox);
  const envelope = [
    geohash5,
    config.overtureRelease,
    bbox.minLon,
    bbox.minLat,
    bbox.maxLon,
    bbox.maxLat,
  ];

  const exists = await query(TILE_EXISTS_READY_OR_RUNNING, [
    geohash5,
    config.overtureRelease,
  ]);
  if (exists.rows[0]?.present === true) {
    return readTile(geohash5);
  }

  if (!config.ingestEnabled) {
    return { status: "ready", restaurants: 0 };
  }

  const claimed =
    (await query(RETRY_FAILED, envelope)).rowCount === 1 ||
    (await query(INSERT_RUNNING, envelope)).rowCount === 1;

  if (claimed) {
    try {
      await enqueue(jobFromBody(body, geohash5));
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      await query(MARK_FAILED, [geohash5, config.overtureRelease, message]);
      throw err;
    }
    return { status: "running" };
  }

  return readTile(geohash5);
};

export const getRegion = async (geohash5: string) => {
  if (!GEOHASH5.test(geohash5)) {
    throw new ApiError(400, "invalid_geohash", "geohash5 is invalid");
  }
  const tile = await query(TILE_SQL, [geohash5, config.overtureRelease]);
  const row = tile.rows[0] as
    | { status: string; restaurant_count: number | null }
    | undefined;
  if (!row) {
    return { tile: null, payablePrefixes: [] as const };
  }
  const prefixes = await query(PAYABLE_PREFIXES_SQL, [
    geohash5,
    config.overtureRelease,
  ]);
  return {
    tile: {
      status: row.status,
      restaurants: row.restaurant_count,
    },
    payablePrefixes: prefixes.rows as Array<{
      overture_id: string;
      name: string;
      shop_origin_host: string | null;
      shop_location_id: string | null;
      x402_version: number;
    }>,
  };
};
