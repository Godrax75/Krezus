-- =====================================================================
-- Tests des notifications et des jetons de push (Lot 9).
-- Exécuté par tools/run_notifications_tests.sh sur un Postgres jetable.
--
-- Deux invariants dominent : une notification part toujours au bon
-- destinataire (jamais à l'émetteur d'une demande, jamais au portefeuille
-- voisin), et un jeton d'appareil ne peut pas être rattaché au compte d'un
-- autre — sans quoi il suffirait d'appeler la RPC avec l'UUID d'autrui pour
-- recevoir ses alertes.
-- =====================================================================

\set ON_ERROR_STOP on

do $$
declare
  v_a uuid; v_b uuid;
begin
  insert into auth.users (email) values ('alice@test.fr') returning id into v_a;
  insert into auth.users (email) values ('bruno@test.fr') returning id into v_b;

  perform set_config('test.alice', v_a::text, false);
  perform set_config('test.bruno', v_b::text, false);

  insert into public.profiles (id, username) values (v_a, 'alice'), (v_b, 'bruno');

  insert into public.securities (symbol, name, currency, asset_type, sector)
  values ('NVDA', 'Nvidia', 'USD', 'stock', 'Semi-conducteurs');

  insert into public.portfolios (user_id, mode, cash_cents) values (v_a, 'paper', 100000);
end $$;

-- ---- Test 1 : un ordre exécuté notifie son propriétaire ----------------
do $$
declare
  v_a   uuid := current_setting('test.alice')::uuid;
  v_pid uuid;
  v_row record;
begin
  select id into v_pid from public.portfolios where user_id = v_a;

  insert into public.orders (portfolio_id, symbol, side, amount_cents,
                             quantity, executed_price, status)
  values (v_pid, 'NVDA', 'buy', 10000, 0.45, 178.45, 'filled');

  select * into v_row from public.notifications
  where user_id = v_a and kind = 'order';

  if v_row is null then raise exception 'T1 aucune notification d''ordre'; end if;
  if v_row.title not like 'Achat exécuté%' then
    raise exception 'T1 titre inattendu : %', v_row.title;
  end if;
  if v_row.read_at is not null then
    raise exception 'T1 la notification naît déjà lue';
  end if;
  raise notice 'T1 OK — ordre exécuté notifié au propriétaire';
end $$;

-- ---- Test 2 : un ordre rejeté ne notifie pas --------------------------
do $$
declare
  v_a   uuid := current_setting('test.alice')::uuid;
  v_pid uuid;
  v_n   integer;
begin
  select id into v_pid from public.portfolios where user_id = v_a;

  insert into public.orders (portfolio_id, symbol, side, amount_cents,
                             quantity, executed_price, status)
  values (v_pid, 'NVDA', 'buy', 900000, 0, 178.45, 'rejected');

  select count(*) into v_n from public.notifications
  where user_id = v_a and kind = 'order';

  if v_n <> 1 then raise exception 'T2 % notifications d''ordre au lieu de 1', v_n; end if;
  raise notice 'T2 OK — ordre rejeté silencieux';
end $$;

-- ---- Test 3 : le passage de rang notifie, la stagnation non -----------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_n integer;
  v_body text;
begin
  update public.profiles set rank_level = 2 where id = v_a;

  select count(*) into v_n from public.notifications
  where user_id = v_a and kind = 'rank_up';
  if v_n <> 1 then raise exception 'T3 % notifications de rang au lieu de 1', v_n; end if;

  select body into v_body from public.notifications
  where user_id = v_a and kind = 'rank_up';
  if v_body not like 'Prochain palier%' then
    raise exception 'T3 le corps n''annonce pas le palier suivant : %', v_body;
  end if;

  -- Une mise à jour qui ne change pas le rang ne doit rien produire.
  update public.profiles set xp = 250 where id = v_a;
  select count(*) into v_n from public.notifications
  where user_id = v_a and kind = 'rank_up';
  if v_n <> 1 then raise exception 'T3 le rang inchangé a notifié'; end if;

  raise notice 'T3 OK — passage de rang notifié une seule fois';
end $$;

-- ---- Test 4 : la demande d'ami notifie le destinataire, pas l'émetteur -
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_b uuid := current_setting('test.bruno')::uuid;
  v_n integer;
  v_title text;
begin
  perform public.send_friend_request(v_a, v_b);

  select count(*) into v_n from public.notifications
  where user_id = v_a and kind = 'friend_request';
  if v_n <> 0 then raise exception 'T4 l''émetteur a été notifié de sa propre demande'; end if;

  select title into v_title from public.notifications
  where user_id = v_b and kind = 'friend_request';
  if v_title is null then raise exception 'T4 le destinataire n''a rien reçu'; end if;
  if v_title not like 'alice%' then
    raise exception 'T4 le pseudo de l''émetteur manque : %', v_title;
  end if;

  raise notice 'T4 OK — demande d''ami notifiée au bon destinataire';
end $$;

-- ---- Test 5 : un badge obtenu notifie --------------------------------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_badge uuid;
  v_label text;
  v_n integer;
begin
  -- L'achat du T1 a déjà déclenché `first_buy` via le trigger de l'Academy :
  -- on prend un badge que le compte n'a pas encore, sinon la clé primaire
  -- rejette l'insertion avant même que le déclencheur s'exécute.
  select b.id, b.title_fr into v_badge, v_label
  from public.badges b
  where not exists (
    select 1 from public.user_badges ub
    where ub.user_id = v_a and ub.badge_id = b.id)
  limit 1;
  if v_badge is null then raise exception 'T5 aucun badge disponible'; end if;

  insert into public.user_badges (user_id, badge_id) values (v_a, v_badge);

  select count(*) into v_n from public.notifications
  where user_id = v_a and kind = 'badge' and title like '%' || v_label || '%';
  if v_n <> 1 then raise exception 'T5 % notifications pour le badge %', v_n, v_label; end if;
  raise notice 'T5 OK — badge notifié';
end $$;

-- ---- Test 6 : un type de notification inconnu est refusé --------------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
begin
  begin
    insert into public.notifications (user_id, kind, title)
    values (v_a, 'promotion', 'Achetez Nvidia maintenant');
    raise exception 'T6 un type inconnu a été accepté';
  exception
    when check_violation then null;   -- comportement attendu
  end;
  raise notice 'T6 OK — type de notification inconnu rejeté';
end $$;

-- ---- Test 7 : un jeton réattribué change de compte sans doublon -------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_b uuid := current_setting('test.bruno')::uuid;
  v_owner uuid;
  v_n integer;
begin
  perform public.upsert_device_token(v_a, 'apns-token-1', 'ios');
  perform public.upsert_device_token(v_b, 'apns-token-1', 'ios');

  select count(*) into v_n from public.device_tokens where token = 'apns-token-1';
  if v_n <> 1 then raise exception 'T7 % lignes pour un même jeton', v_n; end if;

  select user_id into v_owner from public.device_tokens where token = 'apns-token-1';
  if v_owner <> v_b then raise exception 'T7 le jeton n''a pas suivi le nouveau compte'; end if;

  raise notice 'T7 OK — jeton réattribué proprement';
end $$;

-- ---- Test 8 : on ne rattache pas un jeton au compte d'un autre --------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_b uuid := current_setting('test.bruno')::uuid;
begin
  -- Session ouverte au nom d'alice, tentative d'écriture pour bruno.
  perform set_config('test.current_user', v_a::text, false);
  begin
    perform public.upsert_device_token(v_b, 'apns-token-vol', 'ios');
    raise exception 'T8 un jeton a été rattaché au compte d''un autre';
  exception
    when sqlstate 'KR010' then null;  -- comportement attendu
  end;
  perform set_config('test.current_user', '', false);
  raise notice 'T8 OK — rattachement croisé refusé';
end $$;

-- ---- Test 9 : la suppression de compte efface tout en cascade ---------
do $$
declare
  v_a uuid := current_setting('test.alice')::uuid;
  v_n integer;
begin
  perform public.upsert_device_token(v_a, 'apns-token-alice', 'ios');
  perform set_config('test.current_user', v_a::text, false);

  perform public.delete_own_account();

  select count(*) into v_n from auth.users where id = v_a;
  if v_n <> 0 then raise exception 'T9 le compte existe encore'; end if;

  select count(*) into v_n from public.notifications where user_id = v_a;
  if v_n <> 0 then raise exception 'T9 % notifications survivantes', v_n; end if;

  select count(*) into v_n from public.device_tokens where user_id = v_a;
  if v_n <> 0 then raise exception 'T9 % jetons survivants', v_n; end if;

  select count(*) into v_n from public.portfolios where user_id = v_a;
  if v_n <> 0 then raise exception 'T9 le portefeuille survit'; end if;

  perform set_config('test.current_user', '', false);
  raise notice 'T9 OK — suppression de compte en cascade';
end $$;

-- ---- Test 10 : sans session, la suppression est refusée --------------
do $$
begin
  begin
    perform public.delete_own_account();
    raise exception 'T10 suppression acceptée sans session';
  exception
    when sqlstate 'KR010' then null;  -- comportement attendu
  end;
  raise notice 'T10 OK — suppression refusée hors session';
end $$;

select ' TOUS LES TESTS PASSENT ' as resultat;
