-- =====================================================================
-- Lot 3 — Données de marché : conversion de devise et traçabilité du cache.
--
-- Le moteur d'ordres (0002) calcule les parts avec `quotes_cache.price`
-- interprété comme des EUROS (« parts = montant(€) / prix »). Or 12 des 82
-- titres du référentiel cotent en USD. Écrire le cours natif dans `price`
-- ferait acheter 100 € de Nvidia au prix dollar — soit ~8 % de parts en trop.
--
-- Règle posée ici : `price` est TOUJOURS la devise de compte du portefeuille
-- (EUR). Le cours natif et le taux appliqué sont conservés à côté, pour
-- l'affichage (« 165,30 $ ») et pour l'audit d'un ordre passé.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Taux de change (alimenté par la Edge Function `quotes`, paire EURUSD.FOREX)
-- ---------------------------------------------------------------------
create table public.fx_rates (
  pair        text primary key,                    -- 'EURUSD' = USD pour 1 EUR
  rate        numeric not null check (rate > 0),
  fetched_at  timestamptz not null default now()
);

comment on table public.fx_rates is
  'Taux de change différés (EODHD FOREX). `rate` = unités de la devise cotée pour 1 EUR.';

alter table public.fx_rates enable row level security;
create policy "fx readable" on public.fx_rates
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- Cache de cotations : cours natif + taux appliqué
-- ---------------------------------------------------------------------
alter table public.quotes_cache
  add column price_native   numeric,               -- cours dans la devise de cotation
  add column currency       text not null default 'EUR',
  add column fx_rate        numeric not null default 1,  -- price_native / fx_rate = price
  add column previous_close numeric,
  add column quoted_at      timestamptz;           -- horodatage marché (≠ fetched_at)

comment on column public.quotes_cache.price is
  'Cours converti en EUR (devise de compte). C''est CETTE colonne que lit execute_paper_order.';
comment on column public.quotes_cache.price_native is
  'Cours dans la devise de cotation, pour l''affichage. Ex. 165.30 pour NVDA en USD.';
comment on column public.quotes_cache.fx_rate is
  'Taux appliqué au moment du fetch : price = price_native / fx_rate. 1 pour les titres EUR.';
comment on column public.quotes_cache.quoted_at is
  'Horodatage de la cotation chez EODHD. `fetched_at` date notre écriture ; l''écart entre '
  'les deux doit rester cohérent avec le différé de 15 min imposé par la licence.';

-- Backfill des lignes existantes (toutes réputées EUR avant ce lot).
update public.quotes_cache set price_native = price where price_native is null;

-- Un écrivain qui ignore `price_native` (test SQL, correction manuelle) reste
-- valide : la colonne se remplit depuis `price`, ce qui est exact tant qu'on
-- est en euros. Évite d'imposer la connaissance du FX à tout appelant.
create or replace function public.quotes_cache_fill_native()
returns trigger
language plpgsql
as $$
begin
  if new.price_native is null then
    new.price_native := new.price;
  end if;
  return new;
end;
$$;

create trigger quotes_cache_fill_native_trg
  before insert or update on public.quotes_cache
  for each row execute function public.quotes_cache_fill_native();

alter table public.quotes_cache alter column price_native set not null;

-- Garde-fou sur le seul cas dangereux : un titre coté en devise étrangère dont
-- `price` ne serait pas la conversion de `price_native`. C'est exactement la
-- forme qu'aurait le bug « on a écrit le cours dollar dans la colonne euro » —
-- un achat de 100 € de Nvidia sortirait alors ~8 % de parts en trop.
-- Les lignes en euros sont exclues : `price` y fait foi et `price_native` n'est
-- qu'un miroir, que rien n'oblige à mettre à jour en même temps.
alter table public.quotes_cache add constraint quotes_cache_fx_coherent
  check (
    currency = 'EUR'
    or abs(price - price_native / fx_rate) <= greatest(price * 0.005, 0.01)
  );

-- ---------------------------------------------------------------------
-- Historique : les courbes tirent toujours les N derniers points d'un titre
-- ---------------------------------------------------------------------
create index if not exists price_history_symbol_date_desc
  on public.price_history (symbol, date desc);

-- L'historique est stocké dans la devise de cotation (source EODHD brute) ;
-- la conversion d'affichage se fait côté client avec le taux courant.
comment on table public.price_history is
  'Clôtures quotidiennes en devise de cotation (non converties). Source : EODHD /api/eod.';

-- ---------------------------------------------------------------------
-- Observabilité : chaque passage de la Edge Function laisse une trace.
-- Sert à vérifier le point 6 du plan (40 symboles en un appel, différé 15 min).
-- ---------------------------------------------------------------------
create table public.market_data_runs (
  id           bigint generated always as identity primary key,
  function     text not null,                      -- 'quotes' | 'history'
  started_at   timestamptz not null default now(),
  duration_ms  integer,
  symbols      integer,                            -- symboles demandés
  upserted     integer,                            -- lignes écrites
  api_calls    integer,                            -- appels EODHD consommés
  session      text,                               -- 'euronext' | 'us' | 'both' | 'closed'
  error        text
);

create index on public.market_data_runs (started_at desc);

alter table public.market_data_runs enable row level security;
-- Pas de policy : lecture réservée au service role (tableau de bord interne).

comment on table public.market_data_runs is
  'Journal des rafraîchissements de cache. Quota EODHD : 100 000 appels/jour, 1 000/min.';
