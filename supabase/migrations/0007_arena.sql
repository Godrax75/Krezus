-- =====================================================================
-- Lot 7 — Arena : amis, demandes, classement, feed, groupes.
--
-- Règle structurante du plan : le classement expose **pseudo + performance
-- en pourcentage**, jamais les montants. Un portefeuille papier reste une
-- information personnelle ; savoir que quelqu'un a « 1 240 € » n'apporte rien
-- à la comparaison et transforme un jeu en étalage.
--
-- Même principe pour le feed : « Julie a acheté Nvidia » se partage,
-- « Julie a acheté pour 300 € » non. Les payloads ne portent aucun montant.
--
-- Codes SQLSTATE, classe privée « KR » (suite de 0005) :
--   KR040  utilisateur introuvable
--   KR041  demande d'ami invalide (soi-même, ou lien déjà existant)
--   KR042  demande d'ami inexistante
--   KR043  groupe introuvable ou code invalide
--   KR044  déjà membre du groupe
-- =====================================================================

-- ---------------------------------------------------------------------
-- Groupes
-- ---------------------------------------------------------------------
create table public.arena_groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(btrim(name)) between 2 and 40),
  owner_id    uuid not null references auth.users(id) on delete cascade,
  invite_code text not null unique,
  created_at  timestamptz not null default now()
);

create table public.arena_group_members (
  group_id  uuid not null references public.arena_groups(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index on public.arena_group_members (user_id);

-- ---------------------------------------------------------------------
-- Amitiés — la table stocke un lien orienté (demandeur → destinataire),
-- mais une amitié acceptée est symétrique. Cette fonction évite de répéter
-- la double condition dans chaque requête et chaque policy.
-- ---------------------------------------------------------------------
create or replace function public.are_friends(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.user_id = p_a and f.friend_id = p_b)
        or (f.user_id = p_b and f.friend_id = p_a))
  );
$$;

create or replace function public.send_friend_request(p_from uuid, p_to uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_from = p_to then
    raise exception 'On ne peut pas s''ajouter soi-même' using errcode = 'KR041';
  end if;

  if not exists (select 1 from public.profiles where id = p_to) then
    raise exception 'Utilisateur introuvable' using errcode = 'KR040';
  end if;

  -- Un lien existant dans un sens ou dans l'autre bloque la demande : sans ce
  -- garde-fou, deux demandes croisées créeraient deux lignes « pending » que
  -- rien ne réconcilierait.
  if exists (
    select 1 from public.friendships f
    where (f.user_id = p_from and f.friend_id = p_to)
       or (f.user_id = p_to and f.friend_id = p_from)
  ) then
    raise exception 'Une demande ou une amitié existe déjà' using errcode = 'KR041';
  end if;

  insert into public.friendships (user_id, friend_id, status)
  values (p_from, p_to, 'pending');
end;
$$;

create or replace function public.accept_friend_request(p_user uuid, p_requester uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated integer;
begin
  -- Seul le destinataire peut accepter : la ligne est (requester → user).
  update public.friendships
  set status = 'accepted'
  where user_id = p_requester and friend_id = p_user and status = 'pending';

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'Aucune demande en attente de cet utilisateur' using errcode = 'KR042';
  end if;
end;
$$;

create or replace function public.remove_friend(p_user uuid, p_other uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.friendships
  where (user_id = p_user and friend_id = p_other)
     or (user_id = p_other and friend_id = p_user);
end;
$$;

-- ---------------------------------------------------------------------
-- Groupes — création et adhésion par code
-- ---------------------------------------------------------------------
create or replace function public.create_arena_group(p_owner uuid, p_name text)
returns table (id uuid, invite_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if length(btrim(coalesce(p_name, ''))) < 2 then
    raise exception 'Nom de groupe trop court' using errcode = 'KR010';
  end if;

  -- Code court, lisible à l'oral, sans caractères ambigus (0/O, 1/I).
  loop
    v_code := upper(substr(translate(encode(gen_random_bytes(8), 'base64'),
                                     '+/=OI01lo', 'ABCDEFGHJ'), 1, 6));
    exit when not exists (select 1 from public.arena_groups g where g.invite_code = v_code);
  end loop;

  insert into public.arena_groups (name, owner_id, invite_code)
  values (btrim(p_name), p_owner, v_code)
  returning arena_groups.id, arena_groups.invite_code into id, invite_code;

  insert into public.arena_group_members (group_id, user_id)
  values (id, p_owner);

  return next;
end;
$$;

create or replace function public.join_arena_group(p_user uuid, p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group uuid;
begin
  select g.id into v_group
  from public.arena_groups g
  where g.invite_code = upper(btrim(p_code));

  if not found then
    raise exception 'Code d''invitation invalide' using errcode = 'KR043';
  end if;

  if exists (select 1 from public.arena_group_members m
             where m.group_id = v_group and m.user_id = p_user) then
    raise exception 'Tu fais déjà partie de ce groupe' using errcode = 'KR044';
  end if;

  insert into public.arena_group_members (group_id, user_id) values (v_group, p_user);
  return v_group;
end;
$$;

create or replace function public.leave_arena_group(p_user uuid, p_group uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.arena_group_members
  where group_id = p_group and user_id = p_user;
end;
$$;

-- ---------------------------------------------------------------------
-- Classement — pseudo + performance, RIEN d'autre
-- ---------------------------------------------------------------------
-- La performance se mesure contre le capital de départ (1 000 €), pas contre
-- le solde courant : sinon un joueur qui vend tout afficherait 0 % de risque
-- et truquerait le classement.
create or replace view public.v_arena_leaderboard as
with holdings as (
  select
    po.id                                        as portfolio_id,
    po.user_id,
    po.cash_cents,
    coalesce(sum(p.quantity * q.price * 100), 0) as positions_cents
  from public.portfolios po
  left join public.positions p   on p.portfolio_id = po.id and p.quantity > 0
  left join public.quotes_cache q on q.symbol = p.symbol
  where po.mode = 'paper'
  group by po.id, po.user_id, po.cash_cents
)
select
  h.user_id,
  pr.username,
  pr.rank_level,
  pr.streak_days,
  pr.xp,
  -- Performance en pourcentage. Le total en euros n'est délibérément PAS
  -- exposé : la vue est lue par des tiers (amis, membres d'un groupe).
  round(((h.cash_cents + h.positions_cents) - 100000)::numeric / 1000, 2) as performance_pct
from holdings h
join public.profiles pr on pr.id = h.user_id;

comment on view public.v_arena_leaderboard is
  'Classement Arena. N''expose JAMAIS de montant : pseudo, rang, série, XP et '
  'performance en pourcent uniquement. Toute colonne en centimes ajoutée ici '
  'fuiterait le portefeuille d''autrui.';

-- ---------------------------------------------------------------------
-- Feed — alimenté par des triggers, sans aucun montant
-- ---------------------------------------------------------------------
create or replace function public.feed_on_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
  v_name text;
begin
  select po.user_id into v_user from public.portfolios po where po.id = new.portfolio_id;
  if v_user is null then return new; end if;

  select s.name into v_name from public.securities s where s.symbol = new.symbol;

  -- payload sans montant ni quantité : l'événement social est « a acheté
  -- Nvidia », pas « a mis 300 € sur Nvidia ».
  insert into public.arena_feed (actor_id, kind, payload)
  values (v_user, new.side,
          jsonb_build_object('symbol', new.symbol, 'name', coalesce(v_name, new.symbol)));

  return new;
end;
$$;

drop trigger if exists orders_feed on public.orders;
create trigger orders_feed
  after insert on public.orders
  for each row execute function public.feed_on_order();

create or replace function public.feed_on_rank_up()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if new.rank_level <= old.rank_level then
    return new;
  end if;

  select r.name_fr into v_name from public.ranks r where r.level = new.rank_level;

  insert into public.arena_feed (actor_id, kind, payload)
  values (new.id, 'rank_up',
          jsonb_build_object('level', new.rank_level, 'name', coalesce(v_name, '')));

  return new;
end;
$$;

drop trigger if exists profiles_feed_rank_up on public.profiles;
create trigger profiles_feed_rank_up
  after update of rank_level on public.profiles
  for each row execute function public.feed_on_rank_up();

create or replace function public.feed_on_lesson()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
begin
  if new.completed_at is null then return new; end if;
  -- Une leçon rejouée ne republie rien.
  if tg_op = 'UPDATE' and old.completed_at is not null then return new; end if;

  select l.title_fr into v_title from public.lessons l where l.id = new.lesson_id;

  insert into public.arena_feed (actor_id, kind, payload)
  values (new.user_id, 'lesson', jsonb_build_object('title', coalesce(v_title, '')));

  return new;
end;
$$;

drop trigger if exists lesson_progress_feed on public.lesson_progress;
create trigger lesson_progress_feed
  after insert or update on public.lesson_progress
  for each row execute function public.feed_on_lesson();

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table public.arena_groups        enable row level security;
alter table public.arena_group_members enable row level security;

-- Un groupe est visible de ses membres ; il se rejoint par code, pas en
-- parcourant la liste des groupes existants.
create policy "groups visible to members" on public.arena_groups
  for select to authenticated using (
    exists (select 1 from public.arena_group_members m
            where m.group_id = id and m.user_id = auth.uid()));

create policy "group members visible to members" on public.arena_group_members
  for select to authenticated using (
    exists (select 1 from public.arena_group_members m
            where m.group_id = arena_group_members.group_id and m.user_id = auth.uid()));

-- Le feed était lisible par tout utilisateur authentifié (`using (true)`), ce
-- qui exposait l'activité de n'importe qui à n'importe qui. On le restreint
-- aux amis et aux membres d'un même groupe.
drop policy if exists "feed readable" on public.arena_feed;
create policy "feed readable by friends" on public.arena_feed
  for select to authenticated using (
    actor_id = auth.uid()
    or public.are_friends(auth.uid(), actor_id)
    or exists (
      select 1
      from public.arena_group_members mine
      join public.arena_group_members theirs on theirs.group_id = mine.group_id
      where mine.user_id = auth.uid() and theirs.user_id = arena_feed.actor_id));
