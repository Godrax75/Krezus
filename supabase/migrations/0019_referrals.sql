-- =====================================================================
-- Parrainage, et fermeture de trois fonctions appelables par n'importe qui.
--
-- 1. Failles
--
-- `award_xp` et `award_badge` (0005) sont `security definer` et n'ont
-- jamais été retirées au public : les rôles `anon` et `authenticated` les
-- exécutaient. Avec la seule clé publique de l'app, sans même être
-- connecté, on pouvait donner à n'importe quel compte autant d'XP et de
-- badges que voulu — et truquer le classement de l'Arena. Récompenser le
-- parrainage en XP n'aurait aucun sens tant que l'XP se fabrique.
--
-- `notify` avait été retirée à `public` et `authenticated` (0009), mais
-- Supabase accorde aussi l'exécution à `anon` par défaut : un visiteur non
-- connecté pouvait envoyer à tout utilisateur une notification au texte de
-- son choix.
--
-- Seules des fonctions `security definer` les appellent ; elles
-- s'exécutent en propriétaire et ne sont pas concernées.
--
-- 2. Parrainage
--
-- Chaque profil reçoit un code de six caractères, sans 0/O ni 1/I/L pour
-- qu'on le dicte sans erreur. Un nouvel inscrit a sept jours pour saisir
-- le code d'un ami : lui et son parrain gagnent 100 XP. Le parrain n'est
-- récompensé que pour ses dix premiers filleuls — au-delà, l'inscription
-- par e-mail rendrait trop facile de fabriquer des comptes pour monter au
-- classement. Le filleul, lui, ne peut l'être qu'une fois.
-- =====================================================================

-- 1. Failles ---------------------------------------------------------------

revoke all on function public.award_xp(uuid, integer)             from public, anon, authenticated;
revoke all on function public.award_badge(uuid, text)             from public, anon, authenticated;
revoke all on function public.notify(uuid, text, text, text)      from public, anon, authenticated;

-- 2. Codes -----------------------------------------------------------------

alter table public.profiles add column if not exists referral_code text;
create unique index if not exists profiles_referral_code_key on public.profiles (referral_code);

comment on column public.profiles.referral_code is
  'Code de parrainage, six caractères. Attribué à la création, jamais modifié.';

create or replace function public.generate_referral_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where referral_code = v_code);
  end loop;
  return v_code;
end;
$$;

revoke all on function public.generate_referral_code() from public, anon, authenticated;

-- Le code est posé à la création et figé ensuite : la politique « own
-- profile write » laisse l'utilisateur écrire toute sa ligne, il pourrait
-- sinon se choisir le code d'un autre une fois celui-ci libéré.
-- En droits propriétaires : un profil peut naître d'un rôle qui n'a pas
-- accès au générateur, et l'insertion échouerait.
create or replace function public.profiles_referral_code_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.referral_code := coalesce(new.referral_code, public.generate_referral_code());
  else
    new.referral_code := old.referral_code;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_referral_code on public.profiles;
create trigger profiles_referral_code
  before insert or update on public.profiles
  for each row execute function public.profiles_referral_code_guard();

-- Profils existants : un par un, pour que chaque tirage voie les codes
-- déjà attribués. Le déclencheur, qui fige le code en mise à jour, est
-- suspendu le temps de cette attribution.
alter table public.profiles disable trigger profiles_referral_code;
do $$
declare
  r record;
begin
  for r in select id from public.profiles where referral_code is null loop
    update public.profiles set referral_code = public.generate_referral_code() where id = r.id;
  end loop;
end;
$$;
alter table public.profiles enable trigger profiles_referral_code;

alter table public.profiles alter column referral_code set not null;

-- 3. Parrainages -------------------------------------------------------------

create table if not exists public.referrals (
  referee_id   uuid primary key references auth.users(id) on delete cascade,
  referrer_id  uuid not null references auth.users(id) on delete cascade,
  rewarded     boolean not null,          -- le parrain a-t-il reçu ses XP ?
  created_at   timestamptz not null default now(),
  check (referee_id <> referrer_id)
);
create index if not exists referrals_referrer on public.referrals (referrer_id);

comment on table public.referrals is
  'Un filleul, un parrain. Écrite uniquement par redeem_referral_code.';

alter table public.referrals enable row level security;
drop policy if exists "own referrals" on public.referrals;
create policy "own referrals" on public.referrals
  for select to authenticated
  using (referrer_id = auth.uid() or referee_id = auth.uid());

alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('order', 'rank_up', 'badge', 'friend_request',
                  'lesson_reminder', 'market', 'hercule', 'referral'));

-- 4. Saisie d'un code --------------------------------------------------------

create or replace function public.redeem_referral_code(p_code text)
returns table (referrer_username text, xp_awarded integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  c_xp           constant integer  := 100;
  c_window       constant interval := interval '7 days';
  c_rewarded_max constant integer  := 10;
  v_user      uuid := auth.uid();
  v_code      text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_referrer  uuid;
  v_name      text;
  v_joined    timestamptz;
  v_rewarded  boolean;
begin
  if v_user is null then
    raise exception 'Aucune session' using errcode = 'KR010';
  end if;

  select p.id, p.username into v_referrer, v_name
  from public.profiles p where p.referral_code = v_code;
  if v_referrer is null then
    raise exception 'Code de parrainage inconnu' using errcode = 'KR070';
  end if;

  -- Son propre code, ou celui de son propre filleul (boucle A → B → A).
  if v_referrer = v_user
     or exists (select 1 from public.referrals r
                where r.referee_id = v_referrer and r.referrer_id = v_user) then
    raise exception 'Code de parrainage non valable' using errcode = 'KR071';
  end if;

  if exists (select 1 from public.referrals r where r.referee_id = v_user) then
    raise exception 'Déjà parrainé' using errcode = 'KR072';
  end if;

  select u.created_at into v_joined from auth.users u where u.id = v_user;
  if v_joined < now() - c_window then
    raise exception 'Délai de parrainage dépassé' using errcode = 'KR073';
  end if;

  v_rewarded := (select count(*) from public.referrals r
                 where r.referrer_id = v_referrer and r.rewarded) < c_rewarded_max;

  insert into public.referrals (referee_id, referrer_id, rewarded)
  values (v_user, v_referrer, v_rewarded);

  perform public.award_xp(v_user, c_xp);
  if v_rewarded then
    perform public.award_xp(v_referrer, c_xp);
  end if;

  perform public.notify(
    v_referrer, 'referral',
    coalesce((select p.username from public.profiles p where p.id = v_user), 'Un ami')
      || ' a rejoint Krezus avec ton code',
    case when v_rewarded then '+100 XP pour toi.' else 'Merci de faire connaître Krezus.' end);

  referrer_username := v_name;
  xp_awarded := c_xp;
  return next;
end;
$$;

revoke all on function public.redeem_referral_code(text) from public, anon;
grant execute on function public.redeem_referral_code(text) to authenticated;

-- 5. État du parrainage, pour l'écran dédié ---------------------------------

create or replace function public.referral_status()
returns table (code text, referred_count integer, xp_earned integer,
               can_redeem boolean, referred_by text)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.referral_code,
    (select count(*)::int from public.referrals r where r.referrer_id = p.id),
    (select count(*)::int * 100 from public.referrals r where r.referrer_id = p.id and r.rewarded),
    not exists (select 1 from public.referrals r where r.referee_id = p.id)
      and u.created_at >= now() - interval '7 days',
    (select parent.username from public.referrals r
       join public.profiles parent on parent.id = r.referrer_id
      where r.referee_id = p.id)
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = auth.uid();
$$;

revoke all on function public.referral_status() from public, anon;
grant execute on function public.referral_status() to authenticated;
