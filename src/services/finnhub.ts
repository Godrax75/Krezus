import { FINNHUB_API_KEY, FINNHUB_BASE_URL, isLiveDataEnabled } from './config';
import { ApiError, fetchJson } from './http';

/**
 * Client Finnhub bas niveau, strictement en lecture.
 * Aucune écriture, aucun ordre : uniquement cotations, chandeliers et news.
 * Docs : https://finnhub.io/docs/api
 */

export interface FinnhubQuote {
  /** Cours actuel. */
  c: number;
  /** Variation absolue du jour. */
  d: number | null;
  /** Variation en % du jour. */
  dp: number | null;
  /** Plus haut du jour. */
  h: number;
  /** Plus bas du jour. */
  l: number;
  /** Ouverture. */
  o: number;
  /** Clôture précédente. */
  pc: number;
  /** Horodatage UNIX (secondes). */
  t: number;
}

export interface FinnhubCandles {
  /** Cours de clôture. */
  c?: number[];
  /** Horodatages UNIX (secondes). */
  t?: number[];
  s: 'ok' | 'no_data';
}

export interface FinnhubNewsItem {
  id: number;
  headline: string;
  source: string;
  datetime: number;
  image: string;
  url: string;
  summary: string;
}

export interface FinnhubMetrics {
  metric?: Record<string, number | string | null>;
}

export interface FinnhubForexRates {
  base: string;
  quote: Record<string, number>;
}

export type CandleResolution = '1' | '5' | '15' | '30' | '60' | 'D' | 'W' | 'M';

function buildUrl(path: string, params: Record<string, string | number>): string {
  if (!isLiveDataEnabled) {
    throw new ApiError('Aucune clé API configurée (EXPO_PUBLIC_FINNHUB_KEY)');
  }
  const query = new URLSearchParams({
    ...Object.fromEntries(
      Object.entries(params).map(([key, value]) => [key, String(value)])
    ),
    token: FINNHUB_API_KEY,
  });
  return `${FINNHUB_BASE_URL}${path}?${query.toString()}`;
}

/** Cotation temps différé (~15 min sur le palier gratuit). */
export function fetchQuote(symbol: string): Promise<FinnhubQuote> {
  return fetchJson<FinnhubQuote>(buildUrl('/quote', { symbol }));
}

/**
 * Historique de cours.
 * Peut répondre 403 : l'endpoint chandeliers est réservé aux offres payantes
 * sur certains comptes. L'appelant retombe alors sur les données de démo.
 */
export function fetchCandles(
  symbol: string,
  resolution: CandleResolution,
  from: number,
  to: number
): Promise<FinnhubCandles> {
  return fetchJson<FinnhubCandles>(
    buildUrl('/stock/candle', { symbol, resolution, from, to })
  );
}

/** Actualités de l'entreprise sur une fenêtre de dates (format `YYYY-MM-DD`). */
export function fetchCompanyNews(
  symbol: string,
  from: string,
  to: string
): Promise<FinnhubNewsItem[]> {
  return fetchJson<FinnhubNewsItem[]>(
    buildUrl('/company-news', { symbol, from, to })
  );
}

/** Métriques fondamentales : on n'utilise que les plus haut/bas 52 semaines. */
export function fetchMetrics(symbol: string): Promise<FinnhubMetrics> {
  return fetchJson<FinnhubMetrics>(
    buildUrl('/stock/metric', { symbol, metric: 'price' })
  );
}

/** Taux de change, pour convertir les cotations US en euros. */
export function fetchForexRates(base: string): Promise<FinnhubForexRates> {
  return fetchJson<FinnhubForexRates>(buildUrl('/forex/rates', { base }));
}
