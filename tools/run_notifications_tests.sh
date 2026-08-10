#!/usr/bin/env bash
# Tests des notifications et des jetons de push (Lot 9) sur un Postgres jetable.
# Applique le schéma, l'Arena (pour send_friend_request) et 0009, seede les
# badges, puis exécute les assertions de notifications_test.sql.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="krezus_notifications_test_$$"

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
# ranks_missions_badges crée la table ranks, dont dépendent 0005 et le
# déclencheur de passage de rang ; il seede aussi les badges du test 5.
run "$ROOT/supabase/seed/ranks_missions_badges.sql"
run "$ROOT/supabase/migrations/0005_academy.sql"
run "$ROOT/supabase/migrations/0007_arena.sql"
run "$ROOT/supabase/migrations/0009_notifications.sql"

echo "→ exécution des tests"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/notifications_test.sql" \
  | grep -E "T[0-9]+ OK|TOUS LES TESTS"

echo "✓ notifications : tests OK"
