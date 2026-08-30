import { app } from "../app.js";
import { PINNED_OVERTURE_RELEASE } from "../config.js";

const res = await app.request("/regions/ensure", {
  method: "POST",
  headers: {
    "content-type": "application/json",
    "Idempotency-Key": `dev:zzzzz:${PINNED_OVERTURE_RELEASE}`,
  },
  body: JSON.stringify({ min_lon: "west" }),
});

if (res.status !== 400) {
  throw new Error(`expected 400 for invalid bbox, got ${res.status}`);
}

const body = (await res.json()) as { error?: string; code?: string };
if (body.code !== "invalid_bbox") {
  throw new Error(`unexpected body: ${JSON.stringify(body)}`);
}
if (!body.error?.includes("finite")) {
  throw new Error(`unexpected error: ${JSON.stringify(body)}`);
}

process.stdout.write("http bbox validation ok\n");
