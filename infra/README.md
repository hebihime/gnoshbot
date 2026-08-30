# Gnoshbot AWS infrastructure

Control-plane and Overture ingest run in **us-west-2** only. The catalog is `s3://overturemaps-us-west-2` ([Overture cloud sources](https://docs.overturemaps.org/getting-data/cloud-sources/)). Same-region S3 → AWS service transfer is $0; GET request charges still apply. Cross-region reads are a bill, not a strategy (`GROK.md` T01–T05, T04, T10; `ARCHITECTURE.md` §10; `SCALABILITY.md` S1–S8).

This plane is not on the Siri path. Do not provision Lambda concurrency “for Siri.” Do not put DuckDB on the API request thread. Do not ingest the planet.

## Environments

| AWS CLI profile     | Workspace | Purpose                                      |
| ------------------- | --------- | -------------------------------------------- |
| `gnoshbot-staging`  | `staging` | Single-AZ RDS, one city bbox later (N14)     |
| `gnoshbot-prod`     | `prod`    | Multi-AZ RDS, desired count ≥ 2 (N6)         |

Dedicated account per env is preferred. Until then, these named profiles are the deploy roles. Both **must** use region `us-west-2`.

```bash
aws configure get region --profile gnoshbot-staging   # us-west-2
aws configure get region --profile gnoshbot-prod      # us-west-2
```

Pin for Terraform: `locals.region` in `locals.tf`. Do not set `AWS_REGION` / `AWS_DEFAULT_REGION` to another region when using these profiles.

## Overture

- Bucket: `overturemaps-us-west-2`
- Places: `s3://overturemaps-us-west-2/release/<RELEASE>/theme=places/type=place/*.parquet`
- Worked release pin: `2026-08-19.0` until STAC watch (N9 / backend B15)
- We do **not** own the bucket, so we cannot attach a bucket policy. Constrain **our** principals with `policies/deny-compute-outside-us-west-2.json` (permission boundary / SCP-style deny). Prefer an S3 gateway endpoint in us-west-2 (N12) so in-region GET does not hairpin NAT.

## Secrets

`DATABASE_URL`, `SKIP_LOG_HMAC_SECRET`, `MENU_WRAP_KEY_HEX`, APNs `.p8` live in Secrets Manager or SSM SecureString (N4). They are never baked into the ECR image.

## Status

| Atom | State |
| ---- | ----- |
| N0 region pin | this directory + CLI profiles |
| N1+ | not applied; Terraform root is the next atom |
