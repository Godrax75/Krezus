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
  ('0001', 'CK Hutchison Holdings est un conglomérat basé à Hong Kong qui opère dans quatre domaines : les ports et services connexes, le commerce de détail, les infrastructures et les télécommunications. L''entreprise exerce ses activités dans plus de 50 pays et détient plusieurs autres investissements à travers le monde.', 'CK Hutchison Holdings is a Hong Kong-based conglomerate operating in four core businesses: ports and related services, retail, infrastructure, and telecommunications. The company operates in over 50 countries and holds several other investments worldwide.'),
  ('0002', 'CLP Holdings produit et distribue l''électricité à Hong Kong et en Asie, via sa filiale CLP Power Hong Kong ainsi que d''autres activités régionales. Elle opère aussi EnergyAustralia en Australie.', 'CLP Holdings generates, transmits, and retails electricity in Hong Kong and across Asian markets, including through its subsidiary CLP Power Hong Kong and EnergyAustralia in Australia.'),
  ('0003', 'Hong Kong and China Gas Company Limited, qui opère sous la marque Towngas, fournit le gaz de ville à Hong Kong. Fondée en 1862, elle est le seul distributeur de gaz de ville sur tout le territoire.', 'Hong Kong and China Gas Company Limited, trading as Towngas, is the sole provider of town gas across Hong Kong. Founded in 1862, it is one of the oldest listed companies in the territory.'),
  ('0006', 'Power Assets Holdings Limited produit et distribue de l''électricité, notamment via sa participation majoritaire dans la Hongkong Electric Company. Le groupe détient également des participations significatives dans plusieurs fournisseurs et réseaux d''énergie dans le monde, en partenariat avec sa maison mère Cheung Kong Infrastructure Holdings.', 'Power Assets Holdings Limited generates and distributes electricity, notably through its majority stake in the Hongkong Electric Company. The group also holds significant interests in various energy providers and networks worldwide, in partnership with its parent company Cheung Kong Infrastructure Holdings, which owns 38.87% of the business.'),
  ('0012', 'Henderson Land Development est un promoteur immobilier hongkongais. Elle développe, construit et gère des immeubles résidentiels et commerciaux, ainsi que des hôtels et des grands magasins, et elle est l''une des trois plus grandes sociétés de ce secteur à Hong Kong.', 'Henderson Land Development is a Hong Kong property developer. It develops, constructs and operates residential and commercial buildings, hotels and department stores, and ranks among the three largest real estate companies in Hong Kong.'),
  ('0016', 'Sun Hung Kai Properties Limited développe et vend des immeubles à Hong Kong. Elle loue aussi des propriétés, exploite des hôtels, et propose des services de télécommunications et de logistique.', 'Sun Hung Kai Properties Limited develops and sells buildings in Hong Kong. The company also rents properties, operates hotels, and provides telecommunications and logistics services.')
) as v(symbol, fr, en)
where s.symbol = v.symbol;
