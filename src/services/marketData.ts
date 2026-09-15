import { ChartDataPoint, NewsArticle, Portfolio, Position, Stock, TimePeriod } from '../types';
import {
  generateChartData,
  generateStockChartData,
  mockNews,
  mockStocks,
} from '../data/mockData';
import { DISPLAY_CURRENCY, TTL, isLiveDataEnabled } from './config';
import { TtlCache } from './cache';
import {
  CandleResolution,
  FinnhubCandles,
  FinnhubMetrics,
  FinnhubNewsItem,
  FinnhubQuote,
  fetchCandles,
  fetchCompanyNews,
  fetchForexRates,
  fetchMetrics,
  fetchQuote,
} from './finnhub';
import { getSymbolMapping } from './symbols';

/**
 * Façade de données de marché, en lecture seule.
 *
 * Règle unique de ce module : **il ne jette jamais**. Si la clé manque, si le
 * titre n'est pas couvert par le palier gratuit, si le réseau tombe ou si le
 * fournisseur répond 403/429, on retombe sur `src/data/mockData.ts` et on le
 * signale via `isLive: false`. L'app reste utilisable hors ligne et en démo.
 */

export interface MarketDataResult<T> {
  data: T;
  /** `true` si la donnée vient réellement du fournisseur. */
  isLive: boolean;
  /** Message technique du dernier échec, à des fins de diagnostic. */
  error?: string;
}

export interface LiveQuote {
  stockId: string;
  currency: 'EUR' | 'USD';
  currentPrice: number;
  previousClose: number;
  dayChange: number;
  dayChangePercent: number;
  high52w?: number;
  low52w?: number;
  /** Horodatage (ms) de la cotation renvoyée par le fournisseur. */
  quotedAt: number;
}

const quoteCache = new TtlCache<FinnhubQuote>(TTL.quote);
const metricsCache = new TtlCache<FinnhubMetrics>(TTL.profile);
const candleCache = new TtlCache<FinnhubCandles>(TTL.candles);
const newsCache = new TtlCache<FinnhubNewsItem[]>(TTL.news);
const forexCache = new TtlCache<number | null>(TTL.forex);

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'Erreur inconnue';
}

// ---------------------------------------------------------------------------
// Change
// ---------------------------------------------------------------------------

/**
 * Taux de conversion vers la devise d'affichage.
 * Renvoie `null` si le fournisseur ne le donne pas : on préfère afficher un
 * prix en dollars plutôt qu'un prix faux libellé en euros.
 */
async function getConversionRate(from: 'EUR' | 'USD'): Promise<number | null> {
  if (from === DISPLAY_CURRENCY) return 1;
  if (!isLiveDataEnabled) return null;

  return forexCache.resolve(from, async () => {
    try {
      const rates = await fetchForexRates(from);
      const rate = rates?.quote?.[DISPLAY_CURRENCY];
      return typeof rate === 'number' && rate > 0 ? rate : null;
    } catch {
      return null;
    }
  });
}

// ---------------------------------------------------------------------------
// Cotations
// ---------------------------------------------------------------------------

function toNumber(value: number | string | null | undefined): number | undefined {
  const parsed = typeof value === 'string' ? parseFloat(value) : value;
  return typeof parsed === 'number' && Number.isFinite(parsed) ? parsed : undefined;
}

/** Les plus haut/bas 52 semaines sont un bonus : leur échec ne fait pas échouer la cotation. */
async function get52WeekRange(
  symbol: string
): Promise<{ high52w?: number; low52w?: number }> {
  try {
    const metrics = await metricsCache.resolve(symbol, () => fetchMetrics(symbol));
    return {
      high52w: toNumber(metrics?.metric?.['52WeekHigh']),
      low52w: toNumber(metrics?.metric?.['52WeekLow']),
    };
  } catch {
    return {};
  }
}

/**
 * Cotation d'un titre. `null` dès que la donnée réelle n'est pas disponible —
 * l'appelant garde alors la valeur de démo.
 */
export async function getQuote(
  stockId: string,
  force = false
): Promise<LiveQuote | null> {
  const mapping = getSymbolMapping(stockId);
  if (!isLiveDataEnabled || !mapping || !mapping.supported) return null;

  try {
    const quote = await quoteCache.resolve(
      mapping.providerSymbol,
      () => fetchQuote(mapping.providerSymbol),
      force
    );

    // Finnhub renvoie `c: 0` pour un symbole inconnu plutôt qu'une erreur HTTP.
    if (!quote || !Number.isFinite(quote.c) || quote.c <= 0) return null;

    const rate = await getConversionRate(mapping.currency);
    const converted = rate ?? 1;
    const currency: 'EUR' | 'USD' = rate === null ? mapping.currency : DISPLAY_CURRENCY;

    const range = await get52WeekRange(mapping.providerSymbol);
    const currentPrice = quote.c * converted;
    const previousClose = (quote.pc || quote.c) * converted;
    const dayChange = quote.d != null ? quote.d * converted : currentPrice - previousClose;
    const dayChangePercent =
      quote.dp != null
        ? quote.dp
        : previousClose > 0
          ? ((currentPrice - previousClose) / previousClose) * 100
          : 0;

    return {
      stockId: mapping.stockId,
      currency,
      currentPrice,
      previousClose,
      dayChange,
      dayChangePercent,
      high52w: range.high52w != null ? range.high52w * converted : undefined,
      low52w: range.low52w != null ? range.low52w * converted : undefined,
      quotedAt: quote.t ? quote.t * 1000 : Date.now(),
    };
  } catch {
    return null;
  }
}

/** Applique une cotation sur la fiche statique du titre (nom, secteur, description restent locaux). */
export function mergeQuoteIntoStock(stock: Stock, quote: LiveQuote): Stock {
  return {
    ...stock,
    currency: quote.currency,
    currentPrice: round2(quote.currentPrice),
    previousClose: round2(quote.previousClose),
    dayChange: round2(quote.dayChange),
    dayChangePercent: round2(quote.dayChangePercent),
    high52w: quote.high52w != null ? round2(quote.high52w) : stock.high52w,
    low52w: quote.low52w != null ? round2(quote.low52w) : stock.low52w,
  };
}

/**
 * Instantané de toutes les valeurs détenues : mocks enrichis des cotations
 * réellement obtenues. Le dictionnaire garde la clé historique (`AAPL`,
 * `LVMH`, …) pour ne rien casser côté écrans.
 */
export async function getStocksSnapshot(
  stockIds: string[],
  force = false
): Promise<MarketDataResult<Record<string, Stock>>> {
  const snapshot: Record<string, Stock> = { ...mockStocks };
  if (!isLiveDataEnabled) {
    return { data: snapshot, isLive: false };
  }

  const quotes = await Promise.all(stockIds.map((id) => getQuote(id, force)));
  let liveCount = 0;

  quotes.forEach((quote) => {
    if (!quote) return;
    const key = quote.stockId.toUpperCase();
    const stock = snapshot[key];
    if (!stock) return;
    snapshot[key] = mergeQuoteIntoStock(stock, quote);
    liveCount += 1;
  });

  return { data: snapshot, isLive: liveCount > 0 };
}

// ---------------------------------------------------------------------------
// Historique de cours
// ---------------------------------------------------------------------------

function getPeriodRange(period: TimePeriod): {
  resolution: CandleResolution;
  seconds: number;
} {
  const day = 24 * 60 * 60;
  switch (period) {
    case '1J': return { resolution: '5', seconds: day };
    case '1S': return { resolution: '60', seconds: 7 * day };
    case '1M': return { resolution: 'D', seconds: 31 * day };
    case '3M': return { resolution: 'D', seconds: 93 * day };
    case '6M': return { resolution: 'D', seconds: 186 * day };
    case '1A': return { resolution: 'W', seconds: 366 * day };
    default: return { resolution: 'M', seconds: 5 * 366 * day };
  }
}

function candlesToPoints(candles: FinnhubCandles, rate: number): ChartDataPoint[] {
  if (candles.s !== 'ok' || !candles.c?.length || !candles.t?.length) return [];
  const closes = candles.c;
  const times = candles.t;
  const length = Math.min(closes.length, times.length);

  const points: ChartDataPoint[] = [];
  for (let i = 0; i < length; i++) {
    const value = closes[i];
    if (!Number.isFinite(value)) continue;
    points.push({ timestamp: times[i] * 1000, value: round2(value * rate) });
  }
  return points;
}

/**
 * Courbe d'un titre. Retombe sur la courbe déterministe de démo si les
 * chandeliers ne sont pas accessibles (endpoint premium sur certains comptes).
 */
export async function getStockChart(
  stockId: string,
  period: TimePeriod,
  basePrice: number
): Promise<MarketDataResult<ChartDataPoint[]>> {
  const fallback = () => generateStockChartData(period, basePrice);
  const mapping = getSymbolMapping(stockId);
  if (!isLiveDataEnabled || !mapping || !mapping.supported) {
    return { data: fallback(), isLive: false };
  }

  const { resolution, seconds } = getPeriodRange(period);
  const to = Math.floor(Date.now() / 1000);
  const from = to - seconds;

  try {
    const candles = await candleCache.resolve(
      `${mapping.providerSymbol}_${period}`,
      () => fetchCandles(mapping.providerSymbol, resolution, from, to)
    );
    const rate = (await getConversionRate(mapping.currency)) ?? 1;
    const points = candlesToPoints(candles, rate);
    if (points.length < 2) return { data: fallback(), isLive: false };
    return { data: points, isLive: true };
  } catch (error) {
    return { data: fallback(), isLive: false, error: errorMessage(error) };
  }
}

/**
 * Courbe du portefeuille : somme pondérée des courbes de chaque ligne.
 * Il faut que **toutes** les lignes soient couvertes, sinon le total serait
 * faux ; dans le cas contraire on garde la courbe de démo.
 */
export async function getPortfolioChart(
  positions: Position[],
  period: TimePeriod,
  stocks: Record<string, Stock>
): Promise<MarketDataResult<ChartDataPoint[]>> {
  const fallback = () => generateChartData(period);
  if (!isLiveDataEnabled || positions.length === 0) {
    return { data: fallback(), isLive: false };
  }

  const series = await Promise.all(
    positions.map(async (position) => {
      const stock = stocks[position.stockId.toUpperCase()];
      const result = await getStockChart(
        position.stockId,
        period,
        stock?.currentPrice ?? position.averageCost
      );
      return { shares: position.shares, ...result };
    })
  );

  if (series.some((entry) => !entry.isLive)) {
    return { data: fallback(), isLive: false };
  }

  // Les séries peuvent différer en longueur (IPO récente, jours fériés) :
  // on les aligne par la fin, sur la plus courte.
  const length = Math.min(...series.map((entry) => entry.data.length));
  if (length < 2) return { data: fallback(), isLive: false };

  const points: ChartDataPoint[] = [];
  for (let i = 0; i < length; i++) {
    let total = 0;
    series.forEach((entry) => {
      const point = entry.data[entry.data.length - length + i];
      total += point.value * entry.shares;
    });
    const reference = series[0].data[series[0].data.length - length + i];
    points.push({ timestamp: reference.timestamp, value: round2(total) });
  }

  return { data: points, isLive: true };
}

// ---------------------------------------------------------------------------
// Actualités
// ---------------------------------------------------------------------------

function toIsoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** Actualités d'un titre, mappées sur `NewsArticle`. Fallback : `mockNews`. */
export async function getStockNews(
  stockId: string,
  limit = 5
): Promise<MarketDataResult<NewsArticle[]>> {
  const mapping = getSymbolMapping(stockId);
  if (!isLiveDataEnabled || !mapping || !mapping.supported) {
    return { data: mockNews.slice(0, limit), isLive: false };
  }

  const to = new Date();
  const from = new Date(to.getTime() - 30 * 24 * 60 * 60 * 1000);

  try {
    const items = await newsCache.resolve(mapping.providerSymbol, () =>
      fetchCompanyNews(mapping.providerSymbol, toIsoDate(from), toIsoDate(to))
    );

    const articles: NewsArticle[] = (items ?? [])
      .filter((item) => item.headline && item.url)
      .slice(0, limit)
      .map((item) => ({
        id: String(item.id),
        title: item.headline,
        source: item.source || 'Finnhub',
        date: new Date(item.datetime * 1000).toISOString(),
        imageUrl: item.image || '',
        url: item.url,
      }));

    if (articles.length === 0) {
      return { data: mockNews.slice(0, limit), isLive: false };
    }
    return { data: articles, isLive: true };
  } catch (error) {
    return { data: mockNews.slice(0, limit), isLive: false, error: errorMessage(error) };
  }
}

// ---------------------------------------------------------------------------
// Agrégation portefeuille
// ---------------------------------------------------------------------------

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * Recalcule les valorisations à partir des cours courants.
 * Les totaux étaient jusqu'ici écrits en dur : ils sont maintenant dérivés,
 * donc cohérents que la source soit réelle ou fictive.
 */
export function computePortfolio(
  positions: Position[],
  stocks: Record<string, Stock>
): Portfolio {
  const valued = positions.map((position) => {
    const stock = stocks[position.stockId.toUpperCase()];
    const price = stock?.currentPrice ?? position.averageCost;
    const currentValue = price * position.shares;
    const invested = position.averageCost * position.shares;
    const totalGain = currentValue - invested;

    return {
      ...position,
      currentValue: round2(currentValue),
      totalGain: round2(totalGain),
      totalGainPercent: invested > 0 ? round2((totalGain / invested) * 100) : 0,
    };
  });

  const totalValue = valued.reduce((sum, position) => sum + position.currentValue, 0);
  const totalInvested = positions.reduce(
    (sum, position) => sum + position.averageCost * position.shares,
    0
  );
  const totalGain = totalValue - totalInvested;

  return {
    totalValue: round2(totalValue),
    totalGain: round2(totalGain),
    totalGainPercent: totalInvested > 0 ? round2((totalGain / totalInvested) * 100) : 0,
    positions: valued,
  };
}

/** Vide les caches : utilisé par le pull-to-refresh pour forcer un vrai rechargement. */
export function invalidateMarketData(): void {
  quoteCache.clear();
  candleCache.clear();
  newsCache.clear();
}
