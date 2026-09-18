-- =====================================================================
-- Photo de profil.
--
-- Un fichier par utilisateur, `avatars/<user_id>/avatar.jpg`, dans un
-- bucket privé : la photo n'est montrée qu'à son propriétaire — l'Arena
-- affiche des initiales. Une photo visible de tous serait un contenu
-- publié par les utilisateurs, qu'Apple exige alors de pouvoir signaler
-- et modérer. Et un visage sous une URL publique devinable (les
-- identifiants sont lisibles dans `profiles`) n'a rien à y faire.
--
-- Le profil ne stocke que la date de la dernière photo, jamais d'URL :
-- une colonne d'URL libre laisserait n'importe qui y écrire l'adresse de
-- son choix, la politique « own profile write » couvrant toute la ligne.
-- L'app reconstruit le chemin, et la date sert de clé de cache.
-- =====================================================================

alter table public.profiles
  add column if not exists avatar_updated_at timestamptz;

comment on column public.profiles.avatar_updated_at is
  'Date de la dernière photo de profil ; null = pas de photo. Sert de clé de cache côté app.';

-- Bucket privé, JPEG seulement, 1 Mo au plus : l'app envoie du 512 × 512
-- compressé, autour de 60 Ko. La borne arrête tout le reste.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 1048576, array['image/jpeg'])
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Chaque utilisateur ne voit et ne touche que son propre dossier. La
-- lecture est nécessaire à l'upsert, qui vérifie l'existence du fichier.
drop policy if exists "avatars own read"   on storage.objects;
drop policy if exists "avatars own insert" on storage.objects;
drop policy if exists "avatars own update" on storage.objects;
drop policy if exists "avatars own delete" on storage.objects;

create policy "avatars own read" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars own insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars own update" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars own delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
