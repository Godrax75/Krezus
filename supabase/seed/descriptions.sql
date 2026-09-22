-- =====================================================================
-- Fiches « Que fait l'entreprise ? »
--
-- Fichier GÉNÉRÉ par tools/build_fiches.py — ne pas éditer à la main.
-- Source : premier paragraphe de l'article Wikipédia de chaque société,
-- condensé en deux phrases par langue. Aucun fait n'est ajouté à ce que
-- l'article dit.
--
-- Les fiches rédigées à la main ne sont pas écrasées.
-- =====================================================================

update public.securities s set
  description_fr = coalesce(nullif(s.description_fr, ''), v.fr),
  description_en = coalesce(nullif(s.description_en, ''), v.en)
from (values
  ('EBAY', 'eBay est une plateforme de commerce électronique qui permet aux individus, aux entreprises et aux gouvernements d''acheter et de vendre des articles via des enchères ou des ventes instantanées. En 2023, la plateforme a traité 73 milliards de dollars de transactions avec 132 millions d''acheteurs actifs annuels dans 190 marchés mondiaux.', 'eBay is an e-commerce platform that allows individuals, companies and governments to buy and sell items through online auctions or instant sales. In 2023, the platform processed $73 billion in transactions with 132 million annual active buyers across 190 markets worldwide.')
) as v(symbol, fr, en)
where s.symbol = v.symbol;
