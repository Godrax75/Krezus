#!/usr/bin/env bash
# Teste les privilèges colonne sur `profiles` (0017) sur un Postgres jetable.
#
# La suite est jouée DEUX FOIS, parce que 0017 doit tenir dans les deux cas :
#   • sans `avatar_updated_at` — une base recréée de zéro avant 0016_avatars ;
#   • avec — la production, où 0016 est déjà appliqué.
# C'est le bloc `do $$` conditionnel de 0017 qui est vérifié ici.
#
# Chaque passe : stub auth + schéma complet, grants par défaut Supabase,
# puis 0017, puis les assertions. On vérifie deux choses à la fois — le client
# ne peut plus s'offrir Premium, et les fonctions security definer écrivent
# toujours xp / rank_level / premium_until / streak.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Localise psql/createdb (brew keg-only postgresql@16 non lié dans le PATH)
for p in /opt/homebrew/opt/postgresql@16/bin /opt/homebrew/bin /usr/local/bin; do
  [ -x "$p/psql" ] && export PATH="$p:$PATH" && break
done
command -v psql >/dev/null || { echo "psql introuvable"; exit 1; }

DBS=()
cleanup() { for d in "${DBS[@]:-}"; do [ -n "$d" ] && dropdb --if-exists "$d" >/dev/null 2>&1 || true; done; }
trap cleanup EXIT

# $1 = suffixe de base, $2 = "avec" | "sans" (colonne avatar_updated_at)
one_pass() {
  local DB="krezus_profile_priv_$1_$$" avatars="$2"
  DBS+=("$DB")
  echo
  echo "════ passe « $avatars avatar_updated_at » ════"
  createdb "$DB"

  psql_run() { psql -v ON_ERROR_STOP=1 -q -d "$DB" -f "$1"; }

  echo "→ stub auth + schéma complet"
  psql_run "$ROOT/supabase/tests/00_auth_stub.sql"
  local f
  for f in "$ROOT"/supabase/migrations/[0-9]*.sql; do
    case "$f" in *0017_profile_column_privileges.sql) continue;; esac
    psql_run "$f"
  done
  psql_run "$ROOT/supabase/seed/ranks_missions_badges.sql"

  # Reproduit l'environnement Supabase : `authenticated` reçoit `grant all` sur
  # les tables du schéma public et peut appeler auth.uid(). Sans ces grants, la
  # faille que 0017 ferme n'existerait pas sur cette base et le test ne
  # prouverait rien.
  echo "→ grants par défaut Supabase"
  psql -v ON_ERROR_STOP=1 -q -d "$DB" <<'EOSQL'
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
grant all on all sequences in schema public to anon, authenticated;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
EOSQL

  # 0016_avatars.sql n'est pas dans ce dépôt ; on en simule la seule colonne
  # qui nous concerne pour éprouver la branche conditionnelle de 0017.
  if [ "$avatars" = "avec" ]; then
    echo "→ simulation de 0016_avatars.sql (colonne avatar_updated_at)"
    psql -v ON_ERROR_STOP=1 -q -d "$DB" -c \
      "alter table public.profiles add column avatar_updated_at timestamptz;
       grant all on public.profiles to anon, authenticated;"
  fi

  echo "→ migration 0017"
  psql_run "$ROOT/supabase/migrations/0017_profile_column_privileges.sql"

  echo "→ droits résiduels de authenticated sur profiles"
  psql -At -d "$DB" -c "
    select '   table  : '||string_agg(privilege_type, ', ' order by privilege_type)
      from information_schema.table_privileges
     where table_name='profiles' and grantee='authenticated'
    union all
    select '   update : '||string_agg(column_name, ', ' order by column_name)
      from information_schema.column_privileges
     where table_name='profiles' and grantee='authenticated' and privilege_type='UPDATE';"

  echo "→ exécution des tests"
  psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/profile_privileges_test.sql" \
    | grep -E "T[0-9]+b? (OK|—)|TOUS LES TESTS"
}

one_pass sans sans
one_pass avec avec

echo
echo "✓ privilèges colonne sur profiles : tests OK (deux passes)"
