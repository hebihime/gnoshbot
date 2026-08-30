-- TestFlight / public demo fixture. One geohash5 around the PRODUCT_DECISIONS
-- Brooklyn example (40.6944, -73.9903 → dr5rs). Applied after init.sql.
-- Does not scan Overture. Not the production live pool (P9 / P13).

INSERT INTO restaurants (
  overture_id, name, website_url, street_address, coordinates, cuisine_tags, release
) VALUES
  (
    'demo.place.brooklyn.wrap',
    'Demo Kitchen (wrap)',
    'https://demo.gnoshbot.example/',
    '14 Pine Street',
    ST_SetSRID(ST_MakePoint(-73.9903, 40.6944), 4326),
    ARRAY['demo'],
    '2026-08-19.0'
  ),
  (
    'demo.place.brooklyn.unsupported',
    'Demo Diner (unsupported)',
    NULL,
    '200 Atlantic Avenue',
    ST_SetSRID(ST_MakePoint(-73.9948, 40.6909), 4326),
    ARRAY['demo'],
    '2026-08-19.0'
  )
ON CONFLICT (overture_id) DO NOTHING;

INSERT INTO x402_capabilities (
  overture_id, integration_status, shop_origin_host, shop_location_id, x402_version
) VALUES
  (
    'demo.place.brooklyn.wrap',
    'PROXY_WRAPPED',
    'demo-shop.gnoshbot.example',
    'testflight',
    1
  ),
  (
    'demo.place.brooklyn.unsupported',
    'UNSUPPORTED',
    NULL,
    NULL,
    1
  )
ON CONFLICT (overture_id) DO NOTHING;

INSERT INTO region_tiles (geohash5, release, status, geom, restaurant_count, ready_at)
VALUES (
  'dr5rs',
  '2026-08-19.0',
  'ready',
  ST_MakeEnvelope(-74.00390625, 40.693359375, -73.9599609375, 40.7373046875, 4326),
  2,
  now()
)
ON CONFLICT (geohash5, release) DO NOTHING;
