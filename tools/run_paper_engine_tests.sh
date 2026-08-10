#!/usr/bin/env bash
# Teste le moteur d'ordres papier sur un Postgres jetable, sans stack Supabase.
# Crée une base temporaire, applique le stub auth + le schéma + le moteur, seede,
# puis exécute les assertions de paper_engine_test.sql.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="krezus_paper_test_$$"

# Localise psql/createdb (brew keg-only postgresql@16 non lié dans le PATH)
for p in /opt/homebrew/opt/postgresql@16/bin /opt/homebrew/bin /usr/local/bin; do
  [ -x "$p/psql" ] && export PATH="$p:$PATH" && break
done
command -v psql >/dev/null || { echo "psql introuvable"; exit 1; }

cleanup() { dropdb --if-exists "$DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "→ création de la base $DB"
createdb "$DB"

run() { psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$1"; }

echo "→ stub auth + schéma + moteur"
run "$ROOT/supabase/tests/00_auth_stub.sql"
run "$ROOT/supabase/migrations/0001_init.sql"
run "$ROOT/supabase/migrations/0002_paper_engine.sql"
# 0003_rls dépend d'un rôle authentifié Supabase : hors périmètre de ce test unitaire.

echo "→ exécution des tests"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/paper_engine_test.sql" \
  | grep -E "T[0-9] OK|TOUS LES TESTS"

echo "✓ moteur d'ordres papier : tests OK"
