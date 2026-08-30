import { config } from "../config.js";
import { query } from "../db.js";
import { runRuntimeLoop } from "../lambda/runtime.js";
import { runPurge } from "./purge.js";
import { ingestBBox, type BBox, type IngestFn } from "./overture.js";
import { isPurgeEvent, parseIngestJob, type IngestJob } from "./job.js";
import { MARK_FAILED, MARK_READY } from "./tile-sql.js";

export const runIngestJob = async (
  job: IngestJob,
  ingest: IngestFn = ingestBBox
): Promise<number> => {
  if (job.release !== config.overtureRelease) {
    throw new Error(
      `ingest release ${job.release} does not match OVERTURE_RELEASE ${config.overtureRelease}`
    );
  }
  const bbox: BBox = {
    minLon: job.min_lon,
    minLat: job.min_lat,
    maxLon: job.max_lon,
    maxLat: job.max_lat,
  };
  try {
    const count = await ingest(bbox);
    await query(MARK_READY, [job.geohash5, job.release, count]);
    return count;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await query(MARK_FAILED, [job.geohash5, job.release, message]);
    throw err;
  }
};

export const handler = async (
  event: unknown
): Promise<{ ok: true; restaurants?: number; action?: string }> => {
  if (isPurgeEvent(event)) {
    await runPurge();
    return { ok: true, action: "purge" };
  }
  const restaurants = await runIngestJob(parseIngestJob(event));
  return { ok: true, restaurants };
};

if (import.meta.main) {
  if (process.env.AWS_LAMBDA_RUNTIME_API) {
    await runRuntimeLoop(handler);
  } else {
    const raw = process.env.INGEST_PAYLOAD;
    if (!raw) {
      throw new Error("Set INGEST_PAYLOAD to a JSON IngestJob");
    }
    handler(JSON.parse(raw) as unknown)
      .then((result) => {
        process.stdout.write(`ingest worker ${JSON.stringify(result)}\n`);
      })
      .catch((err) => {
        console.error(err);
        process.exit(1);
      });
  }
}
