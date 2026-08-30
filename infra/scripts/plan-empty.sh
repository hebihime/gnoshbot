#!/usr/bin/env bash
# Region-pin only (N0/N1). Cheap compute is plan-cheap.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
cat > backend_override.tf <<'EOF'
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
terraform init -reconfigure -input=false
terraform plan -input=false -target=terraform_data.region_pin \
  -var='manage_neon=false' \
  -var='neon_pooled_database_url=postgresql://placeholder:placeholder@127.0.0.1/gnoshbot?sslmode=require'
