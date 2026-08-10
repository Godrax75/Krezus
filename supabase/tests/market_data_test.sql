-- =====================================================================
-- Tests des données de marché (Lot 3) — conversion de devise.
-- Exécuté par tools/run_edge_function_tests.sh sur un Postgres jetable.
--
-- L'enjeu tient en une phrase : `quotes_cache.price` est lu par le moteur
-- d'ordres comme des euros. Si un cours en dollars y atterrit tel quel, tous
-- les achats sur ce titre sortent un nombre de parts faux, sans aucun signal.
-- =====================================================================

\set ON_ERROR_STOP on

-- Référentiel minimal : un titre en euros, un titre en dollars.
do $$
declare
  v_uid uuid;
begin
  insert into auth.users (email) values ('marc@test.fr') returning id into v_uid;
  perform set_config('test.current_user', v_uid::text, false);

  insert into public.securities (symbol, eodhd_symbol, name, currency, asset_type)
  values ('MC',   'MC.PA',   'LVMH',   'EUR', 'stock'),
         ('NVDA', 'NVDA.US', 'Nvidia', 'USD', 'stock');

  insert into public.portfolios (user_id, mode, cash_cents)
  values (v_uid, 'paper', 100000);   -- 1 000,00 €
end $$;

-- ---- Test 1 : un écrivain qui ignore price_native reste valide -----------
do $$
declare
  v_native numeric;
begin
  insert into public.quotes_cache (symbol, price, open, change_pct, fetched_at)
  values ('MC', 517.60, 512.40, 1.2322, now());

  select price_native into v_native from public.quotes_cache where symbol = 'MC';
  if v_native is distinct from 517.60 then
    raise exception 'T1 price_native non rempli par le trigger (%)', v_native;
  end if;
  raise notice 'T1 OK — price_native rempli depuis price pour un titre en euros';
end $$;

-- ---- Test 2 : une cotation en dollars cohérente est acceptée ------------
do $$
declare
  v_price numeric;
begin
  -- 178,45 $ au taux 1,0842 → 164,59 €
  insert into public.quotes_cache
    (symbol, price, price_native, currency, fx_rate, open, change_pct, fetched_at)
  values ('NVDA', 178.45 / 1.0842, 178.45, 'USD', 1.0842, 176.20 / 1.0842, 1.6229, now());

  select price into v_price from public.quotes_cache where symbol = 'NVDA';
  if v_price >= 178.45 then
    raise exception 'T2 le cours stocké nest pas converti (%)', v_price;
  end if;
  raise notice 'T2 OK — cotation USD convertie et acceptée (% EUR)', round(v_price, 2);
end $$;

-- ---- Test 3 : le cours dollar brut dans `price` est rejeté --------------
-- C'est LE bug que la contrainte existe pour attraper.
do $$
declare
  v_raised boolean := false;
begin
  begin
    update public.quotes_cache
    set price = 178.45, price_native = 178.45, fx_rate = 1.0842
    where symbol = 'NVDA';
  exception when check_violation then v_raised := true;
  end;

  if not v_raised then
    raise exception 'T3 cours dollar non converti accepté dans la colonne euro';
  end if;
  raise notice 'T3 OK — cours USD non converti rejeté par la contrainte';
end $$;

-- ---- Test 4 : le moteur calcule les parts sur le cours converti ---------
do $$
declare
  v_uid  uuid := current_setting('test.current_user')::uuid;
  v_qty  numeric;
  v_want numeric;
begin
  -- Remet une cotation cohérente après le rejet du test 3.
  update public.quotes_cache
  set price = 178.45 / 1.0842, price_native = 178.45, fx_rate = 1.0842, fetched_at = now()
  where symbol = 'NVDA';

  perform public.execute_paper_buy(v_uid, 'NVDA', 10000);   -- 100,00 €

  select quantity into v_qty from public.positions p
    join public.portfolios po on po.id = p.portfolio_id
    where po.user_id = v_uid and p.symbol = 'NVDA';

  -- 100 € achètent 100 / 164,59 = 0,6076 part. Sur le cours dollar non
  -- converti on obtiendrait 100 / 178,45 = 0,5604 — soit 8,4 % de parts en
  -- moins pour le même argent.
  v_want := round((100::numeric) / (178.45 / 1.0842), 8);
  if abs(v_qty - v_want) > 0.00000001 then
    raise exception 'T4 parts calculées % au lieu de %', v_qty, v_want;
  end if;
  raise notice 'T4 OK — 100 EUR sur un titre USD donnent % parts', round(v_qty, 4);
end $$;

-- ---- Test 5 : un taux de change nul ou négatif est refusé ---------------
do $$
declare
  v_raised boolean := false;
begin
  begin
    insert into public.fx_rates (pair, rate) values ('EURUSD', 0);
  exception when check_violation then v_raised := true;
  end;
  if not v_raised then raise exception 'T5 taux de change nul accepté'; end if;

  insert into public.fx_rates (pair, rate) values ('EURUSD', 1.0842);
  raise notice 'T5 OK — taux de change contraint à une valeur positive';
end $$;

select ' TOUS LES TESTS PASSENT ' as resultat;
