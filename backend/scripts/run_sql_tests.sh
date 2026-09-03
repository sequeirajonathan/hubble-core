#!/usr/bin/env bash
# Runs the behavioural SQL tests in backend/tests against an already-migrated db.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
psql_args=(-v ON_ERROR_STOP=1 -q)
if [ -n "${DATABASE_URL:-}" ]; then psql_args+=("$DATABASE_URL"); fi
for f in "$here"/../tests/*.sql; do
  echo "== $(basename "$f")"
  psql "${psql_args[@]}" -f "$f"
done
echo "== sql tests passed"
