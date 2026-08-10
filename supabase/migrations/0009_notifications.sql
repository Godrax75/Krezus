-- =====================================================================
-- Lot 9 — notifications, jetons de push et suppression de compte.
--
-- Deux principes tiennent ce fichier :
--
-- 1. Une notification est **produite par la base**, au moment où le fait
--    survient (ordre exécuté, rang franchi, demande d'ami). La produire côté
--    client la rendrait dépendante de l'app ouverte, et un ordre passé depuis
--    un autre appareil ne notifierait jamais.
--
-- 2. Le contenu est écrit ici, en français, et non calculé à l'affichage : le
--    push part du serveur, il doit donc porter son propre texte.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Jetons d'appareil (APNs)
-- ---------------------------------------------------------------------

create table if not exists public.device_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  platform    text not null default 'ios' check (platform in ('ios', 'android')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Un utilisateur ne voit et ne supprime que ses propres jetons. L'écriture
-- passe par la fonction ci-dessous, jamais par un insert direct.
drop policy if exists "own device tokens" on public.device_tokens;
create policy "own device tokens" on public.device_tokens
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "delete own device tokens" on public.device_tokens;
create policy "delete own device tokens" on public.device_tokens
  for delete to authenticated using (user_id = auth.uid());

-- APNs réattribue un jeton quand un appareil change de main ou que l'app est
-- réinstallée sur un autre compte. Un simple `insert ... on conflict` côté
-- client échouerait alors sur la RLS de la ligne d'autrui : la reprise doit
-- se faire en `security definer`.
create or replace function public.upsert_device_token(
  p_user_id uuid,
  p_token   text,
  p_platform text default 'ios'
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null or coalesce(p_token, '') = '' then
    raise exception 'Paramètre invalide' using errcode = 'KR010';
  end if;

  -- `security definer` contourne la RLS : sans ce garde-fou, n'importe quel
  -- compte connecté pourrait rattacher son appareil au compte d'un autre et
  -- recevoir ses notifications. La condition sur `auth.uid()` non nul laisse
  -- passer les tests sur Postgres nu, où il n'y a pas de session.
  if auth.uid() is not null and p_user_id <> auth.uid() then
    raise exception 'Jeton refusé pour un autre compte' using errcode = 'KR010';
  end if;

  insert into public.device_tokens (token, user_id, platform)
  values (p_token, p_user_id, p_platform)
  on conflict (token) do update
    set user_id    = excluded.user_id,
        platform   = excluded.platform,
        updated_at = now();
end;
$$;

create or replace function public.delete_device_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.device_tokens where token = p_token;
$$;

-- ---------------------------------------------------------------------
-- Écriture des notifications
-- ---------------------------------------------------------------------

-- Les `kind` reconnus par le client (`KrezusNotification.Kind`). Un type
-- inconnu serait ignoré à l'affichage : la contrainte le refuse d'entrée.
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('order', 'rank_up', 'badge', 'friend_request',
                  'lesson_reminder', 'market', 'hercule'));

create or replace function public.notify(
  p_user_id uuid,
  p_kind    text,
  p_title   text,
  p_body    text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.notifications (user_id, kind, title, body)
  values (p_user_id, p_kind, p_title, p_body)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Déclencheurs métier
-- ---------------------------------------------------------------------

-- Ordre exécuté. Les ordres rejetés ne notifient pas : l'erreur est déjà
-- rendue à l'écran par le code SQLSTATE, la répéter en notification serait
-- doublement pénible.
create or replace function public.notify_on_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
  v_name text;
begin
  if new.status <> 'filled' then
    return new;
  end if;

  select user_id into v_user from public.portfolios where id = new.portfolio_id;
  select name into v_name from public.securities where symbol = new.symbol;

  perform public.notify(
    v_user,
    'order',
    case when new.side = 'buy' then 'Achat exécuté · ' else 'Vente exécutée · ' end
      || coalesce(v_name, new.symbol),
    to_char(new.amount_cents / 100.0, 'FM999G999D00') || ' € · '
      || to_char(new.quantity, 'FM999G990D0999') || ' action(s) au portefeuille virtuel');

  return new;
end;
$$;

drop trigger if exists notify_order on public.orders;
create trigger notify_order
  after insert on public.orders
  for each row execute function public.notify_on_order();

-- Passage de rang. On lit le libellé dans `public.ranks` plutôt que de le
-- coder ici : les six paliers y sont déjà seedés.
create or replace function public.notify_on_rank_up()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_next text;
  v_next_xp integer;
begin
  if new.rank_level <= old.rank_level then
    return new;
  end if;

  select name_fr into v_name from public.ranks where level = new.rank_level;
  select name_fr, min_xp into v_next, v_next_xp
    from public.ranks where level = new.rank_level + 1;

  perform public.notify(
    new.id,
    'rank_up',
    'Tu passes ' || coalesce(v_name, 'au rang ' || new.rank_level),
    case
      when v_next is null then 'Rang maximal atteint. Il n''y a plus haut que toi.'
      else 'Prochain palier : ' || v_next || ' à ' || v_next_xp || ' XP.'
    end);

  return new;
end;
$$;

drop trigger if exists notify_rank_up on public.profiles;
create trigger notify_rank_up
  after update of rank_level on public.profiles
  for each row execute function public.notify_on_rank_up();

-- Badge obtenu.
create or replace function public.notify_on_badge()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
begin
  select title_fr into v_title from public.badges where id = new.badge_id;

  perform public.notify(
    new.user_id,
    'badge',
    'Nouveau badge · ' || coalesce(v_title, 'récompense'),
    'Retrouve-le sur ton profil.');

  return new;
end;
$$;

drop trigger if exists notify_badge on public.user_badges;
create trigger notify_badge
  after insert on public.user_badges
  for each row execute function public.notify_on_badge();

-- Demande d'ami reçue. On notifie le destinataire, pas l'émetteur, et
-- uniquement à la création : l'acceptation passe par `accept_friend_request`.
create or replace function public.notify_on_friend_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_username text;
begin
  if new.status <> 'pending' then
    return new;
  end if;

  select username into v_username from public.profiles where id = new.user_id;

  perform public.notify(
    new.friend_id,
    'friend_request',
    coalesce(v_username, 'Un investisseur') || ' veut rejoindre ton Arena',
    'Accepte ou ignore la demande depuis l''onglet Arena.');

  return new;
end;
$$;

drop trigger if exists notify_friend_request on public.friendships;
create trigger notify_friend_request
  after insert on public.friendships
  for each row execute function public.notify_on_friend_request();

-- ---------------------------------------------------------------------
-- Suppression de compte
-- ---------------------------------------------------------------------

-- Guideline App Store 5.1.1(v) et droit à l'effacement du RGPD : la
-- suppression doit être faisable depuis l'app, sans passer par le support.
--
-- Supprimer la ligne `auth.users` suffit : tout le schéma applicatif y est
-- rattaché en `on delete cascade`. Détruire les tables une à une ici
-- laisserait fatalement de côté celles ajoutées plus tard.
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Aucune session' using errcode = 'KR010';
  end if;

  delete from auth.users where id = v_user;
end;
$$;

revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;

revoke all on function public.upsert_device_token(uuid, text, text) from public;
grant execute on function public.upsert_device_token(uuid, text, text) to authenticated;

revoke all on function public.delete_device_token(text) from public;
grant execute on function public.delete_device_token(text) to authenticated;

-- `notify` est un utilitaire serveur : personne ne doit pouvoir se fabriquer
-- une notification, encore moins en fabriquer une à autrui.
revoke all on function public.notify(uuid, text, text, text) from public;
revoke all on function public.notify(uuid, text, text, text) from authenticated;
