#!/usr/bin/env bash
# Apply database/init.sql on the Neon *direct* (non-pooler) URL.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "Set DATABASE_URL to the Neon direct connection string (not the -pooler host)." >&2
  exit 1
fi
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$ROOT/database/init.sql"
echo "applied database/init.sql"
