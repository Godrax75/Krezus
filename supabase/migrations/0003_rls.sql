-- =====================================================================
-- Row Level Security — « propriétaire uniquement » par défaut.
-- Référentiel titres + cotations : lecture pour tout utilisateur authentifié.
-- =====================================================================

alter table public.securities          enable row level security;
alter table public.quotes_cache        enable row level security;
alter table public.price_history       enable row level security;
alter table public.profiles            enable row level security;
alter table public.portfolios          enable row level security;
alter table public.positions           enable row level security;
alter table public.orders              enable row level security;
alter table public.portfolio_snapshots enable row level security;
alter table public.lessons             enable row level security;
alter table public.lesson_progress     enable row level security;
alter table public.quiz_attempts       enable row level security;
alter table public.missions            enable row level security;
alter table public.mission_progress    enable row level security;
alter table public.badges              enable row level security;
alter table public.user_badges         enable row level security;
alter table public.friendships         enable row level security;
alter table public.arena_feed          enable row level security;
alter table public.investor_profile    enable row level security;
alter table public.notifications       enable row level security;
alter table public.hercule_messages    enable row level security;

-- Référentiel : lecture publique authentifiée, écriture réservée au service role
create policy "securities readable" on public.securities
  for select to authenticated using (true);
create policy "quotes readable" on public.quotes_cache
  for select to authenticated using (true);
create policy "history readable" on public.price_history
  for select to authenticated using (true);
create policy "lessons readable" on public.lessons
  for select to authenticated using (true);
create policy "missions readable" on public.missions
  for select to authenticated using (true);
create policy "badges readable" on public.badges
  for select to authenticated using (true);

-- Profil : chacun voit et modifie le sien ; les autres profils sont lisibles
-- pour l'Arena (pseudo + rang), mais pas modifiables.
create policy "own profile write" on public.profiles
  for all to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "profiles readable" on public.profiles
  for select to authenticated using (true);

-- Portefeuille, positions, ordres, snapshots : propriétaire uniquement.
create policy "own portfolio" on public.portfolios
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own positions" on public.positions
  for all to authenticated using (
    exists (select 1 from public.portfolios po
            where po.id = portfolio_id and po.user_id = auth.uid()));

create policy "own orders" on public.orders
  for select to authenticated using (
    exists (select 1 from public.portfolios po
            where po.id = portfolio_id and po.user_id = auth.uid()));

create policy "own snapshots" on public.portfolio_snapshots
  for select to authenticated using (
    exists (select 1 from public.portfolios po
            where po.id = portfolio_id and po.user_id = auth.uid()));

-- Progression : propriétaire uniquement.
create policy "own lesson progress" on public.lesson_progress
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own quiz attempts" on public.quiz_attempts
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own mission progress" on public.mission_progress
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own user badges" on public.user_badges
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own investor profile" on public.investor_profile
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own notifications" on public.notifications
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own hercule messages" on public.hercule_messages
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Amitiés : les deux parties voient la relation ; on ne crée que ses propres demandes.
create policy "friendship visible" on public.friendships
  for select to authenticated using (user_id = auth.uid() or friend_id = auth.uid());
create policy "friendship insert own" on public.friendships
  for insert to authenticated with check (user_id = auth.uid());
create policy "friendship update party" on public.friendships
  for update to authenticated using (user_id = auth.uid() or friend_id = auth.uid());

-- Feed Arena : lecture pour tous les authentifiés, écriture de ses propres événements.
create policy "feed readable" on public.arena_feed
  for select to authenticated using (true);
create policy "feed insert own" on public.arena_feed
  for insert to authenticated with check (actor_id = auth.uid());

-- À la création d'un compte : profil + portefeuille papier initial.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  insert into public.portfolios (user_id, mode, cash_cents)
  values (new.id, 'paper', 100000) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
