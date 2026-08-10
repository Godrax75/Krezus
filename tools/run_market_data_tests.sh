#!/usr/bin/env bash
# Tests du Lot 3 — données de marché.
#   1. adaptateur EODHD (Deno, fixtures enregistrées, aucun appel réseau)
#   2. conversion de devise en base (Postgres jetable)
# Les deux moitiés se vérifient séparément : le parsing chez le fournisseur,
# l'invariant monétaire dans le schéma.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="krezus_market_data_test_$$"

# ---- 1. Adaptateur EODHD -------------------------------------------------
command -v deno >/dev/null || { echo "deno introuvable (brew install deno)"; exit 1; }
echo "→ adaptateur EODHD (fixtures)"
deno test --quiet --allow-read "$ROOT/supabase/functions/tests/"
echo "→ typecheck des Edge Functions"
deno check --quiet "$ROOT/supabase/functions/quotes/index.ts" "$ROOT/supabase/functions/history/index.ts"

# ---- 2. Conversion de devise en base -------------------------------------
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

echo "→ stub auth + schéma + moteur + données de marché"
run "$ROOT/supabase/tests/00_auth_stub.sql"
run "$ROOT/supabase/migrations/0001_init.sql"
run "$ROOT/supabase/migrations/0002_paper_engine.sql"
run "$ROOT/supabase/migrations/0004_market_data.sql"
# 0003_rls dépend d'un rôle authentifié Supabase : hors périmètre unitaire.

echo "→ exécution des tests de conversion"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/market_data_test.sql" \
  | grep -E "T[0-9] OK|TOUS LES TESTS"

echo "✓ données de marché : tests OK"
