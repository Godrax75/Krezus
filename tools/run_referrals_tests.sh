#!/usr/bin/env bash
# Tests du parrainage et des droits d'exécution (0019) sur un Postgres jetable.
# Applique le schéma, l'Academy (award_xp), l'Arena, les notifications et
# 0019, seede les badges, puis exécute les assertions de referrals_test.sql.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="krezus_referrals_test_$$"

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

echo "→ stub auth + schéma"
run "$ROOT/supabase/tests/00_auth_stub.sql"
run "$ROOT/supabase/migrations/0001_init.sql"
run "$ROOT/supabase/migrations/0002_paper_engine.sql"
run "$ROOT/supabase/migrations/0004_market_data.sql"
# 0005 crée la table ranks ; le seed ne fait qu'y écrire les rangs et les
# badges, dont award_xp a besoin au passage de rang.
run "$ROOT/supabase/migrations/0005_academy.sql"
run "$ROOT/supabase/seed/ranks_missions_badges.sql"
run "$ROOT/supabase/migrations/0007_arena.sql"
run "$ROOT/supabase/migrations/0009_notifications.sql"
run "$ROOT/supabase/migrations/0019_referrals.sql"

echo "→ exécution des tests"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/referrals_test.sql" \
  | grep -E "T[0-9]+ OK|TOUS LES TESTS"

echo "✓ parrainage : tests OK"
