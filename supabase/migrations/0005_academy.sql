-- =====================================================================
-- Lot 5 — Academy : progression, XP, rangs, série, missions, badges.
--
-- Même principe que le moteur d'ordres (0002) : la progression se calcule en
-- SQL, pas côté client. Un client qui rejoue une requête ne doit pas pouvoir
-- fabriquer de l'XP, exactement comme il ne peut pas fabriquer de cash.
--
-- Codes SQLSTATE, classe privée « KR » (suite de 0002) :
--   KR020  leçon introuvable
--   KR021  leçon réservée aux abonnés
--   KR022  mission inconnue
-- =====================================================================

-- ---------------------------------------------------------------------
-- Missions ponctuelles vs quotidiennes
-- ---------------------------------------------------------------------
-- « Activer ton compte » se gagne une fois pour toutes : la stocker comme une
-- mission du jour la ferait réapparaître non cochée le lendemain.
alter table public.missions
  add column if not exists is_daily boolean not null default true;

update public.missions set is_daily = false where code = 'activate';

-- ---------------------------------------------------------------------
-- Rangs
-- ---------------------------------------------------------------------
-- Table de référence des rangs (statique — sert aussi à l'écran « Tous les
-- rangs »). Elle vivait dans `seed/ranks_missions_badges.sql`, ce qui rendait
-- l'ordre d'application documenté impossible à suivre : la vue
-- `v_academy_progress` ci-dessous et sa policy RLS en dépendent, or les seeds
-- s'appliquent APRÈS les migrations. Le schéma appartient aux migrations, les
-- données au seed.
create table if not exists public.ranks (
  level       integer primary key,
  emoji       text not null,
  name_fr     text not null,
  name_en     text,
  min_xp      integer not null,
  max_xp      integer,               -- NULL = dernier rang
  image_asset text not null
);

create or replace function public.rank_for_xp(p_xp integer)
returns integer
language sql
immutable
as $$
  select least(6, greatest(1, 1 + (greatest(p_xp, 0) / 200)));
$$;

comment on function public.rank_for_xp is
  'Palier de 200 XP, borné à 6 (Empereur). Doit rester aligné sur la table ranks.';

-- ---------------------------------------------------------------------
-- Badges — attribution idempotente
-- ---------------------------------------------------------------------
create or replace function public.award_badge(p_user uuid, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_badge uuid;
begin
  select id into v_badge from public.badges where code = p_code;
  if not found then
    return false;                       -- badge non seedé : on n'échoue pas pour si peu
  end if;

  insert into public.user_badges (user_id, badge_id)
  values (p_user, v_badge)
  on conflict (user_id, badge_id) do nothing;

  return found;
end;
$$;

-- ---------------------------------------------------------------------
-- XP et montée en rang
-- ---------------------------------------------------------------------
create or replace function public.award_xp(p_user uuid, p_xp integer)
returns table (xp integer, rank_level integer, ranked_up boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before integer;
  v_after  integer;
begin
  select p.rank_level into v_before from public.profiles p where p.id = p_user;
  if not found then
    raise exception 'Profil introuvable' using errcode = 'KR002';
  end if;

  update public.profiles p
  set xp         = greatest(0, p.xp + p_xp),
      rank_level = public.rank_for_xp(greatest(0, p.xp + p_xp))
  where p.id = p_user
  returning p.xp, p.rank_level into xp, rank_level;

  v_after   := rank_level;
  ranked_up := v_after > v_before;

  if ranked_up then
    perform public.award_badge(p_user, 'rank_up');
  end if;

  return next;
end;
$$;

-- ---------------------------------------------------------------------
-- Série (streak)
-- ---------------------------------------------------------------------
-- Appelée à chaque activité qualifiante. Idempotente dans la journée : une
-- deuxième leçon le même jour ne fait pas monter la série deux fois.
create or replace function public.touch_streak(p_user uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last  date;
  v_days  integer;
  v_today date := current_date;
begin
  select streak_last_at, streak_days into v_last, v_days
  from public.profiles where id = p_user
  for update;

  if not found then
    raise exception 'Profil introuvable' using errcode = 'KR002';
  end if;

  if v_last = v_today then
    return v_days;                                   -- déjà compté aujourd'hui
  elsif v_last = v_today - 1 then
    v_days := coalesce(v_days, 0) + 1;               -- journée consécutive
  else
    v_days := 1;                                     -- série rompue (ou première)
  end if;

  update public.profiles
  set streak_days = v_days, streak_last_at = v_today
  where id = p_user;

  if v_days >= 7 then
    perform public.award_badge(p_user, 'streak_7');
  end if;

  return v_days;
end;
$$;

-- ---------------------------------------------------------------------
-- Missions
-- ---------------------------------------------------------------------
-- Renvoie l'XP réellement accordée : 0 si la mission était déjà validée.
-- C'est ce retour qui rend l'appel rejouable sans risque.
create or replace function public.complete_mission(p_user uuid, p_code text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mission  record;
  v_day      date := current_date;
  v_existing integer;
begin
  select id, xp, is_daily into v_mission
  from public.missions where code = p_code;

  if not found then
    raise exception 'Mission inconnue : %', p_code using errcode = 'KR022';
  end if;

  -- Une mission ponctuelle est acquise quel que soit le jour où elle a été
  -- validée ; une mission quotidienne se rejoue chaque jour.
  select count(*) into v_existing
  from public.mission_progress mp
  where mp.user_id = p_user
    and mp.mission_id = v_mission.id
    and mp.done_at is not null
    and (v_mission.is_daily = false or mp.day = v_day);

  if v_existing > 0 then
    return 0;
  end if;

  insert into public.mission_progress (user_id, mission_id, day, done_at)
  values (p_user, v_mission.id, v_day, now())
  on conflict (user_id, mission_id, day) do update set done_at = now()
  where public.mission_progress.done_at is null;

  perform public.award_xp(p_user, v_mission.xp);
  return v_mission.xp;
end;
$$;

-- ---------------------------------------------------------------------
-- Complétion d'une leçon
-- ---------------------------------------------------------------------
-- Transactionnel : progression, XP, série, missions et badges bougent
-- ensemble ou pas du tout.
create or replace function public.complete_lesson(
  p_user         uuid,
  p_lesson       uuid,
  p_quiz_correct boolean default null
)
returns table (xp_gained integer, xp_total integer, rank_level integer, streak_days integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson   record;
  v_premium  timestamptz;
  v_gained   integer := 0;
  v_done     integer;
begin
  select id, is_free into v_lesson from public.lessons where id = p_lesson;
  if not found then
    raise exception 'Leçon introuvable' using errcode = 'KR020';
  end if;

  if not v_lesson.is_free then
    select premium_until into v_premium from public.profiles where id = p_user;
    if v_premium is null or v_premium < now() then
      raise exception 'Leçon réservée aux abonnés' using errcode = 'KR021';
    end if;
  end if;

  -- La progression est un état, pas un compteur : repasser une leçon met à
  -- jour le résultat du quiz sans jamais reverser d'XP.
  insert into public.lesson_progress (user_id, lesson_id, completed_at, quiz_correct)
  values (p_user, p_lesson, now(), p_quiz_correct)
  on conflict (user_id, lesson_id) do update
    set completed_at = coalesce(public.lesson_progress.completed_at, now()),
        quiz_correct = coalesce(excluded.quiz_correct, public.lesson_progress.quiz_correct);

  perform public.touch_streak(p_user);

  v_gained := v_gained + public.complete_mission(p_user, 'lesson');
  if p_quiz_correct then
    v_gained := v_gained + public.complete_mission(p_user, 'quiz');
  end if;

  select count(*) into v_done
  from public.lesson_progress
  where user_id = p_user and completed_at is not null;

  if v_done >= 4 then
    perform public.award_badge(p_user, 'academy_4');
  end if;

  select p.xp, p.rank_level, p.streak_days
  into xp_total, rank_level, streak_days
  from public.profiles p where p.id = p_user;

  xp_gained := v_gained;
  return next;
end;
$$;

-- ---------------------------------------------------------------------
-- Tentative de quiz (historique, pour l'écran de progression)
-- ---------------------------------------------------------------------
create or replace function public.record_quiz_attempt(
  p_user  uuid,
  p_score integer,
  p_total integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_total <= 0 or p_score < 0 or p_score > p_total then
    raise exception 'Score invalide' using errcode = 'KR010';
  end if;

  insert into public.quiz_attempts (user_id, score, total)
  values (p_user, p_score, p_total)
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Badges de trading — déclenchés par l'arrivée d'un ordre
-- ---------------------------------------------------------------------
-- Un trigger sur `orders` plutôt qu'une modification d'`execute_paper_buy` :
-- le moteur du Lot 2 est vérifié par ses propres tests, on ne le rouvre pas
-- pour y greffer de la gamification.
create or replace function public.check_trading_badges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid;
  v_sectors integer;
begin
  select po.user_id into v_user
  from public.portfolios po where po.id = new.portfolio_id;

  if v_user is null then
    return new;
  end if;

  if new.side = 'buy' then
    perform public.award_badge(v_user, 'first_buy');
  end if;

  -- « Portefeuille diversifié » = au moins trois secteurs distincts détenus.
  select count(distinct s.sector) into v_sectors
  from public.positions p
  join public.securities s on s.symbol = p.symbol
  where p.portfolio_id = new.portfolio_id and p.quantity > 0;

  if v_sectors >= 3 then
    perform public.award_badge(v_user, 'diversified');
  end if;

  return new;
end;
$$;

drop trigger if exists orders_award_badges on public.orders;
create trigger orders_award_badges
  after insert on public.orders
  for each row execute function public.check_trading_badges();

-- ---------------------------------------------------------------------
-- « Activer ton compte » — acquise à la création du profil
-- ---------------------------------------------------------------------
create or replace function public.handle_new_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.complete_mission(new.id, 'activate');
  return new;
end;
$$;

drop trigger if exists profiles_activate_mission on public.profiles;
create trigger profiles_activate_mission
  after insert on public.profiles
  for each row execute function public.handle_new_profile();

-- ---------------------------------------------------------------------
-- Vue de progression — une seule requête pour l'écran Academy
-- ---------------------------------------------------------------------
create or replace view public.v_academy_progress as
select
  p.id                                              as user_id,
  p.xp,
  p.rank_level,
  p.streak_days,
  r.name_fr                                         as rank_name,
  r.emoji                                           as rank_emoji,
  r.min_xp                                          as rank_min_xp,
  r.max_xp                                          as rank_max_xp,
  (select count(*) from public.lesson_progress lp
    where lp.user_id = p.id and lp.completed_at is not null)   as lessons_done,
  (select count(*) from public.lesson_progress lp
    where lp.user_id = p.id and lp.quiz_correct)               as quizzes_passed,
  (select count(*) from public.user_badges ub
    where ub.user_id = p.id)                                   as badges_earned
from public.profiles p
join public.ranks r on r.level = p.rank_level;

comment on view public.v_academy_progress is
  'Agrégat de progression pour l''écran Academy. RLS hérite de profiles.';

-- ---------------------------------------------------------------------
-- RLS des tables ajoutées par ce lot
-- ---------------------------------------------------------------------
alter table public.ranks enable row level security;
create policy "ranks readable" on public.ranks
  for select to authenticated using (true);
