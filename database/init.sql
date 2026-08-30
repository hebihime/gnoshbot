-- Gnoshbot control-plane schema (PostgreSQL + PostGIS)
-- Source of truth: GROK.md (Postgres section), SCALABILITY.md §3–§5, ARCHITECTURE.md §10.
-- Ingest compute belongs in us-west-2; this file only defines the index that ingest writes.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE integration_status AS ENUM (
  'UNSUPPORTED',
  'NATIVE',
  'PROXY_WRAPPED'
);

CREATE TYPE region_tile_status AS ENUM (
  'running',
  'ready',
  'failed'
);

-- Discovery index. Identity of a production kitchen remains origin host + location id
-- on web3-restaurant-api; this table points at those prefixes.
CREATE TABLE restaurants (
  overture_id     text PRIMARY KEY,
  name            text NOT NULL,
  website_url     text,
  phone_number    text,
  email_address   text,
  street_address  text,
  coordinates     geometry(Point, 4326) NOT NULL,
  cuisine_tags    text[] NOT NULL DEFAULT '{}',
  release         text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT restaurants_coordinates_finite CHECK (
    ST_X(coordinates) BETWEEN -180 AND 180
    AND ST_Y(coordinates) BETWEEN -90 AND 90
  )
);

CREATE INDEX idx_restaurants_spatial_coordinates
  ON restaurants
  USING GIST (coordinates);

CREATE INDEX idx_restaurants_release
  ON restaurants (release);

CREATE TABLE x402_capabilities (
  overture_id            text PRIMARY KEY
                         REFERENCES restaurants (overture_id)
                         ON DELETE CASCADE,
  integration_status     integration_status NOT NULL DEFAULT 'UNSUPPORTED',
  native_x402_url        text,
  shop_origin_host       text,
  shop_location_id       text,
  x402_version           smallint NOT NULL DEFAULT 1
                         CHECK (x402_version IN (1, 2)),
  proxy_wallet_address   text,
  -- AES-GCM ciphertext of the proxy-hosted Menu Pull JSON (PROXY_WRAPPED only).
  -- Native menus live on the shop host GET; they are not stored here.
  encrypted_menu_schema  bytea,
  menu_schema_nonce      bytea,
  menu_schema_wrapped_key bytea,
  menu_schema_sha256     text,
  CONSTRAINT x402_native_requires_url CHECK (
    integration_status <> 'NATIVE'
    OR native_x402_url IS NOT NULL
  ),
  CONSTRAINT x402_proxy_requires_shop_prefix CHECK (
    integration_status <> 'PROXY_WRAPPED'
    OR (shop_origin_host IS NOT NULL AND shop_location_id IS NOT NULL)
  ),
  CONSTRAINT x402_encrypted_menu_complete CHECK (
    (
      encrypted_menu_schema IS NULL
      AND menu_schema_nonce IS NULL
      AND menu_schema_wrapped_key IS NULL
    )
    OR (
      encrypted_menu_schema IS NOT NULL
      AND menu_schema_nonce IS NOT NULL
      AND octet_length(menu_schema_nonce) = 12
      AND menu_schema_wrapped_key IS NOT NULL
    )
  )
);

CREATE INDEX idx_x402_capabilities_integration_status
  ON x402_capabilities (integration_status);

-- Skip flywheel. No raw user ids, wallets, or delivery street addresses (GROK.md, SCALABILITY.md §7.1).
CREATE TABLE skipped_merchant_logs (
  id                          bigserial PRIMARY KEY,
  overture_id                 text NOT NULL REFERENCES restaurants (overture_id) ON DELETE CASCADE,
  skipped_at                  timestamptz NOT NULL DEFAULT now(),
  estimated_lost_revenue_usdc numeric(12, 2) NOT NULL CHECK (estimated_lost_revenue_usdc >= 0),
  user_id_hash                bytea NOT NULL,
  city_geohash                text NOT NULL
);

CREATE INDEX idx_skipped_merchant_logs_overture_id
  ON skipped_merchant_logs (overture_id);

CREATE INDEX idx_skipped_merchant_logs_skipped_at
  ON skipped_merchant_logs (skipped_at);

CREATE INDEX idx_skipped_merchant_logs_city_geohash
  ON skipped_merchant_logs (city_geohash);

-- Idempotency grain for ingest: geohash5 + Overture release (SCALABILITY.md S3).
CREATE TABLE region_tiles (
  geohash5   text NOT NULL,
  release    text NOT NULL,
  status     region_tile_status NOT NULL,
  geom       geometry(Polygon, 4326) NOT NULL,
  restaurant_count integer,
  started_at timestamptz NOT NULL DEFAULT now(),
  ready_at   timestamptz,
  error      text,
  PRIMARY KEY (geohash5, release)
);

CREATE INDEX idx_region_tiles_status
  ON region_tiles (status);

CREATE INDEX idx_region_tiles_geom
  ON region_tiles
  USING GIST (geom);

-- Device travel / ingest hysteresis. Not a drop-off. GPS is never a destination.
CREATE TABLE user_locations (
  user_id                 uuid PRIMARY KEY,
  last_known_coordinates  geometry(Point, 4326) NOT NULL,
  last_ingest_center      geometry(Point, 4326) NOT NULL,
  last_seen_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_locations_last_known_coordinates
  ON user_locations
  USING GIST (last_known_coordinates);

CREATE INDEX idx_user_locations_last_seen_at
  ON user_locations (last_seen_at);

-- The only legal drop-off set. Street addresses stay here; they never enter skip logs.
CREATE TABLE delivery_locations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  label       text NOT NULL,
  line1       text NOT NULL,
  line2       text,
  city        text NOT NULL,
  region      text NOT NULL,
  postal_code text NOT NULL,
  country     text NOT NULL,
  coordinates geometry(Point, 4326) NOT NULL,
  is_default  boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, label)
);

CREATE UNIQUE INDEX idx_delivery_locations_one_default_per_user
  ON delivery_locations (user_id)
  WHERE is_default;

CREATE INDEX idx_delivery_locations_user_id
  ON delivery_locations (user_id);

CREATE INDEX idx_delivery_locations_coordinates
  ON delivery_locations
  USING GIST (coordinates);

CREATE TABLE device_push_tokens (
  user_id     uuid NOT NULL,
  token       text NOT NULL,
  platform    text NOT NULL DEFAULT 'apns' CHECK (platform IN ('apns')),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, token)
);

-- Bounding-box lookup used by POST /regions/ensure and lunch-path tile hydration.
-- Relies on idx_restaurants_spatial_coordinates (&& uses the GIST index).
CREATE OR REPLACE FUNCTION restaurants_in_bbox(
  min_lon double precision,
  min_lat double precision,
  max_lon double precision,
  max_lat double precision
)
RETURNS TABLE (
  overture_id text,
  name text,
  coordinates geometry(Point, 4326),
  integration_status integration_status,
  shop_origin_host text,
  shop_location_id text,
  x402_version smallint
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    r.overture_id,
    r.name,
    r.coordinates,
    c.integration_status,
    c.shop_origin_host,
    c.shop_location_id,
    c.x402_version
  FROM restaurants r
  JOIN x402_capabilities c ON c.overture_id = r.overture_id
  WHERE r.coordinates && ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
    AND ST_Intersects(
      r.coordinates,
      ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
    );
$$;

-- Daily purge (SCALABILITY.md §5). 8046.72 m = 5 miles. Cast to geography so the
-- radius is meters, not degrees on geometry(4326).
CREATE OR REPLACE FUNCTION purge_stale_unsupported_pois()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM restaurants r
  USING x402_capabilities c
  WHERE r.overture_id = c.overture_id
    AND c.integration_status = 'UNSUPPORTED'
    AND NOT EXISTS (
      SELECT 1
      FROM delivery_locations d
      WHERE ST_DWithin(r.coordinates::geography, d.coordinates::geography, 8046.72)
    )
    AND NOT EXISTS (
      SELECT 1
      FROM user_locations u
      WHERE u.last_seen_at > now() - interval '90 days'
        AND ST_DWithin(
          r.coordinates::geography,
          u.last_known_coordinates::geography,
          8046.72
        )
    );

  DELETE FROM skipped_merchant_logs
  WHERE skipped_at < now() - interval '90 days';

  DELETE FROM region_tiles t
  WHERE t.status = 'ready'
    AND NOT EXISTS (
      SELECT 1
      FROM restaurants r
      WHERE ST_Intersects(r.coordinates, t.geom)
    );
END;
$$;

CREATE OR REPLACE FUNCTION restaurants_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER restaurants_set_updated_at
  BEFORE UPDATE ON restaurants
  FOR EACH ROW
  EXECUTE PROCEDURE restaurants_touch_updated_at();
