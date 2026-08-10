#!/usr/bin/env bash
# Tests de l'Arena (Lot 7) sur un Postgres jetable.
# Couvre les invariants de confidentialité (classement et feed sans montants),
# le cycle des demandes d'ami et les groupes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="krezus_arena_test_$$"

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

echo "→ exécution des tests"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/arena_test.sql" \
  | grep -E "T[0-9]+ OK|TOUS LES TESTS"

echo "✓ Arena : tests OK"
