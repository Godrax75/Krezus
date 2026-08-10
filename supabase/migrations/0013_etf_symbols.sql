-- =====================================================================
-- Cartographie EODHD des ETF du référentiel.
--
-- Les 30 ETF du seed avaient `eodhd_symbol` à NULL : ils s'affichaient dans
-- Explorer sans cours, et tout ordre les concernant aurait été rejeté faute de
-- cotation. Le commentaire du seed annonçait « tickers réels à vérifier contre
-- Euronext avant activation » — c'est fait ici.
--
-- Méthode : recherche de chaque libellé dans le référentiel EODHD, puis appel
-- temps réel pour confirmer que le symbole renvoie bien un cours. Seuls les
-- fonds dont le nom correspond **sans ambiguïté** sont retenus.
--
-- Les 14 autres restent volontairement NULL. Deux cas :
--
--   * aucun candidat coté en euros sur une place européenne (ETFAGRI, ETFBND,
--     ETFEU, ETFHLTH, ETFNKY, ETFREIT, ETFSCEU) ;
--   * un candidat proche mais qui désigne un **autre produit** : « MSCI China
--     Tech » pour ETFCHN, « Euro Corporate Bond Sustainability » pour ETFCORP,
--     la variante IMI pour ETFEM, « Core Physical Gold » pour ETFGLD.
--
-- Écrire ces symboles-là afficherait le cours d'un fonds sous le nom d'un
-- autre. Un cours absent se voit ; un cours faux, non.
--
-- ETFSLV avait un candidat exact (VZLC.XETRA) qui ne renvoie aucun cours : il
-- reste NULL lui aussi.
-- =====================================================================

update public.securities set eodhd_symbol = v.code
from (values
  ('ETF500',   'PE500.PA'),    -- Amundi PEA S&P 500
  ('ETFCAC',   'CAC.PA'),      -- Amundi CAC 40
  ('ETFWLD',   'CW8.PA'),      -- Amundi MSCI World
  ('ETFLUX',   'GLUX.PA'),     -- Amundi S&P Global Luxury
  ('ETFWTR',   'WAT.PA'),      -- Lyxor World Water
  ('ETFESG',   'MWOP.XETRA'),  -- Amundi MSCI World ESG Leaders
  ('ETFNAS',   'EQQQ.XETRA'),  -- Invesco EQQQ NASDAQ-100
  ('ETFDAX',   'DBXD.XETRA'),  -- Xtrackers DAX
  ('ETFCYBR',  'USPY.XETRA'),  -- L&G Cyber Security
  ('ETFDEF',   'DFEN.XETRA'),  -- VanEck Defense
  ('ETFSEMI',  'VVSM.XETRA'),  -- VanEck Semiconductor
  ('ETFROBO',  '2B76.XETRA'),  -- iShares Automation & Robotics
  ('ETFNRG',   'IQQH.XETRA'),  -- iShares Global Clean Energy
  ('ETFIND',   'QDV5.XETRA'),  -- iShares MSCI India
  ('ETFINFRA', 'IQQI.XETRA'),  -- iShares Global Infrastructure
  ('ETFDIV',   'VGWD.XETRA')   -- Vanguard FTSE All-World High Dividend Yield
) as v(symbol, code)
where public.securities.symbol = v.symbol;
