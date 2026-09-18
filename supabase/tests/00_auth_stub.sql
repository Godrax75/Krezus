-- Stub minimal du schéma `auth` de Supabase, pour exécuter les migrations et
-- tester le moteur d'ordres sur un Postgres nu (hors stack Supabase).
-- NE PAS appliquer en production : Supabase fournit déjà `auth.users` et `auth.uid()`.

-- Rôles fournis par Supabase en production ; recréés ici pour que 0003_rls.sql
-- (policies `to authenticated`) s'applique sur un Postgres nu.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  created_at timestamptz not null default now()   -- comme chez Supabase
);

-- `auth.uid()` renvoie l'utilisateur courant. En test, on le pilote via un GUC.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('test.current_user', true), '')::uuid;
$$;
