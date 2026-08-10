-- Rangs, missions et badges — issus des notes développeurs du prototype.
-- Rangs = paliers de 200 XP (rank_level = 1 + floor(xp/200), borné à 6).
-- Les images sont embarquées dans l'app (Assets.xcassets), pas en base.

-- Table de référence des rangs (statique — pratique pour l'écran « Tous les rangs »).
create table if not exists public.ranks (
  level      integer primary key,
  emoji      text not null,
  name_fr    text not null,
  name_en    text,
  min_xp     integer not null,
  max_xp     integer,               -- NULL = dernier rang
  image_asset text not null
);

insert into public.ranks (level, emoji, name_fr, min_xp, max_xp, image_asset) values
  (1, '🏛️', 'Plébéien',     0,    199,  'rank-1-plebeien'),
  (2, '🛡️', 'Légionnaire',  200,  399,  'rank-2-legionnaire'),
  (3, '⚔️', 'Centurion',    400,  599,  'rank-3-centurion'),
  (4, '📜', 'Sénateur',     600,  799,  'rank-4-senateur'),
  (5, '👑', 'Consul',       800,  999,  'rank-5-consul'),
  (6, '🦅', 'Empereur',     1000, null, 'rank-6-empereur')
on conflict (level) do nothing;

insert into public.missions (code, title_fr, xp) values
  ('activate', 'Activer ton compte',        50),
  ('lesson',   'Terminer une leçon du jour', 20),
  ('quiz',     'Réussir le quiz du jour',    30)
on conflict (code) do nothing;

insert into public.badges (code, title_fr) values
  ('first_buy',   'Premier achat'),
  ('diversified', 'Portefeuille diversifié'),
  ('streak_7',    'Série de 7 jours'),
  ('academy_4',   '4 leçons terminées'),
  ('rank_up',     'Montée en rang')
on conflict (code) do nothing;
