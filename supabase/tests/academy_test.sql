-- =====================================================================
-- Tests du moteur de progression (Lot 5).
-- Exécuté par tools/run_academy_tests.sh sur un Postgres jetable.
--
-- Ce qui compte ici : l'XP ne doit jamais pouvoir être fabriquée en rejouant
-- un appel, et la série doit se comporter correctement aux bornes de journée.
-- =====================================================================

\set ON_ERROR_STOP on

do $$
declare
  v_uid uuid;
begin
  insert into auth.users (email) values ('julie@test.fr') returning id into v_uid;
  perform set_config('test.current_user', v_uid::text, false);
  insert into public.profiles (id) values (v_uid);
end $$;

-- ---- Test 1 : les paliers de rang ---------------------------------------
do $$
begin
  if public.rank_for_xp(0)    <> 1 then raise exception 'T1 rang à 0 XP'; end if;
  if public.rank_for_xp(199)  <> 1 then raise exception 'T1 rang à 199 XP'; end if;
  if public.rank_for_xp(200)  <> 2 then raise exception 'T1 rang à 200 XP'; end if;
  if public.rank_for_xp(999)  <> 5 then raise exception 'T1 rang à 999 XP'; end if;
  if public.rank_for_xp(1000) <> 6 then raise exception 'T1 rang à 1000 XP'; end if;
  -- Borné : pas de rang 7 même à 100 000 XP.
  if public.rank_for_xp(100000) <> 6 then raise exception 'T1 rang non borné'; end if;
  if public.rank_for_xp(-50)    <> 1 then raise exception 'T1 XP négative'; end if;
  raise notice 'T1 OK — paliers de rang bornés à 6';
end $$;

-- ---- Test 2 : « Activer ton compte » acquise à la création --------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_xp  integer;
begin
  select xp into v_xp from public.profiles where id = v_uid;
  if v_xp <> 50 then
    raise exception 'T2 mission activate non créditée (xp = %)', v_xp;
  end if;
  raise notice 'T2 OK — mission ponctuelle créditée à la création du profil';
end $$;

-- ---- Test 3 : une mission ponctuelle ne se rejoue jamais ----------------
do $$
declare
  v_uid    uuid := current_setting('test.current_user')::uuid;
  v_gained integer;
  v_xp     integer;
begin
  v_gained := public.complete_mission(v_uid, 'activate');
  select xp into v_xp from public.profiles where id = v_uid;

  if v_gained <> 0 then raise exception 'T3 XP re-créditée (%)', v_gained; end if;
  if v_xp <> 50 then raise exception 'T3 total XP modifié (%)', v_xp; end if;
  raise notice 'T3 OK — rejouer une mission acquise ne crédite rien';
end $$;

-- ---- Test 4 : complétion de leçon → XP, série, progression --------------
do $$
declare
  v_uid    uuid := current_setting('test.current_user')::uuid;
  v_lesson uuid;
  v_res    record;
begin
  select id into v_lesson from public.lessons where position = 1;

  select * into v_res from public.complete_lesson(v_uid, v_lesson, true);

  -- 20 (leçon du jour) + 30 (quiz du jour) = 50, sur 50 déjà acquis.
  if v_res.xp_gained <> 50 then
    raise exception 'T4 XP gagnée % au lieu de 50', v_res.xp_gained;
  end if;
  if v_res.xp_total <> 100 then
    raise exception 'T4 XP totale % au lieu de 100', v_res.xp_total;
  end if;
  if v_res.streak_days <> 1 then
    raise exception 'T4 série % au lieu de 1', v_res.streak_days;
  end if;
  raise notice 'T4 OK — leçon + quiz créditent 50 XP et démarrent la série';
end $$;

-- ---- Test 5 : refaire une leçon le même jour ne crédite rien -----------
do $$
declare
  v_uid    uuid := current_setting('test.current_user')::uuid;
  v_l1     uuid;
  v_l2     uuid;
  v_res    record;
begin
  select id into v_l1 from public.lessons where position = 1;
  select id into v_l2 from public.lessons where position = 2;

  -- Même leçon, rejouée.
  select * into v_res from public.complete_lesson(v_uid, v_l1, true);
  if v_res.xp_gained <> 0 then
    raise exception 'T5 rejouer la même leçon a crédité %', v_res.xp_gained;
  end if;

  -- Autre leçon, mais les missions du jour sont déjà validées.
  select * into v_res from public.complete_lesson(v_uid, v_l2, true);
  if v_res.xp_gained <> 0 then
    raise exception 'T5 deuxième leçon du jour a crédité %', v_res.xp_gained;
  end if;
  if v_res.xp_total <> 100 then
    raise exception 'T5 XP totale dérive (%)', v_res.xp_total;
  end if;
  raise notice 'T5 OK — les missions du jour plafonnent le gain quotidien';
end $$;

-- ---- Test 6 : la série s'incrémente d'un jour à l'autre -----------------
do $$
declare
  v_uid  uuid := current_setting('test.current_user')::uuid;
  v_days integer;
begin
  -- Simule « hier » : la série doit passer de 1 à 2.
  update public.profiles set streak_last_at = current_date - 1 where id = v_uid;
  v_days := public.touch_streak(v_uid);
  if v_days <> 2 then raise exception 'T6 série % au lieu de 2', v_days; end if;

  -- Rejouer le même jour ne bouge plus rien.
  v_days := public.touch_streak(v_uid);
  if v_days <> 2 then raise exception 'T6 série incrémentée deux fois (%)', v_days; end if;

  raise notice 'T6 OK — série +1 par jour, idempotente dans la journée';
end $$;

-- ---- Test 7 : un trou d'un jour remet la série à 1 ----------------------
do $$
declare
  v_uid  uuid := current_setting('test.current_user')::uuid;
  v_days integer;
begin
  update public.profiles
  set streak_last_at = current_date - 3, streak_days = 12
  where id = v_uid;

  v_days := public.touch_streak(v_uid);
  if v_days <> 1 then raise exception 'T7 série % au lieu de 1 après un trou', v_days; end if;
  raise notice 'T7 OK — série rompue repart à 1';
end $$;

-- ---- Test 8 : badge de série à 7 jours ----------------------------------
do $$
declare
  v_uid  uuid := current_setting('test.current_user')::uuid;
  v_has  integer;
begin
  update public.profiles
  set streak_last_at = current_date - 1, streak_days = 6
  where id = v_uid;
  perform public.touch_streak(v_uid);

  select count(*) into v_has
  from public.user_badges ub
  join public.badges b on b.id = ub.badge_id
  where ub.user_id = v_uid and b.code = 'streak_7';

  if v_has <> 1 then raise exception 'T8 badge streak_7 non attribué'; end if;
  raise notice 'T8 OK — badge de série attribué à 7 jours';
end $$;

-- ---- Test 9 : une leçon payante est refusée sans abonnement -------------
do $$
declare
  v_uid    uuid := current_setting('test.current_user')::uuid;
  v_lesson uuid;
  v_state  text;
begin
  select id into v_lesson from public.lessons where is_free = false limit 1;

  begin
    perform public.complete_lesson(v_uid, v_lesson, true);
    raise exception 'T9 leçon payante acceptée sans abonnement';
  exception when sqlstate 'KR021' then
    v_state := 'KR021';
  end;

  if v_state is distinct from 'KR021' then
    raise exception 'T9 code d''erreur inattendu';
  end if;

  -- Avec un abonnement actif, la même leçon passe.
  update public.profiles set premium_until = now() + interval '30 days' where id = v_uid;
  perform public.complete_lesson(v_uid, v_lesson, true);
  raise notice 'T9 OK — paywall des leçons appliqué puis levé par l''abonnement';
end $$;

-- ---- Test 10 : montée en rang et badge associé --------------------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_res record;
  v_has integer;
begin
  update public.profiles set xp = 190, rank_level = 1 where id = v_uid;

  select * into v_res from public.award_xp(v_uid, 20);
  if v_res.rank_level <> 2 then raise exception 'T10 rang % au lieu de 2', v_res.rank_level; end if;
  if not v_res.ranked_up then raise exception 'T10 montée de rang non signalée'; end if;

  select count(*) into v_has
  from public.user_badges ub
  join public.badges b on b.id = ub.badge_id
  where ub.user_id = v_uid and b.code = 'rank_up';
  if v_has <> 1 then raise exception 'T10 badge rank_up non attribué'; end if;

  raise notice 'T10 OK — montée de rang détectée et badge attribué';
end $$;

-- ---- Test 11 : badge « 4 leçons terminées » -----------------------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_has integer;
begin
  -- Les leçons 1, 2 et une payante sont déjà faites ; la 3 fait le compte.
  perform public.complete_lesson(v_uid, id, true)
  from public.lessons where position = 3;

  select count(*) into v_has
  from public.user_badges ub
  join public.badges b on b.id = ub.badge_id
  where ub.user_id = v_uid and b.code = 'academy_4';

  if v_has <> 1 then raise exception 'T11 badge academy_4 non attribué'; end if;
  raise notice 'T11 OK — badge attribué à la 4e leçon terminée';
end $$;

-- ---- Test 12 : le badge « premier achat » suit l'ordre ------------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_pid uuid;
  v_has integer;
begin
  insert into public.securities (symbol, name, currency, asset_type)
  values ('MC', 'LVMH', 'EUR', 'stock') on conflict do nothing;

  insert into public.portfolios (user_id, mode, cash_cents)
  values (v_uid, 'paper', 100000) returning id into v_pid;

  insert into public.orders (portfolio_id, symbol, side, amount_cents, quantity,
                             executed_price, status)
  values (v_pid, 'MC', 'buy', 10000, 0.2, 500.0, 'filled');

  select count(*) into v_has
  from public.user_badges ub
  join public.badges b on b.id = ub.badge_id
  where ub.user_id = v_uid and b.code = 'first_buy';

  if v_has <> 1 then raise exception 'T12 badge first_buy non attribué'; end if;
  raise notice 'T12 OK — badge premier achat déclenché par le trigger sur orders';
end $$;

-- ---- Test 13 : un score de quiz incohérent est rejeté -------------------
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_raised boolean := false;
begin
  begin
    perform public.record_quiz_attempt(v_uid, 5, 3);
  exception when sqlstate 'KR010' then v_raised := true;
  end;
  if not v_raised then raise exception 'T13 score supérieur au total accepté'; end if;

  perform public.record_quiz_attempt(v_uid, 3, 3);
  raise notice 'T13 OK — score de quiz validé';
end $$;

select ' TOUS LES TESTS PASSENT ' as resultat;
