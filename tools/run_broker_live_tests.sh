#!/usr/bin/env bash
# Teste le mode réel (0014) et la garde d'identité (0015) sur un Postgres
# jetable, sans stack Supabase.
#
# Contrairement aux autres runners, celui-ci applique TOUTES les migrations :
# 0015 renomme des fonctions créées par 0002 et 0014 s'appuie sur `securities`
# de 0001. C'est aussi le seul runner qui applique 0003_rls — la garde
# d'identité n'a de sens qu'avec les rôles Supabase présents.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="krezus_broker_test_$$"

# Localise psql (brew keg-only postgresql@16 non lié dans le PATH)
for p in /opt/homebrew/opt/postgresql@16/bin /opt/homebrew/bin /usr/local/bin; do
  [ -x "$p/psql" ] && export PATH="$p:$PATH" && break
done
command -v psql >/dev/null || { echo "psql introuvable"; exit 1; }

cleanup() { dropdb --if-exists "$DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "→ création de la base $DB"
createdb "$DB"

run() { psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$1"; }

echo "→ stub auth + migrations 0001 → 0015"
run "$ROOT/supabase/tests/00_auth_stub.sql"
for f in "$ROOT"/supabase/migrations/00*.sql; do
  run "$f"
done

# Le trigger on_auth_user_created crée le profil, qui déclenche la mission
# « activate » : sans ce seed, la simple création d'un utilisateur de test
# échoue sur KR022.
echo "→ seed rangs / missions / badges"
run "$ROOT/supabase/seed/ranks_missions_badges.sql"

echo "→ exécution des tests"
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/broker_live_test.sql" \
  | grep -E "T[0-9]+ OK|TOUS LES TESTS"

echo "✓ mode réel + garde d'identité : tests OK"
