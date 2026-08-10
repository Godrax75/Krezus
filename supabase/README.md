# Backend Supabase — Krezus

Schéma, moteur d'ordres papier, RLS et seeds pour le mode paper money.

## Contenu

```
migrations/
  0001_init.sql          schéma (titres, cotations, portefeuille, academy, arena, profil…)
  0002_paper_engine.sql  execute_paper_buy / _sell / reset_paper_portfolio (transactionnel)
  0003_rls.sql           Row Level Security + trigger de création de compte
  0004_market_data.sql   conversion de devise, fx_rates, journal des rafraîchissements
functions/
  _shared/eodhd.ts       adaptateur EODHD (URL + parsing, sans I/O)
  _shared/market_hours.ts heures de séance Euronext / US
  _shared/db.ts          accès PostgREST en service role
  quotes/index.ts        rafraîchit quotes_cache (cron 60 s en séance)
  history/index.ts       alimente price_history depuis l'EOD (cron quotidien)
  tests/                 31 tests de contrat sur fixtures enregistrées
seed/
  securities.sql         81 titres (actions FR/US mappées EODHD + 30 ETF à mapper)
  securities_en.sql      description_en / hercule_note_en / sector_en des 81 titres
  lessons.sql            27 leçons + quiz
  ranks_missions_badges.sql
tests/
  00_auth_stub.sql       stub des rôles + schéma auth pour tester sur Postgres nu
  paper_engine_test.sql  6 tests d'assertion du moteur d'ordres
  market_data_test.sql   5 tests de conversion de devise
```

## Tester le moteur d'ordres en local (sans compte Supabase)

Nécessite `postgresql@16` (installé via Homebrew). Le script crée une base jetable,
applique le schéma + le moteur, et lance les assertions :

```bash
./tools/run_paper_engine_tests.sh
```

Couvre : achat à parts fractionnées, coût moyen pondéré, fonds insuffisants (rejet + état
inchangé), cotation périmée rejetée, vente 50 %/100 %, reset.

## Déployer sur un vrai projet Supabase (région EU)

1. Créer un projet sur supabase.com — **région Europe (Francfort)** pour le RGPD.
2. Appliquer le schéma dans l'ordre, via le SQL Editor ou la CLI : les migrations
   `0001_init.sql` → … → `0010_sector_en.sql`, puis les fichiers de `seed/`.
   `securities_en.sql` vient **après** `securities.sql` (il ne fait que des `update`)
   et après `0010`, qui crée la colonne `sector_en` qu'il remplit.
   Ne PAS appliquer `tests/00_auth_stub.sql` (Supabase fournit déjà `auth`).
3. **Auth** → activer *Apple* et *Google* comme fournisseurs, renseigner leurs identifiants.
4. Récupérer *Project Ref* et *anon key* (Settings → API), puis dans l'app :
   ```bash
   cp Krezus/Config/Secrets.example.xcconfig Krezus/Config/Secrets.xcconfig
   # renseigner SUPABASE_PROJECT_REF, SUPABASE_ANON_KEY, GOOGLE_OAUTH_CLIENT_ID
   xcodegen generate
   ```
   Dès que les secrets sont réels, l'`AuthGate` bascule du mode démo vers l'écran de connexion
   puis l'app branchée sur les données.

## Données de marché (Lot 3)

### Sur le plan gratuit EODHD, la Edge Function `quotes` est inutilisable

Le plan gratuit autorise **20 appels par jour** (plus une réserve de bienvenue de
500). La Edge Function est écrite pour un rafraîchissement toutes les 60 s en
séance, soit ~480 appels par jour : elle épuiserait le quota en trois minutes.

Le piège qui décide de tout : **un appel groupé coûte un appel par symbole.**
Passer 50 titres dans une seule URL économise des allers-retours HTTP, pas du
quota — rafraîchir les 51 titres mappés consomme 51 appels.

En attendant un plan payant, `tools/refresh_quotes.py` alimente `quotes_cache` à
la demande, avec un jeu par défaut de 12 titres (13 appels avec le taux de
change) qui tient dans le quota quotidien :

```bash
export KREZUS_DB_URL='postgresql://postgres:MOTDEPASSE@db.<ref>.supabase.co:5432/postgres'
export EODHD_API_TOKEN='...'
python3 tools/refresh_quotes.py --dry-run   # coût, sans rien dépenser
python3 tools/refresh_quotes.py
```

Le moteur rejette une cotation de plus de 15 minutes (KR004) : chaque passage
ouvre donc **un quart d'heure** pendant lequel l'app peut passer des ordres.
Basculer sur le plan EOD+Intraday (29,99 €/mois, 100 000 appels/jour) est ce qui
rend la Edge Function et son cron pertinents.

### La règle à ne pas casser

`quotes_cache.price` est **toujours en euros** — c'est la colonne que lit le moteur
d'ordres pour calculer les parts. Le cours de cotation vit dans `price_native`, avec
le taux appliqué dans `fx_rate`. Douze des 82 titres du référentiel cotent en dollars :
y écrire le cours brut ferait acheter 100 € de Nvidia à ~8 % de parts en trop.

Une contrainte `CHECK` rejette toute ligne en devise étrangère dont `price` n'est pas
la conversion de `price_native`. `tools/run_market_data_tests.sh` le vérifie (T3, T4).

### Tester

```bash
./tools/run_market_data_tests.sh
```

Adaptateur EODHD sur fixtures (aucun appel réseau) + conversion de devise sur une base
jetable. Les fixtures couvrent `MC.PA`, `AIR.PA`, `MT.AS`, `NVDA.US` — euro et dollar,
valeurs `"NA"`, réponse objet d'un symbole seul.

### Déployer les Edge Functions

```bash
supabase secrets set EODHD_API_TOKEN=xxx MARKET_DATA_SECRET=$(openssl rand -hex 32)
supabase functions deploy quotes  --no-verify-jwt
supabase functions deploy history --no-verify-jwt
```

`--no-verify-jwt` parce que l'appelant est un planificateur, pas un utilisateur :
l'authentification se fait par l'en-tête `x-market-data-secret`.

### Planifier

Avec `pg_cron` + `pg_net` (activés depuis Database → Extensions) :

```sql
select cron.schedule('quotes-market-hours', '* 7-22 * * 1-5', $$
  select net.http_post(
    url     := 'https://<ref>.functions.supabase.co/quotes',
    headers := '{"x-market-data-secret":"<secret>"}'::jsonb
  );
$$);

select cron.schedule('history-daily', '30 22 * * 1-5', $$
  select net.http_post(
    url     := 'https://<ref>.functions.supabase.co/history',
    headers := '{"x-market-data-secret":"<secret>"}'::jsonb
  );
$$);
```

La fonction `quotes` détermine elle-même la séance en cours ; le cron peut donc rester
grossier (toutes les minutes sur une plage large en UTC). Hors séance elle rafraîchit
quand même : le moteur rejette une cotation de plus de 15 minutes, et sans ce battement
tout ordre passé le soir échouerait sur `KR004` au lieu de s'exécuter à la clôture.

### Vérifier en conditions réelles

```sql
select * from public.market_data_runs order by started_at desc limit 10;
```

`api_calls` doit valoir 2 pour 82 titres (lots de 50) et `session` refléter l'heure.
L'écart entre `quoted_at` et `fetched_at` dans `quotes_cache` doit rester cohérent avec
le différé de 15 min imposé par la licence EODHD.

### Ce qui n'est pas couvert

- **Courbe 1 semaine** : `price_history` ne stocke que des clôtures quotidiennes. La
  courbe intraday du design (`/api/intraday?interval=5m`) demande soit une table
  dédiée, soit un proxy à la demande — arbitrage à trancher, pas devinable.
- **Jours fériés boursiers** : non gérés. Effet réel nul (on rafraîchit pour rien
  quelques fois par an), mais insuffisant pour afficher « marché fermé ».
- **ETF** : 30 lignes du seed ont `eodhd_symbol` NULL et sont ignorées par les
  fonctions. Leurs tickers Euronext doivent être vérifiés avant activation.

## Progression Academy (Lot 5)

### D'où vient l'XP

**Uniquement des missions**, jamais de la leçon elle-même : `activate` (50, une fois),
`lesson` (20/jour), `quiz` (30/jour). Enchaîner les 27 leçons d'un coup rapporte donc 50 XP,
pas 1 350 — sans ce plafond, le rang maximal s'atteindrait en une session et la série
quotidienne ne servirait plus à rien.

Conséquence directe, vérifiée en simulateur : bonne réponse au quiz = +50 XP,
mauvaise réponse = +20 XP (la leçon compte, le quiz non).

### Fonctions

| Fonction | Rôle |
|---|---|
| `rank_for_xp(xp)` | palier de 200 XP, borné à 6 |
| `award_xp(user, xp)` | crédite, recalcule le rang, attribue `rank_up` |
| `touch_streak(user)` | +1 par jour, idempotente dans la journée, remet à 1 après un trou |
| `complete_mission(user, code)` | renvoie l'XP accordée — 0 si déjà validée |
| `complete_lesson(user, lesson, quiz_correct)` | transactionnel : progression + XP + série + badges |
| `record_quiz_attempt(user, score, total)` | historique |

Badges de trading (`first_buy`, `diversified`) : trigger sur `orders`, pour ne pas rouvrir
le moteur d'ordres du Lot 2 qui est couvert par ses propres tests.

### Tester

```bash
./tools/run_academy_tests.sh
```

13 assertions : paliers de rang, non-rejouabilité des missions, plafond quotidien, série aux
bornes de journée, paywall des leçons, badges.

### Contenu embarqué dans l'app

`Krezus/Resources/lessons.json` et `ranks.json` sont **exportés depuis Postgres**, pas écrits
à la main — la commande est dans l'historique du Lot 5 (`jsonb_agg` sur `lessons` / `ranks`).
Régénérer après toute modification du seed, sinon l'app et la base divergent.

## Codes d'erreur du moteur (classe SQLSTATE « KR »)

Le client Swift (`KrezusError.from(sqlState:)`) mappe chaque code vers un message :
`KR001` fonds insuffisants · `KR002` introuvable · `KR003` cotation indisponible ·
`KR004` cotation périmée · `KR010` paramètre invalide.

> Ne jamais réutiliser la classe `P0` de PL/pgSQL pour des erreurs métier :
> `P0004` = `assert_failure`, que `when others` ne capture jamais.
