#!/usr/bin/env bash
# Applies backend/migrations/*.sql in lexical order against $PG* / $DATABASE_URL.
# Set HUBBLE_SKIP_AUTH_SHIM=1 when targeting a real Supabase database.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mig_dir="$here/../migrations"
psql_args=(-v ON_ERROR_STOP=1 -q)
if [ -n "${DATABASE_URL:-}" ]; then psql_args+=("$DATABASE_URL"); fi

if [ "${HUBBLE_SKIP_AUTH_SHIM:-0}" != "1" ]; then
  echo "== auth shim"
  psql "${psql_args[@]}" -f "$here/local_auth_shim.sql"
fi

for f in "$mig_dir"/*.sql; do
  echo "== $(basename "$f")"
  psql "${psql_args[@]}" -f "$f"
done
echo "== migrations applied"
