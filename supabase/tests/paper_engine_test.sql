-- =====================================================================
-- Tests du moteur d'ordres papier.
-- Exécuté par tools/run_paper_engine_tests.sh sur un Postgres jetable.
-- Chaque bloc lève une exception si une assertion échoue → le script s'arrête
-- en erreur, ce qui fait échouer le test. Un run complet sans exception = OK.
-- =====================================================================

\set ON_ERROR_STOP on

-- Utilisateur de test + portefeuille + cotation fraîche.
do $$
declare
  v_uid uuid;
begin
  insert into auth.users (email) values ('lucie@test.fr') returning id into v_uid;
  perform set_config('test.current_user', v_uid::text, false);

  insert into public.securities (symbol, name, currency, asset_type)
  values ('NVDA', 'Nvidia', 'USD', 'stock');

  insert into public.portfolios (user_id, mode, cash_cents)
  values (v_uid, 'paper', 100000);   -- 1 000,00 €

  insert into public.quotes_cache (symbol, price, open, change_pct, fetched_at)
  values ('NVDA', 100.00, 99.00, 1.0, now());
end $$;

-- ---- Test 1 : achat de 200 € → 2 parts, cash 800 € ----------------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_qty numeric; v_cash bigint;
begin
  perform public.execute_paper_buy(v_uid, 'NVDA', 20000);
  select quantity into v_qty from public.positions p
    join public.portfolios po on po.id = p.portfolio_id
    where po.user_id = v_uid and p.symbol = 'NVDA';
  select cash_cents into v_cash from public.portfolios where user_id = v_uid;

  if v_qty <> 2.0 then raise exception 'T1 parts attendues 2, obtenu %', v_qty; end if;
  if v_cash <> 80000 then raise exception 'T1 cash attendu 80000, obtenu %', v_cash; end if;
  raise notice 'T1 OK — achat 200 EUR -> 2 parts, cash 800 EUR';
end $$;

-- ---- Test 2 : coût moyen pondéré après un 2e achat à prix différent ------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_qty numeric; v_avg bigint;
begin
  update public.quotes_cache set price = 200.00, fetched_at = now() where symbol = 'NVDA';
  perform public.execute_paper_buy(v_uid, 'NVDA', 20000);   -- +1 part à 200 €
  select quantity, avg_cost_cents into v_qty, v_avg from public.positions p
    join public.portfolios po on po.id = p.portfolio_id
    where po.user_id = v_uid and p.symbol = 'NVDA';

  -- 3 parts, coût total 400 € -> coût moyen 13333 c/part (arrondi)
  if v_qty <> 3.0 then raise exception 'T2 parts attendues 3, obtenu %', v_qty; end if;
  if v_avg not between 13332 and 13334 then raise exception 'T2 coût moyen attendu ~13333, obtenu %', v_avg; end if;
  raise notice 'T2 OK — coût moyen pondéré % c/part sur 3 parts', v_avg;
end $$;

-- ---- Test 3 : fonds insuffisants -> exception, état inchangé -------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_cash_before bigint; v_cash_after bigint; v_raised boolean := false;
begin
  select cash_cents into v_cash_before from public.portfolios where user_id = v_uid;
  begin
    perform public.execute_paper_buy(v_uid, 'NVDA', 999999);   -- > cash
  exception when others then v_raised := true;
  end;
  select cash_cents into v_cash_after from public.portfolios where user_id = v_uid;

  if not v_raised then raise exception 'T3 aucune exception sur fonds insuffisants'; end if;
  if v_cash_before <> v_cash_after then raise exception 'T3 cash modifié malgré le rejet'; end if;
  raise notice 'T3 OK — fonds insuffisants rejeté, cash inchangé';
end $$;

-- ---- Test 4 : cotation périmée (>15 min) -> rejet ------------------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_raised boolean := false;
begin
  update public.quotes_cache set fetched_at = now() - interval '20 minutes' where symbol = 'NVDA';
  begin
    perform public.execute_paper_buy(v_uid, 'NVDA', 1000);
  exception when others then v_raised := true;
  end;
  if not v_raised then raise exception 'T4 cotation périmée acceptée à tort'; end if;
  update public.quotes_cache set fetched_at = now() where symbol = 'NVDA';   -- rafraîchit pour la suite
  raise notice 'T4 OK — cotation périmée rejetée';
end $$;

-- ---- Test 5 : vente 50 % puis 100 % -------------------------------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_qty numeric; v_exists boolean;
begin
  -- 3 parts détenues, prix courant 200 €
  perform public.execute_paper_sell(v_uid, 'NVDA', 50);
  select quantity into v_qty from public.positions p
    join public.portfolios po on po.id = p.portfolio_id
    where po.user_id = v_uid and p.symbol = 'NVDA';
  if v_qty <> 1.5 then raise exception 'T5 après vente 50%% attendu 1.5 part, obtenu %', v_qty; end if;

  perform public.execute_paper_sell(v_uid, 'NVDA', 100);
  select exists(
    select 1 from public.positions p
    join public.portfolios po on po.id = p.portfolio_id
    where po.user_id = v_uid and p.symbol = 'NVDA') into v_exists;
  if v_exists then raise exception 'T5 position non soldée après vente 100%%'; end if;
  raise notice 'T5 OK — vente 50%% puis 100%% solde la position';
end $$;

-- ---- Test 6 : reset -> cash 1 000 €, aucune position --------------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_cash bigint; v_positions int;
begin
  update public.quotes_cache set fetched_at = now() where symbol = 'NVDA';
  perform public.execute_paper_buy(v_uid, 'NVDA', 30000);
  perform public.reset_paper_portfolio(v_uid);
  select cash_cents into v_cash from public.portfolios where user_id = v_uid;
  select count(*) into v_positions from public.positions p
    join public.portfolios po on po.id = p.portfolio_id where po.user_id = v_uid;

  if v_cash <> 100000 then raise exception 'T6 cash après reset attendu 100000, obtenu %', v_cash; end if;
  if v_positions <> 0 then raise exception 'T6 positions après reset attendu 0, obtenu %', v_positions; end if;
  raise notice 'T6 OK — reset ramène à 1 000 EUR sans position';
end $$;

select 'TOUS LES TESTS PASSENT' as resultat;
