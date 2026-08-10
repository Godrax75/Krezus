-- =====================================================================
-- Correctif — `create_arena_group` ne pouvait pas générer de code d'invitation.
--
--   ERROR: function gen_random_bytes(integer) does not exist
--
-- `gen_random_bytes` vient de **pgcrypto**, que Supabase installe dans le
-- schéma `extensions` et non dans `public`. Or la fonction fixe
-- `set search_path = public` — bonne pratique contre le détournement de
-- schéma, mais qui rend ici l'extension introuvable.
--
-- Créer un groupe échouait donc systématiquement. Via PostgREST l'erreur
-- remontait en 42883 « No function matches the given name and argument
-- types », ce qui désignait à tort l'appel plutôt que son contenu.
--
-- Les tests SQL du lot 7 ne l'ont pas vu : ils tournent sur une base jetable
-- où `tools/run_arena_tests.sh` installe pgcrypto dans `public`.
--
-- Correctif : ajouter `extensions` au search_path, comme le fait Supabase pour
-- ses propres fonctions. `gen_random_uuid` n'est pas concernée — elle fait
-- partie du cœur de PostgreSQL depuis la version 13.
-- =====================================================================

create or replace function public.create_arena_group(p_owner uuid, p_name text)
returns table (id uuid, invite_code text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text;
begin
  if length(btrim(coalesce(p_name, ''))) < 2 then
    raise exception 'Nom de groupe trop court' using errcode = 'KR010';
  end if;

  -- Code court, lisible à l'oral, sans caractères ambigus (0/O, 1/I).
  loop
    v_code := upper(substr(translate(encode(gen_random_bytes(8), 'base64'),
                                     '+/=OI01lo', 'ABCDEFGHJ'), 1, 6));
    exit when not exists (select 1 from public.arena_groups g where g.invite_code = v_code);
  end loop;

  insert into public.arena_groups (name, owner_id, invite_code)
  values (btrim(p_name), p_owner, v_code)
  returning arena_groups.id, arena_groups.invite_code into id, invite_code;

  insert into public.arena_group_members (group_id, user_id)
  values (id, p_owner);

  return next;
end;
$$;
