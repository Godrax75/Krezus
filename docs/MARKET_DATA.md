# Données de marché (lecture seule)

Ce document décrit la couche `src/services/`, qui remplace les cours fictifs
par des données réelles quand une clé API est disponible.

## Mise en route

1. Créer un compte gratuit sur <https://finnhub.io/register> (60 requêtes/minute).
2. `cp .env.example .env` puis coller la clé dans `EXPO_PUBLIC_FINNHUB_KEY`.
3. Relancer Metro en vidant le cache : `npx expo start -c`.

Sans clé, l'app démarre normalement sur `src/data/mockData.ts` et affiche
« Données de démonstration » sous la valeur du portefeuille.

## ⚠️ La clé n'est pas secrète

Les variables `EXPO_PUBLIC_*` sont **inlinées dans le bundle JavaScript** livré
aux stores : n'importe qui peut les extraire d'un IPA ou d'un APK. C'est
acceptable en développement avec une clé gratuite jetable.

Pour la production, la clé doit vivre côté serveur :

```
App ──► API Krezus (clé Finnhub côté serveur, cache, rate limiting) ──► Finnhub
```

Le passage au proxy ne touche qu'un fichier : `src/services/config.ts`
(`FINNHUB_BASE_URL` → l'URL du backend, et suppression du paramètre `token`
dans `finnhub.ts`). Le reste de la couche est inchangé.

## Architecture

| Fichier | Rôle |
| --- | --- |
| `config.ts` | Clé, URL de base, timeouts, durées de cache |
| `http.ts` | `fetchJson` avec timeout via `AbortController`, `ApiError` |
| `cache.ts` | Cache TTL en mémoire + déduplication des requêtes en vol |
| `finnhub.ts` | Client bas niveau : `/quote`, `/stock/candle`, `/company-news`, `/stock/metric`, `/forex/rates` |
| `symbols.ts` | Correspondance `stockId` interne ↔ symbole fournisseur |
| `marketData.ts` | Façade métier : cotations, courbes, actualités, agrégation portefeuille |

Aucune dépendance HTTP n'a été ajoutée : le `fetch` de React Native suffit.

### Principe de repli

**`marketData.ts` ne jette jamais.** Clé absente, titre non couvert, réseau HS,
réponse 403 (endpoint premium) ou 429 (quota dépassé) : on retombe sur les
données de démo et on le signale avec `isLive: false`. L'app reste utilisable
hors ligne.

### Cache

| Donnée | TTL |
| --- | --- |
| Cotations | 1 min |
| Chandeliers | 5 min |
| Actualités | 15 min |
| Métriques 52 semaines | 24 h |
| Taux de change | 12 h |

Le pull-to-refresh de l'accueil appelle `refreshMarketData(true)`, qui vide les
caches et force un vrai rechargement.

## Points d'intégration

- `src/store/AppContext.tsx` expose `stocks`, `portfolio`, `refreshMarketData`,
  `isLiveMarketData` et `marketDataUpdatedAt`. Les cours sont chargés au
  démarrage puis à chaque pull-to-refresh.
- `HomeScreen` : valorisation, cartes actions et courbe agrégée du portefeuille.
- `StockDetailScreen` : courbe du titre, métriques, et actualités réelles
  (vignette + ouverture du lien).
- Les totaux du portefeuille sont désormais **dérivés** des positions et des
  cours (`computePortfolio`), au lieu d'être écrits en dur.

## Limites connues

1. **LVMH (`MC.PA`, Euronext Paris) reste en données de démo.** Le palier
   gratuit de Finnhub ne couvre que le marché américain. Pour les places
   européennes il faut soit une offre payante, soit un second fournisseur
   (Twelve Data, EODHD, Yahoo Finance non officiel). `symbols.ts` marque ces
   titres `supported: false`.
2. **L'endpoint chandeliers (`/stock/candle`) est premium sur beaucoup de
   comptes gratuits.** En cas de 403, les courbes retombent automatiquement sur
   les séries déterministes de démo — les prix affichés, eux, restent réels.
3. **Conversion de devise.** Les cours US sont convertis en euros via
   `/forex/rates`. Si le taux n'est pas disponible, le prix est affiché dans sa
   devise d'origine (`198.45 $`) plutôt que faussement libellé en euros. Les
   montants du portefeuille (prix de revient, plus-values) restent exprimés en
   euros, devise du registre.
4. **Cotations différées** (~15 min sur le palier gratuit), ce qui convient au
   positionnement « investissement long terme » de l'app.
5. **La courbe du portefeuille exige que toutes les lignes soient couvertes** ;
   sinon le total serait faux et on garde la courbe de démo. Tant que LVMH n'est
   pas couvert, la courbe d'accueil reste donc en mode démo.

## Changer de fournisseur

Seuls `finnhub.ts` (appels bruts) et `marketData.ts` (mapping vers `Stock`,
`ChartDataPoint`, `NewsArticle`) sont à réécrire. Les écrans et le store ne
connaissent que les types de `src/types/index.ts`.
