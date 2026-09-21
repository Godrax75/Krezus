-- =====================================================================
-- 0025 — Grandes places mondiales.
--
-- Le référentiel s'ouvre à Londres, Francfort, Zurich, Madrid, Milan,
-- Amsterdam, Bruxelles, Stockholm, Copenhague, Helsinki, Toronto et Hong
-- Kong. Deux conséquences :
--
-- 1. Une même société peut coter sur plusieurs places (Airbus à Paris et à
--    Francfort). L'ISIN, commun à toutes ses lignes, permet de n'en garder
--    qu'une ; il est désormais conservé.
-- 2. Les cours arrivent en livres (en pence, à Londres), francs suisses,
--    couronnes, dollars canadiens ou de Hong Kong. Le rattrapage des
--    relevés de portefeuille convertit chacune avec la série de change de
--    sa date — il ne connaissait que le dollar.
-- =====================================================================

alter table public.securities add column if not exists isin text;
create index if not exists securities_isin_idx on public.securities (isin);

create or replace function public.backfill_portfolio_snapshots()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with pf as (
    select po.id, greatest(po.created_at, coalesce(po.reset_at, po.created_at)) as started
    from public.portfolios po
    where po.mode = 'paper'
  ),
  days as (
    select pf.id as pid, pf.started, d::date as day
    from pf, generate_series(pf.started::date, current_date - 1, interval '1 day') as d
  ),
  moves as (
    select dd.pid, dd.day, o.symbol,
           case when o.side = 'buy' then -o.amount_cents else o.amount_cents end as cash_delta,
           case when o.side = 'buy' then o.quantity else -o.quantity end        as qty_delta
    from days dd
    join public.orders o
      on o.portfolio_id = dd.pid and o.status = 'filled'
     and o.created_at >= dd.started and o.created_at < (dd.day + 1)
  ),
  added as (
    select dd.pid, dd.day, coalesce(sum(d.amount_cents), 0) as deposit_cents
    from days dd
    left join public.cash_deposits d
      on d.portfolio_id = dd.pid and d.created_at >= dd.started and d.created_at < (dd.day + 1)
    group by dd.pid, dd.day
  ),
  cash as (
    select dd.pid, dd.day,
           100000 + coalesce(sum(m.cash_delta), 0)
                  + (select a.deposit_cents from added a where a.pid = dd.pid and a.day = dd.day)
             as cash_cents
    from days dd
    left join moves m on m.pid = dd.pid and m.day = dd.day
    group by dd.pid, dd.day
  ),
  holdings as (
    select m.pid, m.day, m.symbol, sum(m.qty_delta) as qty
    from moves m
    group by m.pid, m.day, m.symbol
    having sum(m.qty_delta) > 1e-9
  ),
  valued as (
    select h.pid, h.day,
           sum(h.qty * coalesce(
             (select ph.close
                   -- Les pence de Londres valent un centième de livre.
                   / case when s.currency = 'GBX' then 100 else 1 end
                   / case when s.currency = 'EUR' then 1
                          else nullif((select f.rate from public.fx_history f
                                       where f.pair = 'EUR' || case when s.currency = 'GBX'
                                                                    then 'GBP' else s.currency end
                                         and f.date <= h.day
                                       order by f.date desc limit 1), 0)
                     end
              from public.price_history ph
              where ph.symbol = h.symbol and ph.date <= h.day
              order by ph.date desc limit 1),
             (select q.price from public.quotes_cache q where q.symbol = h.symbol)
           ) * 100) as positions_cents
    from holdings h
    join public.securities s on s.symbol = h.symbol
    group by h.pid, h.day
  )
  insert into public.portfolio_snapshots (portfolio_id, date, total_value_cents, deposits_cents)
  select c.pid, c.day, c.cash_cents + coalesce(round(v.positions_cents), 0)::bigint, a.deposit_cents
  from cash c
  join added a on a.pid = c.pid and a.day = c.day
  left join valued v on v.pid = c.pid and v.day = c.day
  on conflict (portfolio_id, date) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.backfill_portfolio_snapshots() from public, anon, authenticated;
