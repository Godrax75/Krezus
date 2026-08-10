-- =====================================================================
-- Correctif — récursion infinie dans la RLS des groupes Arena.
--
-- La policy de lecture de `arena_group_members` interrogeait
-- `arena_group_members` pour savoir si l'utilisateur est membre du groupe.
-- Cette sous-requête redéclenche la policy, qui redéclenche la sous-requête :
--
--   42P17  infinite recursion detected in policy for relation
--          "arena_group_members"
--
-- Conséquence : toute lecture des groupes échouait en HTTP 500, donc l'onglet
-- Groupes de l'Arena était inutilisable. Le défaut ne pouvait pas se voir dans
-- les tests SQL (`supabase/tests/arena_test.sql`), qui tournent en `postgres`,
-- un rôle qui contourne la RLS. Il fallait une vraie requête PostgREST
-- authentifiée pour le déclencher.
--
-- Le correctif est le motif déjà employé par `are_friends` dans 0007 : passer
-- par une fonction `security definer`, qui lit la table sans réévaluer sa
-- policy et coupe donc la récursion.
-- =====================================================================

create or replace function public.is_group_member(p_group uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.arena_group_members m
    where m.group_id = p_group and m.user_id = p_user
  );
$$;

comment on function public.is_group_member is
  'Appartenance à un groupe, en security definer pour être appelable depuis '
  'une policy sur arena_group_members sans récursion (42P17).';

-- Deux membres partagent-ils un groupe ? Sert au feed, qui joignait
-- `arena_group_members` à elle-même depuis une policy sur `arena_feed` : la
-- lecture y était filtrée par la RLS de la table jointe, ce qui rendait le
-- résultat dépendant de l'ordre d'évaluation.
create or replace function public.shares_group(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.arena_group_members mine
    join public.arena_group_members theirs on theirs.group_id = mine.group_id
    where mine.user_id = p_a and theirs.user_id = p_b
  );
$$;

drop policy if exists "group members visible to members" on public.arena_group_members;
create policy "group members visible to members" on public.arena_group_members
  for select to authenticated
  using (public.is_group_member(group_id, auth.uid()));

drop policy if exists "groups visible to members" on public.arena_groups;
create policy "groups visible to members" on public.arena_groups
  for select to authenticated
  using (public.is_group_member(id, auth.uid()));

drop policy if exists "feed readable by friends" on public.arena_feed;
create policy "feed readable by friends" on public.arena_feed
  for select to authenticated
  using (
    actor_id = auth.uid()
    or public.are_friends(auth.uid(), actor_id)
    or public.shares_group(auth.uid(), actor_id)
  );
