-- =====================================================================
-- Tests de l'Oracle (Lot 6).
-- Exécuté par tools/run_oracle_tests.sh sur un Postgres jetable.
--
-- Deux enjeux : le profil investisseur ne doit pas accepter n'importe quoi,
-- et les vues de repères ne doivent jamais inventer une valeur quand la
-- donnée manque — c'est ce qui distingue un repère factuel d'un avis déguisé.
-- =====================================================================

\set ON_ERROR_STOP on

do $$
declare
  v_uid uuid;
begin
  insert into auth.users (email) values ('sofia@test.fr') returning id into v_uid;
  perform set_config('test.current_user', v_uid::text, false);
  insert into public.profiles (id) values (v_uid);

  -- Deux titres du même secteur (pour une médiane sectorielle qui ait un sens)
  -- et un troisième sans fondamentaux.
  insert into public.securities (symbol, name, currency, asset_type, sector,
                                 pe_ratio, peg_ratio, dividend_yield)
  values ('MC',   'LVMH',         'EUR', 'stock', 'Luxe',   22.4, 2.3, 1.8),
         ('RMS',  'Hermès',       'EUR', 'stock', 'Luxe',   38.5, 3.1, 0.9),
         ('NVDA', 'Nvidia',       'USD', 'stock', 'Tech',   NULL, NULL, 0.03);
end $$;

-- ---- Test 1 : médiane sectorielle sur les seules valeurs connues ---------
do $$
declare
  v_median numeric;
  v_with   integer;
begin
  select median_pe, with_pe into v_median, v_with
  from public.v_sector_fundamentals where sector = 'Luxe';

  -- Médiane de 22,4 et 38,5 = 30,45.
  if v_median is distinct from 30.45 then
    raise exception 'T1 médiane Luxe = % au lieu de 30.45', v_median;
  end if;
  if v_with <> 2 then raise exception 'T1 compte de PER = %', v_with; end if;
  raise notice 'T1 OK — médiane sectorielle calculée sur les PER connus';
end $$;

-- ---- Test 2 : un secteur sans fondamentaux ne produit pas de repère ------
do $$
declare
  v_median numeric;
  v_with   integer;
begin
  select median_pe, with_pe into v_median, v_with
  from public.v_sector_fundamentals where sector = 'Tech';

  -- Le titre est compté, mais aucune médiane n'est inventée.
  if v_median is not null then
    raise exception 'T2 médiane inventée pour un secteur sans PER (%)', v_median;
  end if;
  if v_with <> 0 then raise exception 'T2 compte de PER = %', v_with; end if;
  raise notice 'T2 OK — aucune médiane fabriquée quand la donnée manque';
end $$;

-- ---- Test 3 : le profil investisseur refuse les entrées invalides --------
do $$
declare
  v_uid    uuid := current_setting('test.current_user')::uuid;
  v_raised boolean;
begin
  v_raised := false;
  begin
    perform public.save_investor_profile(v_uid, '[]'::jsonb, 'Le Gardien', '{}'::jsonb);
  exception when sqlstate 'KR030' then v_raised := true;
  end;
  if not v_raised then raise exception 'T3 réponses non-objet acceptées'; end if;

  v_raised := false;
  begin
    perform public.save_investor_profile(v_uid, '{"horizon": 2}'::jsonb, '  ', '{}'::jsonb);
  exception when sqlstate 'KR030' then v_raised := true;
  end;
  if not v_raised then raise exception 'T3 archétype vide accepté'; end if;

  raise notice 'T3 OK — profil investisseur validé avant écriture';
end $$;

-- ---- Test 4 : le profil s'écrit puis se met à jour sans doublon ----------
do $$
declare
  v_uid   uuid := current_setting('test.current_user')::uuid;
  v_arch  text;
  v_count integer;
begin
  perform public.save_investor_profile(
    v_uid, '{"horizon": 2, "drawdown": 1}'::jsonb, 'Le Bâtisseur',
    '{"patience": 80, "prudence": 55}'::jsonb);

  perform public.save_investor_profile(
    v_uid, '{"horizon": 0}'::jsonb, 'Le Gardien', '{"prudence": 92}'::jsonb);

  select archetype into v_arch from public.investor_profile where user_id = v_uid;
  select count(*) into v_count from public.investor_profile where user_id = v_uid;

  if v_arch <> 'Le Gardien' then raise exception 'T4 archétype non mis à jour (%)', v_arch; end if;
  if v_count <> 1 then raise exception 'T4 doublon de profil (%)', v_count; end if;
  raise notice 'T4 OK — refaire le questionnaire remplace le profil';
end $$;

-- ---- Test 5 : la santé du portefeuille se mesure sur les positions -------
do $$
declare
  v_uid    uuid := current_setting('test.current_user')::uuid;
  v_pid    uuid;
  v_health record;
begin
  insert into public.portfolios (user_id, mode, cash_cents)
  values (v_uid, 'paper', 100000) returning id into v_pid;

  insert into public.quotes_cache (symbol, price, fetched_at) values
    ('MC', 500.00, now()), ('RMS', 2000.00, now()), ('NVDA', 150.00, now());

  -- 3 lignes, 2 secteurs, 2 devises. Hermès pèse le plus.
  insert into public.positions (portfolio_id, symbol, quantity, avg_cost_cents) values
    (v_pid, 'MC',   1.0, 50000),
    (v_pid, 'RMS',  1.0, 200000),
    (v_pid, 'NVDA', 1.0, 15000);

  select * into v_health from public.v_portfolio_health where portfolio_id = v_pid;

  if v_health.positions_held <> 3 then
    raise exception 'T5 positions = %', v_health.positions_held;
  end if;
  if v_health.sectors_held <> 2 then
    raise exception 'T5 secteurs = %', v_health.sectors_held;
  end if;
  if v_health.currencies_held <> 2 then
    raise exception 'T5 devises = %', v_health.currencies_held;
  end if;

  -- Hermès : 2000 / 2650 = 75,5 % du portefeuille.
  if round(v_health.top_position_weight, 3) <> 0.755 then
    raise exception 'T5 poids de la plus grosse ligne = %', v_health.top_position_weight;
  end if;
  raise notice 'T5 OK — concentration mesurée à % pourcent', round(v_health.top_position_weight * 100);
end $$;

-- ---- Test 6 : un portefeuille vide ne divise pas par zéro ----------------
do $$
declare
  v_uid2   uuid;
  v_pid    uuid;
  v_health record;
begin
  insert into auth.users (email) values ('vide@test.fr') returning id into v_uid2;
  insert into public.profiles (id) values (v_uid2);
  insert into public.portfolios (user_id, mode, cash_cents)
  values (v_uid2, 'paper', 100000) returning id into v_pid;

  select * into v_health from public.v_portfolio_health where portfolio_id = v_pid;

  if v_health.positions_held <> 0 then
    raise exception 'T6 positions = %', v_health.positions_held;
  end if;
  if v_health.top_position_weight <> 0 then
    raise exception 'T6 poids = % au lieu de 0', v_health.top_position_weight;
  end if;
  raise notice 'T6 OK — portefeuille vide géré sans division par zéro';
end $$;

-- ---- Test 7 : le cache Polymarket borne les probabilités ----------------
do $$
declare
  v_raised boolean := false;
begin
  begin
    insert into public.polymarket_cache (id, question, probability)
    values ('bad', 'Question hors bornes ?', 1.4);
  exception when check_violation then v_raised := true;
  end;
  if not v_raised then raise exception 'T7 probabilité > 1 acceptée'; end if;

  insert into public.polymarket_cache (id, question, probability, volume)
  values ('512847', 'Will the Fed cut rates?', 0.72, 4821993.21);
  raise notice 'T7 OK — probabilités contraintes à [0, 1]';
end $$;

select ' TOUS LES TESTS PASSENT ' as resultat;
