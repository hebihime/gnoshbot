# Remote state lives in us-west-2 only. Bucket and lock table are created by
# infra/bootstrap (local state) once, then this backend is used.
# Init: terraform init -backend-config=backend/staging.hcl
# Partial config so staging vs prod can share the bucket with different keys
# without baking a profile name into git.

terraform {
  backend "s3" {
    encrypt = true
  }
}
