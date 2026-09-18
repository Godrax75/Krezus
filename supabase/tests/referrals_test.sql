-- =====================================================================
-- Tests du parrainage (0019) et de la fermeture d'award_xp / notify.
-- Exécuté par tools/run_referrals_tests.sh sur un Postgres jetable.
-- Chaque bloc lève une exception si une assertion échoue.
-- =====================================================================

\set ON_ERROR_STOP on

-- Deux comptes récents, Alice (marraine) et Bruno (filleul).
do $$
declare
  v_alice uuid; v_bruno uuid;
begin
  insert into auth.users (email) values ('alice@test.fr') returning id into v_alice;
  insert into auth.users (email) values ('bruno@test.fr') returning id into v_bruno;
  insert into public.profiles (id, username) values (v_alice, 'alice'), (v_bruno, 'bruno');
  perform set_config('test.alice', v_alice::text, false);
  perform set_config('test.bruno', v_bruno::text, false);
end $$;

create or replace function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('test.current_user', p::text, false);
$$;

-- T1 : un code de six caractères, sans caractère ambigu, posé à la création.
do $$
declare v_code text;
begin
  select referral_code into v_code from public.profiles where username = 'alice';
  if v_code !~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$' then
    raise exception 'T1 code inattendu : %', v_code;
  end if;
  raise notice 'T1 OK — code % attribué à la création', v_code;
end $$;

-- T2 : le code est figé, même par une mise à jour de la ligne entière.
do $$
declare v_before text; v_after text;
begin
  select referral_code into v_before from public.profiles where username = 'alice';
  update public.profiles set referral_code = 'ZZZZZZ' where username = 'alice';
  select referral_code into v_after from public.profiles where username = 'alice';
  if v_after <> v_before then raise exception 'T2 code modifié : % → %', v_before, v_after; end if;
  raise notice 'T2 OK — code figé';
end $$;

-- T3 : Bruno saisit le code d'Alice, écrit en minuscules avec un espace.
do $$
declare
  v_alice uuid := current_setting('test.alice')::uuid;
  v_bruno uuid := current_setting('test.bruno')::uuid;
  v_code text; v_xp_a int; v_xp_b int; v_notif int; v_before_a int; v_before_b int;
begin
  -- Écarts plutôt que totaux : la mission « Activer ton compte » crédite
  -- déjà 50 XP à la création du profil.
  select xp into v_before_a from public.profiles where id = v_alice;
  select xp into v_before_b from public.profiles where id = v_bruno;
  select lower(substr(referral_code, 1, 3) || ' ' || substr(referral_code, 4)) into v_code
  from public.profiles where id = v_alice;
  perform pg_temp.act_as(v_bruno);
  perform * from public.redeem_referral_code(v_code);

  select xp - v_before_a into v_xp_a from public.profiles where id = v_alice;
  select xp - v_before_b into v_xp_b from public.profiles where id = v_bruno;
  select count(*) into v_notif from public.notifications where user_id = v_alice and kind = 'referral';
  if v_xp_a <> 100 or v_xp_b <> 100 then raise exception 'T3 XP gagnés : alice %, bruno %', v_xp_a, v_xp_b; end if;
  if v_notif <> 1 then raise exception 'T3 notification attendue, % trouvée(s)', v_notif; end if;
  raise notice 'T3 OK — 100 XP chacun, Alice notifiée';
end $$;

-- T4 : on n'est parrainé qu'une fois (KR072).
do $$
declare v_code text;
begin
  select referral_code into v_code from public.profiles where username = 'alice';
  perform pg_temp.act_as(current_setting('test.bruno')::uuid);
  begin
    perform * from public.redeem_referral_code(v_code);
    raise exception 'T4 un second parrainage est passé';
  exception when sqlstate 'KR072' then null;
  end;
  raise notice 'T4 OK — second parrainage refusé';
end $$;

-- T5 : ni son propre code, ni celui de son filleul (KR071).
do $$
declare v_own text; v_child text;
begin
  select referral_code into v_own   from public.profiles where username = 'alice';
  select referral_code into v_child from public.profiles where username = 'bruno';
  perform pg_temp.act_as(current_setting('test.alice')::uuid);
  begin
    perform * from public.redeem_referral_code(v_own);
    raise exception 'T5 son propre code est passé';
  exception when sqlstate 'KR071' then null;
  end;
  begin
    perform * from public.redeem_referral_code(v_child);
    raise exception 'T5 la boucle A → B → A est passée';
  exception when sqlstate 'KR071' then null;
  end;
  raise notice 'T5 OK — propre code et boucle refusés';
end $$;

-- T6 : code inconnu (KR070).
do $$
begin
  perform pg_temp.act_as(current_setting('test.alice')::uuid);
  begin
    perform * from public.redeem_referral_code('XXXXXX');
    raise exception 'T6 un code inconnu est passé';
  exception when sqlstate 'KR070' then null;
  end;
  raise notice 'T6 OK — code inconnu refusé';
end $$;

-- T7 : au-delà de sept jours d'ancienneté, trop tard (KR073).
do $$
declare v_old uuid; v_code text;
begin
  insert into auth.users (email, created_at) values ('ancien@test.fr', now() - interval '8 days')
    returning id into v_old;
  insert into public.profiles (id, username) values (v_old, 'ancien');
  select referral_code into v_code from public.profiles where username = 'alice';
  perform pg_temp.act_as(v_old);
  begin
    perform * from public.redeem_referral_code(v_code);
    raise exception 'T7 un compte ancien a été parrainé';
  exception when sqlstate 'KR073' then null;
  end;
  raise notice 'T7 OK — délai de sept jours appliqué';
end $$;

-- T8 : au-delà de dix filleuls récompensés, le parrain ne gagne plus d'XP ;
-- le filleul, si.
do $$
declare
  v_alice uuid := current_setting('test.alice')::uuid;
  v_code text; v_new uuid; v_xp_a int; v_xp_new int; v_before_a int; v_before_new int;
begin
  select referral_code into v_code from public.profiles where id = v_alice;
  select xp into v_before_a from public.profiles where id = v_alice;
  for i in 2..11 loop      -- Bruno était le premier : neuf de plus → dix, puis un onzième
    insert into auth.users (email) values ('filleul' || i || '@test.fr') returning id into v_new;
    insert into public.profiles (id, username) values (v_new, 'filleul' || i);
    select xp into v_before_new from public.profiles where id = v_new;
    perform pg_temp.act_as(v_new);
    perform * from public.redeem_referral_code(v_code);
  end loop;
  -- Neuf filleuls de plus, mais seuls les neuf premiers (2 à 10) paient Alice.
  select xp - v_before_a into v_xp_a from public.profiles where id = v_alice;
  select xp - v_before_new into v_xp_new from public.profiles where id = v_new;
  if v_xp_a <> 900 then raise exception 'T8 Alice devrait gagner 900 XP de plus (plafond à dix), a %', v_xp_a; end if;
  if v_xp_new <> 100 then raise exception 'T8 le onzième filleul devrait gagner 100 XP, a %', v_xp_new; end if;
  raise notice 'T8 OK — parrain plafonné à dix récompenses, filleul toujours servi';
end $$;

-- T9 : l'état renvoyé à l'écran.
do $$
declare r record;
begin
  perform pg_temp.act_as(current_setting('test.alice')::uuid);
  select * into r from public.referral_status();
  if r.referred_count <> 11 or r.xp_earned <> 1000 or r.referred_by is not null then
    raise exception 'T9 état inattendu : % filleuls, % XP, parrain %', r.referred_count, r.xp_earned, r.referred_by;
  end if;
  perform pg_temp.act_as(current_setting('test.bruno')::uuid);
  select * into r from public.referral_status();
  if r.can_redeem or r.referred_by <> 'alice' then
    raise exception 'T9 Bruno : can_redeem %, parrain %', r.can_redeem, r.referred_by;
  end if;
  raise notice 'T9 OK — état du parrainage cohérent';
end $$;

-- T10 : award_xp, award_badge et notify ne sont plus exécutables par les
-- rôles de l'API ; les RPC de parrainage le sont par les seuls connectés.
do $$
begin
  if has_function_privilege('anon', 'public.award_xp(uuid, integer)', 'execute')
     or has_function_privilege('authenticated', 'public.award_xp(uuid, integer)', 'execute') then
    raise exception 'T10 award_xp encore exécutable depuis l''API';
  end if;
  if has_function_privilege('anon', 'public.award_badge(uuid, text)', 'execute')
     or has_function_privilege('authenticated', 'public.award_badge(uuid, text)', 'execute') then
    raise exception 'T10 award_badge encore exécutable depuis l''API';
  end if;
  if has_function_privilege('anon', 'public.notify(uuid, text, text, text)', 'execute') then
    raise exception 'T10 notify encore exécutable par anon';
  end if;
  if has_function_privilege('anon', 'public.redeem_referral_code(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.redeem_referral_code(text)', 'execute') then
    raise exception 'T10 droits de redeem_referral_code incorrects';
  end if;
  raise notice 'T10 OK — fonctions internes fermées à l''API';
end $$;

do $$ begin raise notice 'TOUS LES TESTS PASSENT'; end $$;
