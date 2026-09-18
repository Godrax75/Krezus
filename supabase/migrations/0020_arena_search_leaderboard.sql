-- =====================================================================
-- Recherche de joueurs, classement par période — et fermeture des
-- fonctions appelables par n'importe qui.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Durcissement
--
-- Supabase accorde l'exécution de toute fonction du schéma public au rôle
-- `anon`, celui d'un visiteur sans compte. Trente-cinq fonctions `security
-- definer` lui étaient ouvertes. Et la garde `assert_is_self` (0015)
-- laisse passer un appel sans session, pour les tâches serveur : elle ne
-- protégeait donc rien contre un appel anonyme. Avec la seule clé publique
-- de l'app, on pouvait passer des ordres dans le portefeuille d'autrui,
-- s'offrir Hercule Premium, rattacher son téléphone au compte d'un autre
-- pour recevoir ses notifications, ou accepter ses demandes d'ami.
--
-- a) Plus aucune fonction à pleins droits n'est exécutable par `anon`.
-- b) Les utilitaires serveur ne le sont plus non plus par `authenticated`.
-- c) Les fonctions appelées par l'app qui prennent l'identifiant de
--    l'utilisateur en paramètre sont enveloppées, comme en 0015 : la
--    version d'origine devient `<nom>_unguarded`, fermée, et une fonction
--    de même nom et même signature vérifie l'appelant avant de déléguer.
--    L'app n'a rien à changer.
-- ---------------------------------------------------------------------

-- a) Aucune fonction à pleins droits pour les visiteurs sans compte.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    execute format('revoke execute on function %s from public, anon', r.sig);
  end loop;
end;
$$;

-- b) Utilitaires serveur : ni l'app ni un visiteur n'ont à les appeler.
do $$
declare
  v_sig text;
begin
  foreach v_sig in array array[
    'public.award_xp(uuid, integer)',
    'public.award_badge(uuid, text)',
    'public.notify(uuid, text, text, text)',
    'public.complete_mission(uuid, text)',
    'public.touch_streak(uuid)',
    'public.record_hercule_exchange(uuid, text, text)',
    'public.record_hercule_subscription(uuid, text, text, timestamptz, text)'
  ] loop
    if to_regprocedure(v_sig) is not null then
      execute format('revoke execute on function %s from authenticated', v_sig);
      execute format('grant execute on function %s to service_role', v_sig);
    end if;
  end loop;
end;
$$;

-- c) Enveloppes vérifiant l'appelant. Le premier paramètre est toujours
--    l'utilisateur concerné.
do $$
declare
  v_sig    text;
  v_oid    oid;
  v_name   text;
  v_args   text;
  v_idargs text;
  v_result text;
  v_first  text;
  v_call   text;
  v_body   text;
begin
  foreach v_sig in array array[
    'public.complete_lesson(uuid, uuid, boolean)',
    'public.record_quiz_attempt(uuid, integer, integer)',
    'public.save_investor_profile(uuid, jsonb, text, jsonb)',
    'public.hercule_quota(uuid)',
    'public.send_friend_request(uuid, uuid)',
    'public.accept_friend_request(uuid, uuid)',
    'public.remove_friend(uuid, uuid)',
    'public.create_arena_group(uuid, text)',
    'public.join_arena_group(uuid, text)',
    'public.leave_arena_group(uuid, uuid)'
  ] loop
    v_oid := to_regprocedure(v_sig);
    continue when v_oid is null;
    select p.proname into v_name from pg_proc p where p.oid = v_oid;
    -- Déjà enveloppée (migration rejouée) : rien à faire.
    continue when to_regprocedure(replace(v_sig, v_name || '(', v_name || '_unguarded(')) is not null;

    v_args   := pg_get_function_arguments(v_oid);
    v_idargs := pg_get_function_identity_arguments(v_oid);
    v_result := pg_get_function_result(v_oid);
    -- Paramètres d'entrée seulement : pour une fonction « returns table »,
    -- proargnames liste aussi les colonnes renvoyées.
    select string_agg(quote_ident(a), ', ' order by o), (array_agg(quote_ident(a) order by o))[1]
      into v_call, v_first
    from pg_proc p,
         unnest(p.proargnames, coalesce(p.proargmodes, array_fill('i'::"char", array[cardinality(p.proargnames)])))
           with ordinality as t(a, m, o)
    where p.oid = v_oid and m in ('i', 'b', 'v');

    execute format('alter function public.%I(%s) rename to %I', v_name, v_idargs, v_name || '_unguarded');
    execute format('revoke execute on function public.%I(%s) from public, anon, authenticated',
                   v_name || '_unguarded', v_idargs);
    execute format('grant execute on function public.%I(%s) to service_role',
                   v_name || '_unguarded', v_idargs);

    v_body := case
      when v_result = 'void'      then format('perform public.%I(%s);', v_name || '_unguarded', v_call)
      when v_result like 'TABLE%' or v_result like 'SETOF%'
                                  then format('return query select * from public.%I(%s);', v_name || '_unguarded', v_call)
      else                             format('return public.%I(%s);', v_name || '_unguarded', v_call)
    end;

    execute format($f$
      create function public.%I(%s)
      returns %s
      language plpgsql
      security definer
      set search_path = public
      as $w$
      begin
        -- Sans session, l'appel vient d'une tâche serveur : `anon` n'a pas
        -- accès à cette fonction, seul le service role arrive jusqu'ici.
        perform public.assert_is_self(%s);
        %s
      end;
      $w$
    $f$, v_name, v_args, v_result, v_first, v_body);

    execute format('revoke execute on function public.%I(%s) from public, anon', v_name, v_idargs);
    execute format('grant execute on function public.%I(%s) to authenticated, service_role', v_name, v_idargs);
  end loop;
end;
$$;

-- Un jeton ne se supprime que chez son propriétaire.
create or replace function public.delete_device_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;
revoke execute on function public.delete_device_token(text) from public, anon;
grant execute on function public.delete_device_token(text) to authenticated;

-- Le classement n'a pas à être public.
revoke select on public.v_arena_leaderboard from anon;

-- ---------------------------------------------------------------------
-- 2. Recherche de joueurs
--
-- Par pseudo, à partir de deux caractères, vingt résultats au plus : de
-- quoi trouver un ami, pas de quoi aspirer l'annuaire. Aucun montant,
-- aucune photo — les photos sont privées (0016). Chaque résultat dit où
-- l'on en est avec la personne, pour afficher le bon bouton.
-- ---------------------------------------------------------------------
create or replace function public.search_users(p_query text)
returns table (user_id uuid, username text, rank_level integer, relation text)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_me    uuid := auth.uid();
  v_query text := btrim(coalesce(p_query, ''));
  v_like  text;
begin
  if v_me is null then
    raise exception 'Aucune session' using errcode = 'KR010';
  end if;
  if length(v_query) < 2 then
    return;
  end if;
  -- % et _ sont des jokers de LIKE : on les prend au pied de la lettre.
  v_like := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');

  return query
  select p.id, p.username, p.rank_level,
         case
           when f.status = 'accepted'  then 'friend'
           when f.user_id = v_me       then 'sent'
           when f.friend_id = v_me     then 'received'
           else 'none'
         end
  from public.profiles p
  left join public.friendships f
    on (f.user_id = v_me and f.friend_id = p.id) or (f.user_id = p.id and f.friend_id = v_me)
  where p.id <> v_me
    and p.username is not null
    and p.username ilike '%' || v_like || '%'
  order by (lower(p.username) = lower(v_query)) desc,
           (p.username ilike v_like || '%') desc,
           length(p.username), p.username
  limit 20;
end;
$$;

revoke execute on function public.search_users(text) from public, anon;
grant execute on function public.search_users(text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Valeur quotidienne des portefeuilles
--
-- `portfolio_snapshots` existe depuis 0001 sans que rien ne l'alimente.
-- Le classement par période en a besoin : la performance d'une semaine se
-- mesure contre la valeur de la veille du lundi, pour tout le monde.
-- ---------------------------------------------------------------------

-- Valeur courante, au cours du cache — la même que v_arena_leaderboard.
create or replace function public.portfolio_value_cents(p_portfolio uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select po.cash_cents
       + coalesce((select round(sum(p.quantity * q.price * 100))::bigint
                   from public.positions p
                   join public.quotes_cache q on q.symbol = p.symbol
                   where p.portfolio_id = po.id and p.quantity > 0), 0)
  from public.portfolios po
  where po.id = p_portfolio;
$$;

revoke execute on function public.portfolio_value_cents(uuid) from public, anon, authenticated;

-- Photographie du jour, pour tous les portefeuilles papier.
create or replace function public.snapshot_portfolios()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  insert into public.portfolio_snapshots (portfolio_id, date, total_value_cents)
  select po.id, current_date, public.portfolio_value_cents(po.id)
  from public.portfolios po
  where po.mode = 'paper'
  on conflict (portfolio_id, date) do update
    set total_value_cents = excluded.total_value_cents;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.snapshot_portfolios() from public, anon, authenticated;

-- Rattrapage : reconstitue chaque jour écoulé depuis l'ouverture (ou la
-- remise à zéro) de chaque portefeuille, à partir de ses ordres et des
-- clôtures, converties en euros au taux de leur date. C'est le calcul de
-- PortfolioHistory côté app.
create or replace function public.backfill_portfolio_snapshots()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with pf as (
    select po.id, greatest(po.created_at, coalesce(po.reset_at, po.created_at)) as started
    from public.portfolios po
    where po.mode = 'paper'
  ),
  days as (
    select pf.id as pid, pf.started, d::date as day
    from pf, generate_series(pf.started::date, current_date - 1, interval '1 day') as d
  ),
  moves as (
    select dd.pid, dd.day, o.symbol,
           case when o.side = 'buy' then -o.amount_cents else o.amount_cents end as cash_delta,
           case when o.side = 'buy' then o.quantity else -o.quantity end        as qty_delta
    from days dd
    join public.orders o
      on o.portfolio_id = dd.pid and o.status = 'filled'
     and o.created_at >= dd.started and o.created_at < (dd.day + 1)
  ),
  cash as (
    select dd.pid, dd.day, 100000 + coalesce(sum(m.cash_delta), 0) as cash_cents
    from days dd
    left join moves m on m.pid = dd.pid and m.day = dd.day
    group by dd.pid, dd.day
  ),
  holdings as (
    select m.pid, m.day, m.symbol, sum(m.qty_delta) as qty
    from moves m
    group by m.pid, m.day, m.symbol
    having sum(m.qty_delta) > 1e-9
  ),
  valued as (
    select h.pid, h.day,
           sum(h.qty * coalesce(
             (select ph.close
                   / case when s.currency = 'USD'
                          then nullif((select f.rate from public.fx_history f
                                       where f.pair = 'EURUSD' and f.date <= h.day
                                       order by f.date desc limit 1), 0)
                          else 1 end
              from public.price_history ph
              where ph.symbol = h.symbol and ph.date <= h.day
              order by ph.date desc limit 1),
             (select q.price from public.quotes_cache q where q.symbol = h.symbol)
           ) * 100) as positions_cents
    from holdings h
    join public.securities s on s.symbol = h.symbol
    group by h.pid, h.day
  )
  insert into public.portfolio_snapshots (portfolio_id, date, total_value_cents)
  select c.pid, c.day, c.cash_cents + coalesce(round(v.positions_cents), 0)::bigint
  from cash c
  left join valued v on v.pid = c.pid and v.day = c.day
  on conflict (portfolio_id, date) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.backfill_portfolio_snapshots() from public, anon, authenticated;

select public.backfill_portfolio_snapshots();
select public.snapshot_portfolios();

-- Chaque soir après la clôture américaine, week-end compris : le
-- classement « jour » du lundi se mesure contre la veille.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'portfolio-snapshots';
    perform cron.schedule('portfolio-snapshots', '40 22 * * *', 'select public.snapshot_portfolios()');
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Classement par période
--
-- `p_period` : day | week | month | ytd | all. La performance se mesure
-- contre la valeur du portefeuille à la clôture précédant la période —
-- ou contre les 1 000 € de départ si le portefeuille est né (ou a été
-- remis à zéro) pendant la période. « all » mesure contre 1 000 € : c'est
-- le classement historique.
--
-- `p_scope` : global | friends. Le classement général ne retient que les
-- joueurs qui ont passé au moins un ordre — sinon il s'ouvrirait sur une
-- foule d'égalités à 0 % — et s'arrête aux cent premiers. L'appelant y
-- figure toujours, avec son vrai rang.
--
-- Comme v_arena_leaderboard, aucun montant ne sort : pseudo, rang, série
-- et pourcentage.
-- ---------------------------------------------------------------------
create or replace function public.arena_leaderboard(p_period text default 'all',
                                                    p_scope  text default 'global')
returns table (place integer, user_id uuid, username text, rank_level integer,
               streak_days integer, performance_pct numeric, is_me boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_me    uuid := auth.uid();
  v_start date;
begin
  if v_me is null then
    raise exception 'Aucune session' using errcode = 'KR010';
  end if;

  v_start := case p_period
    when 'day'   then current_date
    when 'week'  then date_trunc('week',  now())::date
    when 'month' then date_trunc('month', now())::date
    when 'ytd'   then date_trunc('year',  now())::date
    when 'all'   then null
    else null
  end;
  if p_period not in ('day', 'week', 'month', 'ytd', 'all') then
    raise exception 'Période inconnue' using errcode = 'KR010';
  end if;
  if p_scope not in ('global', 'friends') then
    raise exception 'Portée inconnue' using errcode = 'KR010';
  end if;

  return query
  with players as (
    select po.id as pid, po.user_id as uid,
           greatest(po.created_at, coalesce(po.reset_at, po.created_at)) as started
    from public.portfolios po
    where po.mode = 'paper'
      and (po.user_id = v_me
           or (p_scope = 'global' and exists (select 1 from public.orders o
                                              where o.portfolio_id = po.id and o.status = 'filled'))
           or (p_scope = 'friends' and public.are_friends(v_me, po.user_id)))
  ),
  scored as (
    select pl.uid,
           public.portfolio_value_cents(pl.pid) as now_cents,
           case
             when v_start is null or pl.started::date >= v_start then 100000
             else coalesce((select s.total_value_cents from public.portfolio_snapshots s
                            where s.portfolio_id = pl.pid and s.date < v_start
                            order by s.date desc limit 1), 100000)
           end as base_cents
    from players pl
  ),
  ranked as (
    select sc.uid,
           round((sc.now_cents - sc.base_cents)::numeric * 100 / nullif(sc.base_cents, 0), 2) as pct,
           row_number() over (order by (sc.now_cents - sc.base_cents)::numeric / nullif(sc.base_cents, 0) desc,
                                       sc.uid) as pos
    from scored sc
  )
  select r.pos::integer, r.uid, pr.username, pr.rank_level, pr.streak_days,
         coalesce(r.pct, 0), r.uid = v_me
  from ranked r
  join public.profiles pr on pr.id = r.uid
  where r.pos <= 100 or r.uid = v_me
  order by r.pos;
end;
$$;

revoke execute on function public.arena_leaderboard(text, text) from public, anon;
grant execute on function public.arena_leaderboard(text, text) to authenticated;
