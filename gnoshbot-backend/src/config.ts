const required = (name: string, fallback?: string): string => {
  const value = process.env[name] ?? fallback;
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
};

export const config = {
  awsRegion: required("AWS_REGION", "us-west-2"),
  databaseUrl: required(
    "DATABASE_URL",
    "postgres://gnoshbot:gnoshbot@127.0.0.1:5432/gnoshbot"
  ),
  overtureRelease: required("OVERTURE_RELEASE", "2026-08-19.0"),
  overtureBucket: "overturemaps-us-west-2",
  listenPort: Number(process.env.PORT ?? "8080"),
  skipLogHmacSecret: required("SKIP_LOG_HMAC_SECRET", "dev-only-rotate-in-prod"),
  menuWrapKeyHex: required(
    "MENU_WRAP_KEY_HEX",
    "0000000000000000000000000000000000000000000000000000000000000000"
  ),
} as const;

export const overturePlacesGlob = (): string =>
  `s3://${config.overtureBucket}/release/${config.overtureRelease}/theme=places/type=place/*`;
