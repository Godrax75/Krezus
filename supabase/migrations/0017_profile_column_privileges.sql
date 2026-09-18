-- =====================================================================
-- Privilèges colonne par colonne sur `profiles`.
--
-- LE PROBLÈME
-- 0003_rls.sql pose une seule policy d'écriture sur le profil :
--
--   create policy "own profile write" on public.profiles
--     for all to authenticated using (id = auth.uid()) with check (id = auth.uid());
--
-- Elle contrôle QUELLE LIGNE on peut écrire — la sienne — mais pas
-- QUELLES COLONNES. Aucune migration ultérieure ne restreint les
-- privilèges colonne ; `authenticated` conserve donc le `grant all`
-- que Supabase applique par défaut aux tables du schéma `public`.
--
-- Conséquence : n'importe quel porteur d'un JWT authentifié peut, d'un
-- simple PATCH PostgREST sur sa propre ligne, écrire les colonnes que
-- seul le serveur devrait toucher :
--
--   PATCH /rest/v1/profiles?id=eq.<son uuid>
--   { "premium_until": "2099-01-01T00:00:00Z" }   → Hercule Premium à vie
--   { "xp": 999999, "rank_level": 6 }             → rang maximal instantané
--   { "streak_days": 365 }                        → série et badge streak_7
--
-- Le contournement est total : `premium_until` est la seule source de
-- vérité de l'abonnement (0008, `is_premium`), et le quota Hercule s'y
-- fie directement. La vérification du reçu StoreKit dans la Edge
-- Function devient décorative si la colonne qu'elle alimente est
-- inscriptible par le client.
--
-- C'est la même famille de faille que 0015 : la surface publique du
-- backend est plus large que ce que l'app iOS en utilise. L'app n'écrit
-- que `username`, `dark_mode`, `locale` et `avatar_updated_at`
-- (ProfileRepository.swift) ; tout le reste passe par des fonctions
-- `security definer`.
--
-- LA MÉTHODE
-- La RLS filtre les lignes, les privilèges filtrent les colonnes : il
-- faut les deux. On retire à `anon` et `authenticated` tout droit
-- d'écriture sur la table, puis on rend UPDATE colonne par colonne, sur
-- la liste exacte que le client édite. PostgREST répond alors 403 sur
-- toute autre colonne, avant même d'évaluer la policy.
--
-- On resserre aussi la policy elle-même en UPDATE seul. Le `for all`
-- couvrait INSERT et DELETE, dont le client n'a aucun usage : la ligne
-- est créée par le trigger `handle_new_user` (0003) et supprimée par la
-- cascade de `delete_own_account` (0009), toutes deux `security
-- definer`. Sans policy INSERT/DELETE, un futur `grant all` malencontreux
-- sur le schéma ne rouvrirait pas la brèche à lui seul — et
-- réciproquement. Deux verrous indépendants, pas un seul.
--
-- Les fonctions `security definer` ne sont pas affectées : elles
-- s'exécutent avec les droits de leur propriétaire (`postgres`, qui
-- possède la table), pas avec ceux de l'appelant. Vérifié une par une,
-- les treize fonctions qui touchent `profiles` sont toutes `security
-- definer` :
--
--   handle_new_user (0003)            insert  id
--   handle_new_profile (0005)         trigger after insert
--   award_xp (0005)                   update  xp, rank_level
--   touch_streak (0005)               update  streak_days, streak_last_at
--   complete_lesson (0005)            → award_xp / touch_streak
--   feed_on_rank_up (0007)            trigger after update of rank_level
--   send_friend_request (0007)        select
--   leave_arena_group (0007)          select
--   is_premium (0008)                 select  premium_until
--   record_hercule_subscription (0008) update premium_until ← chemin StoreKit
--   record_hercule_exchange (0008)    select … for update
--   notify_on_rank_up (0009)          trigger after update of rank_level
--   notify_on_friend_request (0009)   select
--
-- Deux points de vigilance pour la suite :
--
--   • `record_hercule_exchange` pose un `select … for update` sur
--     `profiles` pour sérialiser deux envois concurrents. Postgres exige
--     le droit UPDATE sur au moins une colonne pour verrouiller ainsi.
--     La fonction est `security definer` et ne dépend donc pas des grants
--     ci-dessous, mais un `revoke update` TOTAL casserait tout chemin
--     `for update` en droits appelant. Les grants colonne conservent ce
--     droit à `authenticated`.
--
--   • Les vues qui lisent `profiles` (`v_hercule_context`, la vue de
--     progression Academy) s'exécutent avec les droits de leur
--     propriétaire — aucune n'est en `security_invoker` — et ne font que
--     du SELECT, que cette migration ne touche pas.
--
-- Si une fonction écrivant `profiles` était un jour recréée en
-- `security invoker`, ou par un rôle qui ne possède pas la table, elle
-- échouerait ici. C'est le comportement voulu : le droit d'écrire xp,
-- rank_level ou premium_until doit rester attaché au propriétaire.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Plus aucun droit d'écriture direct sur la table.
--
-- `truncate`, `references` et `trigger` partent aussi : ils font partie du
-- `grant all` par défaut et n'ont aucun usage côté client.
-- SELECT est conservé — `profiles` doit rester lisible par les
-- authentifiés pour l'Arena (policy « profiles readable », 0003).
-- ---------------------------------------------------------------------
revoke insert, update, delete, truncate, references, trigger
  on public.profiles from anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. UPDATE rendu colonne par colonne, sur ce que l'app édite.
--
--   username    EditUsernameScreen → ProfileRepository.updateUsername
--   dark_mode   ModeSwitchSheet    → ProfileRepository.updatePreferences
--   locale      réglages           → ProfileRepository.updatePreferences
--   first_name  / last_name : identité déclarative, non privilégiée.
--     Aucun écran ne les écrit aujourd'hui (elles ne sont que lues, via
--     Models.swift, pour l'initiale de l'avatar) ; le grant est posé
--     d'avance pour l'onboarding. Les retirer d'ici ne casse rien tant
--     que c'est le cas.
--
-- Ce qui n'est PAS dans cette liste, et ne doit jamais y entrer :
--   id, created_at            clés et horodatage
--   xp, rank_level            économie de jeu   → award_xp
--   streak_days, streak_last_at                 → touch_streak
--   premium_until             abonnement payant → record_hercule_subscription
-- ---------------------------------------------------------------------
grant update (username, first_name, last_name, locale, dark_mode)
  on public.profiles to authenticated;

-- ---------------------------------------------------------------------
-- 3. `avatar_updated_at` (0016_avatars.sql), écrite par le client après
-- un upload réussi vers le bucket avatars.
--
-- Le grant est conditionné à l'existence de la colonne : cette migration
-- doit pouvoir s'appliquer telle quelle sur une base où 0016 n'a pas
-- encore été joué (base de test jetable, environnement recréé de zéro),
-- sans faire échouer la transaction sur une colonne absente.
--
-- ⚠️ Si 0016 est appliqué APRÈS cette migration, rejouer ce bloc — sinon
-- l'upload d'avatar échouera en 403 sur la colonne.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'profiles'
      and column_name  = 'avatar_updated_at'
  ) then
    execute 'grant update (avatar_updated_at) on public.profiles to authenticated';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. La policy passe de `for all` à `for update`.
--
-- SELECT reste couvert par « profiles readable » (0003) ; INSERT et
-- DELETE n'ont plus de policy du tout, donc plus de chemin client.
-- ---------------------------------------------------------------------
drop policy if exists "own profile write" on public.profiles;

create policy "own profile update" on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

comment on table public.profiles is
  'Profil utilisateur. Écriture client limitée aux colonnes de préférence '
  'et d''identité (grants colonne, 0017) ; xp, rank_level, streak_* et '
  'premium_until ne sont écrites que par des fonctions security definer.';
