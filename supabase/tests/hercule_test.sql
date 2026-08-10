-- =====================================================================
-- Tests d'Hercule (Lot 8) — quota, abonnement, contexte.
-- Exécuté par tools/run_hercule_tests.sh sur un Postgres jetable.
--
-- Le quota est une monnaie : s'il se décompte côté client, il ne se décompte
-- pas. Ces tests vérifient qu'on ne peut ni le contourner, ni raccourcir un
-- abonnement en rejouant un vieux reçu.
-- =====================================================================

\set ON_ERROR_STOP on

do $$
declare
  v_uid uuid;
begin
  insert into auth.users (email) values ('lea@test.fr') returning id into v_uid;
  perform set_config('test.user', v_uid::text, false);
  insert into public.profiles (id, username, xp) values (v_uid, 'lea', 120);
end $$;

-- ---- Test 1 : quota gratuit initial --------------------------------------
do $$
declare
  v_uid uuid := current_setting('test.user')::uuid;
  v_q   record;
begin
  select * into v_q from public.hercule_quota(v_uid);

  if v_q.is_premium then raise exception 'T1 premium par défaut'; end if;
  if v_q.daily_quota <> 5 then raise exception 'T1 quota = %', v_q.daily_quota; end if;
  if v_q.remaining <> 5 then raise exception 'T1 restant = %', v_q.remaining; end if;
  raise notice 'T1 OK — 5 messages gratuits par jour';
end $$;

-- ---- Test 2 : chaque échange décrémente le quota -------------------------
do $$
declare
  v_uid uuid := current_setting('test.user')::uuid;
  v_r   integer;
begin
  select remaining into v_r
  from public.record_hercule_exchange(v_uid, 'C''est quoi un dividende ?', 'Une part des bénéfices.');

  if v_r <> 4 then raise exception 'T2 restant = % au lieu de 4', v_r; end if;

  -- Les deux messages du tour sont bien persistés.
  if (select count(*) from public.hercule_messages where user_id = v_uid) <> 2 then
    raise exception 'T2 tour non enregistré';
  end if;
  raise notice 'T2 OK — un échange consomme un crédit et enregistre les deux messages';
end $$;

-- ---- Test 3 : quota épuisé rejeté ---------------------------------------
do $$
declare
  v_uid    uuid := current_setting('test.user')::uuid;
  v_raised boolean := false;
  i        integer;
begin
  for i in 1..4 loop
    perform public.record_hercule_exchange(v_uid, 'question ' || i, 'réponse ' || i);
  end loop;

  begin
    perform public.record_hercule_exchange(v_uid, 'une de trop', 'réponse');
  exception when sqlstate 'KR050' then v_raised := true;
  end;

  if not v_raised then raise exception 'T3 6e message accepté'; end if;
  -- Le message refusé ne doit pas avoir été écrit.
  if (select count(*) from public.hercule_messages where user_id = v_uid) <> 10 then
    raise exception 'T3 message refusé tout de même enregistré';
  end if;
  raise notice 'T3 OK — quota épuisé rejeté, rien écrit';
end $$;

-- ---- Test 4 : l'abonnement lève le plafond ------------------------------
do $$
declare
  v_uid uuid := current_setting('test.user')::uuid;
  v_q   record;
  v_r   integer;
begin
  perform public.record_hercule_subscription(
    v_uid, 'com.krezus.hercule.monthly', 'tx-0001', now() + interval '30 days');

  select * into v_q from public.hercule_quota(v_uid);
  if not v_q.is_premium then raise exception 'T4 abonnement non pris en compte'; end if;
  if v_q.remaining <> -1 then raise exception 'T4 restant = % au lieu de -1', v_q.remaining; end if;

  -- Et l'envoi passe malgré les 5 messages déjà consommés.
  select remaining into v_r
  from public.record_hercule_exchange(v_uid, 'question premium', 'réponse');
  if v_r <> -1 then raise exception 'T4 envoi premium plafonné (%)', v_r; end if;

  raise notice 'T4 OK — abonnement déplafonne le quota';
end $$;

-- ---- Test 5 : un reçu rejoué ne raccourcit pas l'abonnement -------------
do $$
declare
  v_uid    uuid := current_setting('test.user')::uuid;
  v_before timestamptz;
  v_after  timestamptz;
  v_count  integer;
begin
  select premium_until into v_before from public.profiles where id = v_uid;

  -- Un vieux reçu, rejoué : ni la date ni le nombre de lignes ne doivent bouger.
  v_after := public.record_hercule_subscription(
    v_uid, 'com.krezus.hercule.monthly', 'tx-0000', now() + interval '1 day');

  if v_after < v_before then
    raise exception 'T5 abonnement raccourci : % < %', v_after, v_before;
  end if;

  -- Et le même identifiant de transaction ne crée pas de doublon.
  perform public.record_hercule_subscription(
    v_uid, 'com.krezus.hercule.monthly', 'tx-0001', now() + interval '30 days');
  select count(*) into v_count from public.hercule_subscriptions where user_id = v_uid;
  if v_count <> 2 then raise exception 'T5 % lignes au lieu de 2', v_count; end if;

  raise notice 'T5 OK — reçu rejoué sans effet, premium_until ne recule jamais';
end $$;

-- ---- Test 6 : messages invalides rejetés --------------------------------
do $$
declare
  v_uid    uuid := current_setting('test.user')::uuid;
  v_raised boolean;
begin
  v_raised := false;
  begin perform public.record_hercule_exchange(v_uid, '   ', 'réponse');
  exception when sqlstate 'KR051' then v_raised := true; end;
  if not v_raised then raise exception 'T6 message vide accepté'; end if;

  v_raised := false;
  begin perform public.record_hercule_exchange(v_uid, repeat('a', 2001), 'réponse');
  exception when sqlstate 'KR051' then v_raised := true; end;
  if not v_raised then raise exception 'T6 message trop long accepté'; end if;

  raise notice 'T6 OK — message vide et message trop long rejetés';
end $$;

-- ---- Test 7 : le contexte n'expose aucun montant ------------------------
do $$
declare
  v_leak text;
begin
  select string_agg(column_name, ', ') into v_leak
  from information_schema.columns
  where table_schema = 'public' and table_name = 'v_hercule_context'
    and (column_name like '%cents%' or column_name like '%cash%'
      or column_name like '%amount%' or column_name like '%value%'
      or column_name like '%price%');

  if v_leak is not null then
    raise exception 'T7 le contexte envoyé au modèle expose : %', v_leak;
  end if;
  raise notice 'T7 OK — contexte sans montant';
end $$;

-- ---- Test 8 : le contexte remonte bien les titres détenus ---------------
do $$
declare
  v_uid  uuid := current_setting('test.user')::uuid;
  v_pid  uuid;
  v_ctx  record;
begin
  insert into public.securities (symbol, name, currency, asset_type, sector)
  values ('NVDA', 'Nvidia', 'USD', 'stock', 'Semi-conducteurs');
  insert into public.quotes_cache (symbol, price, fetched_at) values ('NVDA', 150.00, now());

  insert into public.portfolios (user_id, mode, cash_cents)
  values (v_uid, 'paper', 100000) returning id into v_pid;
  insert into public.positions (portfolio_id, symbol, quantity, avg_cost_cents)
  values (v_pid, 'NVDA', 0.45, 15000);

  select * into v_ctx from public.v_hercule_context where user_id = v_uid;

  if jsonb_array_length(v_ctx.holdings) <> 1 then
    raise exception 'T8 % titre(s) remonté(s)', jsonb_array_length(v_ctx.holdings);
  end if;
  if v_ctx.holdings->0->>'name' <> 'Nvidia' then
    raise exception 'T8 titre inattendu : %', v_ctx.holdings->0;
  end if;
  -- Le titre est nommé, la quantité ne l'est pas.
  if v_ctx.holdings->0 ? 'quantity' then
    raise exception 'T8 la quantité détenue est transmise au modèle';
  end if;
  if not v_ctx.is_premium then raise exception 'T8 statut premium non reflété'; end if;

  raise notice 'T8 OK — titres transmis, quantités non';
end $$;

select ' TOUS LES TESTS PASSENT ' as resultat;
