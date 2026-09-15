/**
 * Configuration du fournisseur de données financières (lecture seule).
 *
 * SÉCURITÉ — à lire avant de mettre une clé en production :
 * les variables `EXPO_PUBLIC_*` sont inlinées dans le bundle JS livré aux
 * stores. Elles ne sont PAS secrètes : n'importe qui peut extraire la clé de
 * l'IPA/APK. C'est acceptable pour du dev et pour une clé gratuite jetable,
 * mais en production les appels doivent passer par un proxy côté serveur qui
 * détient la vraie clé (voir docs/MARKET_DATA.md).
 *
 * Sans clé, l'app fonctionne normalement sur les données de démo
 * (src/data/mockData.ts) : aucun écran ne casse.
 */

export const FINNHUB_BASE_URL = 'https://finnhub.io/api/v1';

/**
 * Renseignée via un fichier `.env` à la racine (voir `.env.example`) :
 *   EXPO_PUBLIC_FINNHUB_KEY=xxxxxxxxxxxx
 * Redémarrer Metro avec `npx expo start -c` après modification.
 */
export const FINNHUB_API_KEY = (process.env.EXPO_PUBLIC_FINNHUB_KEY ?? '').trim();

/** `true` dès qu'une clé est présente : sinon on reste sur les mocks. */
export const isLiveDataEnabled = FINNHUB_API_KEY.length > 0;

/** Coupe une requête qui traîne plutôt que de bloquer un pull-to-refresh. */
export const REQUEST_TIMEOUT_MS = 8000;

/** Durées de cache mémoire, calibrées sur les quotas du palier gratuit (60 req/min). */
export const TTL = {
  quote: 60 * 1000,
  candles: 5 * 60 * 1000,
  news: 15 * 60 * 1000,
  profile: 24 * 60 * 60 * 1000,
  forex: 12 * 60 * 60 * 1000,
} as const;

/** Devise d'affichage de l'app (les prix sont convertis quand c'est possible). */
export const DISPLAY_CURRENCY = 'EUR';
