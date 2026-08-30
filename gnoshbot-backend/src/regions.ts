import ngeohash from "ngeohash";
import { config } from "./config.js";
import { query } from "./db.js";
import { ingestBBox, type BBox } from "./ingest/overture.js";

export type EnsureBody = {
  min_lon: number;
  min_lat: number;
  max_lon: number;
  max_lat: number;
  reason: "onboarding" | "significant_location" | "saved_address";
};

const TILE_SQL = `
SELECT status, restaurant_count
FROM region_tiles
WHERE geohash5 = $1 AND release = $2
`;

const INSERT_RUNNING = `
INSERT INTO region_tiles (geohash5, release, status, geom)
VALUES (
  $1, $2, 'running',
  ST_MakeEnvelope($3, $4, $5, $6, 4326)
)
ON CONFLICT (geohash5, release) DO NOTHING
`;

const MARK_READY = `
UPDATE region_tiles
SET status = 'ready',
    restaurant_count = $3,
    ready_at = now(),
    error = NULL
WHERE geohash5 = $1 AND release = $2
`;

const MARK_FAILED = `
UPDATE region_tiles
SET status = 'failed', error = $3
WHERE geohash5 = $1 AND release = $2
`;

export const geohash5ForBBox = (bbox: BBox): string => {
  const lat = (bbox.minLat + bbox.maxLat) / 2;
  const lon = (bbox.minLon + bbox.maxLon) / 2;
  return ngeohash.encode(lat, lon, 5);
};

export const ensureRegion = async (
  body: EnsureBody
): Promise<{ status: "ready" | "running"; restaurants?: number }> => {
  const bbox: BBox = {
    minLon: body.min_lon,
    minLat: body.min_lat,
    maxLon: body.max_lon,
    maxLat: body.max_lat,
  };
  const geohash5 = geohash5ForBBox(bbox);
  const existing = await query(TILE_SQL, [geohash5, config.overtureRelease]);
  const row = existing.rows[0] as
    | { status: string; restaurant_count: number | null }
    | undefined;

  if (row?.status === "ready") {
    return { status: "ready", restaurants: row.restaurant_count ?? 0 };
  }
  if (row?.status === "running") {
    return { status: "running" };
  }

  await query(INSERT_RUNNING, [
    geohash5,
    config.overtureRelease,
    bbox.minLon,
    bbox.minLat,
    bbox.maxLon,
    bbox.maxLat,
  ]);

  void runWorker(geohash5, bbox);
  return { status: "running" };
};

const runWorker = async (geohash5: string, bbox: BBox): Promise<void> => {
  try {
    const count = await ingestBBox(bbox);
    await query(MARK_READY, [geohash5, config.overtureRelease, count]);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await query(MARK_FAILED, [geohash5, config.overtureRelease, message]);
  }
};

export const getRegion = async (geohash5: string) => {
  const tile = await query(TILE_SQL, [geohash5, config.overtureRelease]);
  const prefixes = await query(
    `
    SELECT r.overture_id, r.name, c.integration_status, c.shop_origin_host,
           c.shop_location_id, c.x402_version
    FROM restaurants r
    JOIN x402_capabilities c ON c.overture_id = r.overture_id
    JOIN region_tiles t ON t.geohash5 = $1 AND t.release = $2
    WHERE ST_Intersects(r.coordinates, t.geom)
      AND c.integration_status IN ('NATIVE', 'PROXY_WRAPPED')
    `,
    [geohash5, config.overtureRelease]
  );
  return {
    tile: tile.rows[0] ?? null,
    payablePrefixes: prefixes.rows,
  };
};
