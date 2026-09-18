-- =====================================================================
-- 0021 — Versement hebdomadaire et identité choisie à l'inscription
--
-- 1. Chaque semaine, 300 € fictifs de plus, versés à la première
--    connexion de la semaine. Une semaine sans passage est perdue : le
--    versement récompense la régularité, il ne s'accumule pas.
-- 2. Ces versements sont des apports, pas des gains : le classement et
--    la courbe les retirent de la performance. Sans cela, le joueur le
--    plus assidu serait « le meilleur investisseur » sans avoir rien fait.
-- 3. Le pseudo est choisi à l'inscription, unique sans égard à la casse,
--    et vérifiable avant l'envoi.
--
--   KR080 pseudo déjà pris
--   KR081 pseudo ou prénom invalide
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Versements
-- ---------------------------------------------------------------------
create table if not exists public.cash_deposits (
  id            uuid primary key default gen_random_uuid(),
  portfolio_id  uuid not null references public.portfolios(id) on delete cascade,
  kind          text not null check (kind in ('weekly')),
  amount_cents  bigint not null check (amount_cents > 0),
  -- Lundi de la semaine versée, à l'heure de Paris.
  period_start  date not null,
  created_at    timestamptz not null default now(),
  unique (portfolio_id, kind, period_start)
);
create index if not exists cash_deposits_portfolio_idx
  on public.cash_deposits (portfolio_id, created_at);

alter table public.cash_deposits enable row level security;

drop policy if exists "deposits read own" on public.cash_deposits;
create policy "deposits read own" on public.cash_deposits
  for select to authenticated
  using (exists (select 1 from public.portfolios po
                 where po.id = portfolio_id and po.user_id = auth.uid()));
-- Aucune politique d'écriture : seul claim_weekly_bonus verse.

-- Montant hebdomadaire, en un seul endroit.
create or replace function public.weekly_bonus_cents()
returns bigint language sql immutable as $$ select 30000::bigint $$;

-- Lundi de la semaine en cours, heure de Paris : la semaine d'un joueur
-- français ne bascule pas le dimanche à 1 h du matin.
create or replace function public.current_bonus_week()
returns date language sql stable as $$
  select date_trunc('week', now() at time zone 'Europe/Paris')::date
$$;

-- Verse le bonus de la semaine s'il n'a pas encore été versé.
--
-- La semaine d'ouverture (ou de remise à zéro) du portefeuille ne donne
-- rien : les 1 000 € de départ en tiennent lieu. Idempotent : un second
-- appel dans la semaine rend 0.
create or replace function public.claim_weekly_bonus()
returns table (credited_cents bigint, week_start date, next_week_start date)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_me        uuid := auth.uid();
  v_week      date := public.current_bonus_week();
  v_portfolio public.portfolios%rowtype;
  v_started   date;
  v_inserted  integer;
begin
  if v_me is null then
    raise exception 'Aucune session' using errcode = 'KR010';
  end if;

  select * into v_portfolio from public.portfolios
  where user_id = v_me and mode = 'paper'
  for update;
  if not found then
    raise exception 'Portefeuille introuvable' using errcode = 'KR002';
  end if;

  v_started := date_trunc('week', greatest(v_portfolio.created_at,
                 coalesce(v_portfolio.reset_at, v_portfolio.created_at))
                 at time zone 'Europe/Paris')::date;

  credited_cents := 0;
  week_start := v_week;
  next_week_start := v_week + 7;

  if v_started >= v_week then
    return next;
    return;
  end if;

  insert into public.cash_deposits (portfolio_id, kind, amount_cents, period_start)
  values (v_portfolio.id, 'weekly', public.weekly_bonus_cents(), v_week)
  on conflict (portfolio_id, kind, period_start) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 1 then
    update public.portfolios
    set cash_cents = cash_cents + public.weekly_bonus_cents()
    where id = v_portfolio.id;
    credited_cents := public.weekly_bonus_cents();
  end if;

  return next;
end;
$$;

revoke execute on function public.claim_weekly_bonus() from public, anon;
grant execute on function public.claim_weekly_bonus() to authenticated;

-- Apports d'un portefeuille depuis une date (incluse), ouverture comprise
-- s'il n'y a pas de date.
create or replace function public.deposits_since(p_portfolio uuid, p_since timestamptz)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(d.amount_cents), 0)::bigint
  from public.cash_deposits d
  join public.portfolios po on po.id = d.portfolio_id
  where d.portfolio_id = p_portfolio
    and d.created_at >= greatest(po.created_at, coalesce(po.reset_at, po.created_at))
    and (p_since is null or d.created_at >= p_since);
$$;

revoke execute on function public.deposits_since(uuid, timestamptz) from public, anon, authenticated;

-- Chaque relevé retient le cumul des apports qu'il contient : la
-- performance d'une période en retire exactement ceux versés depuis.
alter table public.portfolio_snapshots
  add column if not exists deposits_cents bigint not null default 0;

create or replace function public.snapshot_portfolios()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into public.portfolio_snapshots (portfolio_id, date, total_value_cents, deposits_cents)
  select po.id, current_date, public.portfolio_value_cents(po.id), public.deposits_since(po.id, null)
  from public.portfolios po
  where po.mode = 'paper'
  on conflict (portfolio_id, date) do update
    set total_value_cents = excluded.total_value_cents,
        deposits_cents    = excluded.deposits_cents;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.snapshot_portfolios() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Performance hors apports
--
-- Gain = valeur − valeur de départ − apports versés depuis ;
-- base = valeur de départ + apports versés depuis. Un apport en fin de
-- période dilue un peu la performance plutôt que de la gonfler : c'est
-- le sens prudent.
-- ---------------------------------------------------------------------
create or replace function public.arena_leaderboard(p_period text default 'all',
                                                    p_scope  text default 'global')
returns table (place integer, user_id uuid, username text, rank_level integer,
               streak_days integer, performance_pct numeric, is_me boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_me    uuid := auth.uid();
  v_start date;
begin
  if v_me is null then
    raise exception 'Aucune session' using errcode = 'KR010';
  end if;

  if p_period not in ('day', 'week', 'month', 'ytd', 'all') then
    raise exception 'Période inconnue' using errcode = 'KR010';
  end if;
  if p_scope not in ('global', 'friends') then
    raise exception 'Portée inconnue' using errcode = 'KR010';
  end if;

  v_start := case p_period
    when 'day'   then current_date
    when 'week'  then date_trunc('week',  now())::date
    when 'month' then date_trunc('month', now())::date
    when 'ytd'   then date_trunc('year',  now())::date
    else null
  end;

  return query
  with players as (
    select po.id as pid, po.user_id as uid,
           greatest(po.created_at, coalesce(po.reset_at, po.created_at)) as started
    from public.portfolios po
    where po.mode = 'paper'
      and (po.user_id = v_me
           or (p_scope = 'global' and exists (select 1 from public.orders o
                                              where o.portfolio_id = po.id and o.status = 'filled'))
           or (p_scope = 'friends' and public.are_friends(v_me, po.user_id)))
  ),
  based as (
    select pl.pid, pl.uid,
           public.portfolio_value_cents(pl.pid) as now_cents,
           (v_start is null or pl.started::date >= v_start) as from_inception
    from players pl
  ),
  scored as (
    select b.uid, b.now_cents,
           coalesce(snap.total_value_cents, 100000) as base_cents,
           -- Les apports versés après le relevé de base, et eux seuls : le
           -- relevé retient le cumul qu'il contenait déjà.
           public.deposits_since(b.pid, null) - coalesce(snap.deposits_cents, 0) as added_cents
    from based b
    left join lateral (
      select s.total_value_cents, s.deposits_cents
      from public.portfolio_snapshots s
      where not b.from_inception and s.portfolio_id = b.pid and s.date < v_start
      order by s.date desc limit 1
    ) snap on true
  ),
  ranked as (
    select sc.uid,
           round((sc.now_cents - sc.base_cents - sc.added_cents)::numeric * 100
                 / nullif(sc.base_cents + sc.added_cents, 0), 2) as pct,
           row_number() over (order by (sc.now_cents - sc.base_cents - sc.added_cents)::numeric
                                       / nullif(sc.base_cents + sc.added_cents, 0) desc,
                                       sc.uid) as pos
    from scored sc
  )
  select r.pos::integer, r.uid, pr.username, pr.rank_level, pr.streak_days,
         coalesce(r.pct, 0), r.uid = v_me
  from ranked r
  join public.profiles pr on pr.id = r.uid
  where r.pos <= 100 or r.uid = v_me
  order by r.pos;
end;
$$;

revoke execute on function public.arena_leaderboard(text, text) from public, anon;
grant execute on function public.arena_leaderboard(text, text) to authenticated;

-- La vue historique (encore lue pour la liste d'amis) : même correction.
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
),
contributed as (
  -- Sous-requête plutôt que deposits_since : une fonction appelée dans une
  -- vue s'exécute avec les droits du lecteur, qui ne l'a pas.
  select h.*, 100000 + coalesce((
           select sum(d.amount_cents) from public.cash_deposits d
           join public.portfolios po on po.id = d.portfolio_id
           where d.portfolio_id = h.portfolio_id
             and d.created_at >= greatest(po.created_at, coalesce(po.reset_at, po.created_at))
         ), 0) as invested_cents
  from holdings h
)
select
  c.user_id,
  pr.username,
  pr.rank_level,
  pr.streak_days,
  pr.xp,
  round(((c.cash_cents + c.positions_cents) - c.invested_cents)::numeric * 100
        / c.invested_cents, 2) as performance_pct
from contributed c
join public.profiles pr on pr.id = c.user_id;

revoke all on public.v_arena_leaderboard from anon;

-- Rattrapage des relevés : les apports entrent dans les liquidités.
create or replace function public.backfill_portfolio_snapshots()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with pf as (
    select po.id, greatest(po.created_at, coalesce(po.reset_at, po.created_at)) as started
    from public.portfolios po
    where po.mode = 'paper'
  ),
  days as (
    select pf.id as pid, pf.started, d::date as day
    from pf, generate_series(pf.started::date, current_date - 1, interval '1 day') as d
  ),
  moves as (
    select dd.pid, dd.day, o.symbol,
           case when o.side = 'buy' then -o.amount_cents else o.amount_cents end as cash_delta,
           case when o.side = 'buy' then o.quantity else -o.quantity end        as qty_delta
    from days dd
    join public.orders o
      on o.portfolio_id = dd.pid and o.status = 'filled'
     and o.created_at >= dd.started and o.created_at < (dd.day + 1)
  ),
  added as (
    select dd.pid, dd.day, coalesce(sum(d.amount_cents), 0) as deposit_cents
    from days dd
    left join public.cash_deposits d
      on d.portfolio_id = dd.pid and d.created_at >= dd.started and d.created_at < (dd.day + 1)
    group by dd.pid, dd.day
  ),
  cash as (
    select dd.pid, dd.day,
           100000 + coalesce(sum(m.cash_delta), 0)
                  + (select a.deposit_cents from added a where a.pid = dd.pid and a.day = dd.day)
             as cash_cents
    from days dd
    left join moves m on m.pid = dd.pid and m.day = dd.day
    group by dd.pid, dd.day
  ),
  holdings as (
    select m.pid, m.day, m.symbol, sum(m.qty_delta) as qty
    from moves m
    group by m.pid, m.day, m.symbol
    having sum(m.qty_delta) > 1e-9
  ),
  valued as (
    select h.pid, h.day,
           sum(h.qty * coalesce(
             (select ph.close
                   / case when s.currency = 'USD'
                          then nullif((select f.rate from public.fx_history f
                                       where f.pair = 'EURUSD' and f.date <= h.day
                                       order by f.date desc limit 1), 0)
                          else 1 end
              from public.price_history ph
              where ph.symbol = h.symbol and ph.date <= h.day
              order by ph.date desc limit 1),
             (select q.price from public.quotes_cache q where q.symbol = h.symbol)
           ) * 100) as positions_cents
    from holdings h
    join public.securities s on s.symbol = h.symbol
    group by h.pid, h.day
  )
  insert into public.portfolio_snapshots (portfolio_id, date, total_value_cents, deposits_cents)
  select c.pid, c.day, c.cash_cents + coalesce(round(v.positions_cents), 0)::bigint, a.deposit_cents
  from cash c
  join added a on a.pid = c.pid and a.day = c.day
  left join valued v on v.pid = c.pid and v.day = c.day
  on conflict (portfolio_id, date) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.backfill_portfolio_snapshots() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Pseudo unique, choisi à l'inscription
-- ---------------------------------------------------------------------

-- « Louis » et « louis » sont le même joueur au classement.
create unique index if not exists profiles_username_lower_key
  on public.profiles (lower(username)) where username is not null;

create or replace function public.is_valid_username(p_username text)
returns boolean language sql immutable as $$
  select p_username ~ '^[A-Za-z0-9_.-]{3,20}$'
$$;

-- Disponibilité, sans dévoiler à qui appartient un pseudo pris. Son propre
-- pseudo est « disponible » : le garder n'est pas un conflit.
create or replace function public.username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_valid_username(trim(p_username))
     and not exists (select 1 from public.profiles p
                     where lower(p.username) = lower(trim(p_username))
                       and p.id is distinct from auth.uid());
$$;

revoke execute on function public.username_available(text) from public, anon;
grant execute on function public.username_available(text) to authenticated;

-- Prénom et pseudo en une écriture. Le prénom est facultatif ; le pseudo,
-- non. L'index unique tranche les courses entre deux inscriptions.
create or replace function public.set_profile_identity(p_first_name text, p_username text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me    uuid := auth.uid();
  v_user  text := trim(p_username);
  v_first text := nullif(trim(p_first_name), '');
begin
  if v_me is null then
    raise exception 'Aucune session' using errcode = 'KR010';
  end if;
  if not public.is_valid_username(v_user)
     or (v_first is not null and char_length(v_first) > 40) then
    raise exception 'Pseudo ou prénom invalide' using errcode = 'KR081';
  end if;
  if exists (select 1 from public.profiles p
             where lower(p.username) = lower(v_user) and p.id <> v_me) then
    raise exception 'Pseudo déjà pris' using errcode = 'KR080';
  end if;

  begin
    update public.profiles
    set username = v_user,
        first_name = coalesce(v_first, first_name)
    where id = v_me;
  exception when unique_violation then
    raise exception 'Pseudo déjà pris' using errcode = 'KR080';
  end;
end;
$$;

revoke execute on function public.set_profile_identity(text, text) from public, anon;
grant execute on function public.set_profile_identity(text, text) to authenticated;
