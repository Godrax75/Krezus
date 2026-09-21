-- =====================================================================
-- 0022 — Logo distant des titres.
--
-- `logo_asset` désigne une image embarquée dans l'app : cela tenait avec
-- quelques dizaines de valeurs, pas avec les 500 du S&P 500. Les logos
-- des nouveaux titres sont servis par une URL publique (Wikimedia
-- Commons pour les marques du domaine public, EODHD sinon), chargée et
-- mise en cache par l'app. Sans logo, les initiales restent le repli.
-- =====================================================================

alter table public.securities
  add column if not exists logo_url text;

comment on column public.securities.logo_url is
  'URL publique du logo. Ne sert que d''illustration : un titre sans logo '
  'affiche ses initiales.';
