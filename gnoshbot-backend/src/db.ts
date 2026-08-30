import pg from "pg";
import { config } from "./config.js";

export type QueryFn = (
  text: string,
  params?: unknown[]
) => Promise<pg.QueryResult>;

const runningOnLambda = Boolean(
  process.env.AWS_LAMBDA_FUNCTION_NAME || process.env.LAMBDA_TASK_ROOT
);

/** Neon pooled (`*.neon.tech`) and explicit sslmode=require need TLS. Local compose does not. */
export const databaseUsesTls = (databaseUrl: string): boolean => {
  try {
    const parsed = new URL(databaseUrl.replace(/^postgres(ql)?:/i, "http:"));
    const sslmode = parsed.searchParams.get("sslmode");
    if (sslmode === "disable" || sslmode === "allow") {
      return false;
    }
    if (sslmode === "require" || sslmode === "verify-full" || sslmode === "verify-ca") {
      return true;
    }
    return parsed.hostname.endsWith(".neon.tech");
  } catch {
    return databaseUrl.includes("neon.tech");
  }
};

export const pool = new pg.Pool({
  connectionString: config.databaseUrl,
  max: runningOnLambda ? 1 : 10,
  idleTimeoutMillis: 30_000,
  allowExitOnIdle: true,
  ssl: databaseUsesTls(config.databaseUrl)
    ? { rejectUnauthorized: true }
    : undefined,
});

export const query: QueryFn = (text, params) => pool.query(text, params);

export const withTransaction = async <T>(
  fn: (q: QueryFn) => Promise<T>
): Promise<T> => {
  const client = await pool.connect();
  const q: QueryFn = (text, params) => client.query(text, params);
  try {
    await client.query("BEGIN");
    const result = await fn(q);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
};
