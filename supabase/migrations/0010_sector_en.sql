-- =====================================================================
-- Lot 10 (suite) — libellé de secteur en anglais.
--
-- `securities.sector` reste la donnée de référence, en français : le
-- regroupement du portefeuille (`TradingStore.groupOf`) s'appuie dessus, et
-- les vues sectorielles de l'Oracle (`v_sector_fundamentals`) agrègent sur
-- cette colonne. La traduction est un libellé d'affichage, donc une colonne
-- à part — exactement le couple `description_fr` / `description_en`.
--
-- `NULL` = pas encore traduit : le client retombe sur le français plutôt que
-- d'afficher un blanc (voir `StockInfo.sectorLocalized`).
-- =====================================================================

alter table public.securities add column if not exists sector_en text;

comment on column public.securities.sector is
  'Secteur en français — DONNÉE de référence : sert au regroupement du '
  'portefeuille et aux médianes sectorielles. Ne pas traduire cette colonne.';
comment on column public.securities.sector_en is
  'Libellé de secteur en anglais — AFFICHAGE seul. NULL = repli sur `sector`.';
