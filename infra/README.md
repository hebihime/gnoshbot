# Gnoshbot AWS infrastructure — cheap shape

Control-plane HTTP and Overture ingest run in **us-west-2** only. The catalog is `s3://overturemaps-us-west-2` (`GROK.md` T01–T05, T10). Same-region S3 → Lambda transfer is $0; **GET request charges still apply**. Cross-region reads are a bill. DuckDB never runs on the HTTP Function URL.

This plane is not on the Siri path. **Do not** add provisioned-concurrency Lambda, NAT Gateway, ALB, RDS, or SQS. Those are the expensive N2/N6/N8 path in `plans/infrastructure.md` and are **not** this stack.

Terraform only. Do not add CDK.

## What “free” means (hobby-scale)

This is **not** an AWS/Neon free-tier product guarantee. It is cheap enough for a few cities and bbox jobs:

| Piece | Why it stays small | How it leaks |
| ----- | ------------------ | ------------ |
| Neon Postgres+PostGIS `aws-us-west-2` | Suspends, 0.25–2 CU, pooled URL in `DATABASE_URL` | Compute-hours if tiles never go idle; storage if you ingest more than a city |
| API Lambda 512 MB, 30 s, Function URL | No ALB, no NAT, no provisioned concurrency | CloudWatch Logs (retention 7 days on purpose) |
| Ingest Lambda 2048 MB, 900 s, container image | Bbox predicates only; never scan `theme=places` | Duration + S3 GET counts; `/tmp` spill |
| EventBridge `cron(0 9 * * ? *)` UTC | Calls ingest with `{ "action": "purge" }` → `purge_stale_unsupported_pois` | Negligible |
| ECR | One repo, lifecycle expires untagged | **Image storage is a leak** if you push every CI run and never expire |
| SSM Standard SecureString | Not Secrets Manager | Free at this scale |
| S3 Overture | In-region GET | GET **requests** are billed even when transfer is $0 |

Do not ingest the planet. Pin `OVERTURE_RELEASE`. One 5-mile bbox per saved address, not a theme glob.

TestFlight without AWS: `infra/demo/README.md` (seeded compose, ingest off).

## Backend contract

Public origin is the **Function URL** (terraform output `api_function_url`), e.g. `https://<url-id>.lambda-url.us-west-2.on.aws/`. No hostname on an ALB.

Env injected on both functions (SSM Standard → Lambda environment at deploy):

| Name | Value |
| ---- | ----- |
| `DATABASE_URL` | Neon **pooled** connection string (`sslmode=require`, `*.neon.tech`) |
| `AWS_REGION` | Set by Lambda to `us-west-2` (function is pinned there; production boot rejects anything else) |
| `SKIP_LOG_HMAC_SECRET` | SSM SecureString |
| `MENU_WRAP_KEY_HEX` | 32-byte hex, SSM SecureString |
| `OVERTURE_RELEASE` | default `2026-08-19.0` |
| `NODE_ENV` / `GNOSHBOT_ENV` | `production` |
| `INGEST_LAMBDA_FUNCTION_NAME` | **API only** — ingest function name |

`POST /regions/ensure` returns 202 after an **async** `lambda:Invoke` (`InvocationType=Event`). Payload:

```json
{
  "geohash5": "dr5re",
  "release": "2026-08-19.0",
  "bbox": {
    "min_lon": -74.08,
    "min_lat": 40.68,
    "max_lon": -73.93,
    "max_lat": 40.79
  },
  "idempotency_key": "opaqueUser:dr5re:2026-08-19.0"
}
```

The worker also accepts flat `min_lon`… fields. Purge is `{ "action": "purge" }` from EventBridge, not this payload.

Image CMDs (same ECR image, DuckDB preinstalled at build):

- API: `bun run src/lambda-http.ts`
- Ingest: `bun run src/ingest/worker.ts`

## Environments

| AWS CLI profile    | Workspace | Purpose |
| ------------------ | --------- | ------- |
| `gnoshbot-staging` | `staging` | Hobby Neon + Lambdas, one city bbox |
| `gnoshbot-prod`    | `prod`    | Same shape; still no RDS/ALB/NAT |
| *(none)*           | **demo**  | TestFlight + seeded compose; **not** AWS. See `demo/README.md` |

```bash
aws configure get region --profile gnoshbot-staging   # us-west-2
aws configure get region --profile gnoshbot-prod      # us-west-2
```

Pin: `locals.region` and `provider "aws" { region = local.region }`. The operator default profile on this machine is `us-east-1`; never apply Gnoshbot with that profile.

## Apply order

```bash
# 1. State bucket (once). infra/bootstrap
AWS_PROFILE=gnoshbot-staging terraform -chdir=infra/bootstrap apply

# 2. Cheap stack. Neon API key creates PostGIS in aws-us-west-2 and applies database/init.sql
#    on the *direct* URL. DATABASE_URL in SSM is the *pooled* URL.
cd infra
AWS_PROFILE=gnoshbot-staging terraform init -backend-config=backend/staging.hcl
AWS_PROFILE=gnoshbot-staging terraform workspace select staging
AWS_PROFILE=gnoshbot-staging terraform apply \
  -var="neon_api_key=$NEON_API_KEY"

# 3. Push the Bun+DuckDB image, then apply again so Lambda can pull :latest
AWS_PROFILE=gnoshbot-staging ./scripts/push-ecr.sh
AWS_PROFILE=gnoshbot-staging terraform apply -var="neon_api_key=$NEON_API_KEY"
```

If you created Neon in the console instead of Terraform: `-var='manage_neon=false'` and `-var='neon_pooled_database_url=...'`, then `DATABASE_URL=<direct-non-pooler> ./scripts/apply-schema.sh`.

Local region-pin proof (no Neon, no Lambdas in the target):

```bash
cd infra
./scripts/plan-empty.sh    # terraform_data.region_pin only
./scripts/plan-cheap.sh    # full cheap graph; needs AWS creds
```

Attach `policies/deny-compute-outside-us-west-2.json` as a permission boundary or SCP on the deploy roles.

## Overture

- Bucket: `overturemaps-us-west-2`
- Places: `s3://overturemaps-us-west-2/release/<RELEASE>/theme=places/type=place/*.parquet`
- Worked release pin: `2026-08-19.0`
- We do **not** own the bucket. Constrain **our** principals with the deny policy. No NAT: Lambdas are not in a VPC.

## Status

| Atom | Cheap shape |
| ---- | ----------- |
| N0 region pin | `locals.region` = us-west-2 |
| N1 Terraform | S3 state in us-west-2 |
| N2 RDS | **Skipped** — Neon `aws-us-west-2` |
| N4 secrets | SSM Standard, not Secrets Manager |
| N5 ECR | us-west-2, lifecycle policy |
| N6 ECS/ALB | **Skipped** — Function URL |
| N7 ingest | Container Lambda 2048 MB / 900 s |
| N8 SQS | **Skipped** — async Invoke |
| N9 purge | EventBridge → ingest `{action: purge}` |
| N12 NAT | **Skipped** — no VPC |
| N16 budget | us-west-2 $15 default |
| N17 demo | `demo/` compose; independent |
| N3 versioned migrations | TBD (`apply-schema.sh` is one-shot `init.sql`) |
| N10 APNs | TBD |
| N11 dashboard / GET-count alarm | TBD (log groups exist) |
| N13 OIDC deploy | TBD |
| N14 one-city cap | TBD (operator discipline) |
| N15 Neon restore drill | TBD |
| Apply + ECR push | **ops TBD** — Terraform is in tree; live Function URL not assumed |
