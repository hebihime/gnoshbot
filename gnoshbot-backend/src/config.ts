/** Documented local defaults. Production boot must not use these. */
export const DEV_SKIP_LOG_HMAC_SECRET = "dev-only-rotate-in-prod";
export const DEV_MENU_WRAP_KEY_HEX =
  "0000000000000000000000000000000000000000000000000000000000000000";
export const PINNED_OVERTURE_RELEASE = "2026-08-19.0";
export const INGEST_AWS_REGION = "us-west-2";

/**
 * Env contract. Infra creates the Neon project and Lambdas; this package only reads names.
 *
 * Shared (HTTP Function URL + ingest worker):
 *   DATABASE_URL  Neon **pooled** Postgres+PostGIS in us-west-2 (`sslmode=require`).
 *                 Local / `bun test`: docker-compose PostGIS (default below).
 *   AWS_REGION    must be us-west-2 in production (Overture catalog region)
 *   OVERTURE_RELEASE  default 2026-08-19.0
 *   SKIP_LOG_HMAC_SECRET / MENU_WRAP_KEY_HEX  required in production; documented
 *                 defaults are rejected (B0). 32-byte hex for the wrap key.
 *   NODE_ENV or GNOSHBOT_ENV = production
 *
 * HTTP (Lambda Function URL handler in lambda-http.ts; Bun.serve in index.ts):
 *   PORT  local listen only
 *   INGEST_LAMBDA_FUNCTION_NAME  worker to Invoke with InvocationType=Event
 *                 (required in production). Payload: geohash5, release, bbox
 *                 {min_lon,min_lat,max_lon,max_lat}, idempotency_key. No SQS.
 *   GNOSHBOT_INGEST=0 / GNOSHBOT_ENV=demo  skip enqueue (seeded local demo)
 *
 * Ingest worker (ingest/worker.ts, not Function URL):
 *   same DATABASE_URL, AWS_REGION, OVERTURE_RELEASE
 *   DuckDB spill uses /tmp when AWS_LAMBDA_FUNCTION_NAME or LAMBDA_TASK_ROOT is set
 */
export type GnoshbotConfig = {
  awsRegion: string;
  databaseUrl: string;
  overtureRelease: string;
  overtureBucket: string;
  listenPort: number;
  skipLogHmacSecret: string;
  menuWrapKeyHex: string;
  /** False on the TestFlight/demo compose path so a public box never DuckDB-scans Overture. */
  ingestEnabled: boolean;
  /** Empty locally so `bun test` never calls AWS. Required in production. */
  ingestLambdaFunctionName: string;
};

type Env = Record<string, string | undefined>;

export const isProductionEnv = (env: Env = process.env): boolean =>
  env.NODE_ENV === "production" || env.GNOSHBOT_ENV === "production";

const required = (env: Env, name: string, fallback?: string): string => {
  const value = env[name] ?? fallback;
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
};

export const loadConfig = (env: Env = process.env): GnoshbotConfig => {
  const production = isProductionEnv(env);

  const awsRegion = production
    ? required(env, "AWS_REGION")
    : required(env, "AWS_REGION", INGEST_AWS_REGION);
  if (production && awsRegion !== INGEST_AWS_REGION) {
    throw new Error(
      `AWS_REGION must be ${INGEST_AWS_REGION} in production (ingest colocated with Overture)`
    );
  }

  const skipLogHmacSecret = production
    ? required(env, "SKIP_LOG_HMAC_SECRET")
    : required(env, "SKIP_LOG_HMAC_SECRET", DEV_SKIP_LOG_HMAC_SECRET);
  const menuWrapKeyHex = production
    ? required(env, "MENU_WRAP_KEY_HEX")
    : required(env, "MENU_WRAP_KEY_HEX", DEV_MENU_WRAP_KEY_HEX);

  if (production) {
    if (skipLogHmacSecret === DEV_SKIP_LOG_HMAC_SECRET) {
      throw new Error(
        "SKIP_LOG_HMAC_SECRET is the documented dev default; set a production secret"
      );
    }
    if (menuWrapKeyHex === DEV_MENU_WRAP_KEY_HEX) {
      throw new Error(
        "MENU_WRAP_KEY_HEX is the documented all-zero default; set a production key"
      );
    }
  }

  const ingestEnabled = production
    ? true
    : env.GNOSHBOT_ENV !== "demo" && env.GNOSHBOT_INGEST !== "0";

  const ingestLambdaFunctionName = production
    ? required(env, "INGEST_LAMBDA_FUNCTION_NAME")
    : (env.INGEST_LAMBDA_FUNCTION_NAME ?? "");

  return {
    awsRegion,
    databaseUrl: required(
      env,
      "DATABASE_URL",
      "postgres://gnoshbot:gnoshbot@127.0.0.1:5432/gnoshbot"
    ),
    overtureRelease: required(env, "OVERTURE_RELEASE", PINNED_OVERTURE_RELEASE),
    overtureBucket: "overturemaps-us-west-2",
    listenPort: Number(env.PORT ?? "8080"),
    skipLogHmacSecret,
    menuWrapKeyHex,
    ingestEnabled,
    ingestLambdaFunctionName,
  };
};

export const config = loadConfig();

export const overturePlacesGlob = (): string =>
  `s3://${config.overtureBucket}/release/${config.overtureRelease}/theme=places/type=place/*`;

export const duckdbOnLambda = (env: Env = process.env): boolean =>
  Boolean(env.AWS_LAMBDA_FUNCTION_NAME || env.LAMBDA_TASK_ROOT);
