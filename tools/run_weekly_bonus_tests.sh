#!/usr/bin/env bash
# Tests du versement hebdomadaire et du pseudo (0021).
# Versements, performance hors apports, pseudo unique — sur un Postgres jetable.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="krezus_weekly_bonus_test_$$"

for p in /opt/homebrew/opt/postgresql@16/bin /opt/homebrew/bin /usr/local/bin; do
  [ -x "$p/psql" ] && export PATH="$p:$PATH" && break
done
command -v psql >/dev/null || { echo "psql introuvable"; exit 1; }

cleanup() { dropdb --if-exists "$DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

createdb "$DB"
run() { psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$1" >/dev/null; }

echo "→ schéma"
run "$ROOT/supabase/tests/00_auth_stub.sql"
psql -q -d "$DB" -c "create extension if not exists pgcrypto" >/dev/null
for m in 0001_init 0002_paper_engine 0004_market_data 0005_academy; do
  run "$ROOT/supabase/migrations/$m.sql"
done
run "$ROOT/supabase/seed/ranks_missions_badges.sql"
for m in 0006_oracle 0007_arena 0008_hercule 0009_notifications 0015_paper_identity_guard \
         0017_portfolio_history 0019_referrals 0020_arena_search_leaderboard 0021_weekly_bonus_identity; do
  run "$ROOT/supabase/migrations/$m.sql"
done

echo "→ exécution des tests"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/weekly_bonus_test.sql" 2>&1 \
  | grep -E "T[0-9]+ OK|TOUS LES TESTS|ERROR"

echo "✓ versement hebdomadaire et pseudo : tests OK"
