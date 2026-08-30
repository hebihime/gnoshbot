# Free public demo (TestFlight-shaped)

AWS N2–N6 (RDS + ALB + Fargate + NAT) is the always-on bill. A public beta does not need it.

**TestFlight** is how testers install the iOS app. Apple hosts the binary. That is $0 beyond the Apple Developer Program. The voice path does not call this control plane (`GROK.md`).

**This directory** is how testers share one HTTPS control plane without Oregon RDS: seeded PostGIS, ingest off, one city tile.

## What testers get

| Layer | Where it runs | Cost |
| --- | --- | --- |
| App binary | TestFlight | $0 extra (ADP required) |
| Launch / Inquiry | On device (SwiftData) | $0 |
| Control plane `POST /regions/ensure` | Seeded compose, ingest disabled | $0 if you host it on a free VM / tunnel |
| Overture DuckDB | **Off** | No S3 GET storm |
| Settlement | Existing shop host (x402) | Whatever that host already is |

Save **Home** as the Brooklyn example (`14 Pine Street`, ~40.6944, -73.9903, geohash5 `dr5rs`) so ensure hits the seeded ready tile. Other cities return 200 with `restaurants: 0` (empty pool after confirm). That is intentional: demo does not ingest the planet.

Sandbox shops stay out of the **production** live pool (`PRODUCT_DECISIONS.md` P9). The demo wrap row (`demo-shop.gnoshbot.example` / `testflight`) exists only in this seed. Point it at a shop prefix you actually operate before testers can settle; do not put that prefix on the prod RDS live pool.

## Run locally (proof)

From `gnoshbot-backend/`:

```bash
docker compose -f docker-compose.yml -f docker-compose.demo.yml up --build
```

`GNOSHBOT_ENV=demo` sets `ingestEnabled=false`. Existing `dr5rs` + release `2026-08-19.0` is already `ready`. The overlay builds `Dockerfile.demo` (no DuckDB native addon) so a public box never compiles or range-reads Overture.

## Public HTTPS without AWS

Pick one. None of these are us-west-2 ingest (ingest is off).

1. **Cloudflare Tunnel** in front of the compose stack on a machine you already leave on. Free; URL is public; laptop-off means demo-off.
2. **Oracle Cloud “Always Free” ARM VM** (or any leftover free VM): install Docker, run the same compose, terminate TLS with Caddy. Not AWS. Destroy the VM when the TestFlight round ends.
3. **Fly.io / Render free allowances** if you still have one: same `Dockerfile.demo`, same env, **do not** attach a managed Postgres bill if the free Postgres is gone — keep PostGIS in the compose project.

Do **not** put an ALB or NAT in front of this for a beta. Do **not** set `NODE_ENV=production` on this stack (that path requires real secrets and keeps ingest on).

TestFlight build setting: control-plane base URL = that public HTTPS origin. iOS I7 is the client; until I0 exists there is nothing to upload.

## What this is not

- Not prod. Not Multi-AZ. Not Overture.
- Not a license to deliver to GPS.
- Not an AWS free-tier loophole for RDS + ALB; those stay paid if you `apply` N2/N6.
