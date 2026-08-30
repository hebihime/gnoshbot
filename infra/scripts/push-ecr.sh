#!/usr/bin/env bash
# Build linux/amd64 (DuckDB native addon) and push to ECR us-west-2.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/infra"
REPO="$(terraform output -raw ecr_repository_url)"
REGION="$(terraform output -raw region)"
TAG="${IMAGE_TAG:-latest}"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${REPO%%/*}"
docker build --platform linux/amd64 -t "${REPO}:${TAG}" "$ROOT/gnoshbot-backend"
docker push "${REPO}:${TAG}"
