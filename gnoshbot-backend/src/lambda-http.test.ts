import { expect, test } from "bun:test";
import {
  functionUrlEventToRequest,
  handler,
  type FunctionUrlEvent,
} from "./lambda-http.js";

test("Function URL adapter returns 400 for missing Idempotency-Key without AWS", async () => {
  const event: FunctionUrlEvent = {
    version: "2.0",
    rawPath: "/regions/ensure",
    rawQueryString: "",
    headers: { "content-type": "application/json" },
    requestContext: {
      domainName: "example.lambda-url.us-west-2.on.aws",
      http: { method: "POST", path: "/regions/ensure" },
    },
    body: JSON.stringify({
      min_lon: -74.08,
      min_lat: 40.68,
      max_lon: -73.93,
      max_lat: 40.79,
      reason: "onboarding",
    }),
    isBase64Encoded: false,
  };
  const result = await handler(event);
  expect(result.statusCode).toBe(400);
  const body = JSON.parse(result.body) as { code: string };
  expect(body.code).toBe("missing_idempotency_key");
});

test("Function URL event maps path, method, and body onto Request", () => {
  const request = functionUrlEventToRequest({
    rawPath: "/devices/push-token",
    rawQueryString: "",
    headers: { "content-type": "application/json" },
    requestContext: {
      domainName: "example.lambda-url.us-west-2.on.aws",
      http: { method: "POST", path: "/devices/push-token" },
    },
    body: '{"user_id":"x"}',
  });
  expect(request.method).toBe("POST");
  expect(new URL(request.url).pathname).toBe("/devices/push-token");
});
