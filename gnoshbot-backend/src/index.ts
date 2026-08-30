import { app } from "./app.js";
import { config } from "./config.js";

// Local HTTP. Lambda Function URL entry is src/lambda-http.ts (fetch + handler).
const server = Bun.serve({
  port: config.listenPort,
  fetch: app.fetch,
});

process.stdout.write(
  `gnoshbot-backend listening on ${server.port} (region ${config.awsRegion}, release ${config.overtureRelease})\n`
);
