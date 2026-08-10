-- =====================================================================
-- Moteur d'ordres papier — logique transactionnelle côté serveur.
-- Placer la logique ici (et non dans l'app) empêche de fabriquer du cash
-- en rejouant une requête : le débit, le crédit et l'écriture de l'ordre
-- sont atomiques et le prix vient du cache serveur, pas du client.
--
-- Codes d'erreur SQLSTATE, classe privée « KR » (le client Swift les mappe
-- vers un message utilisateur). Ne PAS réutiliser la classe P0 de PL/pgSQL :
-- P0004 = assert_failure, que `when others` ne capture jamais.
--   KR001 fonds insuffisants · KR002 portefeuille/position introuvable
--   KR003 cotation indisponible · KR004 cotation périmée · KR010 paramètre invalide
-- =====================================================================

-- Achat pour un MONTANT en centimes (parts fractionnées).
-- Renvoie l'ordre créé. Lève une exception (rollback) si fonds insuffisants
-- ou cotation périmée.
create or replace function public.execute_paper_buy(
  p_user_id      uuid,
  p_symbol       text,
  p_amount_cents bigint
) returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_portfolio   public.portfolios;
  v_price       numeric;
  v_fetched_at  timestamptz;
  v_qty         numeric(18,8);
  v_order       public.orders;
begin
  if p_amount_cents <= 0 then
    raise exception 'Montant invalide' using errcode = 'KR010';
  end if;

  select * into v_portfolio
  from public.portfolios
  where user_id = p_user_id and mode = 'paper'
  for update;                                    -- verrou : sérialise les ordres concurrents

  if not found then
    raise exception 'Portefeuille papier introuvable' using errcode = 'KR002';
  end if;

  if p_amount_cents > v_portfolio.cash_cents then
    raise exception 'Fonds insuffisants' using errcode = 'KR001';
  end if;

  select price, fetched_at into v_price, v_fetched_at
  from public.quotes_cache where symbol = p_symbol;

  if not found or v_price is null or v_price <= 0 then
    raise exception 'Cotation indisponible pour %', p_symbol using errcode = 'KR003';
  end if;
  if v_fetched_at < now() - interval '15 minutes' then
    raise exception 'Cotation périmée pour %', p_symbol using errcode = 'KR004';
  end if;

  -- parts = montant(€) / prix. amount_cents/100 donne les euros ; /price les parts.
  v_qty := round((p_amount_cents::numeric / 100) / v_price, 8);
  if v_qty <= 0 then
    raise exception 'Montant trop faible pour acheter une fraction' using errcode = 'KR010';
  end if;

  update public.portfolios
  set cash_cents = cash_cents - p_amount_cents
  where id = v_portfolio.id;

  -- upsert position avec coût de revient moyen pondéré (en centimes par part)
  insert into public.positions (portfolio_id, symbol, quantity, avg_cost_cents)
  values (v_portfolio.id, p_symbol, v_qty, round(p_amount_cents::numeric / v_qty))
  on conflict (portfolio_id, symbol) do update set
    avg_cost_cents = round(
      (public.positions.quantity * public.positions.avg_cost_cents
       + p_amount_cents) / (public.positions.quantity + excluded.quantity)),
    quantity = public.positions.quantity + excluded.quantity;

  insert into public.orders (portfolio_id, symbol, side, amount_cents, quantity,
                             executed_price, status)
  values (v_portfolio.id, p_symbol, 'buy', p_amount_cents, v_qty, v_price, 'filled')
  returning * into v_order;

  return v_order;
end;
$$;

-- Vente d'un POURCENTAGE (1..100) de la position détenue.
create or replace function public.execute_paper_sell(
  p_user_id  uuid,
  p_symbol   text,
  p_pct      integer
) returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_portfolio    public.portfolios;
  v_position     public.positions;
  v_price        numeric;
  v_fetched_at   timestamptz;
  v_sell_qty     numeric(18,8);
  v_proceeds     bigint;
  v_order        public.orders;
begin
  if p_pct < 1 or p_pct > 100 then
    raise exception 'Pourcentage invalide' using errcode = 'KR010';
  end if;

  select * into v_portfolio
  from public.portfolios
  where user_id = p_user_id and mode = 'paper'
  for update;
  if not found then
    raise exception 'Portefeuille papier introuvable' using errcode = 'KR002';
  end if;

  select * into v_position
  from public.positions
  where portfolio_id = v_portfolio.id and symbol = p_symbol
  for update;
  if not found then
    raise exception 'Aucune position sur %', p_symbol using errcode = 'KR002';
  end if;

  select price, fetched_at into v_price, v_fetched_at
  from public.quotes_cache where symbol = p_symbol;
  if not found or v_price is null or v_price <= 0 then
    raise exception 'Cotation indisponible pour %', p_symbol using errcode = 'KR003';
  end if;
  if v_fetched_at < now() - interval '15 minutes' then
    raise exception 'Cotation périmée pour %', p_symbol using errcode = 'KR004';
  end if;

  if p_pct = 100 then
    v_sell_qty := v_position.quantity;
  else
    v_sell_qty := round(v_position.quantity * p_pct / 100.0, 8);
  end if;

  v_proceeds := round(v_sell_qty * v_price * 100);   -- en centimes

  update public.portfolios
  set cash_cents = cash_cents + v_proceeds
  where id = v_portfolio.id;

  if p_pct = 100 or v_position.quantity - v_sell_qty <= 0 then
    delete from public.positions
    where portfolio_id = v_portfolio.id and symbol = p_symbol;
  else
    update public.positions
    set quantity = quantity - v_sell_qty
    where portfolio_id = v_portfolio.id and symbol = p_symbol;
  end if;

  insert into public.orders (portfolio_id, symbol, side, amount_cents, quantity,
                             executed_price, status)
  values (v_portfolio.id, p_symbol, 'sell', v_proceeds, v_sell_qty, v_price, 'filled')
  returning * into v_order;

  return v_order;
end;
$$;

-- Réinitialise le portefeuille papier à 1 000 € et solde toutes les positions.
create or replace function public.reset_paper_portfolio(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_portfolio_id uuid;
begin
  select id into v_portfolio_id
  from public.portfolios where user_id = p_user_id and mode = 'paper' for update;
  if not found then
    raise exception 'Portefeuille papier introuvable' using errcode = 'KR002';
  end if;
  delete from public.positions where portfolio_id = v_portfolio_id;
  update public.portfolios
  set cash_cents = 100000, reset_at = now()
  where id = v_portfolio_id;
end;
$$;
