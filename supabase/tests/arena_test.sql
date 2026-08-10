-- =====================================================================
-- Tests de l'Arena (Lot 7).
-- Exécuté par tools/run_arena_tests.sh sur un Postgres jetable.
--
-- Priorité aux invariants de confidentialité : le classement et le feed sont
-- lus par des tiers. Une colonne en centimes qui s'y glisserait exposerait le
-- portefeuille d'autrui, et aucun test fonctionnel ne le remarquerait.
-- =====================================================================

\set ON_ERROR_STOP on

do $$
declare
  v_a uuid; v_b uuid; v_c uuid;
begin
  insert into auth.users (email) values ('alice@test.fr') returning id into v_a;
  insert into auth.users (email) values ('bruno@test.fr') returning id into v_b;
  insert into auth.users (email) values ('chloe@test.fr') returning id into v_c;

  perform set_config('test.alice', v_a::text, false);
  perform set_config('test.bruno', v_b::text, false);
  perform set_config('test.chloe', v_c::text, false);

  insert into public.profiles (id, username) values
    (v_a, 'alice'), (v_b, 'bruno'), (v_c, 'chloe');

  insert into public.securities (symbol, name, currency, asset_type, sector)
  values ('NVDA', 'Nvidia', 'USD', 'stock', 'Semi-conducteurs');

  insert into public.quotes_cache (symbol, price, fetched_at) values ('NVDA', 100.00, now());
end $$;

-- ---- Test 1 : le classement n'expose aucun montant ----------------------
do $$
declare
  v_leak text;
begin
  -- Toute colonne évoquant des centimes, du cash ou une valeur absolue est
  -- une fuite. Ce test échoue si quelqu'un en ajoute une plus tard.
  select string_agg(column_name, ', ') into v_leak
  from information_schema.columns
  where table_schema = 'public' and table_name = 'v_arena_leaderboard'
    and (column_name like '%cents%' or column_name like '%cash%'
      or column_name like '%value%' or column_name like '%amount%');

  if v_leak is not null then
    raise exception 'T1 le classement expose des montants : %', v_leak;
  end if;
  raise notice 'T1 OK — classement sans aucune colonne de montant';
end $$;

-- ---- Test 2 : la performance se mesure contre le capital de départ ------
do $$
declare
  v_alice uuid := current_setting('test.alice')::uuid;
  v_pid   uuid;
  v_perf  numeric;
begin
  -- 800 € de cash + 3 parts à 100 € = 1 100 € → +10 %.
  insert into public.portfolios (user_id, mode, cash_cents)
  values (v_alice, 'paper', 80000) returning id into v_pid;
  insert into public.positions (portfolio_id, symbol, quantity, avg_cost_cents)
  values (v_pid, 'NVDA', 3.0, 10000);

  select performance_pct into v_perf
  from public.v_arena_leaderboard where user_id = v_alice;

  if v_perf is distinct from 10.00 then
    raise exception 'T2 performance = % au lieu de 10.00', v_perf;
  end if;
  raise notice 'T2 OK — performance calculée contre les 1 000 EUR de départ';
end $$;

-- ---- Test 3 : vendre pour figer son score ne truque pas le classement ---
do $$
declare
  v_bruno uuid := current_setting('test.bruno')::uuid;
  v_pid   uuid;
  v_perf  numeric;
begin
  -- Bruno n'a que du cash, au niveau du départ : 0 %, pas un score neutre
  -- avantageux.
  insert into public.portfolios (user_id, mode, cash_cents)
  values (v_bruno, 'paper', 100000) returning id into v_pid;

  select performance_pct into v_perf
  from public.v_arena_leaderboard where user_id = v_bruno;

  if v_perf is distinct from 0.00 then
    raise exception 'T3 performance = % au lieu de 0.00', v_perf;
  end if;
  raise notice 'T3 OK — un portefeuille 100 pourcent cash affiche 0 pourcent';
end $$;

-- ---- Test 4 : cycle complet d'une demande d'ami -------------------------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_b uuid := current_setting('test.bruno')::uuid;
begin
  perform public.send_friend_request(v_a, v_b);

  if public.are_friends(v_a, v_b) then
    raise exception 'T4 amitié effective avant acceptation';
  end if;

  perform public.accept_friend_request(v_b, v_a);

  if not public.are_friends(v_a, v_b) then raise exception 'T4 amitié non établie'; end if;
  -- La symétrie compte : le lien est stocké orienté, il doit se lire des deux côtés.
  if not public.are_friends(v_b, v_a) then raise exception 'T4 amitié non symétrique'; end if;

  raise notice 'T4 OK — demande, acceptation, amitié symétrique';
end $$;

-- ---- Test 5 : les demandes aberrantes sont rejetées ---------------------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_b uuid := current_setting('test.bruno')::uuid;
  v_raised boolean;
begin
  v_raised := false;
  begin perform public.send_friend_request(v_a, v_a);
  exception when sqlstate 'KR041' then v_raised := true; end;
  if not v_raised then raise exception 'T5 auto-ajout accepté'; end if;

  -- Doublon, y compris dans le sens inverse.
  v_raised := false;
  begin perform public.send_friend_request(v_b, v_a);
  exception when sqlstate 'KR041' then v_raised := true; end;
  if not v_raised then raise exception 'T5 demande croisée acceptée'; end if;

  v_raised := false;
  begin perform public.send_friend_request(v_a, gen_random_uuid());
  exception when sqlstate 'KR040' then v_raised := true; end;
  if not v_raised then raise exception 'T5 demande vers un inconnu acceptée'; end if;

  raise notice 'T5 OK — auto-ajout, doublon et destinataire inconnu rejetés';
end $$;

-- ---- Test 6 : accepter une demande inexistante échoue -------------------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_c uuid := current_setting('test.chloe')::uuid;
  v_raised boolean := false;
begin
  begin perform public.accept_friend_request(v_c, v_a);
  exception when sqlstate 'KR042' then v_raised := true; end;
  if not v_raised then raise exception 'T6 acceptation sans demande'; end if;
  raise notice 'T6 OK — acceptation sans demande préalable rejetée';
end $$;

-- ---- Test 7 : retirer un ami efface le lien dans les deux sens ----------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_b uuid := current_setting('test.bruno')::uuid;
  v_left integer;
begin
  perform public.remove_friend(v_b, v_a);   -- retiré par l'autre partie

  select count(*) into v_left from public.friendships
  where (user_id = v_a and friend_id = v_b) or (user_id = v_b and friend_id = v_a);

  if v_left <> 0 then raise exception 'T7 % lien(s) subsistant(s)', v_left; end if;
  if public.are_friends(v_a, v_b) then raise exception 'T7 amitié toujours active'; end if;
  raise notice 'T7 OK — suppression symétrique';
end $$;

-- ---- Test 8 : groupes, code d'invitation, adhésion ---------------------
do $$
declare
  v_a    uuid := current_setting('test.alice')::uuid;
  v_b    uuid := current_setting('test.bruno')::uuid;
  v_grp  record;
  v_join uuid;
  v_raised boolean;
  v_members integer;
begin
  select * into v_grp from public.create_arena_group(v_a, 'Les Investisseurs');

  if length(v_grp.invite_code) <> 6 then
    raise exception 'T8 code = % (longueur %)', v_grp.invite_code, length(v_grp.invite_code);
  end if;
  -- Le créateur est membre d'office.
  select count(*) into v_members from public.arena_group_members where group_id = v_grp.id;
  if v_members <> 1 then raise exception 'T8 créateur non membre'; end if;

  -- Adhésion insensible à la casse (le code se transmet à l'oral).
  v_join := public.join_arena_group(v_b, lower(v_grp.invite_code));
  if v_join <> v_grp.id then raise exception 'T8 mauvais groupe rejoint'; end if;

  v_raised := false;
  begin perform public.join_arena_group(v_b, v_grp.invite_code);
  exception when sqlstate 'KR044' then v_raised := true; end;
  if not v_raised then raise exception 'T8 double adhésion acceptée'; end if;

  v_raised := false;
  begin perform public.join_arena_group(v_b, 'ZZZZZZ');
  exception when sqlstate 'KR043' then v_raised := true; end;
  if not v_raised then raise exception 'T8 code invalide accepté'; end if;

  raise notice 'T8 OK — création, adhésion par code, doublon et code invalide';
end $$;

-- ---- Test 9 : le feed d'un ordre ne porte aucun montant ----------------
do $$
declare
  v_a       uuid := current_setting('test.alice')::uuid;
  v_pid     uuid;
  v_payload jsonb;
begin
  select id into v_pid from public.portfolios where user_id = v_a;

  insert into public.orders (portfolio_id, symbol, side, amount_cents, quantity,
                             executed_price, status)
  values (v_pid, 'NVDA', 'buy', 30000, 3.0, 100.0, 'filled');

  select payload into v_payload from public.arena_feed
  where actor_id = v_a and kind = 'buy' order by created_at desc limit 1;

  if v_payload is null then raise exception 'T9 aucun événement publié'; end if;
  if v_payload ? 'amount_cents' or v_payload ? 'quantity' or v_payload ? 'executed_price' then
    raise exception 'T9 le feed expose un montant : %', v_payload;
  end if;
  if v_payload->>'name' <> 'Nvidia' then
    raise exception 'T9 nom du titre absent : %', v_payload;
  end if;

  raise notice 'T9 OK — feed publie le titre, jamais le montant';
end $$;

-- ---- Test 10 : la montée en rang alimente le feed une seule fois -------
do $$
declare
  v_a     uuid := current_setting('test.alice')::uuid;
  v_count integer;
begin
  update public.profiles set xp = 250, rank_level = 2 where id = v_a;
  -- Une mise à jour qui ne change pas le rang ne republie pas.
  update public.profiles set xp = 260 where id = v_a;

  select count(*) into v_count from public.arena_feed
  where actor_id = v_a and kind = 'rank_up';

  if v_count <> 1 then raise exception 'T10 % événements rank_up au lieu de 1', v_count; end if;
  raise notice 'T10 OK — montée de rang publiée une seule fois';
end $$;

-- ---- Test 11 : une leçon rejouée ne republie rien ----------------------
do $$
declare
  v_a      uuid := current_setting('test.alice')::uuid;
  v_lesson uuid;
  v_count  integer;
begin
  insert into public.lessons (position, title_fr, is_free)
  values (1, 'C''est quoi une action ?', true) returning id into v_lesson;

  insert into public.lesson_progress (user_id, lesson_id, completed_at, quiz_correct)
  values (v_a, v_lesson, now(), true);

  update public.lesson_progress set quiz_correct = false
  where user_id = v_a and lesson_id = v_lesson;

  select count(*) into v_count from public.arena_feed
  where actor_id = v_a and kind = 'lesson';

  if v_count <> 1 then raise exception 'T11 % événements leçon au lieu de 1', v_count; end if;
  raise notice 'T11 OK — leçon rejouée ne republie pas';
end $$;

select ' TOUS LES TESTS PASSENT ' as resultat;
