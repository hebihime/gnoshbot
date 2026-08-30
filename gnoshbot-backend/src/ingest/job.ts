export const GEOHASH5 = /^[0-9b-hjkmnp-z]{5}$/;

export type IngestBBox = {
  min_lon: number;
  min_lat: number;
  max_lon: number;
  max_lat: number;
};

/**
 * Async Lambda Invoke payload.
 * Contract: geohash5, release, bbox, idempotency_key.
 * Flat min_lon… fields are also written so workers can read either shape.
 */
export type IngestJob = {
  geohash5: string;
  release: string;
  bbox: IngestBBox;
  min_lon: number;
  min_lat: number;
  max_lon: number;
  max_lat: number;
  idempotency_key: string;
};

const isFiniteNumber = (n: unknown): n is number =>
  typeof n === "number" && Number.isFinite(n);

const readBBox = (body: Record<string, unknown>): IngestBBox | null => {
  const nested = body.bbox;
  if (nested !== null && typeof nested === "object" && !Array.isArray(nested)) {
    const box = nested as Record<string, unknown>;
    if (
      isFiniteNumber(box.min_lon) &&
      isFiniteNumber(box.min_lat) &&
      isFiniteNumber(box.max_lon) &&
      isFiniteNumber(box.max_lat)
    ) {
      return {
        min_lon: box.min_lon,
        min_lat: box.min_lat,
        max_lon: box.max_lon,
        max_lat: box.max_lat,
      };
    }
  }
  if (
    isFiniteNumber(body.min_lon) &&
    isFiniteNumber(body.min_lat) &&
    isFiniteNumber(body.max_lon) &&
    isFiniteNumber(body.max_lat)
  ) {
    return {
      min_lon: body.min_lon,
      min_lat: body.min_lat,
      max_lon: body.max_lon,
      max_lat: body.max_lat,
    };
  }
  return null;
};

export const parseIngestJob = (raw: unknown): IngestJob => {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("ingest payload must be a JSON object");
  }
  const body = raw as Record<string, unknown>;
  if (typeof body.geohash5 !== "string" || !GEOHASH5.test(body.geohash5)) {
    throw new Error("ingest payload geohash5 is invalid");
  }
  if (typeof body.release !== "string" || !body.release) {
    throw new Error("ingest payload release is required");
  }
  if (typeof body.idempotency_key !== "string" || !body.idempotency_key) {
    throw new Error("ingest payload idempotency_key is required");
  }
  const bbox = readBBox(body);
  if (!bbox) {
    throw new Error("ingest payload bbox fields must be finite numbers");
  }
  return {
    geohash5: body.geohash5,
    release: body.release,
    bbox,
    min_lon: bbox.min_lon,
    min_lat: bbox.min_lat,
    max_lon: bbox.max_lon,
    max_lat: bbox.max_lat,
    idempotency_key: body.idempotency_key,
  };
};

export const isPurgeEvent = (raw: unknown): boolean => {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    return false;
  }
  const body = raw as Record<string, unknown>;
  return body.action === "purge" || body.source === "aws.events";
};
