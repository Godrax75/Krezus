-- =====================================================================
-- 0023 — Les services aux collectivités deviennent une famille à part.
--
-- L'entrée du S&P 500 a amené une cinquantaine d'électriciens, de
-- distributeurs d'eau et de gaz, rangés faute de mieux avec le pétrole.
-- Un producteur d'électricité régulé et une major pétrolière ne réagissent
-- pas au même choc : la répartition d'un portefeuille doit les distinguer.
-- =====================================================================

alter table public.securities drop constraint if exists securities_sector_group_check;
alter table public.securities add constraint securities_sector_group_check
  check (sector_group = any (array['technology', 'finance', 'consumer', 'industry',
                                   'energy', 'utilities', 'health', 'auto', 'materials',
                                   'telecom', 'realestate', 'broad', 'bonds', 'commodities']));

update public.securities
set sector_group = 'utilities'
where sector_group = 'energy'
  and (sector = 'Services aux collectivités'
       or sector_en = 'Utilities'
       or sector in ('Environnement-eau', 'Énergie-services'));
