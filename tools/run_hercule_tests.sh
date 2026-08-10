#!/usr/bin/env bash
# Tests du Lot 8 — Hercule.
#   1. prompt et contexte (Deno, fixtures, aucun appel réseau)
#   2. quota, abonnement et contexte SQL (Postgres jetable)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="krezus_hercule_test_$$"

command -v deno >/dev/null || { echo "deno introuvable (brew install deno)"; exit 1; }
echo "→ prompt et contexte (fixtures)"
deno test --quiet --allow-read "$ROOT/supabase/functions/tests/hercule_test.ts"

for p in /opt/homebrew/opt/postgresql@16/bin /opt/homebrew/bin /usr/local/bin; do
  [ -x "$p/psql" ] && export PATH="$p:$PATH" && break
done
command -v psql >/dev/null || { echo "psql introuvable"; exit 1; }
pg_isready -q || { echo "postgres arrêté (brew services start postgresql@16)"; exit 1; }

cleanup() { dropdb --if-exists "$DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "→ création de la base $DB"
createdb "$DB"

run() { psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$1"; }

echo "→ stub auth + schéma + moteurs"
run "$ROOT/supabase/tests/00_auth_stub.sql"
run "$ROOT/supabase/migrations/0001_init.sql"
run "$ROOT/supabase/migrations/0002_paper_engine.sql"
run "$ROOT/supabase/migrations/0004_market_data.sql"
run "$ROOT/supabase/seed/ranks_missions_badges.sql"
run "$ROOT/supabase/migrations/0005_academy.sql"
run "$ROOT/supabase/migrations/0006_oracle.sql"
run "$ROOT/supabase/migrations/0007_arena.sql"
run "$ROOT/supabase/migrations/0008_hercule.sql"

echo "→ exécution des tests"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/hercule_test.sql" \
  | grep -E "T[0-9]+ OK|TOUS LES TESTS"

echo "✓ Hercule : tests OK"
