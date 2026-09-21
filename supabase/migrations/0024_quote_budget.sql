-- =====================================================================
-- 0024 — Rafraîchir les cotations sans épuiser le quota EODHD.
--
-- Chaque titre demandé à l'API temps réel coûte un appel, et le quota est
-- de 100 000 par jour. Avec plus de mille titres, rafraîchir tout le
-- catalogue chaque minute l'épuisait en deux heures : le cache se figeait
-- et plus aucun ordre ne passait (KR004), jusqu'au lendemain.
--
-- Désormais :
--   - le cron `quotes` tourne chaque minute des jours ouvrés, et choisit
--     lui-même, dans un budget fixe, ce qui mérite un appel (titres
--     détenus, places ouvertes, dernier relevé après la clôture) ;
--   - l'app rafraîchit à la demande le titre qu'on consulte ou qu'on
--     achète (`quote-refresh`), dans une limite par utilisateur tenue ici ;
--   - l'historique quotidien est découpé en quatre parts, pour tenir dans
--     le temps d'exécution d'une fonction.
-- =====================================================================

create table if not exists public.quote_refresh_requests (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  symbol      text not null,
  created_at  timestamptz not null default now()
);
create index if not exists quote_refresh_requests_user_idx
  on public.quote_refresh_requests (user_id, created_at desc);

-- Écrite et lue par la fonction seule (service role) : aucune politique.
alter table public.quote_refresh_requests enable row level security;

do $$
declare
  v_headers text := $h$jsonb_build_object('x-market-data-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'market_data_secret'))$h$;
  v_base text := 'https://nxvqupjaqkdulhddnlvy.functions.supabase.co';
  v_part integer;
begin
  if not exists (select 1 from pg_namespace where nspname = 'cron') then
    return;
  end if;

  -- Cotations : chaque minute des jours ouvrés, toutes places confondues —
  -- Tokyo et Hong Kong cotent pendant la nuit européenne. La fonction ne
  -- dépense rien quand aucune place n'est ouverte.
  perform cron.unschedule(jobid) from cron.job where jobname in ('quotes-market-hours', 'quotes-off-hours');
  perform cron.schedule('quotes-market-hours', '* * * * 1-5',
    format('select net.http_post(url := %L, headers := %s)', v_base || '/quotes', v_headers));
  -- Le week-end, un passage par heure suffit à fixer les clôtures du vendredi.
  perform cron.schedule('quotes-off-hours', '0 * * * 0,6',
    format('select net.http_post(url := %L, headers := %s)', v_base || '/quotes', v_headers));

  -- Historique : quatre parts, six minutes d'écart, dix jours de profondeur
  -- (le rattrapage long se fait à la main, titre par titre).
  perform cron.unschedule(jobid) from cron.job where jobname like 'history-daily%';
  for v_part in 0..3 loop
    perform cron.schedule(format('history-daily-%s', v_part),
      format('%s 22 * * 1-5', 30 + v_part * 6),
      format('select net.http_post(url := %L, headers := %s)',
             v_base || format('/history?days=10&part=%s/4', v_part), v_headers));
  end loop;

  -- Journal des demandes : deux jours suffisent à la limite par minute.
  perform cron.unschedule(jobid) from cron.job where jobname = 'quote-refresh-purge';
  perform cron.schedule('quote-refresh-purge', '15 3 * * *',
    $sql$delete from public.quote_refresh_requests where created_at < now() - interval '2 days'$sql$);
end;
$$;
