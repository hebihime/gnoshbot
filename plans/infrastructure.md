# Gnoshbot backend infrastructure — atomic execution plan

Status: execution slice. Not source of truth. `GROK.md` T01–T10, T04, `ARCHITECTURE.md` §10, `SCALABILITY.md` S1–S8 win.

**Cheap shape (what `infra/` implements):** Neon Postgres+PostGIS in `aws-us-west-2`, two Lambdas in AWS us-west-2 (Function URL API + container ingest), SSM Standard, EventBridge purge, bbox GET to `s3://overturemaps-us-west-2`. **Do not implement N2 RDS, N6 ECS/ALB/NAT, or N8 SQS as required.** Those are the expensive path. Hobby-scale only (few cities); CloudWatch + ECR are the cost leak.

Goal of the expensive path (below, deferred): Fargate + RDS + ALB. Voice path does not call this plane. Do not buy provisioned-concurrency Lambda for Siri.

Today: `Dockerfile` (`oven/bun:1`, `bun run smoke:duckdb` at build), `docker-compose.yml` (PostGIS 16 + api), GitHub Actions smokes. Cheap AWS is Terraform in `infra/` (no NAT/ALB/RDS).

Do not: ingest from us-east-1; cross-region S3 as the strategy; DuckDB on iPhone; putting `MENU_WRAP_KEY_HEX` in the image.

Commit each atom with Conventional Commits. Body is why.

---

## N0 — AWS account + region pin

**Depends on:** none  
**Do:** dedicated account or env `gnoshbot-prod` / `gnoshbot-staging`. Every compute/data resource in **us-west-2**. Deny-by-policy for S3 access to the Overture bucket from other regions if possible.  
**Done when:** AWS CLI `aws configure get region` for the deploy role is `us-west-2`; written in infra README or terraform `locals.region`.

---

## N1 — Terraform/CDK root (pick one, do not mix)

**Depends on:** N0  
**Files:** `infra/` (new) — Terraform preferred unless the operator already standardizes CDK  
**Do:** state in s3+dynamodb **in us-west-2**. Workspaces staging/prod.  
**Do not:** click-ops that cannot be reproduced.  
**Done when:** `terraform plan` in empty workspace shows region us-west-2 only.

---

## N2 — PostGIS

**Depends on:** N1  
**Do:** RDS Postgres 16 + PostGIS **or** Aurora Postgres with postgis, us-west-2, not public (`publicly_accessible=false`). SG: api tasks only. Apply `database/init.sql` via migration runner (N3), not “paste in console.” Parameter group: `shared_preload_libraries` as required for PostGIS. Multi-AZ prod; single-AZ staging ok.  
**Done when:** from a bastion or task, `\dx` shows postgis; `idx_restaurants_spatial_coordinates` exists after migrate.

---

## N3 — Migrations

**Depends on:** N2  
**Files:** `database/migrations/001_init.sql` copied from `init.sql` + bun migrate command  
**Do:** one-way versions. No destructive purge in migrate.  
**Done when:** empty DB + migrate = schema matching `init.sql`; second run no-op.

---

## N4 — Secrets

**Depends on:** N1  
**Do:** Secrets Manager or SSM Parameter Store (SecureString): `DATABASE_URL`, `SKIP_LOG_HMAC_SECRET`, `MENU_WRAP_KEY_HEX` (32-byte hex), APNs key (N10), optional `OVERTURE_RELEASE`. Task role injects env. Rotate HMAC independently of menu wrap key.  
**Do not:** bake into ECR image; commit `.env`.  
**Done when:** task definition has secrets from ARNs; `aws ecs execute-command` (or equivalent) env dump does not print secret values in CI logs.

---

## N5 — ECR image

**Depends on:** existing `gnoshbot-backend/Dockerfile`  
**Do:** repo in us-west-2. Build on CI (linux/arm64 **or** amd64; pick one and pin DuckDB native addon). Dockerfile already `INSTALL`s spatial at build — keep that so worker clock does not `INSTALL`.  
**Done when:** `docker pull` from us-west-2 succeeds; image `CMD` is `bun run src/index.ts` for API; separate tag `ingest` with `CMD bun run src/ingest/worker.ts` once B7 exists.

---

## N6 — Control-plane service (ECS Fargate)

**Depends on:** N2, N4, N5  
**Do:** Fargate in private subnets, us-west-2. CPU/mem modest (API is not DuckDB). ALB HTTPS. Idle timeout ≥ 60 s. Health: `GET /regions/zzzzz` 404 is ok **or** add `GET /health` in backend B1 (if adding `/health`, one GROK line in same PR). Desired count ≥ 2 prod.  
**Do not:** put DuckDB extract on this service’s request thread (backend B7).  
**Done when:** public POST `/regions/ensure` without key is 400 from the ALB target.

---

## N7 — Ingest worker compute

**Depends on:** N5, N2, backend B7  
**Do:** **Container** Lambda (10 GB image) **or** ECS task from SQS. Timeout ≤ 900 s Lambda max. Memory start 2048 MB, `/tmp` 512 MB+ (raise if spill). Same-region S3 GET to `overturemaps-us-west-2` (anonymous list ok; GET request charges apply; transfer $0 in-region). Task role: `s3:GetObject` on that bucket prefix `release/*` if signing; unsigned Overture is documented as anonymous.  
**Do not:** zip + `INSTALL spatial` on cold start as the production path.  
**Done when:** one 5-mile bbox job completes; CloudWatch duration &lt; 900 s; S3 access from us-west-2 only.

---

## N8 — Queue between API and ingest

**Depends on:** N6, N7  
**Do:** SQS in us-west-2. Message: `{ geohash5, release, min_lon, min_lat, max_lon, max_lat, idempotency_key }`. Visibility timeout ≥ expected DuckDB p95 + buffer. DLQ + alarm. API enqueue only.  
**Done when:** poison message lands on DLQ; tile `failed` on worker error (backend B7).

---

## N9 — Nightly purge + STAC watch

**Depends on:** N2, backend B14, B15  
**Do:** EventBridge cron quiet hours us-west-2 → run `bun run src/ingest/purge.ts` (Fargate scheduled task, not Siri). Separate weekly/daily STAC check → enqueue rollover tiles.  
**Done when:** EventBridge rules exist; one forced invoke deletes a fixture UNSUPPORTED POI in staging.

---

## N10 — APNs from control plane

**Depends on:** N4, backend B10, B11  
**Do:** store `.p8` in Secrets Manager. Send silent `region-ready:{geohash5}`. Production + sandbox keys separated.  
**Do not:** put user street addresses in the payload.  
**Done when:** staging device receives silent push after tile ready.

---

## N11 — Observability

**Depends on:** N6, N7  
**Do:** CloudWatch logs + metrics: ensure 200 vs 202 count, ingest duration, S3 GET count, tile failed. Alarm: ingest duration &gt; 600 s; failed tiles &gt; N/hour. Tracing optional.  
**Done when:** dashboard shows bbox jobs; no PII in logs (no line1).

---

## N12 — Networking / NAT

**Depends on:** N6, N7  
**Do:** private tasks, NAT for S3 if no S3 gateway; **prefer S3 gateway endpoint** in us-west-2 so Overture GETs do not hairpin NAT. Interface endpoints for ECR/Logs/Secrets.  
**Done when:** ingest works with `aws:SourceVpce` to S3; NAT data transfer for S3 is ~0.

---

## N13 — CI deploy

**Depends on:** N5, existing `.github/workflows/backend.yml`  
**Do:** on `main`: bun frozen lockfile, typecheck, `smoke:duckdb`, `smoke:http`, `bun test` when B16 exists, build/push ECR us-west-2, terraform apply staging auto, prod manual. OIDC to AWS.  
**Do not:** long-lived AWS keys in GitHub.  
**Done when:** PR CI green; staging deploy from main.

---

## N14 — Staging data policy

**Depends on:** N2  
**Do:** staging may ingest one small bbox (operator laptop city). Do not ingest the planet. Pin release.  
**Done when:** `restaurants` count is O(city), not tens of millions.

---

## N15 — Backup / restore

**Depends on:** N2  
**Do:** RDS automated backups ≥ 7 days prod. Restore drill once: new instance, migrate not required if snapshot includes schema.  
**Done when:** documented RPO/RTO; drill notes in `infra/`.

---

## N16 — Cost guards

**Depends on:** N7  
**Do:** budget alarm us-west-2. Ingest without bbox filter will explode S3 GET counts — alarm GET count vs tile. No provisioned Lambda concurrency for API “because Siri” (`PERFORMANCE_CONSIDERATIONS.md` §1.2).  
**Done when:** budget + GET-count alarm exist.

---

## N17 — Free public demo (TestFlight-shaped)

**Depends on:** existing `Dockerfile` + `docker-compose.yml`; iOS I0+ to actually upload TestFlight  
**Files:** `infra/demo/README.md`, `database/seed/demo.sql`, `gnoshbot-backend/docker-compose.demo.yml`  
**Do:** testers install via TestFlight (Apple hosts the app). Control plane is compose + seed tile `dr5rs`, `GNOSHBOT_ENV=demo` so DuckDB/Overture does not run. Public HTTPS via tunnel or a free VM, not N2/N6.  
**Do not:** apply RDS/ALB/NAT “for TestFlight”; ingest the planet; put demo wraps on the production live pool (P9/P13).  
**Done when:** `docker compose -f docker-compose.yml -f docker-compose.demo.yml up` serves the seeded tile; README lists TestFlight vs AWS.

---

## Progress (2026-08-31) — cheap vs expensive

`infra/` **implements the cheap shape**. It does **not** implement N2 RDS, N6 Fargate/ALB, N8 SQS, or N12 NAT. Those stay deferred until a Multi-AZ + idle-ALB bill is acceptable. GROK T01–T10 still win: ingest compute is us-west-2; HTTP does not DuckDB; no provisioned-concurrency Lambda for Siri.

| Atom | Cheap | Expensive path |
| --- | --- | --- |
| N0–N1 | **code** (`locals.region`, S3 state backend) | same |
| N2 PostGIS | **skipped** — Neon `aws-us-west-2` | RDS/Aurora |
| N3 migrations | **partial** — `scripts/apply-schema.sh` + `init.sql` on Neon direct URL. Versioned `database/migrations/` TBD | same gap |
| N4 secrets | **code** — SSM Standard | Secrets Manager optional later |
| N5 ECR | **code** — us-west-2 + lifecycle | same |
| N6 API | **skipped** — Lambda Function URL | ECS + ALB |
| N7 ingest | **code** — container Lambda 2048 MB / 900 s | or ECS from SQS |
| N8 queue | **skipped** — async `lambda:Invoke` | SQS + DLQ |
| N9 purge | **code** — EventBridge → `{action:purge}` | Fargate scheduled task |
| N10 APNs | TBD | `.p8` + backend B11 |
| N11 observability | TBD beyond 7-day log groups | dashboard + GET-count alarm |
| N12 NAT | **skipped** — Lambdas not in a VPC | S3 gateway + NAT |
| N13 CI deploy | TBD — GitHub is typecheck/smokes/`bun test` only | OIDC + ECR push + apply |
| N14 staging data | TBD — “one city bbox” is operator discipline | same |
| N15 backup | TBD — Neon restore drill | RDS 7-day |
| N16 budget | **code** — us-west-2, default $15 | same |
| N17 demo | **done locally** — compose + seed `dr5rs` | never AWS |

**Ops TBD:** `terraform apply` + `push-ecr.sh` on `gnoshbot-staging`; one bbox job &lt; 900 s; iOS base URL = Function URL. Do not apply N2/N6 “to go live.”

## Order

**Cheap (current):** N0 → N1 → Neon (not N2) → apply-schema → N4 SSM → N5 ECR → Function URL (not N6) → N7 ingest Lambda → async Invoke (not N8) → N9 EventBridge → N16. N17 in parallel. N10 / N11 / N13 / N14 / N15 still open.

**Expensive (deferred):** N2 → N6 → N8 → N12. Do not mix (no ALB in front of the Function URL).

**Local:** `gnoshbot-backend/docker-compose.yml` for B16. Demo overlay: `docker-compose.demo.yml`.
