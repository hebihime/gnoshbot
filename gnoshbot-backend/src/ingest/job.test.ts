import { expect, test } from "bun:test";
import { parseIngestJob } from "./job.js";

test("parseIngestJob requires geohash5, release, bbox, and idempotency_key", () => {
  expect(() => parseIngestJob(null)).toThrow(/JSON object/);
  expect(() =>
    parseIngestJob({
      geohash5: "dr5re",
      release: "2026-08-19.0",
      min_lon: -74,
      min_lat: 40,
      max_lon: -73,
      max_lat: 41,
    })
  ).toThrow(/idempotency_key/);

  expect(
    parseIngestJob({
      geohash5: "dr5re",
      release: "2026-08-19.0",
      min_lon: -74.08,
      min_lat: 40.68,
      max_lon: -73.93,
      max_lat: 40.79,
      idempotency_key: "u:dr5re:2026-08-19.0",
    })
  ).toEqual({
    geohash5: "dr5re",
    release: "2026-08-19.0",
    bbox: {
      min_lon: -74.08,
      min_lat: 40.68,
      max_lon: -73.93,
      max_lat: 40.79,
    },
    min_lon: -74.08,
    min_lat: 40.68,
    max_lon: -73.93,
    max_lat: 40.79,
    idempotency_key: "u:dr5re:2026-08-19.0",
  });
});

test("parseIngestJob accepts nested bbox (cheap-shape Invoke contract)", () => {
  expect(
    parseIngestJob({
      geohash5: "dr5re",
      release: "2026-08-19.0",
      bbox: {
        min_lon: -74.08,
        min_lat: 40.68,
        max_lon: -73.93,
        max_lat: 40.79,
      },
      idempotency_key: "u:dr5re:2026-08-19.0",
    }).bbox
  ).toEqual({
    min_lon: -74.08,
    min_lat: 40.68,
    max_lon: -73.93,
    max_lat: 40.79,
  });
});
