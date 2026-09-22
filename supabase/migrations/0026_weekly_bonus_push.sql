-- =====================================================================
-- 0026 — Rappel du versement hebdomadaire par notification.
--
-- Les 300 € de la semaine ne se réclament qu'en ouvrant l'app, et ne se
-- cumulent pas : une semaine sans passage est perdue. Le rappel du lundi
-- matin est donc la moitié de la récompense — sans lui, elle ne profite
-- qu'à ceux qui pensent déjà à revenir.
--
-- Trois pièces ici :
--   1. le consentement, tenu côté serveur : l'app seule ne peut pas le
--      connaître au moment où le cron décide d'envoyer ;
--   2. le journal des envois, pour qu'un cron rejoué n'envoie pas deux
--      fois le même rappel ;
--   3. la liste des destinataires, réservée au service role.
-- =====================================================================

-- 1. Consentement ------------------------------------------------------

alter table public.profiles
  add column if not exists push_weekly_bonus boolean not null default true;

comment on column public.profiles.push_weekly_bonus is
  'Rappel du versement hebdomadaire par notification. Réglable depuis '
  'l''app ; tenu ici parce que c''est le serveur qui décide d''envoyer.';

-- Le rappel est une notification comme une autre dans la boîte de l'app.
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('order', 'rank_up', 'badge', 'friend_request',
                  'lesson_reminder', 'market', 'hercule', 'referral', 'bonus'));

-- 2. Journal des envois ------------------------------------------------

create table if not exists public.push_campaigns (
  user_id      uuid not null references auth.users(id) on delete cascade,
  campaign     text not null,
  -- Semaine concernée : deux rappels d'une même semaine ne partent pas.
  period_start date not null,
  sent_at      timestamptz not null default now(),
  primary key (user_id, campaign, period_start)
);

alter table public.push_campaigns enable row level security;
-- Aucune politique : écrit et lu par la fonction d'envoi (service role).

-- 3. Destinataires -----------------------------------------------------

-- Qui mérite le rappel de cette semaine : un compte qui a un appareil
-- enregistré, qui n'a pas dit non, dont le portefeuille est ouvert depuis
-- la semaine dernière au moins (la semaine d'ouverture ne donne rien), et
-- qui n'a pas encore touché le versement — ni reçu ce rappel.
--
-- Un même compte peut avoir plusieurs appareils : chacun reçoit.
create or replace function public.weekly_bonus_targets(p_campaign text)
returns table (user_id uuid, locale text, token text, platform text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.locale, d.token, d.platform
  from public.profiles p
  join public.device_tokens d on d.user_id = p.id
  join public.portfolios po on po.user_id = p.id and po.mode = 'paper'
  where p.push_weekly_bonus
    and date_trunc('week', greatest(po.created_at, coalesce(po.reset_at, po.created_at))
                   at time zone 'Europe/Paris')::date < public.current_bonus_week()
    and not exists (
      select 1 from public.cash_deposits c
      where c.portfolio_id = po.id
        and c.kind = 'weekly'
        and c.period_start = public.current_bonus_week())
    and not exists (
      select 1 from public.push_campaigns pc
      where pc.user_id = p.id
        and pc.campaign = p_campaign
        and pc.period_start = public.current_bonus_week());
$$;

revoke execute on function public.weekly_bonus_targets(text) from public, anon, authenticated;
grant execute on function public.weekly_bonus_targets(text) to service_role;

-- Un envoi réussi s'inscrit au journal : c'est ce qui rend le cron rejouable.
create or replace function public.record_push_campaign(p_user_id uuid, p_campaign text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.push_campaigns (user_id, campaign, period_start)
  values (p_user_id, p_campaign, public.current_bonus_week())
  on conflict do nothing;
$$;

revoke execute on function public.record_push_campaign(uuid, text) from public, anon, authenticated;
grant execute on function public.record_push_campaign(uuid, text) to service_role;

-- Un jeton qu'Apple déclare périmé n'a plus rien à faire en base.
create or replace function public.drop_device_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.device_tokens where token = p_token;
$$;

revoke execute on function public.drop_device_token(text) from public, anon, authenticated;
grant execute on function public.drop_device_token(text) to service_role;

-- 4. Cadence -----------------------------------------------------------
--
-- Lundi 9 h à Paris, quand les 300 € viennent d'être remis en jeu, et
-- samedi 11 h pour ceux qui ne sont pas passés — il leur reste deux jours
-- avant de les perdre. Les heures sont en UTC : l'écart d'une heure entre
-- été et hiver est sans conséquence pour un rappel.
do $$
declare
  v_headers text := $h$jsonb_build_object('x-market-data-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'market_data_secret'))$h$;
  v_base text := 'https://nxvqupjaqkdulhddnlvy.functions.supabase.co/push';
begin
  if not exists (select 1 from pg_namespace where nspname = 'cron') then
    return;
  end if;

  perform cron.unschedule(jobid) from cron.job where jobname like 'weekly-bonus-%';
  perform cron.schedule('weekly-bonus-monday', '0 7 * * 1',
    format('select net.http_post(url := %L, headers := %s)',
           v_base || '?campaign=weekly_bonus', v_headers));
  perform cron.schedule('weekly-bonus-saturday', '0 9 * * 6',
    format('select net.http_post(url := %L, headers := %s)',
           v_base || '?campaign=weekly_bonus_last_chance', v_headers));
end;
$$;
