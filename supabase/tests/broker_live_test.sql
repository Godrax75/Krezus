-- =====================================================================
-- Tests du mode réel (0014) et de la garde d'identité (0015).
-- Exécuté par tools/run_broker_live_tests.sh sur un Postgres jetable.
-- Chaque bloc lève une exception si une assertion échoue → psql s'arrête
-- en erreur. Un run complet sans exception = OK.
-- =====================================================================

\set ON_ERROR_STOP on

-- Deux utilisateurs : Lucie (l'appelante) et Marc (la cible).
-- Toute la question de 0015 tient dans ce couple.
do $$
declare
  v_lucie uuid;
  v_marc  uuid;
begin
  insert into auth.users (email) values ('lucie@test.fr') returning id into v_lucie;
  insert into auth.users (email) values ('marc@test.fr')  returning id into v_marc;

  perform set_config('test.lucie', v_lucie::text, false);
  perform set_config('test.marc',  v_marc::text,  false);
  perform set_config('test.current_user', v_lucie::text, false);   -- auth.uid() = Lucie

  insert into public.securities (symbol, name, currency, asset_type, mic)
  values ('NVDA', 'Nvidia', 'USD', 'stock', 'NASDAQ'),
         ('MC',   'LVMH',   'EUR', 'stock', 'XPAR');

  -- Les portefeuilles ne sont pas créés ici : le trigger
  -- on_auth_user_created (0003) les a déjà posés à 1 000 € avec le profil.
  -- Les créer à la main violerait unique(user_id, mode) — ce qui est
  -- précisément la garantie qu'on veut.

  insert into public.quotes_cache (symbol, price, open, change_pct, fetched_at)
  values ('NVDA', 100.00, 99.00, 1.0, now()),
         ('MC',   500.00, 495.00, 1.0, now());
end $$;


-- =====================================================================
-- 0015 — garde d'identité
-- =====================================================================

-- ---- T1 : Lucie achète sur SON portefeuille → passe ---------------------
do $$
declare
  v_lucie uuid := current_setting('test.lucie')::uuid;
  v_cash  bigint;
begin
  perform public.execute_paper_buy(v_lucie, 'NVDA', 20000);
  select cash_cents into v_cash from public.portfolios where user_id = v_lucie;
  if v_cash <> 80000 then
    raise exception 'T1 cash attendu 80000, obtenu %', v_cash;
  end if;
  raise notice 'T1 OK — l''ordre sur son propre portefeuille passe';
end $$;

-- ---- T2 : Lucie achète sur le portefeuille de MARC → KR011 --------------
-- C'est la faille que 0015 ferme : avant la migration, cet appel réussissait.
do $$
declare
  v_marc uuid := current_setting('test.marc')::uuid;
  v_cash bigint;
begin
  begin
    perform public.execute_paper_buy(v_marc, 'NVDA', 20000);
    raise exception 'T2 ÉCHEC — l''achat sur le portefeuille d''un tiers a été accepté';
  exception
    when sqlstate 'KR011' then
      null;   -- attendu
  end;

  select cash_cents into v_cash from public.portfolios where user_id = v_marc;
  if v_cash <> 100000 then
    raise exception 'T2 le cash de Marc a bougé : %', v_cash;
  end if;
  raise notice 'T2 OK — achat sur le portefeuille d''un tiers refusé (KR011)';
end $$;

-- ---- T3 : idem pour la vente et la réinitialisation ---------------------
do $$
declare
  v_marc uuid := current_setting('test.marc')::uuid;
begin
  begin
    perform public.execute_paper_sell(v_marc, 'NVDA', 100);
    raise exception 'T3 ÉCHEC — vente sur un tiers acceptée';
  exception when sqlstate 'KR011' then null;
  end;

  begin
    perform public.reset_paper_portfolio(v_marc);
    raise exception 'T3 ÉCHEC — réinitialisation d''un tiers acceptée';
  exception when sqlstate 'KR011' then null;
  end;

  raise notice 'T3 OK — vente et réinitialisation d''un tiers refusées (KR011)';
end $$;

-- ---- T4 : les implémentations ne sont plus exécutables par authenticated -
do $$
declare
  v_has boolean;
begin
  select bool_or(has_function_privilege('authenticated', p.oid, 'execute'))
  into v_has
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('execute_paper_buy_impl', 'execute_paper_sell_impl',
                      'reset_paper_portfolio_impl');

  if v_has then
    raise exception 'T4 ÉCHEC — une fonction _impl reste exécutable par authenticated';
  end if;
  raise notice 'T4 OK — les _impl sont hors de portée du rôle authenticated';
end $$;


-- =====================================================================
-- 0014 — mode réel
-- =====================================================================

-- ---- T5 : le paper et le réel ne peuvent pas se croiser -----------------
-- L'invariant est structurel, pas conventionnel : portfolios.mode reste
-- contraint à 'paper', donc aucun portefeuille réel ne peut exister là où
-- execute_paper_buy va chercher.
do $$
declare
  v_lucie uuid := current_setting('test.lucie')::uuid;
begin
  begin
    insert into public.portfolios (user_id, mode, cash_cents)
    values (v_lucie, 'live', 100000);
    raise exception 'T5 ÉCHEC — un portefeuille mode=live a pu être créé';
  exception when check_violation then null;
  end;

  if exists (
    select 1
    from information_schema.table_constraints tc
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
    where tc.table_name = 'live_order_intents'
      and tc.constraint_type = 'FOREIGN KEY'
      and ccu.table_name = 'portfolios'
  ) then
    raise exception 'T5 ÉCHEC — live_order_intents référence portfolios';
  end if;

  raise notice 'T5 OK — le moteur papier ne peut pas atteindre un compte réel';
end $$;

-- ---- T6 : pas de table miroir des positions réelles ---------------------
-- IBKR est la seule source de vérité. Si quelqu'un ajoute un jour une
-- table live_positions, ce test le dit avant que deux vérités divergent.
do $$
declare
  v_bad text;
begin
  select string_agg(tablename, ', ') into v_bad
  from pg_tables
  where schemaname = 'public'
    and tablename in ('live_positions', 'live_cash', 'live_orders', 'live_portfolios');

  if v_bad is not null then
    raise exception 'T6 ÉCHEC — table miroir présente : %', v_bad;
  end if;
  raise notice 'T6 OK — aucun miroir des positions réelles';
end $$;

-- ---- T7 : l'idempotence repose sur la clé primaire, pas sur un if -------
do $$
declare
  v_lucie uuid := current_setting('test.lucie')::uuid;
  v_id    uuid := gen_random_uuid();
  v_rows  int;
begin
  insert into public.live_order_intents
    (id, user_id, account_id, symbol, side, seen_price_cents, seen_price_at, coid)
  values (v_id, v_lucie, 'DU1234567', 'MC', 'buy', 50000, now(), 'krz-aaaaaaaaaaaa');

  -- Le rejeu de la même intention n'insère rien et ne lève rien : c'est
  -- exactement ce que le route handler observe pour décider de NE PAS
  -- rappeler IBKR.
  with ins as (
    insert into public.live_order_intents
      (id, user_id, account_id, symbol, side, seen_price_cents, seen_price_at, coid)
    values (v_id, v_lucie, 'DU1234567', 'MC', 'buy', 50000, now(), 'krz-bbbbbbbbbbbb')
    on conflict (id) do nothing
    returning 1
  )
  select count(*) into v_rows from ins;

  if v_rows <> 0 then
    raise exception 'T7 ÉCHEC — le rejeu a inséré % ligne(s)', v_rows;
  end if;

  -- Le coid est unique lui aussi : seconde barrière, côté IBKR.
  begin
    insert into public.live_order_intents
      (id, user_id, account_id, symbol, side, seen_price_cents, seen_price_at, coid)
    values (gen_random_uuid(), v_lucie, 'DU1234567', 'MC', 'buy', 50000, now(),
            'krz-aaaaaaaaaaaa');
    raise exception 'T7 ÉCHEC — un coid dupliqué a été accepté';
  exception when unique_violation then null;
  end;

  raise notice 'T7 OK — rejeu d''intention neutralisé, coid unique';
end $$;

-- ---- T8 : négociabilité en réel — un conid ne suffit pas ----------------
do $$
declare
  v_tradable boolean;
begin
  -- Conid renseigné mais empreinte jamais vérifiée ⇒ NON négociable.
  update public.securities
     set ibkr_conid = 4815747, ibkr_exchange = 'SBF', ibkr_currency = 'EUR'
   where symbol = 'MC';
  select is_tradable_live into v_tradable from public.v_live_tradable where symbol = 'MC';
  if v_tradable then
    raise exception 'T8 ÉCHEC — négociable sans empreinte de contrat vérifiée';
  end if;

  update public.securities
     set ibkr_contract_fingerprint = 'sha256:deadbeef', ibkr_checked_at = now()
   where symbol = 'MC';
  select is_tradable_live into v_tradable from public.v_live_tradable where symbol = 'MC';
  if not v_tradable then
    raise exception 'T8 ÉCHEC — non négociable alors que tout est vérifié';
  end if;

  -- NVDA n'a pas de conid : jamais négociable en réel (KR061 côté serveur).
  select is_tradable_live into v_tradable from public.v_live_tradable where symbol = 'NVDA';
  if v_tradable then
    raise exception 'T8 ÉCHEC — négociable sans conid';
  end if;

  raise notice 'T8 OK — conid + empreinte requis pour négocier en réel';
end $$;

-- ---- T9 : un conid ne peut pas être partagé par deux titres -------------
do $$
begin
  begin
    update public.securities set ibkr_conid = 4815747 where symbol = 'NVDA';
    raise exception 'T9 ÉCHEC — deux titres partagent le même conid';
  exception when unique_violation then null;
  end;
  raise notice 'T9 OK — conid unique entre titres';
end $$;

-- ---- T10 : le journal d'événements est la preuve d'idempotence ----------
do $$
declare
  v_intent uuid;
  v_n      int;
begin
  select id into v_intent from public.live_order_intents limit 1;

  insert into public.live_order_events (intent_id, kind, payload) values
    (v_intent, 'created', '{}'::jsonb),
    (v_intent, 'drift_check_ok', '{}'::jsonb),
    (v_intent, 'ibkr_submit', '{"coid":"krz-aaaaaaaaaaaa"}'::jsonb);

  select count(*) into v_n
  from public.live_order_events
  where intent_id = v_intent and kind = 'ibkr_submit';

  if v_n <> 1 then
    raise exception 'T10 ÉCHEC — % soumission(s) IBKR pour une intention', v_n;
  end if;

  -- Un `kind` non prévu doit être refusé : le journal est une machine à
  -- états, pas un sac à logs.
  begin
    insert into public.live_order_events (intent_id, kind) values (v_intent, 'whatever');
    raise exception 'T10 ÉCHEC — un kind inconnu a été accepté';
  exception when check_violation then null;
  end;

  raise notice 'T10 OK — une seule soumission IBKR par intention';
end $$;

-- ---- T11 : suppression du compte ⇒ tout disparaît (RGPD / 5.1.1(v)) -----
do $$
declare
  v_lucie uuid := current_setting('test.lucie')::uuid;
  v_n     int;
begin
  insert into public.broker_connections (user_id, account_id, is_paper_account)
  values (v_lucie, 'DU1234567', true);

  delete from auth.users where id = v_lucie;

  select count(*) into v_n from public.live_order_intents where user_id = v_lucie;
  if v_n <> 0 then raise exception 'T11 ÉCHEC — % intention(s) survivent', v_n; end if;

  select count(*) into v_n from public.broker_connections where user_id = v_lucie;
  if v_n <> 0 then raise exception 'T11 ÉCHEC — connexion courtier survivante'; end if;

  select count(*) into v_n from public.live_order_events;
  if v_n <> 0 then raise exception 'T11 ÉCHEC — % événement(s) orphelin(s)', v_n; end if;

  raise notice 'T11 OK — la suppression du compte emporte le mode réel';
end $$;

select 'TOUS LES TESTS OK' as resultat;
