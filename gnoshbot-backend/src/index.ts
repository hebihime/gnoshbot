import { app } from "./app.js";
import { config } from "./config.js";

const server = Bun.serve({
  port: config.listenPort,
  fetch: app.fetch,
});

process.stdout.write(
  `gnoshbot-backend listening on ${server.port} (region ${config.awsRegion}, release ${config.overtureRelease})\n`
);
