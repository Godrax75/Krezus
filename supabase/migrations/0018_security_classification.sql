-- =====================================================================
-- Classification des titres : famille de secteur et zone géographique.
--
-- `sector` est trop fin pour trier ou regrouper : 45 libellés pour
-- 51 actions, et « Luxe », « Luxe-mode », « Luxe-maroquinerie » y sont
-- trois cases. L'app retombait sur des mots-clés — « gaz » rangeait Air
-- Liquide en Énergie, et tout le reste en Industrie, Danone, Sanofi et
-- Visa compris. La répartition du portefeuille en était faussée.
--
-- `sector_group` : une famille parmi treize, stable, que l'app traduit.
-- Les trois dernières n'ont de sens que pour les ETF.
--
-- `region` : la zone d'exposition. Pour un ETF, `country_code` est le pays
-- de domiciliation — un ETF irlandais peut suivre le S&P 500 —, donc sans
-- valeur pour dire où l'on investit. La zone est fixée ici, titre par titre.
-- =====================================================================

alter table public.securities
  add column if not exists sector_group text,
  add column if not exists region       text;

alter table public.securities drop constraint if exists securities_sector_group_check;
alter table public.securities add constraint securities_sector_group_check
  check (sector_group in ('technology', 'finance', 'consumer', 'industry', 'energy',
                          'health', 'auto', 'materials', 'telecom', 'realestate',
                          'broad', 'bonds', 'commodities'));

alter table public.securities drop constraint if exists securities_region_check;
alter table public.securities add constraint securities_region_check
  check (region in ('fr', 'europe', 'us', 'asia_em', 'world'));

comment on column public.securities.sector_group is
  'Famille de secteur (clé stable, traduite par l''app). Sert au tri du marché et à la répartition du portefeuille.';
comment on column public.securities.region is
  'Zone d''exposition. Pour un ETF, la zone où il investit, pas son pays de domiciliation.';

-- Actions ------------------------------------------------------------------

update public.securities set sector_group = v.g
from (values
  ('AAPL', 'technology'), ('MSFT', 'technology'), ('GOOG', 'technology'), ('NVDA', 'technology'),
  ('STM', 'technology'), ('CAPG', 'technology'), ('DSY', 'technology'),
  ('JPM', 'finance'), ('WFC', 'finance'), ('BAC', 'finance'), ('GLE', 'finance'), ('BNP', 'finance'),
  ('CS', 'finance'), ('BRKB', 'finance'), ('V', 'finance'), ('MA', 'finance'), ('ENX', 'finance'),
  ('MC', 'consumer'), ('RMS', 'consumer'), ('KER', 'consumer'), ('OREAL', 'consumer'), ('RI', 'consumer'),
  ('BN', 'consumer'), ('CARR', 'consumer'), ('AC', 'consumer'), ('AMZN', 'consumer'),
  ('SAF', 'industry'), ('AIRB', 'industry'), ('HO', 'industry'), ('SU', 'industry'), ('LR', 'industry'),
  ('FGR', 'industry'), ('DG', 'industry'), ('BOUY', 'industry'), ('BVI', 'industry'),
  ('TTE', 'energy'), ('ENGI', 'energy'), ('VIE', 'energy'),
  ('SAN', 'health'), ('EFX', 'health'), ('ERF', 'health'),
  ('RNO', 'auto'), ('STLA', 'auto'), ('TSLA', 'auto'), ('ML', 'auto'),
  ('AI', 'materials'), ('SGO', 'materials'), ('MT', 'materials'),
  ('ORAN', 'telecom'), ('PUB', 'telecom'),
  ('URW', 'realestate')
) as v(symbol, g)
where securities.symbol = v.symbol;

-- Les actions : la zone suit le pays du siège.
update public.securities
set region = case country_code
               when 'FR' then 'fr'
               when 'US' then 'us'
               else 'europe'
             end
where asset_type = 'stock';

-- ETF ----------------------------------------------------------------------

update public.securities set sector_group = v.g, region = v.r
from (values
  ('ETFWLD', 'broad', 'world'),     ('ETF500', 'broad', 'us'),        ('ETFEU', 'broad', 'europe'),
  ('ETFCAC', 'broad', 'fr'),        ('ETFDAX', 'broad', 'europe'),    ('ETFUK', 'broad', 'europe'),
  ('ETFNKY', 'broad', 'asia_em'),   ('ETFCHN', 'broad', 'asia_em'),   ('ETFIND', 'broad', 'asia_em'),
  ('ETFEM', 'broad', 'asia_em'),    ('ETFSCEU', 'broad', 'europe'),   ('ETFESG', 'broad', 'world'),
  ('ETFDIV', 'broad', 'world'),
  ('ETFNAS', 'technology', 'us'),   ('ETFSEMI', 'technology', 'world'),
  ('ETFROBO', 'technology', 'world'), ('ETFCYBR', 'technology', 'world'),
  ('ETFBIO', 'health', 'us'),       ('ETFHLTH', 'health', 'world'),
  ('ETFDEF', 'industry', 'world'),  ('ETFINFRA', 'industry', 'world'),
  ('ETFNRG', 'energy', 'world'),    ('ETFWTR', 'energy', 'world'),
  ('ETFREIT', 'realestate', 'world'),
  ('ETFLUX', 'consumer', 'world'),
  ('ETFCORP', 'bonds', 'europe'),   ('ETFBND', 'bonds', 'us'),
  ('ETFGLD', 'commodities', 'world'), ('ETFSLV', 'commodities', 'world'),
  ('ETFAGRI', 'commodities', 'world')
) as v(symbol, g, r)
where securities.symbol = v.symbol;
