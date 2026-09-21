-- =====================================================================
-- Les sociétés du SBF 120.
--
-- Fichier GÉNÉRÉ par tools/build_index_seed.py — ne pas éditer à la
-- main. Composition : Wikipédia. ISIN et secteur d'activité :
-- Wikidata. Mnémonique et devise : EODHD. Logos : Wikimedia Commons
-- (domaine public ou marque déposée) ou EODHD.
--
-- Rejouable : les fiches déjà rédigées ne sont pas écrasées, seul leur
-- logo est complété.
-- =====================================================================

insert into public.securities
  (symbol, eodhd_symbol, currency, asset_type, name, country_code, country,
   sector, sector_en, sector_group, region, initials, logo_url)
values
  ('ADP.PA', 'ADP.PA', 'EUR', 'stock', 'ADP', 'FR', 'France', 'Centre de services aéronautiques', 'Fixed-base operator', 'industry', 'fr', 'AD', 'https://commons.wikimedia.org/wiki/Special:FilePath/Groupe_ADP.svg?width=160'),
  ('AF', 'AF.PA', 'EUR', 'stock', 'Air France-KLM', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'AI', 'https://commons.wikimedia.org/wiki/Special:FilePath/Air_France_KLM_Group_logo.svg?width=160'),
  ('ALO', 'ALO.PA', 'EUR', 'stock', 'Alstom', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'AL', 'https://commons.wikimedia.org/wiki/Special:FilePath/Alstom_logo.svg?width=160'),
  ('ATE', 'ATE.PA', 'EUR', 'stock', 'Alten', 'FR', 'France', 'Ingénierie', 'Engineering', 'industry', 'fr', 'AL', 'https://commons.wikimedia.org/wiki/Special:FilePath/ALTEN-Logo.svg?width=160'),
  ('AMUN', 'AMUN.PA', 'EUR', 'stock', 'Amundi', 'FR', 'France', 'Service financier', 'Financial services', 'finance', 'fr', 'AM', 'https://commons.wikimedia.org/wiki/Special:FilePath/Amundi_logo.svg?width=160'),
  ('APAM', 'APAM.AS', 'EUR', 'stock', 'Aperam', 'NL', 'Pays-Bas', 'Sidérurgie', 'Iron and steel industry', 'materials', 'europe', 'AP', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_aperam_2026.png?width=160'),
  ('ARG', 'ARG.PA', 'EUR', 'stock', 'Argan', 'FR', 'France', 'Immobilier logistique', 'Logistics property', 'realestate', 'fr', 'AR', null),
  ('AKE', 'AKE.PA', 'EUR', 'stock', 'Arkema', 'FR', 'France', 'Industrie chimique', 'Chemical industry', 'materials', 'fr', 'AR', 'https://commons.wikimedia.org/wiki/Special:FilePath/Arkema.svg?width=160'),
  ('ATO.PA', 'ATO.PA', 'EUR', 'stock', 'Atos', 'FR', 'France', 'Gestion des services informatiques', 'IT service management', 'technology', 'fr', 'AT', null),
  ('AYV', 'AYV.PA', 'EUR', 'stock', 'Ayvens', 'FR', 'France', 'Location longue durée', 'Vehicle leasing', 'finance', 'fr', 'AY', 'https://commons.wikimedia.org/wiki/Special:FilePath/Ayvens_Logo_2024.svg?width=160'),
  ('BB', 'BB.PA', 'EUR', 'stock', 'Bic', 'FR', 'France', 'Consommation', 'Consumer', 'consumer', 'fr', 'BI', 'https://commons.wikimedia.org/wiki/Special:FilePath/Bic_logo.svg?width=160'),
  ('BIM', 'BIM.PA', 'EUR', 'stock', 'Biomérieux', 'FR', 'France', 'Fabrication de préparations pharmaceutiques', null, 'health', 'fr', 'BI', 'https://commons.wikimedia.org/wiki/Special:FilePath/BioM%C3%A9rieux.svg?width=160'),
  ('BOL', 'BOL.PA', 'EUR', 'stock', 'Bolloré', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'BO', null),
  ('CARM', 'CARM.PA', 'EUR', 'stock', 'Carmila', 'FR', 'France', 'Immobilier', 'Real estate', 'realestate', 'fr', 'CA', null),
  ('CLARI', 'CLARI.PA', 'EUR', 'stock', 'Clariane', 'FR', 'France', 'Établissement d''hébergement pour personnes âgées dépendantes', 'Accommodation facility for dependent elderly people', 'industry', 'fr', 'CL', 'https://commons.wikimedia.org/wiki/Special:FilePath/Korian_logo.svg?width=160'),
  ('COFA', 'COFA.PA', 'EUR', 'stock', 'Coface', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'CO', null),
  ('COV', 'COV.PA', 'EUR', 'stock', 'Covivio', 'FR', 'France', 'Immobilier', 'Real estate', 'realestate', 'fr', 'CO', null),
  ('ACA', 'ACA.PA', 'EUR', 'stock', 'Crédit agricole', 'FR', 'France', 'Communication-médias', 'Communication services', 'telecom', 'fr', 'CR', null),
  ('AM', 'AM.PA', 'EUR', 'stock', 'Dassault Aviation', 'FR', 'France', 'Secteur aéronautique et spatial', 'Aerospace industry', 'industry', 'fr', 'DA', 'https://commons.wikimedia.org/wiki/Special:FilePath/Dassault_Aviation_Logo.jpg?width=160'),
  ('DBG', 'DBG.PA', 'EUR', 'stock', 'Derichebourg', 'FR', 'France', 'Récupération de déchets triés', null, 'industry', 'fr', 'DE', null),
  ('EDEN', 'EDEN.PA', 'EUR', 'stock', 'Edenred', 'FR', 'France', 'Finance', 'Financials', 'finance', 'fr', 'ED', 'https://commons.wikimedia.org/wiki/Special:FilePath/Edenred.svg?width=160'),
  ('ELIOR', 'ELIOR.PA', 'EUR', 'stock', 'Elior', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'EL', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_Elior.svg?width=160'),
  ('ELIS', 'ELIS.PA', 'EUR', 'stock', 'Elis', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'EL', null),
  ('EMEIS', 'EMEIS.PA', 'EUR', 'stock', 'Emeis', 'FR', 'France', 'Hébergement médicalisé pour personnes âgées', null, 'health', 'fr', 'EM', 'https://commons.wikimedia.org/wiki/Special:FilePath/Orpea-Gruppe_logo.svg?width=160'),
  ('ERA', 'ERA.PA', 'EUR', 'stock', 'Eramet', 'FR', 'France', 'Matériaux', 'Materials', 'materials', 'fr', 'ER', 'https://commons.wikimedia.org/wiki/Special:FilePath/Eramet_Logotype.png?width=160'),
  ('NAE', 'NAE.PA', 'EUR', 'stock', 'Esso', 'FR', 'France', 'Industrie pétrolière', 'Petroleum industry', 'energy', 'fr', 'ES', 'https://commons.wikimedia.org/wiki/Special:FilePath/Esso_textlogo.svg?width=160'),
  ('RF.PA', 'RF.PA', 'EUR', 'stock', 'Eurazeo', 'FR', 'France', 'Capital-investissement', 'Private equity', 'finance', 'fr', 'EU', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo-eurazeo-version-pour-le-web-format-jpg_popin_img.jpg?width=160'),
  ('FDJU', 'FDJU.PA', 'EUR', 'stock', 'FDJ', 'FR', 'France', 'Jeux d''argent', 'Gaming and lotteries', 'consumer', 'fr', 'FD', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_FDJ.svg?width=160'),
  ('FRVIA', 'FRVIA.PA', 'EUR', 'stock', 'Forvia', 'FR', 'France', 'Construction automobile', 'Automotive industry', 'auto', 'fr', 'FO', 'https://commons.wikimedia.org/wiki/Special:FilePath/Faurecia_logo.svg?width=160'),
  ('GFC', 'GFC.PA', 'EUR', 'stock', 'Gecina', 'FR', 'France', 'Secteur de l''immobilier', 'Real estate industry', 'realestate', 'fr', 'GE', null),
  ('GET', 'GET.PA', 'EUR', 'stock', 'Getlink', 'FR', 'France', 'Transport', 'Transport', 'industry', 'fr', 'GE', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_Getlink_2025.svg?width=160'),
  ('GTT', 'GTT.PA', 'EUR', 'stock', 'GTT', 'FR', 'France', 'Ingénierie', 'Engineering', 'industry', 'fr', 'GT', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_GTT_Gaztransport_Technigaz.svg?width=160'),
  ('ICAD', 'ICAD.PA', 'EUR', 'stock', 'Icade', 'FR', 'France', 'Immobilier', 'Real estate', 'realestate', 'fr', 'IC', null),
  ('IDL', 'IDL.PA', 'EUR', 'stock', 'ID Logistics Group', 'FR', 'France', 'Transport-logistique', 'Transport and logistics', 'industry', 'fr', 'ID', 'https://commons.wikimedia.org/wiki/Special:FilePath/ID_Logistics_logo.svg?width=160'),
  ('NK', 'NK.PA', 'EUR', 'stock', 'Imerys', 'FR', 'France', 'Minéraux industriels', 'Industrial minerals', 'materials', 'fr', 'IM', null),
  ('ITP', 'ITP.PA', 'EUR', 'stock', 'Interparfums', 'FR', 'France', 'Fabrication de parfums et de produits pour la toilette', 'Manufacture of perfumes and toiletries', 'consumer', 'fr', 'IN', null),
  ('IPN', 'IPN.PA', 'EUR', 'stock', 'Ipsen', 'FR', 'France', 'Industrie pharmaceutique', 'Pharmaceutical industry', 'health', 'fr', 'IP', 'https://commons.wikimedia.org/wiki/Special:FilePath/Ipsen_logo.svg?width=160'),
  ('IPS', 'IPS.PA', 'EUR', 'stock', 'Ipsos', 'FR', 'France', 'Étude de marché', 'Market research', 'industry', 'fr', 'IP', null),
  ('DEC', 'DEC.PA', 'EUR', 'stock', 'JCDecaux', 'FR', 'France', 'Régie publicitaire de médias', null, 'telecom', 'fr', 'JC', 'https://commons.wikimedia.org/wiki/Special:FilePath/JCDecaux_logo.svg?width=160'),
  ('LI', 'LI.PA', 'EUR', 'stock', 'Klepierre', 'FR', 'France', 'Secteur de l''immobilier', 'Real estate industry', 'realestate', 'fr', 'KL', 'https://commons.wikimedia.org/wiki/Special:FilePath/Klepierre_logo.jpeg?width=160'),
  ('MAU', 'MAU.PA', 'EUR', 'stock', 'Maurel & Prom', 'FR', 'France', 'Énergie-pétrole', 'Energy and oil', 'energy', 'fr', 'MA', null),
  ('MEDCL', 'MEDCL.PA', 'EUR', 'stock', 'MedinCell', 'FR', 'France', 'Pharmaceutique', 'Pharmaceuticals', 'health', 'fr', 'ME', null),
  ('MERY', 'MERY.PA', 'EUR', 'stock', 'Mercialys', 'FR', 'France', 'Immobilier', 'Real estate', 'realestate', 'fr', 'ME', null),
  ('MRN', 'MRN.PA', 'EUR', 'stock', 'Mersen', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'ME', 'https://commons.wikimedia.org/wiki/Special:FilePath/Mersen_logo.svg?width=160'),
  ('NEX', 'NEX.PA', 'EUR', 'stock', 'Nexans', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'NE', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_Nexans.svg?width=160'),
  ('NXI', 'NXI.PA', 'EUR', 'stock', 'Nexity', 'FR', 'France', 'Promotion immobilière', 'Real estate development', 'realestate', 'fr', 'NE', null),
  ('OPM', 'OPM.PA', 'EUR', 'stock', 'OPmobility', 'FR', 'France', 'Équipementier automobile', 'Automotive supplier', 'auto', 'fr', 'OP', 'https://commons.wikimedia.org/wiki/Special:FilePath/Plastic_Omnium.svg?width=160'),
  ('PLNW', 'PLNW.PA', 'EUR', 'stock', 'Planisware', 'FR', 'France', 'Technologie de l''information', 'Information technology', 'technology', 'fr', 'PL', 'https://commons.wikimedia.org/wiki/Special:FilePath/Planisware_logo.svg?width=160'),
  ('PLX', 'PLX.PA', 'EUR', 'stock', 'Pluxee', 'FR', 'France', 'Services aux salariés', 'Employee benefits', 'finance', 'fr', 'PL', 'https://commons.wikimedia.org/wiki/Special:FilePath/Sodexo_logo.svg?width=160'),
  ('RCO', 'RCO.PA', 'EUR', 'stock', 'Remy Cointreau', 'FR', 'France', 'Boissons-spiritueux', 'Drinks and spirits', 'consumer', 'fr', 'RE', 'https://commons.wikimedia.org/wiki/Special:FilePath/R%C3%A9my_Cointreau_logo.svg?width=160'),
  ('RXL', 'RXL.PA', 'EUR', 'stock', 'Rexel', 'FR', 'France', 'Distribution professionnelle', 'Industrial distribution', 'industry', 'fr', 'RE', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo-rexel.svg?width=160'),
  ('RBT', 'RBT.PA', 'EUR', 'stock', 'Robertet', 'FR', 'France', 'Arômes et parfums', 'Flavours and fragrances', 'materials', 'fr', 'RO', 'https://commons.wikimedia.org/wiki/Special:FilePath/Robertet_logo.svg?width=160'),
  ('RUI', 'RUI.PA', 'EUR', 'stock', 'Rubis', 'FR', 'France', 'Industrie pétrolière', 'Petroleum industry', 'energy', 'fr', 'RU', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_de_Rubis.svg?width=160'),
  ('SK', 'SK.PA', 'EUR', 'stock', 'SEB', 'FR', 'France', 'Électroménager', 'Home appliances', 'consumer', 'fr', 'SE', null),
  ('DIM', 'DIM.PA', 'EUR', 'stock', 'Sartorius Stedim Biotech', 'FR', 'France', 'Industrie pharmaceutique', 'Pharmaceutical industry', 'health', 'fr', 'SA', 'https://commons.wikimedia.org/wiki/Special:FilePath/Sartorius.svg?width=160'),
  ('SCR', 'SCR.PA', 'EUR', 'stock', 'Scor SE', 'FR', 'France', 'Réassurance', null, 'finance', 'fr', 'SC', 'https://commons.wikimedia.org/wiki/Special:FilePath/Scor.svg?width=160'),
  ('SESG', 'SESG.PA', 'EUR', 'stock', 'SES', 'FR', 'France', 'Télécommunications', 'Telecommunications industry', 'telecom', 'fr', 'SE', 'https://commons.wikimedia.org/wiki/Special:FilePath/SES_S.A._logo.svg?width=160'),
  ('SW.PA', 'SW.PA', 'EUR', 'stock', 'Sodexo', 'FR', 'France', 'Restauration collective sous contrat', null, 'consumer', 'fr', 'SO', 'https://commons.wikimedia.org/wiki/Special:FilePath/Sodexo_logo.svg?width=160'),
  ('SOI', 'SOI.PA', 'EUR', 'stock', 'Soitec', 'FR', 'France', 'Fabrication de composants électroniques', 'Manufacture of electronic components', 'technology', 'fr', 'SO', null),
  ('SOLB', 'SOLB.BR', 'EUR', 'stock', 'Solvay', 'BE', 'Belgique', 'Industrie chimique', 'Chemical industry', 'materials', 'europe', 'SO', 'https://commons.wikimedia.org/wiki/Special:FilePath/Solvay_Logo_2023.svg?width=160'),
  ('SOP', 'SOP.PA', 'EUR', 'stock', 'Sopra Steria', 'FR', 'France', 'Conseil en systèmes et logiciels informatiques', 'IT systems and software consulting', 'technology', 'fr', 'SO', 'https://commons.wikimedia.org/wiki/Special:FilePath/Sopra_Steria_logo.svg?width=160'),
  ('SPIE', 'SPIE.PA', 'EUR', 'stock', 'Spie', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'SP', 'https://commons.wikimedia.org/wiki/Special:FilePath/SPIE_%28Unternehmen%29_logo.svg?width=160'),
  ('TE', 'TE.PA', 'EUR', 'stock', 'Technip Energies', 'FR', 'France', 'Ingénierie · Énergie', 'Engineering · Energy', 'energy', 'fr', 'TE', null),
  ('TEP', 'TEP.PA', 'EUR', 'stock', 'Teleperformance', 'FR', 'France', 'Services aux entreprises', 'Business services', 'industry', 'fr', 'TE', 'https://commons.wikimedia.org/wiki/Special:FilePath/Teleperformance_logo.svg?width=160'),
  ('TFI', 'TFI.PA', 'EUR', 'stock', 'TF1', 'FR', 'France', 'Médias-audiovisuel', 'Media and broadcasting', 'telecom', 'fr', 'TF', null),
  ('TRI', 'TRI.PA', 'EUR', 'stock', 'Trigano', 'FR', 'France', 'Véhicules de loisirs', 'Leisure vehicles', 'consumer', 'fr', 'TR', null),
  ('UBI', 'UBI.PA', 'EUR', 'stock', 'Ubisoft', 'FR', 'France', 'Édition de jeux électroniques', 'Video game publishing', 'technology', 'fr', 'UB', 'https://commons.wikimedia.org/wiki/Special:FilePath/Ubisoft_logo.svg?width=160'),
  ('FR', 'FR.PA', 'EUR', 'stock', 'Valeo', 'FR', 'France', 'Construction automobile', 'Automotive industry', 'auto', 'fr', 'VA', 'https://commons.wikimedia.org/wiki/Special:FilePath/Valeo_Logo.svg?width=160'),
  ('VK', 'VK.PA', 'EUR', 'stock', 'Vallourec', 'FR', 'France', 'Industrie', 'Industrials', 'industry', 'fr', 'VA', 'https://commons.wikimedia.org/wiki/Special:FilePath/Vallourec_Logo.jpg?width=160'),
  ('VLA', 'VLA.PA', 'EUR', 'stock', 'Valneva SE', 'FR', 'France', 'Recherche-développement en biotechnologie', 'Research and development in biotechnology', 'health', 'fr', 'VA', 'https://commons.wikimedia.org/wiki/Special:FilePath/Valneva_logo.svg?width=160'),
  ('VRLA', 'VRLA.PA', 'EUR', 'stock', 'Verallia', 'FR', 'France', 'Fabrication de verre creux', 'Manufacture of hollow glass', 'materials', 'fr', 'VE', null),
  ('VCT', 'VCT.PA', 'EUR', 'stock', 'Vicat', 'FR', 'France', 'Fabrication de ciment', null, 'materials', 'fr', 'VI', 'https://commons.wikimedia.org/wiki/Special:FilePath/Vicat_SA_logo.svg?width=160'),
  ('VIRP', 'VIRP.PA', 'EUR', 'stock', 'Virbac', 'FR', 'France', 'Fabrication de préparations pharmaceutiques', null, 'health', 'fr', 'VI', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_Virbac.svg?width=160'),
  ('VIRI', 'VIRI.PA', 'EUR', 'stock', 'Viridien', 'FR', 'France', 'Industrie pétrolière', 'Petroleum industry', 'energy', 'fr', 'VI', 'https://commons.wikimedia.org/wiki/Special:FilePath/CGG.svg?width=160'),
  ('VIV', 'VIV.PA', 'EUR', 'stock', 'Vivendi', 'FR', 'France', 'Médias', 'Media', 'telecom', 'fr', 'VI', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_vivendi.svg?width=160'),
  ('VU', 'VU.PA', 'EUR', 'stock', 'Vusion', 'FR', 'France', 'Étiquettes électroniques', 'Digital shelf labels', 'technology', 'fr', 'VU', 'https://commons.wikimedia.org/wiki/Special:FilePath/SES-imagotag_logo.svg?width=160'),
  ('MF', 'MF.PA', 'EUR', 'stock', 'Wendel', 'FR', 'France', 'Capital-investissement', 'Private equity', 'finance', 'fr', 'WE', 'https://commons.wikimedia.org/wiki/Special:FilePath/Wendel_Logo.svg?width=160'),
  ('WLN', 'WLN.PA', 'EUR', 'stock', 'Worldline', 'FR', 'France', 'Paiements', 'Payments', 'finance', 'fr', 'WO', null)
on conflict (symbol) do update set
  logo_url = coalesce(public.securities.logo_url, excluded.logo_url);

-- Logos des titres déjà au catalogue.
update public.securities set logo_url = v.logo
from (values
  ('MT', 'https://commons.wikimedia.org/wiki/Special:FilePath/Arcelor_Mittal.svg?width=160'),
  ('CS', 'https://commons.wikimedia.org/wiki/Special:FilePath/AXA_Logo.svg?width=160'),
  ('BNP', 'https://commons.wikimedia.org/wiki/Special:FilePath/BNP_Paribas.svg?width=160'),
  ('BOUY', 'https://commons.wikimedia.org/wiki/Special:FilePath/Bouygues_logo.svg?width=160'),
  ('CAPG', 'https://commons.wikimedia.org/wiki/Special:FilePath/Capgemini_201x_logo.svg?width=160'),
  ('DSY', 'https://commons.wikimedia.org/wiki/Special:FilePath/Dassault_systemes_logo.svg?width=160'),
  ('FGR', 'https://commons.wikimedia.org/wiki/Special:FilePath/Eiffage_logo.svg?width=160'),
  ('ENGI', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo-engie.svg?width=160'),
  ('EFX', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_EssilorLuxottica.svg?width=160'),
  ('ERF', 'https://commons.wikimedia.org/wiki/Special:FilePath/Eurofins_Scientific_logo.png?width=160'),
  ('ENX', 'https://commons.wikimedia.org/wiki/Special:FilePath/New_Euronext_logo.svg?width=160'),
  ('RMS', 'https://commons.wikimedia.org/wiki/Special:FilePath/Hermes_wordmark.svg?width=160'),
  ('KER', 'https://commons.wikimedia.org/wiki/Special:FilePath/Kering-logo.svg?width=160'),
  ('OREAL', 'https://commons.wikimedia.org/wiki/Special:FilePath/L%27Or%C3%A9al_logo.svg?width=160'),
  ('LR', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo_Legrand_SA.svg?width=160'),
  ('MC', 'https://commons.wikimedia.org/wiki/Special:FilePath/LVMH_wordmark.svg?width=160'),
  ('ML', 'https://commons.wikimedia.org/wiki/Special:FilePath/Michelin_Wordmark.svg?width=160'),
  ('ORAN', 'https://commons.wikimedia.org/wiki/Special:FilePath/Orange_logo.svg?width=160'),
  ('SGO', 'https://commons.wikimedia.org/wiki/Special:FilePath/Saint-Gobain_Logo_2025.png?width=160'),
  ('GLE', 'https://commons.wikimedia.org/wiki/Special:FilePath/Logo-SG-Soci%C3%A9t%C3%A9-G%C3%A9n%C3%A9rale.svg?width=160'),
  ('STLA', 'https://commons.wikimedia.org/wiki/Special:FilePath/Stellantis.svg?width=160'),
  ('STM', 'https://commons.wikimedia.org/wiki/Special:FilePath/STMicroelectronics.png?width=160'),
  ('HO', 'https://commons.wikimedia.org/wiki/Special:FilePath/Thales_Logo.svg?width=160'),
  ('VIE', 'https://commons.wikimedia.org/wiki/Special:FilePath/Veolia_logo.svg?width=160'),
  ('DG', 'https://commons.wikimedia.org/wiki/Special:FilePath/Vinci_%28Unternehmen%29_logo.svg?width=160')
) as v(symbol, logo)
where public.securities.symbol = v.symbol
  and public.securities.logo_url is distinct from v.logo;

