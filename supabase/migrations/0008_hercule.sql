-- =====================================================================
-- Lot 8 — Hercule : quota du chat, abonnement Premium, journal d'usage.
--
-- Le quota se compte et se décrémente **en base**, pas dans l'app : un client
-- qui rejoue une requête ne doit pas pouvoir s'offrir des messages gratuits,
-- exactement comme il ne peut pas fabriquer de cash (0002) ni d'XP (0005).
--
-- Codes SQLSTATE, classe privée « KR » (suite de 0007) :
--   KR050  quota de messages épuisé
--   KR051  message vide ou trop long
--   KR052  reçu d'achat invalide
-- =====================================================================

-- ---------------------------------------------------------------------
-- Paramètres du quota
-- ---------------------------------------------------------------------
-- Le gratuit doit laisser goûter le produit sans le remplacer : 5 messages
-- par jour couvrent une vraie question et ses relances, pas une session.
create table public.hercule_limits (
  id                integer primary key default 1 check (id = 1),
  free_daily_quota  integer not null default 5 check (free_daily_quota >= 0),
  max_message_chars integer not null default 2000 check (max_message_chars > 0)
);

insert into public.hercule_limits (id) values (1) on conflict do nothing;

alter table public.hercule_limits enable row level security;
create policy "limits readable" on public.hercule_limits
  for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- Abonnement
-- ---------------------------------------------------------------------
-- Trace des achats StoreKit. `transaction_id` est l'identifiant Apple : sa
-- contrainte d'unicité est ce qui empêche de rejouer un même reçu.
create table public.hercule_subscriptions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  product_id      text not null,
  transaction_id  text not null unique,
  expires_at      timestamptz not null,
  environment     text not null default 'production'
                  check (environment in ('production', 'sandbox')),
  created_at      timestamptz not null default now()
);

create index on public.hercule_subscriptions (user_id, expires_at desc);

alter table public.hercule_subscriptions enable row level security;
create policy "own subscriptions" on public.hercule_subscriptions
  for select to authenticated using (user_id = auth.uid());

-- Enregistre un achat vérifié et prolonge l'abonnement.
--
-- La vérification cryptographique du reçu se fait dans la Edge Function
-- (clé Apple), pas ici : cette fonction est le point d'écriture, et elle
-- s'exécute en service role. `premium_until` ne recule jamais — un reçu plus
-- ancien rejoué ne peut pas raccourcir un abonnement en cours.
create or replace function public.record_hercule_subscription(
  p_user           uuid,
  p_product_id     text,
  p_transaction_id text,
  p_expires_at     timestamptz,
  p_environment    text default 'production'
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_premium timestamptz;
begin
  if p_transaction_id is null or length(btrim(p_transaction_id)) = 0 then
    raise exception 'Identifiant de transaction manquant' using errcode = 'KR052';
  end if;
  if p_expires_at is null then
    raise exception 'Date d''expiration manquante' using errcode = 'KR052';
  end if;

  insert into public.hercule_subscriptions
    (user_id, product_id, transaction_id, expires_at, environment)
  values (p_user, p_product_id, btrim(p_transaction_id), p_expires_at, p_environment)
  on conflict (transaction_id) do nothing;

  update public.profiles
  set premium_until = greatest(coalesce(premium_until, p_expires_at), p_expires_at)
  where id = p_user
  returning premium_until into v_premium;

  return v_premium;
end;
$$;

create or replace function public.is_premium(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(premium_until > now(), false) from public.profiles where id = p_user;
$$;

-- ---------------------------------------------------------------------
-- Quota de messages
-- ---------------------------------------------------------------------
create or replace function public.hercule_quota(p_user uuid)
returns table (is_premium boolean, used_today integer, daily_quota integer, remaining integer)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_quota integer;
begin
  select free_daily_quota into v_quota from public.hercule_limits where id = 1;

  is_premium := public.is_premium(p_user);

  select count(*) into used_today
  from public.hercule_messages m
  where m.user_id = p_user
    and m.role = 'user'
    and m.created_at >= date_trunc('day', now());

  -- L'abonnement lève le plafond ; on renvoie -1 plutôt que NULL pour que le
  -- client puisse afficher « illimité » sans cas particulier sur le null.
  if is_premium then
    daily_quota := -1;
    remaining   := -1;
  else
    daily_quota := v_quota;
    remaining   := greatest(0, v_quota - used_today);
  end if;

  return next;
end;
$$;

-- Enregistre le tour de conversation et décrémente le quota, en une
-- transaction. Le contrôle et l'écriture sont indissociables : les séparer
-- laisserait passer deux messages envoyés simultanément sur le dernier crédit.
create or replace function public.record_hercule_exchange(
  p_user      uuid,
  p_question  text,
  p_answer    text
)
returns table (remaining integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quota  record;
  v_limits record;
begin
  select * into v_limits from public.hercule_limits where id = 1;

  if p_question is null or length(btrim(p_question)) = 0 then
    raise exception 'Message vide' using errcode = 'KR051';
  end if;
  if length(p_question) > v_limits.max_message_chars then
    raise exception 'Message trop long (% caractères, maximum %)',
      length(p_question), v_limits.max_message_chars using errcode = 'KR051';
  end if;

  -- Verrou sur le profil : sérialise deux envois concurrents du même
  -- utilisateur, sinon tous deux verraient le même quota restant.
  perform 1 from public.profiles where id = p_user for update;

  select * into v_quota from public.hercule_quota(p_user);
  if not v_quota.is_premium and v_quota.remaining <= 0 then
    raise exception 'Quota de messages épuisé pour aujourd''hui' using errcode = 'KR050';
  end if;

  insert into public.hercule_messages (user_id, role, content)
  values (p_user, 'user', btrim(p_question)), (p_user, 'assistant', p_answer);

  select q.remaining into remaining from public.hercule_quota(p_user) q;
  return next;
end;
$$;

-- ---------------------------------------------------------------------
-- Contexte injecté dans le prompt
-- ---------------------------------------------------------------------
-- Une seule vue plutôt que cinq requêtes depuis la Edge Function : le
-- contexte doit être cohérent à un instant donné, et c'est aussi la surface
-- qu'il faut auditer pour savoir ce qui part chez le fournisseur du modèle.
create or replace view public.v_hercule_context as
select
  p.id                                                  as user_id,
  p.username,
  p.xp,
  p.rank_level,
  p.streak_days,
  coalesce(p.premium_until > now(), false)              as is_premium,
  ip.archetype                                          as investor_archetype,
  (select count(*) from public.lesson_progress lp
    where lp.user_id = p.id and lp.completed_at is not null)  as lessons_done,
  (select count(*) from public.lessons)                       as lessons_total,
  (select coalesce(jsonb_agg(jsonb_build_object(
            'symbol', s.symbol, 'name', s.name, 'sector', s.sector)
          order by pos.quantity * q.price desc), '[]'::jsonb)
     from public.positions pos
     join public.portfolios po on po.id = pos.portfolio_id
     join public.securities s  on s.symbol = pos.symbol
     left join public.quotes_cache q on q.symbol = pos.symbol
    where po.user_id = p.id and pos.quantity > 0)            as holdings
from public.profiles p
left join public.investor_profile ip on ip.user_id = p.id;

comment on view public.v_hercule_context is
  'Contexte envoyé au modèle. N''expose ni montants ni valeur de portefeuille : '
  'Hercule explique des mécanismes, il n''a pas besoin de savoir combien on a mis.';
