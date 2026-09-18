-- =====================================================================
-- Tests des privilèges colonne sur `profiles` (0017).
-- Exécuté par tools/run_profile_privileges_tests.sh sur un Postgres jetable.
-- Chaque bloc lève une exception si une assertion échoue → le script s'arrête
-- en erreur, ce qui fait échouer le test. Un run complet sans exception = OK.
--
-- Les appels client sont faits `set local role authenticated`, comme le ferait
-- PostgREST : c'est le seul angle qui prouve quoi que ce soit.
-- =====================================================================

\set ON_ERROR_STOP on

-- Compte de test. Le trigger `handle_new_user` (0003) crée profil et
-- portefeuille ; `handle_new_profile` (0005) valide la mission « activate ».
do $$
declare v_uid uuid;
begin
  insert into auth.users (email) values ('lucie@test.fr') returning id into v_uid;
  perform set_config('test.current_user', v_uid::text, false);
  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'Fixture : profil non créé par handle_new_user';
  end if;
end $$;

-- ---- Test 1 : les colonnes serveur sont refusées en 42501 ---------------
-- C'est la faille que 0017 ferme : avant, ce bloc passait sans erreur.
do $$
declare
  v_uid uuid := current_setting('test.current_user')::uuid;
  v_sql text; c text; v_ok int := 0;
begin
  foreach c in array array['premium_until', 'xp', 'rank_level',
                           'streak_days', 'streak_last_at', 'id', 'created_at']
  loop
    v_sql := format('update public.profiles set %I = %L where id = %L', c,
      case c
        when 'premium_until'  then '2099-01-01'
        when 'streak_last_at' then '2030-01-01'
        when 'created_at'     then '2030-01-01'
        when 'id'             then gen_random_uuid()::text
        else '999999'
      end, v_uid);
    begin
      set local role authenticated;
      execute v_sql;
      reset role;
      raise exception 'T1 % reste inscriptible par authenticated', c;
    exception when insufficient_privilege then
      reset role;
      v_ok := v_ok + 1;
    end;
  end loop;
  if v_ok <> 7 then raise exception 'T1 % colonnes refusées sur 7', v_ok; end if;
  raise notice 'T1 OK — 7 colonnes serveur refusées (42501), dont premium_until';
end $$;

-- ---- Test 2 : les colonnes éditées par l'app restent inscriptibles ------
do $$
declare v_uid uuid := current_setting('test.current_user')::uuid; r record;
begin
  set local role authenticated;
  update public.profiles
     set username = 'lucie', dark_mode = true, locale = 'en',
         first_name = 'Lucie', last_name = 'Martin'
   where id = auth.uid();
  reset role;

  select username, dark_mode, locale, first_name, last_name into r
    from public.profiles where id = v_uid;
  if r.username <> 'lucie' or not r.dark_mode or r.locale <> 'en'
     or r.first_name <> 'Lucie' or r.last_name <> 'Martin' then
    raise exception 'T2 écriture client incomplète : %', r;
  end if;
  raise notice 'T2 OK — username, dark_mode, locale, first_name, last_name écrits';
end $$;

-- ---- Test 2 bis : avatar_updated_at, si 0016 est appliqué --------------
do $$
declare v_uid uuid := current_setting('test.current_user')::uuid; v_set boolean;
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'profiles'
                   and column_name = 'avatar_updated_at') then
    raise notice 'T2b — ignoré (0016_avatars.sql non appliqué sur cette base)';
    return;
  end if;
  set local role authenticated;
  execute format('update public.profiles set avatar_updated_at = now() where id = %L', v_uid);
  reset role;
  execute format('select avatar_updated_at is not null from public.profiles where id = %L', v_uid)
    into v_set;
  if not v_set then raise exception 'T2b avatar_updated_at non écrit'; end if;
  raise notice 'T2b OK — avatar_updated_at écrit par le client';
end $$;

-- ---- Test 3 : la RLS protège toujours la ligne d'autrui -----------------
do $$
declare v_other uuid; n int;
begin
  insert into auth.users (email) values ('bob@test.fr') returning id into v_other;
  set local role authenticated;
  update public.profiles set username = 'usurpe' where id = v_other;
  get diagnostics n = row_count;
  reset role;
  if n <> 0 then raise exception 'T3 % ligne(s) d''un autre compte modifiée(s)', n; end if;
  raise notice 'T3 OK — RLS bloque la ligne d''un autre compte (0 ligne touchée)';
end $$;

-- ---- Test 4 : plus d'INSERT ni de DELETE côté client --------------------
do $$
declare v_uid uuid := current_setting('test.current_user')::uuid; v_ok int := 0;
begin
  begin
    set local role authenticated;
    insert into public.profiles (id) values (gen_random_uuid());
    reset role;
    raise exception 'T4 insert client accepté';
  exception when insufficient_privilege then reset role; v_ok := v_ok + 1; end;

  begin
    set local role authenticated;
    delete from public.profiles where id = v_uid;
    reset role;
    raise exception 'T4 delete client accepté';
  exception when insufficient_privilege then reset role; v_ok := v_ok + 1; end;

  if v_ok <> 2 then raise exception 'T4 %/2', v_ok; end if;
  raise notice 'T4 OK — insert et delete client refusés';
end $$;

-- =====================================================================
-- Les fonctions `security definer` doivent être intactes : elles écrivent
-- précisément les colonnes que le Test 1 vient de rendre interdites.
-- Toutes sont appelées en tant que `authenticated`.
-- =====================================================================

-- ---- Test 5 : award_xp écrit toujours xp et rank_level ------------------
do $$
declare v_uid uuid := current_setting('test.current_user')::uuid; v_before int; r record;
begin
  select xp into v_before from public.profiles where id = v_uid;
  set local role authenticated;
  select * into r from public.award_xp(v_uid, 1200);
  reset role;
  if r.xp <> v_before + 1200 then
    raise exception 'T5 xp attendu %, obtenu %', v_before + 1200, r.xp;
  end if;
  if r.rank_level < 2 then raise exception 'T5 rang non recalculé : %', r.rank_level; end if;
  raise notice 'T5 OK — award_xp : xp=% rank=% (triggers rank_up passés)', r.xp, r.rank_level;
end $$;

-- ---- Test 6 : touch_streak écrit toujours streak_days / streak_last_at --
do $$
declare v_uid uuid := current_setting('test.current_user')::uuid; d int; l date;
begin
  set local role authenticated;
  d := public.touch_streak(v_uid);
  reset role;
  select streak_last_at into l from public.profiles where id = v_uid;
  if d < 1 or l <> current_date then
    raise exception 'T6 streak_days=% streak_last_at=%', d, l;
  end if;
  raise notice 'T6 OK — touch_streak : streak_days=% streak_last_at=%', d, l;
end $$;

-- ---- Test 7 : le chemin StoreKit écrit toujours premium_until -----------
-- Le test qui compte : c'est la colonne que le Test 1 verrouille.
do $$
declare v_uid uuid := current_setting('test.current_user')::uuid; v_until timestamptz; v_prem boolean;
begin
  set local role authenticated;
  v_until := public.record_hercule_subscription(
    v_uid, 'krezus.hercule.monthly', 'txn-test-0001', now() + interval '30 days', 'sandbox');
  v_prem := public.is_premium(v_uid);
  reset role;
  if v_until is null or not v_prem then
    raise exception 'T7 premium_until=% is_premium=%', v_until, v_prem;
  end if;
  raise notice 'T7 OK — record_hercule_subscription : premium_until=% is_premium=%', v_until::date, v_prem;
end $$;

-- ---- Test 8 : `select … for update` sur profiles tient toujours ---------
-- record_hercule_exchange verrouille le profil pour sérialiser deux envois.
-- Postgres exige UPDATE sur au moins une colonne pour ce verrou.
do $$
declare v_uid uuid := current_setting('test.current_user')::uuid; r int;
begin
  set local role authenticated;
  select remaining into r from public.record_hercule_exchange(v_uid, 'Bonjour Hercule', 'Bonjour.');
  reset role;
  -- -1 = illimité : le T7 vient de rendre le compte premium (0008, hercule_quota).
  if r is null then raise exception 'T8 record_hercule_exchange n''a rien renvoyé'; end if;
  raise notice 'T8 OK — record_hercule_exchange (select … for update) : remaining=% (-1 = illimité)', r;
end $$;

-- ---- Test 9 : complete_lesson (award_xp + touch_streak enchaînés) -------
do $$
declare v_uid uuid := current_setting('test.current_user')::uuid; v_lesson uuid; r record;
begin
  insert into public.lessons (position, title_fr, title_en, duration_label,
    paragraphs_fr, paragraphs_en, examples_fr, examples_en, quiz_fr, quiz_en, theme, is_free)
  values (999, 'Leçon test', 'Test lesson', '3 min',
    '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, 'bases', true)
  returning id into v_lesson;

  set local role authenticated;
  select * into r from public.complete_lesson(v_uid, v_lesson);
  reset role;
  if r.xp_total is null or r.rank_level is null then
    raise exception 'T9 complete_lesson : %', r;
  end if;
  raise notice 'T9 OK — complete_lesson : xp_gagné=% xp_total=% rang=% série=%',
    r.xp_gained, r.xp_total, r.rank_level, r.streak_days;
end $$;

-- ---- Test 10 : création et suppression de compte ------------------------
do $$
declare v_new uuid; v_xp int; n int;
begin
  insert into auth.users (email) values ('nouveau@test.fr') returning id into v_new;
  select xp into v_xp from public.profiles where id = v_new;
  if v_xp is null then raise exception 'T10 handle_new_user : profil non créé'; end if;
  if v_xp = 0 then raise exception 'T10 handle_new_profile : mission activate non validée'; end if;

  perform set_config('test.current_user', v_new::text, false);
  set local role authenticated;
  perform public.delete_own_account();
  reset role;
  select count(*) into n from public.profiles where id = v_new;
  if n <> 0 then raise exception 'T10 delete_own_account : profil non supprimé'; end if;
  raise notice 'T10 OK — handle_new_user (xp=%) puis delete_own_account (cascade)', v_xp;
end $$;

select 'TOUS LES TESTS OK' as resultat;
