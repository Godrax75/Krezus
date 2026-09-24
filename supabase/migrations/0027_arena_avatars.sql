-- =====================================================================
-- 0027 — Les photos de profil s'affichent à l'Arena.
--
-- Jusqu'ici, chacun ne voyait que sa propre photo : le dossier d'un
-- utilisateur n'était lisible que par lui (0016). Le classement affichait
-- donc un emoji de rang à côté de chaque pseudo.
--
-- Montrer les visages au classement suppose que **tout joueur connecté
-- puisse lire la photo d'un autre**. C'est le prix de la fonctionnalité,
-- et il est assumé : une photo déposée pour apparaître au classement est,
-- par nature, une photo publique entre joueurs.
--
-- Ce qui ne change pas : seul le propriétaire écrit, remplace ou efface
-- la sienne, et le dépôt reste réservé aux comptes connectés — rien
-- n'est accessible sans session.
-- =====================================================================

drop policy if exists "avatars readable by players" on storage.objects;
create policy "avatars readable by players" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars');
