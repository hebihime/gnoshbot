#!/usr/bin/env bash
# Cheap-shape plan against local state. Does not create RDS, ALB, NAT, or SQS.
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
terraform plan -input=false \
  -var='manage_neon=false' \
  -var='neon_pooled_database_url=postgresql://placeholder:placeholder@127.0.0.1/gnoshbot?sslmode=require'
