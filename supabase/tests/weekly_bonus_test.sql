-- =====================================================================
-- Tests de 0021. Exécuté par tools/run_weekly_bonus_tests.sh.
-- Chaque bloc lève une exception si une assertion échoue.
-- =====================================================================

\set ON_ERROR_STOP on

create or replace function pg_temp.act_as(p uuid) returns void language sql as $$
  select set_config('test.current_user', coalesce(p::text, ''), false);
$$;

do $$
declare v_a uuid; v_b uuid;
begin
  insert into auth.users (email) values ('alice@t.fr') returning id into v_a;
  insert into auth.users (email) values ('bruno@t.fr') returning id into v_b;
  -- Le trigger d'inscription n'est pas posé ici : profils et portefeuilles à la main.
  insert into public.profiles (id, username) values (v_a, 'Alice'), (v_b, null);
  insert into public.portfolios (user_id, mode, cash_cents, created_at)
  values (v_a, 'paper', 100000, now() - interval '20 days'),
         (v_b, 'paper', 100000, now());
  perform set_config('test.a', v_a::text, false);
  perform set_config('test.b', v_b::text, false);
end $$;

-- T1 : la semaine d'ouverture ne verse rien, les 1 000 € en tiennent lieu.
do $$
declare v_b uuid := current_setting('test.b')::uuid; v_credit bigint;
begin
  perform pg_temp.act_as(v_b);
  select credited_cents into v_credit from public.claim_weekly_bonus();
  if v_credit <> 0 then raise exception 'T1 bonus versé la semaine d''ouverture (%)', v_credit; end if;
  if (select cash_cents from public.portfolios where user_id = v_b) <> 100000 then
    raise exception 'T1 liquidités modifiées';
  end if;
  raise notice 'T1 OK — rien la semaine d''ouverture';
end $$;

-- T2 : 300 € une fois par semaine, pas deux.
do $$
declare v_a uuid := current_setting('test.a')::uuid; v_credit bigint; v_next date;
begin
  perform pg_temp.act_as(v_a);
  select credited_cents, next_week_start into v_credit, v_next from public.claim_weekly_bonus();
  if v_credit <> 30000 then raise exception 'T2 premier passage : % au lieu de 30000', v_credit; end if;
  if v_next <> public.current_bonus_week() + 7 then raise exception 'T2 prochaine semaine fausse'; end if;
  select credited_cents into v_credit from public.claim_weekly_bonus();
  if v_credit <> 0 then raise exception 'T2 second versement dans la semaine'; end if;
  if (select cash_cents from public.portfolios where user_id = v_a) <> 130000 then
    raise exception 'T2 liquidités : %', (select cash_cents from public.portfolios where user_id = v_a);
  end if;
  raise notice 'T2 OK — 300 € une seule fois par semaine';
end $$;

-- T3 : l'apport n'est pas une performance.
do $$
declare v_a uuid := current_setting('test.a')::uuid; v_pct numeric;
begin
  perform pg_temp.act_as(v_a);
  select performance_pct into v_pct from public.arena_leaderboard('all', 'global') where is_me;
  if v_pct <> 0 then raise exception 'T3 classement « all » : % au lieu de 0', v_pct; end if;
  select performance_pct into v_pct from public.v_arena_leaderboard where user_id = v_a;
  if v_pct <> 0 then raise exception 'T3 vue historique : % au lieu de 0', v_pct; end if;
  raise notice 'T3 OK — l''apport ne compte pas comme un gain';
end $$;

-- T4 : sur une période, seuls les apports postérieurs au relevé de base
-- sont retirés. Relevé de la semaine dernière : 1 100 € dont 0 apport ;
-- aujourd'hui 1 300 € dont 300 € versés depuis → +0 %, et non +18 %.
do $$
declare v_a uuid := current_setting('test.a')::uuid; v_pid uuid; v_pct numeric;
begin
  select id into v_pid from public.portfolios where user_id = v_a;
  update public.portfolios set cash_cents = 140000 where id = v_pid;   -- 1 100 € + 300 €
  insert into public.portfolio_snapshots (portfolio_id, date, total_value_cents, deposits_cents)
  values (v_pid, date_trunc('week', now())::date - 3, 110000, 0);
  perform pg_temp.act_as(v_a);
  select performance_pct into v_pct from public.arena_leaderboard('week', 'global') where is_me;
  if v_pct <> 0 then raise exception 'T4 semaine : % au lieu de 0', v_pct; end if;

  -- Et un apport déjà contenu dans le relevé n'est pas retiré deux fois.
  update public.portfolio_snapshots set deposits_cents = 30000, total_value_cents = 140000
  where portfolio_id = v_pid;
  select performance_pct into v_pct from public.arena_leaderboard('week', 'global') where is_me;
  if v_pct <> 0 then raise exception 'T4 apport compté deux fois : %', v_pct; end if;
  raise notice 'T4 OK — performance de période hors apports';
end $$;

-- T5 : le relevé du soir retient le cumul des apports.
do $$
declare v_a uuid := current_setting('test.a')::uuid; v_dep bigint;
begin
  perform pg_temp.act_as(null);
  perform public.snapshot_portfolios();
  select s.deposits_cents into v_dep from public.portfolio_snapshots s
  join public.portfolios po on po.id = s.portfolio_id
  where po.user_id = v_a and s.date = current_date;
  if v_dep <> 30000 then raise exception 'T5 cumul relevé : %', v_dep; end if;
  raise notice 'T5 OK — relevé avec cumul des apports';
end $$;

-- T6 : pseudo unique sans égard à la casse, format contrôlé.
do $$
declare v_a uuid := current_setting('test.a')::uuid; v_b uuid := current_setting('test.b')::uuid;
begin
  perform pg_temp.act_as(v_b);
  if public.username_available('alice') then raise exception 'T6 « alice » dit libre'; end if;
  if not public.username_available('bruno_75') then raise exception 'T6 « bruno_75 » dit pris'; end if;
  if public.username_available('a b') then raise exception 'T6 espace accepté'; end if;
  begin
    perform public.set_profile_identity('Bruno', 'ALICE');
    raise exception 'T6 pseudo pris accepté';
  exception when sqlstate 'KR080' then null;
  end;
  begin
    perform public.set_profile_identity('Bruno', 'x');
    raise exception 'T6 pseudo trop court accepté';
  exception when sqlstate 'KR081' then null;
  end;
  perform public.set_profile_identity('  Bruno ', 'bruno_75');
  if (select username || '/' || first_name from public.profiles where id = v_b) <> 'bruno_75/Bruno' then
    raise exception 'T6 identité mal enregistrée';
  end if;
  -- Son propre pseudo reste disponible pour soi.
  if not public.username_available('Bruno_75') then raise exception 'T6 son propre pseudo dit pris'; end if;

  -- Même en contournant la fonction, l'index refuse le doublon.
  begin
    update public.profiles set username = 'BRUNO_75' where id = v_a;
    raise exception 'T6 doublon de casse accepté par la table';
  exception when unique_violation then null;
  end;
  raise notice 'T6 OK — pseudo unique et contrôlé';
end $$;

-- T7 : rien d'ouvert aux visiteurs sans compte.
do $$
begin
  if has_function_privilege('anon', 'public.claim_weekly_bonus()', 'execute')
     or has_function_privilege('anon', 'public.username_available(text)', 'execute')
     or has_function_privilege('anon', 'public.set_profile_identity(text, text)', 'execute')
     or has_function_privilege('authenticated', 'public.deposits_since(uuid, timestamptz)', 'execute') then
    raise exception 'T7 fonction ouverte à tort';
  end if;
  perform pg_temp.act_as(null);
  begin
    perform public.claim_weekly_bonus();
    raise exception 'T7 versement sans session';
  exception when sqlstate 'KR010' then null;
  end;
  raise notice 'T7 OK — droits d''exécution';
end $$;

select 'TOUS LES TESTS 0021 PASSENT' as resultat;
