-- =====================================================================
-- Mode réel — courtier externe (Interactive Brokers).
--
-- DÉCISION STRUCTURANTE : IBKR EST LA SEULE SOURCE DE VÉRITÉ.
-- Il n'y a volontairement AUCUNE table `live_positions`, `live_cash` ou
-- `live_orders` miroir. Trois raisons :
--
--   1. Un miroir est une seconde vérité, fausse au pire moment.
--      Exécution partielle, opération sur titres, dividende, conversion
--      de change, ordre passé depuis l'application IBKR elle-même, frais
--      prélevés : tout ça modifie le compte sans passer par nous. Le
--      miroir diverge dès le premier de ces événements, et il diverge
--      silencieusement.
--   2. Le reconstruire correctement, c'est réécrire un teneur de
--      position à partir d'une API HTTP paginée sans flux d'événements
--      fiable. C'est le métier du courtier.
--   3. Un solde faux sur de l'argent fictif est un bug ; sur de l'argent
--      réel, c'est une réclamation.
--
-- Ce qui est stocké ici, c'est ce qu'IBKR n'a pas : notre INTENTION, ce
-- qu'on a envoyé, et ce qui nous a été répondu. Le cache court des
-- positions vit côté navigateur (TanStack Query), pas en base.
--
-- INVARIANT : le moteur papier et le mode réel ne se croisent JAMAIS.
--   * `portfolios.mode` reste `check (mode = 'paper')` — NON étendu.
--     Un compte réel n'a pas de ligne dans `portfolios`, donc
--     `execute_paper_buy` ne peut structurellement pas le trouver.
--   * `live_order_intents` n'a AUCUNE clé étrangère vers `portfolios`.
--   * Aucune ligne réelle n'entre dans `orders` ni dans `positions`.
--
-- Codes SQLSTATE ajoutés (classe privée « KR ») :
--   KR060 courtier non connecté        KR061 titre non négociable en réel
--   KR062 dérive de cotation           KR063 confirmation courtier requise
--   KR064 intention déjà soumise       KR065 session courtier concurrente
-- =====================================================================


-- =====================================================================
-- 1. Référentiel — de quoi router un ordre réel sans ambiguïté
-- =====================================================================
--
-- `securities.symbol` est un identifiant Krezus (`AIRB`, `MC`, `BOUY`),
-- `eodhd_symbol` vaut `AIR.PA`, `mic` vaut `XPAR`. Une recherche IBKR sur
-- « AIR » rend des dizaines de contrats sur autant de places. Résoudre le
-- conid automatiquement au moment de l'ordre finira par acheter le
-- mauvais titre — et contrairement à un cours absent, ça ne se voit pas.
--
-- D'où : résolution HORS LIGNE, relue par un humain
-- (scripts/resolve-ibkr-conids.ts du dépôt web produit un CSV de
-- candidats ; il n'écrit pas en base). 81 lignes, une fois.

alter table public.securities
  add column if not exists isin                      text,
  add column if not exists ibkr_conid                bigint,
  add column if not exists ibkr_exchange             text,
  add column if not exists ibkr_currency             text,
  -- Hash de symbol + currency + exchange + companyName tels que renvoyés
  -- par /iserver/contract/{conid}/info au moment de la validation
  -- humaine. Un conid peut changer de titre sur une fusion ou un
  -- changement d'ISIN : rare, et catastrophique. On compare avant le
  -- premier ordre, et périodiquement.
  add column if not exists ibkr_contract_fingerprint text,
  add column if not exists ibkr_checked_at           timestamptz;

comment on column public.securities.isin is
  'Identifiant international du titre. Sert à lever l''ambiguïté sur le conid '
  'ET à s''afficher dans le récapitulatif d''ordre réel.';
comment on column public.securities.ibkr_conid is
  'Contrat Interactive Brokers. NULL = titre NON négociable en mode réel '
  '(KR061). Jamais de repli sur une recherche : même esprit que 0013 sur les ETF.';

-- Deux titres ne peuvent pas pointer le même contrat.
create unique index if not exists securities_ibkr_conid_key
  on public.securities (ibkr_conid)
  where ibkr_conid is not null;

create unique index if not exists securities_isin_key
  on public.securities (isin)
  where isin is not null;


-- =====================================================================
-- 2. Connexion courtier
-- =====================================================================
--
-- Une ligne par utilisateur et par courtier. On n'y stocke AUCUN secret :
-- la passerelle Client Portal tient la session par cookie, en mémoire du
-- processus serveur. Cette table dit à quel compte on parle, pas comment
-- s'y authentifier.

create table if not exists public.broker_connections (
  user_id          uuid not null references auth.users(id) on delete cascade,
  broker           text not null default 'ibkr' check (broker in ('ibkr')),
  account_id       text not null,
  -- Compte IBKR de démo (DU…). À NE PAS confondre avec le simulateur
  -- Krezus : ici la chaîne d'ordre est réelle, seul l'argent est fictif.
  -- Trois libellés distincts à l'écran, sinon quelqu'un se trompera.
  is_paper_account boolean not null default true,
  base_currency    text not null default 'EUR',
  status           text not null default 'disconnected'
                   check (status in ('connected', 'disconnected', 'competing')),
  last_checked_at  timestamptz,
  created_at       timestamptz not null default now(),
  primary key (user_id, broker)
);

alter table public.broker_connections enable row level security;

create policy "broker_connections own" on public.broker_connections
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());


-- =====================================================================
-- 3. Intentions d'ordre — la clé de l'idempotence
-- =====================================================================
--
-- L'`id` est généré par le client à l'OUVERTURE du sheet de trade, pas au
-- clic. Un rechargement de page détruit le sheet donc l'intention : il n'y
-- a pas de POST à rejouer. Un double-clic, un double-effet React
-- StrictMode et un retry réseau envoient tous le MÊME id.
--
-- La deuxième barrière est ici : `insert … on conflict (id) do nothing
-- returning *`. C'est la clé primaire Postgres qui arbitre, pas un `if`
-- applicatif. Zéro ligne retournée signifie « quelqu'un est déjà passé »,
-- et on n'appelle pas IBKR.
--
-- La troisième est le `coid`, transmis à IBKR, qui refuse un identifiant
-- client dupliqué dans la journée. C'est aussi la clé qui permet de
-- RETROUVER un ordre chez IBKR quand notre processus est mort entre
-- l'envoi et la réponse (voir la réconciliation, §5).

create table if not exists public.live_order_intents (
  id                uuid primary key,                   -- fourni par le client
  user_id           uuid not null references auth.users(id) on delete cascade,
  broker            text not null default 'ibkr',
  account_id        text not null,

  symbol            text not null references public.securities(symbol),
  conid             bigint,                             -- figé à la soumission
  side              text not null check (side in ('buy', 'sell')),
  order_type        text not null default 'MKT' check (order_type in ('MKT', 'LMT')),
  tif               text not null default 'DAY' check (tif in ('DAY', 'GTC')),

  -- Ce que l'utilisateur a demandé…
  requested_amount_cents bigint,
  requested_quantity     numeric(18,8),
  limit_price_cents      bigint,
  -- …et le prix qu'il avait SOUS LES YEUX. Sert au contrôle de dérive :
  -- on ne passe pas un ordre sur un prix qu'il n'a pas vu (KR062).
  seen_price_cents       bigint not null,
  seen_price_at          timestamptz not null,

  -- `coid` transmis à IBKR : 'krz-' + 12 caractères. Longueur et jeu de
  -- caractères admis varient selon le build de la passerelle.
  coid              text not null unique,

  status            text not null default 'created'
                    check (status in ('created', 'submitting', 'awaiting_confirmation',
                                      'submitted', 'partially_filled', 'filled',
                                      'cancelled', 'rejected', 'failed')),
  ibkr_order_id     text,
  reply_id          text,
  questions         jsonb,

  filled_quantity   numeric(18,8) not null default 0,
  avg_price_cents   bigint,

  -- Quand un ordre réel tourne mal, c'est la seule question qui compte :
  -- qu'a-t-on envoyé, qu'a-t-on reçu.
  request_payload   jsonb,
  last_response     jsonb,
  reject_reason     text,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists live_order_intents_user_created_idx
  on public.live_order_intents (user_id, created_at desc);

-- La réconciliation balaie ces deux états : un intent bloqué là depuis
-- plus de deux minutes est un ordre potentiellement parti chez IBKR sans
-- trace locale de son sort.
create index if not exists live_order_intents_in_flight_idx
  on public.live_order_intents (updated_at)
  where status in ('submitting', 'awaiting_confirmation');

alter table public.live_order_intents enable row level security;

-- Lecture seule côté client. Toute écriture passe par le route handler
-- serveur en service role : un ordre réel ne s'écrit pas depuis un
-- navigateur, même avec la bonne RLS.
create policy "live_order_intents read own" on public.live_order_intents
  for select to authenticated
  using (user_id = auth.uid());


-- =====================================================================
-- 4. Journal d'événements — append-only
-- =====================================================================
--
-- Une ligne par transition. C'est la trace d'audit, et c'est aussi la
-- preuve d'idempotence TESTABLE :
--
--   select count(*) from live_order_events
--    where intent_id = $1 and kind = 'ibkr_submit';   -- doit valoir 1
--
-- Écriture service role uniquement (aucune policy d'insert), lecture
-- propriétaire.

create table if not exists public.live_order_events (
  id         bigserial primary key,
  intent_id  uuid not null references public.live_order_intents(id) on delete cascade,
  kind       text not null check (kind in (
               'created', 'drift_check_ok', 'drift_check_failed',
               'contract_check_ok', 'contract_check_failed',
               'ibkr_submit', 'ibkr_question', 'user_confirmed',
               'ibkr_accepted', 'filled', 'cancelled', 'rejected',
               'reconciled', 'failed')),
  payload    jsonb,
  at         timestamptz not null default now()
);

create index if not exists live_order_events_intent_idx
  on public.live_order_events (intent_id, at);

alter table public.live_order_events enable row level security;

create policy "live_order_events read own" on public.live_order_events
  for select to authenticated
  using (exists (
    select 1 from public.live_order_intents i
    where i.id = live_order_events.intent_id
      and i.user_id = auth.uid()
  ));


-- =====================================================================
-- 5. Horodatage
-- =====================================================================

create or replace function public.touch_live_order_intent()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists live_order_intents_touch on public.live_order_intents;
create trigger live_order_intents_touch
  before update on public.live_order_intents
  for each row execute function public.touch_live_order_intent();


-- =====================================================================
-- 6. Lecture : les titres négociables en réel
-- =====================================================================
--
-- Un conid non nul ne suffit pas — il faut aussi que l'empreinte de
-- contrat ait été vérifiée. Cette vue est ce que l'UI consulte pour
-- décider si le bouton « Acheter — argent réel » est actif.

create or replace view public.v_live_tradable as
select
  s.symbol,
  s.name,
  s.isin,
  s.ibkr_conid,
  s.ibkr_exchange,
  s.ibkr_currency,
  s.currency,
  s.mic,
  (s.ibkr_conid is not null
   and s.ibkr_contract_fingerprint is not null
   and s.ibkr_checked_at is not null) as is_tradable_live
from public.securities s;

comment on view public.v_live_tradable is
  'Négociabilité en mode réel. is_tradable_live = false ⇒ KR061 côté serveur '
  'et bouton désactivé côté UI. Aucun repli sur une recherche de contrat.';

grant select on public.v_live_tradable to authenticated;
