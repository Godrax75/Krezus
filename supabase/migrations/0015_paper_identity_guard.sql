-- =====================================================================
-- Garde d'identité sur le moteur d'ordres papier.
--
-- LE PROBLÈME
-- `execute_paper_buy`, `execute_paper_sell` et `reset_paper_portfolio`
-- (0002) prennent `p_user_id uuid` en paramètre, sont `security definer`
-- — donc contournent la RLS — et ne vérifient nulle part que ce
-- paramètre correspond à l'appelant. Elles sont exécutables par le rôle
-- `authenticated` (droit par défaut sur les fonctions).
--
-- Conséquence : n'importe quel porteur d'un JWT authentifié peut passer
-- un ordre, vendre une position ou réinitialiser le portefeuille d'un
-- AUTRE utilisateur, en envoyant simplement son uuid — qui n'est pas un
-- secret, `profiles` étant lisible par tous pour les besoins de l'Arena.
--
-- L'app iOS n'exploite pas la faille (elle passe toujours l'id de sa
-- propre session), mais le web est un second client et la surface
-- devient publique. 0009_notifications.sql:62 pose déjà exactement ce
-- garde-fou sur `upsert_device_token` ; on l'applique aux trois
-- fonctions qui déplacent de l'argent.
--
-- LA MÉTHODE
-- On renomme l'implémentation en `_impl`, on lui retire le droit
-- d'exécution, et on recrée une fonction publique de MÊME signature qui
-- vérifie l'identité avant de déléguer. Le corps du moteur n'est pas
-- recopié : le dupliquer ici garantirait qu'un correctif futur sur 0002
-- soit oublié dans l'une des deux copies.
--
-- La signature exposée est inchangée : PortfolioRepository.swift:50-70
-- continue d'appeler `execute_paper_buy(p_user_id, p_symbol, …)` sans
-- modification, et le web fait de même.
--
-- ⚠️ Si 0002 était réappliqué après cette migration, son
-- `create or replace` écraserait les wrappers et rouvrirait la faille.
-- Les migrations s'appliquent une fois, dans l'ordre — mais si tu
-- retouches 0002 un jour, rejoue 0015 derrière.
--
--   KR011 identité : p_user_id ne correspond pas à auth.uid()
-- =====================================================================

-- ---------------------------------------------------------------------
-- Le garde lui-même, en un seul endroit auditable.
--
-- La condition `auth.uid() is not null` laisse passer les suites de
-- tests SQL, qui tournent sur un Postgres nu sans session (voir
-- supabase/tests/00_auth_stub.sql). C'est la même tolérance que 0009 :
-- hors session il n'y a pas d'appelant à usurper.
-- ---------------------------------------------------------------------
create or replace function public.assert_is_self(p_user_id uuid)
returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if p_user_id is null then
    raise exception 'Paramètre invalide' using errcode = 'KR010';
  end if;
  if auth.uid() is not null and p_user_id <> auth.uid() then
    raise exception 'Opération refusée pour un autre compte' using errcode = 'KR011';
  end if;
end;
$$;

comment on function public.assert_is_self(uuid) is
  'Refuse une opération dont le p_user_id n''est pas celui de l''appelant. '
  'À appeler en tête de toute fonction security definer qui prend un user_id.';

-- ---------------------------------------------------------------------
-- execute_paper_buy
-- ---------------------------------------------------------------------
alter function public.execute_paper_buy(uuid, text, bigint)
  rename to execute_paper_buy_impl;

revoke all on function public.execute_paper_buy_impl(uuid, text, bigint)
  from public, anon, authenticated;

create function public.execute_paper_buy(
  p_user_id      uuid,
  p_symbol       text,
  p_amount_cents bigint
) returns public.orders
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_is_self(p_user_id);
  return public.execute_paper_buy_impl(p_user_id, p_symbol, p_amount_cents);
end;
$$;

-- ---------------------------------------------------------------------
-- execute_paper_sell
-- ---------------------------------------------------------------------
alter function public.execute_paper_sell(uuid, text, integer)
  rename to execute_paper_sell_impl;

revoke all on function public.execute_paper_sell_impl(uuid, text, integer)
  from public, anon, authenticated;

create function public.execute_paper_sell(
  p_user_id uuid,
  p_symbol  text,
  p_pct     integer
) returns public.orders
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_is_self(p_user_id);
  return public.execute_paper_sell_impl(p_user_id, p_symbol, p_pct);
end;
$$;

-- ---------------------------------------------------------------------
-- reset_paper_portfolio
-- ---------------------------------------------------------------------
alter function public.reset_paper_portfolio(uuid)
  rename to reset_paper_portfolio_impl;

revoke all on function public.reset_paper_portfolio_impl(uuid)
  from public, anon, authenticated;

create function public.reset_paper_portfolio(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_is_self(p_user_id);
  perform public.reset_paper_portfolio_impl(p_user_id);
end;
$$;

-- Les wrappers sont `security definer` et exécutables par `authenticated`
-- (droit par défaut) ; les `_impl` ne le sont plus. Le seul chemin vers le
-- moteur passe donc désormais par le garde.
