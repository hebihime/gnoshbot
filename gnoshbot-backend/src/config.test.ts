import { expect, test } from "bun:test";
import {
  DEV_MENU_WRAP_KEY_HEX,
  DEV_SKIP_LOG_HMAC_SECRET,
  INGEST_AWS_REGION,
  PINNED_OVERTURE_RELEASE,
  loadConfig,
} from "./config.js";

const prodSecrets = {
  SKIP_LOG_HMAC_SECRET: "production-hmac-not-the-dev-default",
  MENU_WRAP_KEY_HEX:
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  AWS_REGION: INGEST_AWS_REGION,
};

test("dev boot uses documented defaults and pinned Overture release", () => {
  const cfg = loadConfig({});
  expect(cfg.skipLogHmacSecret).toBe(DEV_SKIP_LOG_HMAC_SECRET);
  expect(cfg.menuWrapKeyHex).toBe(DEV_MENU_WRAP_KEY_HEX);
  expect(cfg.overtureRelease).toBe(PINNED_OVERTURE_RELEASE);
  expect(cfg.awsRegion).toBe(INGEST_AWS_REGION);
});

test("production boot without secrets throws", () => {
  expect(() => loadConfig({ NODE_ENV: "production" })).toThrow(
    /Missing required environment variable AWS_REGION/
  );
  expect(() =>
    loadConfig({ NODE_ENV: "production", AWS_REGION: INGEST_AWS_REGION })
  ).toThrow(/SKIP_LOG_HMAC_SECRET/);
});

test("GNOSHBOT_ENV=production also rejects documented defaults", () => {
  expect(() =>
    loadConfig({
      GNOSHBOT_ENV: "production",
      AWS_REGION: INGEST_AWS_REGION,
      SKIP_LOG_HMAC_SECRET: DEV_SKIP_LOG_HMAC_SECRET,
      MENU_WRAP_KEY_HEX: DEV_MENU_WRAP_KEY_HEX,
    })
  ).toThrow(/SKIP_LOG_HMAC_SECRET is the documented dev default/);
});

test("production boot with all-zero MENU_WRAP_KEY_HEX throws", () => {
  expect(() =>
    loadConfig({
      NODE_ENV: "production",
      ...prodSecrets,
      MENU_WRAP_KEY_HEX: DEV_MENU_WRAP_KEY_HEX,
    })
  ).toThrow(/MENU_WRAP_KEY_HEX is the documented all-zero default/);
});

test("production AWS_REGION must be us-west-2", () => {
  expect(() =>
    loadConfig({
      NODE_ENV: "production",
      ...prodSecrets,
      AWS_REGION: "us-east-1",
    })
  ).toThrow(/AWS_REGION must be us-west-2/);
});

test("production boot with real secrets and us-west-2 succeeds", () => {
  const cfg = loadConfig({ NODE_ENV: "production", ...prodSecrets });
  expect(cfg.awsRegion).toBe(INGEST_AWS_REGION);
  expect(cfg.overtureRelease).toBe(PINNED_OVERTURE_RELEASE);
  expect(cfg.skipLogHmacSecret).toBe(prodSecrets.SKIP_LOG_HMAC_SECRET);
});
