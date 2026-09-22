-- =====================================================================
-- Rendement du dividende, sur les douze derniers mois.
--
-- Fichier GÉNÉRÉ par tools/build_dividends.py — ne pas éditer à la main.
-- Somme des dividendes versés sur un an, rapportée au cours du jour.
-- Un titre absent de la liste n'a rien versé sur la période : sa fiche
-- affiche « — », ce qui est la vérité, et non un rendement de zéro.
-- =====================================================================

update public.securities s set dividend_yield = v.yield
from (values
  ('0001', 3.48),
  ('0002', 4.11),
  ('0003', 4.93),
  ('0006', 4.67),
  ('0012', 4.77),
  ('0016', 3.46),
  ('0027', 7.48),
  ('0066', 3.98),
  ('0101', 7.93),
  ('0175', 3.18),
  ('0241', 2.41),
  ('0267', 6.85)
) as v(symbol, yield)
where s.symbol = v.symbol;
