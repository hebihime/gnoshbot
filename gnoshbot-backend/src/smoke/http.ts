import { app } from "../app.js";

const res = await app.request("/regions/ensure", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ min_lon: "west" }),
});

if (res.status !== 400) {
  throw new Error(`expected 400 for invalid bbox, got ${res.status}`);
}

const body = (await res.json()) as { error?: string };
if (body.error !== "bbox fields must be numbers") {
  throw new Error(`unexpected body: ${JSON.stringify(body)}`);
}

process.stdout.write("http bbox validation ok\n");
