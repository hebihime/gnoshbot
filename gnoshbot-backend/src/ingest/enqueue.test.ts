import { expect, test } from "bun:test";
import { config } from "../config.js";
import { enqueueIngestLambda } from "./enqueue.js";

test("enqueue is a no-op when INGEST_LAMBDA_FUNCTION_NAME is unset (no AWS)", async () => {
  if (config.ingestLambdaFunctionName) {
    return;
  }
  await enqueueIngestLambda({
    geohash5: "dr5re",
    release: config.overtureRelease,
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
    idempotency_key: `u:dr5re:${config.overtureRelease}`,
  });
});
