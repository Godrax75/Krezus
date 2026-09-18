-- =====================================================================
-- Données de la courbe du portefeuille.
--
-- `portfolio_snapshots` existe depuis 0001 mais rien ne l'alimente. Plutôt
-- que de l'écrire chaque soir pour chaque utilisateur, l'app reconstitue la
-- valeur passée à partir de ce qui existe déjà : ses ordres (quantités et
-- montants datés) et les clôtures de `price_history`. La reconstitution est
-- rétroactive — elle couvre aussi les jours écoulés avant cette migration.
--
-- Il manque deux séries, que cette migration ajoute :
--
--   fx_history      Les clôtures sont en devise de cotation. Convertir un
--                   titre américain d'il y a six mois au taux du jour
--                   ferait bouger la courbe au gré du dollar d'aujourd'hui.
--                   Alimentée par la fonction `history` (EURUSD.FOREX).
--
--   price_intraday  Un point par titre à chaque passage de `quotes`, déjà
--                   converti en euros comme `quotes_cache.price`. Il sert la
--                   vue « 1 jour » ; au-delà de quatre jours, la fonction
--                   l'élague — le quotidien prend le relais.
-- =====================================================================

create table if not exists public.fx_history (
  pair  text    not null,                               -- 'EURUSD' = USD pour 1 EUR
  date  date    not null,
  rate  numeric not null check (rate > 0),
  primary key (pair, date)
);

comment on table public.fx_history is
  'Clôtures quotidiennes des paires de change (EODHD FOREX). `rate` = unités de la devise cotée pour 1 EUR.';

alter table public.fx_history enable row level security;
drop policy if exists "fx history readable" on public.fx_history;
create policy "fx history readable" on public.fx_history
  for select to authenticated using (true);

create table if not exists public.price_intraday (
  symbol  text        not null references public.securities(symbol) on delete cascade,
  ts      timestamptz not null,
  price   numeric     not null check (price > 0),       -- en euros, comme quotes_cache.price
  primary key (symbol, ts)
);

create index if not exists price_intraday_ts on public.price_intraday (ts);

comment on table public.price_intraday is
  'Cours en euros relevés à chaque passage de la fonction `quotes`. Élagué au-delà de 4 jours.';

alter table public.price_intraday enable row level security;
drop policy if exists "intraday readable" on public.price_intraday;
create policy "intraday readable" on public.price_intraday
  for select to authenticated using (true);
