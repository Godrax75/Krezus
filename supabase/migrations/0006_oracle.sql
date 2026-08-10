-- =====================================================================
-- Lot 6 — Oracle : repères de valorisation, prédictions, profil investisseur.
--
-- Contrainte structurante, tirée de la section réglementaire du plan :
-- l'Oracle ne doit produire AUCUNE recommandation personnalisée d'achat sur
-- titre nommé — ce serait du conseil en investissement (statut CIF). Tout ce
-- qui est calculé ici est un rapprochement de chiffres publics, présenté comme
-- tel, jamais un signal d'achat.
--
-- Ce que le plan prévoyait et qui n'est PAS livré : les listes « sous-évaluées
-- / surévaluées » devaient s'appuyer sur `securities.analyst_target`. La
-- colonne existe mais le seed ne la renseigne pas — le prototype ne portait
-- pas d'objectifs de cours. Inventer ces valeurs aurait donné une liste
-- d'achats sur titres nommés adossée à des données fabriquées. Les repères
-- ci-dessous s'appuient uniquement sur les fondamentaux réellement seedés.
--
-- Codes SQLSTATE, classe privée « KR » :
--   KR030  réponses de profil invalides
-- =====================================================================

-- ---------------------------------------------------------------------
-- Repères sectoriels — médianes des fondamentaux réellement disponibles
-- ---------------------------------------------------------------------
-- Comparer le PER d'une action à celui de son secteur est un fait, pas un
-- avis. C'est le seul cadrage honnête possible sans objectifs analystes.
create or replace view public.v_sector_fundamentals as
select
  s.sector,
  count(*)                                                     as securities,
  count(s.pe_ratio)                                            as with_pe,
  percentile_cont(0.5) within group (order by s.pe_ratio)      as median_pe,
  percentile_cont(0.5) within group (order by s.peg_ratio)     as median_peg,
  percentile_cont(0.5) within group (order by s.dividend_yield) as median_dividend
from public.securities s
where s.sector is not null and s.asset_type = 'stock'
group by s.sector;

comment on view public.v_sector_fundamentals is
  'Médianes sectorielles des fondamentaux seedés. Sert de repère de comparaison '
  'pédagogique — jamais de signal d''achat.';

-- ---------------------------------------------------------------------
-- Cache Polymarket
-- ---------------------------------------------------------------------
-- API Gamma publique, sans clé, ~60 req/min. Mise en cache 15 min côté
-- serveur : l'app ne doit pas taper une API tierce à chaque affichage, et le
-- bloc reste purement informatif (aucun lien sortant vers la plateforme de
-- paris — guideline App Store 4.7).
create table public.polymarket_cache (
  id            text primary key,               -- identifiant du marché chez Polymarket
  question      text not null,
  probability   numeric not null check (probability >= 0 and probability <= 1),
  volume        numeric,
  ends_at       timestamptz,
  category      text,
  fetched_at    timestamptz not null default now()
);

create index on public.polymarket_cache (fetched_at desc);

alter table public.polymarket_cache enable row level security;
create policy "polymarket readable" on public.polymarket_cache
  for select to authenticated using (true);

comment on table public.polymarket_cache is
  'Probabilités de marchés prédictifs, à titre informatif. Aucun lien de pari '
  'sortant ne doit être exposé dans l''app.';

-- ---------------------------------------------------------------------
-- Profil investisseur
-- ---------------------------------------------------------------------
-- L'archétype est un résultat de questionnaire, pas un profil de risque
-- réglementaire (MiFID) : il oriente le ton pédagogique, il ne conditionne
-- aucun accès produit.
create or replace function public.save_investor_profile(
  p_user      uuid,
  p_answers   jsonb,
  p_archetype text,
  p_dna       jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Réponses de profil invalides' using errcode = 'KR030';
  end if;
  if p_archetype is null or length(trim(p_archetype)) = 0 then
    raise exception 'Archétype manquant' using errcode = 'KR030';
  end if;

  insert into public.investor_profile (user_id, answers, archetype, dna, updated_at)
  values (p_user, p_answers, p_archetype, coalesce(p_dna, '{}'::jsonb), now())
  on conflict (user_id) do update
    set answers    = excluded.answers,
        archetype  = excluded.archetype,
        dna        = excluded.dna,
        updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------
-- Coach — indicateurs factuels du portefeuille
-- ---------------------------------------------------------------------
-- Chaque axe du radar est une mesure vérifiable, pas une note d'opinion :
-- l'utilisateur doit pouvoir retrouver le chiffre lui-même dans ses positions.
create or replace view public.v_portfolio_health as
select
  po.id                                              as portfolio_id,
  po.user_id,
  count(distinct s.sector) filter (where p.quantity > 0)  as sectors_held,
  count(*) filter (where p.quantity > 0)                  as positions_held,
  count(distinct s.currency) filter (where p.quantity > 0) as currencies_held,
  -- Poids de la plus grosse position : au-delà de ~40 %, le portefeuille suit
  -- surtout une seule entreprise.
  coalesce(max(p.quantity * q.price) / nullif(sum(p.quantity * q.price), 0), 0)
                                                          as top_position_weight,
  sum(p.quantity * q.price)                               as holdings_value
from public.portfolios po
left join public.positions p   on p.portfolio_id = po.id
left join public.securities s  on s.symbol = p.symbol
left join public.quotes_cache q on q.symbol = p.symbol
group by po.id, po.user_id;

comment on view public.v_portfolio_health is
  'Mesures factuelles servant le radar du Coach. Aucune notation ni conseil.';
