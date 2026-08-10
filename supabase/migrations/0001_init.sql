-- =====================================================================
-- Krezus — schéma initial (v1 paper money)
-- Postgres / Supabase. RLS activé partout ; policies dans 0002_rls.sql.
-- Montants stockés en centimes (bigint) pour éviter tout flottant sur l'argent.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- Référentiel titres (lecture publique authentifiée)
-- ---------------------------------------------------------------------
create table public.securities (
  symbol            text primary key,               -- id interne (= id du prototype)
  eodhd_symbol      text,                            -- symbole de cotation EODHD (NULL pour ETF non mappés)
  mic               text,                            -- place de cotation (XPAR, NASDAQ, NYSE, XAMS)
  currency          text not null default 'EUR',
  asset_type        text not null default 'stock'    -- 'stock' | 'etf'
                    check (asset_type in ('stock', 'etf')),
  name              text not null,
  country_code      text,
  country           text,
  sector            text,
  founded           text,
  logo_asset        text,                            -- nom d'asset embarqué dans l'app
  initials          text,                            -- fallback quand pas de logo
  dividend_yield    numeric,                         -- % (instantané éditorial)
  market_cap_label  text,                            -- ex. « 3 900 Md$ »
  pe_ratio          numeric,
  peg_ratio         numeric,
  analyst_target    numeric,                         -- objectif de cours (seed v1)
  ceo               text,
  description_fr    text,
  description_en    text,
  hercule_note_fr   text,
  hercule_note_en   text,
  updated_at        timestamptz not null default now()
);
create index on public.securities (asset_type);

-- Cache de cotations (différé 15 min ; rafraîchi par la Edge Function `quotes`)
create table public.quotes_cache (
  symbol       text primary key references public.securities(symbol) on delete cascade,
  price        numeric not null,
  open         numeric,
  change_pct   numeric,
  fetched_at   timestamptz not null default now()
);

-- Historique quotidien (courbes 1M / 1A / Tout)
create table public.price_history (
  symbol   text not null references public.securities(symbol) on delete cascade,
  date     date not null,
  close    numeric not null,
  primary key (symbol, date)
);

-- ---------------------------------------------------------------------
-- Utilisateurs et gamification
-- ---------------------------------------------------------------------
create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  username        text unique,
  first_name      text,
  last_name       text,
  locale          text not null default 'fr' check (locale in ('fr', 'en')),
  dark_mode       boolean not null default false,
  xp              integer not null default 0,
  rank_level      integer not null default 1,        -- calculé : 1 + xp/200, borné à 6
  streak_days     integer not null default 0,
  streak_last_at  date,
  premium_until   timestamptz,                        -- abonnement Hercule
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Portefeuille papier
-- ---------------------------------------------------------------------
create table public.portfolios (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  mode        text not null default 'paper' check (mode = 'paper'),
  cash_cents  bigint not null default 100000,          -- 1 000,00 € fictifs
  reset_at    timestamptz,
  created_at  timestamptz not null default now(),
  unique (user_id, mode)
);

create table public.positions (
  portfolio_id   uuid not null references public.portfolios(id) on delete cascade,
  symbol         text not null references public.securities(symbol),
  quantity       numeric(18,8) not null,                -- parts fractionnées
  avg_cost_cents bigint not null,                        -- prix de revient moyen pondéré, en centimes/part
  primary key (portfolio_id, symbol),
  check (quantity > 0)
);

create table public.orders (
  id              uuid primary key default gen_random_uuid(),
  portfolio_id    uuid not null references public.portfolios(id) on delete cascade,
  symbol          text not null references public.securities(symbol),
  side            text not null check (side in ('buy', 'sell')),
  amount_cents    bigint not null,                       -- montant demandé (achat) ou produit (vente)
  quantity        numeric(18,8) not null,
  executed_price  numeric not null,                      -- cours d'exécution (unité devise du titre)
  status          text not null default 'filled' check (status in ('filled', 'rejected')),
  created_at      timestamptz not null default now()
);
create index on public.orders (portfolio_id, created_at desc);

-- Instantané quotidien de valeur (courbe du portefeuille)
create table public.portfolio_snapshots (
  portfolio_id      uuid not null references public.portfolios(id) on delete cascade,
  date              date not null,
  total_value_cents bigint not null,
  primary key (portfolio_id, date)
);

-- ---------------------------------------------------------------------
-- Academy
-- ---------------------------------------------------------------------
create table public.lessons (
  id              uuid primary key default gen_random_uuid(),
  position        integer not null unique,
  title_fr        text not null,
  title_en        text,
  duration_label  text,
  paragraphs_fr   jsonb not null default '[]',
  paragraphs_en   jsonb,
  examples_fr     jsonb not null default '[]',
  examples_en     jsonb,
  quiz_fr         jsonb,                                 -- { q, opts[], a, why }
  quiz_en         jsonb,
  theme           text,
  is_free         boolean not null default false
);

create table public.lesson_progress (
  user_id      uuid not null references auth.users(id) on delete cascade,
  lesson_id    uuid not null references public.lessons(id) on delete cascade,
  completed_at timestamptz,
  quiz_correct boolean,
  primary key (user_id, lesson_id)
);

create table public.quiz_attempts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  score       integer not null,
  total       integer not null,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Missions quotidiennes & badges
-- ---------------------------------------------------------------------
create table public.missions (
  id        uuid primary key default gen_random_uuid(),
  code      text not null unique,
  title_fr  text not null,
  title_en  text,
  xp        integer not null
);

create table public.mission_progress (
  user_id    uuid not null references auth.users(id) on delete cascade,
  mission_id uuid not null references public.missions(id) on delete cascade,
  day        date not null,
  done_at    timestamptz,
  primary key (user_id, mission_id, day)
);

create table public.badges (
  id        uuid primary key default gen_random_uuid(),
  code      text not null unique,
  title_fr  text not null,
  title_en  text
);

create table public.user_badges (
  user_id    uuid not null references auth.users(id) on delete cascade,
  badge_id   uuid not null references public.badges(id) on delete cascade,
  earned_at  timestamptz not null default now(),
  primary key (user_id, badge_id)
);

-- ---------------------------------------------------------------------
-- Arena (social)
-- ---------------------------------------------------------------------
create table public.friendships (
  user_id     uuid not null references auth.users(id) on delete cascade,
  friend_id   uuid not null references auth.users(id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at  timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create table public.arena_feed (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid not null references auth.users(id) on delete cascade,
  kind        text not null,                             -- 'buy' | 'lesson' | 'rank_up' | ...
  payload     jsonb not null default '{}',
  created_at  timestamptz not null default now()
);
create index on public.arena_feed (created_at desc);

-- ---------------------------------------------------------------------
-- Profil investisseur, notifications, Hercule
-- ---------------------------------------------------------------------
create table public.investor_profile (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  answers     jsonb not null default '{}',
  archetype   text,
  dna         jsonb,
  updated_at  timestamptz not null default now()
);

create table public.notifications (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references auth.users(id) on delete cascade,
  kind      text not null,
  title     text not null,
  body      text,
  read_at   timestamptz,
  created_at timestamptz not null default now()
);
create index on public.notifications (user_id, created_at desc);

create table public.hercule_messages (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references auth.users(id) on delete cascade,
  role      text not null check (role in ('user', 'assistant')),
  content   text not null,
  created_at timestamptz not null default now()
);
create index on public.hercule_messages (user_id, created_at);

-- Vue leaderboard : expose pseudo + performance, jamais les montants absolus.
create view public.arena_leaderboard as
select
  p.id            as user_id,
  p.username,
  p.rank_level,
  case
    when po.cash_cents is null then 0
    else round((po.cash_cents - 100000)::numeric / 1000, 2)   -- perf % vs mise initiale
  end             as perf_pct
from public.profiles p
left join public.portfolios po on po.user_id = p.id and po.mode = 'paper';
