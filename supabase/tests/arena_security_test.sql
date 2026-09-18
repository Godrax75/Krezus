-- =====================================================================
-- Tests de 0020. Exécuté par tools/run_arena_security_tests.sh.
-- Chaque bloc lève une exception si une assertion échoue.
-- =====================================================================

\set ON_ERROR_STOP on

create or replace function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('test.current_user', coalesce(p::text, ''), false);
$$;

do $$
declare v_a uuid; v_b uuid; v_c uuid;
begin
  insert into auth.users (email) values ('alice@t.fr') returning id into v_a;
  insert into auth.users (email) values ('bruno@t.fr') returning id into v_b;
  insert into auth.users (email) values ('chloe@t.fr') returning id into v_c;
  insert into public.profiles (id, username) values (v_a, 'alice'), (v_b, 'bruno'), (v_c, 'chloe_du_75');
  perform set_config('test.a', v_a::text, false);
  perform set_config('test.b', v_b::text, false);
  perform set_config('test.c', v_c::text, false);
end $$;

-- T1 : plus aucune fonction à pleins droits pour un visiteur sans compte.
do $$
declare v_open text;
begin
  select string_agg(p.proname, ', ') into v_open
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef
    and has_function_privilege('anon', p.oid, 'execute');
  if v_open is not null then raise exception 'T1 encore ouvertes à anon : %', v_open; end if;
  raise notice 'T1 OK — aucune fonction à pleins droits pour anon';
end $$;

-- T2 : les utilitaires serveur sont fermés à l'app, ouverts au service role.
do $$
begin
  if has_function_privilege('authenticated', 'public.award_xp(uuid, integer)', 'execute')
     or has_function_privilege('authenticated', 'public.record_hercule_subscription(uuid, text, text, timestamptz, text)', 'execute')
     or has_function_privilege('authenticated', 'public.complete_mission(uuid, text)', 'execute') then
    raise exception 'T2 un utilitaire serveur reste ouvert à authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.record_hercule_exchange(uuid, text, text)', 'execute') then
    raise exception 'T2 le service role a perdu record_hercule_exchange';
  end if;
  raise notice 'T2 OK — utilitaires serveur réservés au service role';
end $$;

-- T3 : on ne peut pas agir au nom d'un autre.
do $$
declare v_a uuid := current_setting('test.a')::uuid; v_b uuid := current_setting('test.b')::uuid;
begin
  perform pg_temp.act_as(v_b);
  begin
    perform public.send_friend_request(v_a, v_b);          -- Bruno se fait passer pour Alice
    raise exception 'T3 demande envoyée au nom d''un autre';
  exception when sqlstate 'KR011' then null;
  end;
  begin
    perform public.remove_friend(v_a, v_b);
    raise exception 'T3 amitié supprimée au nom d''un autre';
  exception when sqlstate 'KR011' then null;
  end;
  begin
    perform * from public.hercule_quota(v_a);
    raise exception 'T3 quota Hercule lu au nom d''un autre';
  exception when sqlstate 'KR011' then null;
  end;
  raise notice 'T3 OK — usurpation refusée (KR011)';
end $$;

-- T4 : le parcours normal fonctionne toujours.
do $$
declare v_a uuid := current_setting('test.a')::uuid; v_b uuid := current_setting('test.b')::uuid;
begin
  perform pg_temp.act_as(v_a);
  perform public.send_friend_request(v_a, v_b);
  perform pg_temp.act_as(v_b);
  perform public.accept_friend_request(v_b, v_a);
  if not public.are_friends(v_a, v_b) then raise exception 'T4 amitié non établie'; end if;
  raise notice 'T4 OK — demande envoyée puis acceptée par les bons comptes';
end $$;

-- T5 : un appel serveur, sans session, passe toujours l'enveloppe.
do $$
declare v_a uuid := current_setting('test.a')::uuid;
begin
  perform pg_temp.act_as(null);
  perform * from public.hercule_quota(v_a);
  raise notice 'T5 OK — appel serveur sans session accepté';
end $$;

-- T6 : recherche par pseudo, avec la relation.
do $$
declare v_a uuid := current_setting('test.a')::uuid; r record; n int;
begin
  perform pg_temp.act_as(v_a);
  select * into r from public.search_users('BRU');
  if r.username <> 'bruno' or r.relation <> 'friend' then
    raise exception 'T6 bruno attendu en ami, obtenu % / %', r.username, r.relation;
  end if;
  select count(*) into n from public.search_users('b');
  if n <> 0 then raise exception 'T6 un seul caractère ne doit rien renvoyer'; end if;
  select count(*) into n from public.search_users('_');
  if n <> 0 then raise exception 'T6 « _ » doit être pris au pied de la lettre'; end if;
  select count(*) into n from public.search_users('du_7');
  if n <> 1 then raise exception 'T6 « du_7 » devrait trouver chloe_du_75'; end if;
  select count(*) into n from public.search_users('ali');
  if n <> 0 then raise exception 'T6 on ne se trouve pas soi-même'; end if;
  raise notice 'T6 OK — recherche, relation et jokers';
end $$;

-- T7 : classement par période contre la valeur de la veille.
do $$
declare
  v_a uuid := current_setting('test.a')::uuid; v_b uuid := current_setting('test.b')::uuid;
  v_pa uuid; v_pb uuid; r record;
begin
  insert into public.securities (symbol, name, currency, asset_type) values ('AI', 'Air Liquide', 'EUR', 'stock');
  insert into public.quotes_cache (symbol, price, open, change_pct, fetched_at) values ('AI', 110, 110, 0, now());

  -- Deux portefeuilles ouverts il y a un an, de 1 000 €.
  insert into public.portfolios (user_id, mode, cash_cents, created_at)
    values (v_a, 'paper', 0, now() - interval '1 year') returning id into v_pa;
  insert into public.portfolios (user_id, mode, cash_cents, created_at)
    values (v_b, 'paper', 100000, now() - interval '1 year') returning id into v_pb;
  -- Alice : 10 parts d'Air Liquide à 100 €, aujourd'hui à 110 € → 1 100 €.
  insert into public.positions (portfolio_id, symbol, quantity, avg_cost_cents) values (v_pa, 'AI', 10, 10000);
  insert into public.orders (portfolio_id, symbol, side, amount_cents, quantity, executed_price, created_at)
    values (v_pa, 'AI', 'buy', 100000, 10, 100, now() - interval '1 year');
  -- Valeur d'Alice la veille : 1 050 €. Bruno n'a rien fait : 1 000 €.
  insert into public.portfolio_snapshots values (v_pa, current_date - 1, 105000), (v_pb, current_date - 1, 100000);

  perform pg_temp.act_as(v_b);
  select * into r from public.arena_leaderboard('day', 'friends') where username = 'alice';
  -- (1 100 − 1 050) / 1 050 = 4,76 %
  if r.performance_pct <> 4.76 or r.place <> 1 then
    raise exception 'T7 jour : alice attendue 1re à 4,76 %%, obtenu % à %', r.place, r.performance_pct;
  end if;
  select * into r from public.arena_leaderboard('all', 'friends') where username = 'alice';
  if r.performance_pct <> 10.00 then raise exception 'T7 depuis le début : 10 %% attendus, obtenu %', r.performance_pct; end if;
  select * into r from public.arena_leaderboard('day', 'global') where is_me;
  if r.username <> 'bruno' or r.place <> 2 then raise exception 'T7 bruno doit se voir 2e, obtenu %', r.position; end if;
  raise notice 'T7 OK — performance du jour contre la veille, historique contre 1 000 €';
end $$;

-- T8 : sans ordre, on n'entre pas dans le classement général (sauf soi).
do $$
declare v_c uuid := current_setting('test.c')::uuid; n int;
begin
  insert into public.portfolios (user_id, mode, cash_cents) values (v_c, 'paper', 100000);
  perform pg_temp.act_as(current_setting('test.a')::uuid);
  select count(*) into n from public.arena_leaderboard('all', 'global') where username = 'chloe_du_75';
  if n <> 0 then raise exception 'T8 un joueur sans ordre figure au classement général'; end if;
  perform pg_temp.act_as(v_c);
  select count(*) into n from public.arena_leaderboard('all', 'global') where is_me;
  if n <> 1 then raise exception 'T8 on doit toujours se voir soi-même'; end if;
  raise notice 'T8 OK — classement général réservé aux joueurs actifs, soi toujours inclus';
end $$;

-- T9 : le rattrapage reconstitue la valeur passée.
do $$
declare v_pa uuid; v_val bigint;
begin
  insert into public.price_history (symbol, date, close) values ('AI', current_date - 30, 95);
  select id into v_pa from public.portfolios where user_id = current_setting('test.a')::uuid;
  delete from public.portfolio_snapshots where portfolio_id = v_pa;
  perform public.backfill_portfolio_snapshots();
  select total_value_cents into v_val from public.portfolio_snapshots
  where portfolio_id = v_pa and date = current_date - 30;
  -- 0 € de liquidités + 10 parts × 95 € = 950 €.
  if v_val <> 95000 then raise exception 'T9 950 € attendus il y a 30 jours, obtenu %', v_val; end if;
  raise notice 'T9 OK — valeur reconstituée depuis les ordres et les clôtures';
end $$;

do $$ begin raise notice 'TOUS LES TESTS PASSENT'; end $$;
