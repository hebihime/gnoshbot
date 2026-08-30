import { expect, test } from "bun:test";
import { databaseUsesTls } from "./db.js";

test("Neon pooled hosts and sslmode=require use TLS; local compose does not", () => {
  expect(
    databaseUsesTls(
      "postgresql://u:p@ep-foo-pooler.us-west-2.aws.neon.tech/neondb?sslmode=require"
    )
  ).toBe(true);
  expect(
    databaseUsesTls("postgres://gnoshbot:gnoshbot@127.0.0.1:5432/gnoshbot")
  ).toBe(false);
});
