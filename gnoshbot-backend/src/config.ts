/** Documented local defaults. Production boot must not use these. */
export const DEV_SKIP_LOG_HMAC_SECRET = "dev-only-rotate-in-prod";
export const DEV_MENU_WRAP_KEY_HEX =
  "0000000000000000000000000000000000000000000000000000000000000000";
export const PINNED_OVERTURE_RELEASE = "2026-08-19.0";
export const INGEST_AWS_REGION = "us-west-2";

export type GnoshbotConfig = {
  awsRegion: string;
  databaseUrl: string;
  overtureRelease: string;
  overtureBucket: string;
  listenPort: number;
  skipLogHmacSecret: string;
  menuWrapKeyHex: string;
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
  };
};

export const config = loadConfig();

export const overturePlacesGlob = (): string =>
  `s3://${config.overtureBucket}/release/${config.overtureRelease}/theme=places/type=place/*`;
