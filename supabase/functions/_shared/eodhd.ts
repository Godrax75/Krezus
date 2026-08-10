// =====================================================================
// Adaptateur EODHD — construction d'URL et parsing, sans aucune I/O.
//
// Vit côté serveur et pas dans l'app : le jeton EODHD est extractible d'un
// binaire iOS en quelques minutes, et les conditions de redistribution
// interdisent d'exposer le flux brut. L'app lit `quotes_cache`, jamais EODHD.
//
// Toutes les fonctions de ce fichier sont pures — c'est ce qui rend les tests
// de contrat sur fixtures possibles (voir tests/eodhd_test.ts).
// =====================================================================

export const EODHD_BASE = "https://eodhd.com/api";

/** Paire de change : `close` = dollars pour 1 euro. */
export const FX_PAIR = "EURUSD.FOREX";

/** Devise de compte des portefeuilles. Tout est ramené à celle-ci. */
export const ACCOUNT_CURRENCY = "EUR";

/**
 * Symboles par appel temps réel. EODHD n'impose pas de limite documentée sur
 * `s=`, mais l'URL doit rester sous la limite pratique des proxies (~2 000
 * caractères) : 50 symboles × ~8 caractères laisse une marge confortable.
 */
export const REALTIME_BATCH_SIZE = 50;

export interface RawQuote {
  code: string;
  close: number | null;
  open: number | null;
  previousClose: number | null;
  changePct: number | null;
  /** Horodatage marché, en secondes epoch. */
  timestamp: number | null;
}

export interface QuoteRow {
  symbol: string;
  price: number;
  price_native: number;
  currency: string;
  fx_rate: number;
  open: number | null;
  change_pct: number | null;
  previous_close: number | null;
  quoted_at: string | null;
  fetched_at: string;
}

export interface HistoryPoint {
  symbol: string;
  date: string;
  close: number;
}

/** Titre du référentiel, réduit à ce dont l'adaptateur a besoin. */
export interface SecurityRef {
  symbol: string;
  eodhd_symbol: string;
  currency: string;
}

/**
 * EODHD renvoie `"NA"` (et non `null`) pour une valeur absente, et sérialise
 * parfois les nombres en chaînes. Tout ce qui n'est pas un nombre fini → null.
 */
export function toNumber(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (trimmed === "" || trimmed.toUpperCase() === "NA") return null;
    const parsed = Number(trimmed);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function chunk<T>(items: readonly T[], size: number): T[][] {
  if (size <= 0) throw new RangeError("chunk: size doit être > 0");
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * Un seul appel couvre tout un lot : le premier symbole va dans le chemin, les
 * suivants dans `s=`. C'est ce qui permet de tenir 82 titres en 2 appels.
 */
export function buildRealTimeURL(symbols: readonly string[], token: string): string {
  if (symbols.length === 0) throw new RangeError("buildRealTimeURL: aucun symbole");
  const [head, ...rest] = symbols;
  const url = new URL(`${EODHD_BASE}/real-time/${encodeURIComponent(head)}`);
  url.searchParams.set("api_token", token);
  url.searchParams.set("fmt", "json");
  if (rest.length > 0) url.searchParams.set("s", rest.join(","));
  return url.toString();
}

export function buildEODURL(symbol: string, token: string, from?: string): string {
  const url = new URL(`${EODHD_BASE}/eod/${encodeURIComponent(symbol)}`);
  url.searchParams.set("api_token", token);
  url.searchParams.set("fmt", "json");
  url.searchParams.set("period", "d");
  if (from) url.searchParams.set("from", from);
  return url.toString();
}

/**
 * La réponse temps réel est un objet quand un seul symbole est demandé, un
 * tableau sinon. Les entrées inexploitables (pas de code, pas de cours) sont
 * écartées plutôt que de faire échouer le lot entier.
 */
export function parseRealTime(payload: unknown): RawQuote[] {
  const entries = Array.isArray(payload) ? payload : [payload];
  const quotes: RawQuote[] = [];

  for (const entry of entries) {
    if (entry === null || typeof entry !== "object") continue;
    const row = entry as Record<string, unknown>;
    const code = typeof row.code === "string" ? row.code.trim() : "";
    if (code === "") continue;

    const close = toNumber(row.close);
    if (close === null || close <= 0) continue;

    quotes.push({
      code,
      close,
      open: toNumber(row.open),
      previousClose: toNumber(row.previousClose),
      changePct: toNumber(row.change_p),
      timestamp: toNumber(row.timestamp),
    });
  }
  return quotes;
}

export function parseEOD(symbol: string, payload: unknown): HistoryPoint[] {
  if (!Array.isArray(payload)) return [];
  const points: HistoryPoint[] = [];

  for (const entry of payload) {
    if (entry === null || typeof entry !== "object") continue;
    const row = entry as Record<string, unknown>;
    const date = typeof row.date === "string" ? row.date.trim() : "";
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) continue;

    // `adjusted_close` corrige splits et dividendes : c'est la série qui donne
    // une courbe continue. On retombe sur `close` si elle manque.
    const close = toNumber(row.adjusted_close) ?? toNumber(row.close);
    if (close === null || close <= 0) continue;

    points.push({ symbol, date, close });
  }
  return points;
}

/** Extrait le taux EURUSD d'une réponse temps réel contenant la paire FOREX. */
export function extractFxRate(quotes: readonly RawQuote[]): number | null {
  const fx = quotes.find((q) => q.code.toUpperCase() === FX_PAIR);
  if (!fx || fx.close === null || fx.close <= 0) return null;
  return fx.close;
}

/**
 * Ramène un cours à la devise de compte. `eurUsd` = dollars pour 1 euro, donc
 * un cours en dollars se divise par ce taux.
 *
 * Renvoie null si la conversion est impossible : mieux vaut ne pas rafraîchir
 * une ligne que d'écrire un prix faux, sur lequel un ordre serait exécuté.
 */
export function convertToAccountCurrency(
  priceNative: number,
  currency: string,
  eurUsd: number | null,
): { price: number; fxRate: number } | null {
  const code = currency.trim().toUpperCase();
  if (code === ACCOUNT_CURRENCY) return { price: priceNative, fxRate: 1 };
  if (code === "USD") {
    if (eurUsd === null || eurUsd <= 0) return null;
    return { price: priceNative / eurUsd, fxRate: eurUsd };
  }
  return null;
}

/**
 * Assemble les lignes prêtes à être upsertées dans `quotes_cache`.
 *
 * Le tri se fait sur `eodhd_symbol` et non sur le symbole interne : ce sont
 * deux espaces de nommage distincts (interne `MC` ↔ cotation `MC.PA`), et les
 * confondre est exactement le piège que le référentiel documente.
 */
export function buildQuoteRows(
  quotes: readonly RawQuote[],
  securities: readonly SecurityRef[],
  eurUsd: number | null,
  now: Date,
): { rows: QuoteRow[]; skipped: string[] } {
  const byEodhdSymbol = new Map<string, SecurityRef>();
  for (const sec of securities) {
    if (sec.eodhd_symbol) byEodhdSymbol.set(sec.eodhd_symbol.toUpperCase(), sec);
  }

  const rows: QuoteRow[] = [];
  const skipped: string[] = [];
  const fetchedAt = now.toISOString();

  for (const quote of quotes) {
    const code = quote.code.toUpperCase();
    if (code === FX_PAIR) continue;             // la paire de change n'est pas un titre

    const security = byEodhdSymbol.get(code);
    if (!security) { skipped.push(quote.code); continue; }
    if (quote.close === null) { skipped.push(quote.code); continue; }

    const converted = convertToAccountCurrency(quote.close, security.currency, eurUsd);
    if (converted === null) { skipped.push(quote.code); continue; }

    // Priorité à `change_p` fourni par EODHD ; sinon recalcul sur la clôture
    // précédente. Le ratio est invariant par changement de devise, donc il se
    // calcule indifféremment sur le cours natif.
    let changePct = quote.changePct;
    if (changePct === null && quote.previousClose !== null && quote.previousClose > 0) {
      changePct = ((quote.close - quote.previousClose) / quote.previousClose) * 100;
    }

    const openNative = quote.open;
    const openConverted = openNative === null
      ? null
      : convertToAccountCurrency(openNative, security.currency, eurUsd)?.price ?? null;
    const prevConverted = quote.previousClose === null
      ? null
      : convertToAccountCurrency(quote.previousClose, security.currency, eurUsd)?.price ?? null;

    rows.push({
      symbol: security.symbol,
      price: round(converted.price, 6),
      price_native: round(quote.close, 6),
      currency: security.currency.toUpperCase(),
      fx_rate: round(converted.fxRate, 8),
      open: openConverted === null ? null : round(openConverted, 6),
      change_pct: changePct === null ? null : round(changePct, 4),
      previous_close: prevConverted === null ? null : round(prevConverted, 6),
      quoted_at: quote.timestamp === null
        ? null
        : new Date(quote.timestamp * 1000).toISOString(),
      fetched_at: fetchedAt,
    });
  }

  return { rows, skipped };
}

/**
 * Arrondi décimal. `price` est comparé en base à `price_native / fx_rate` par
 * une contrainte CHECK : arrondir trop court ferait échouer l'insertion.
 */
export function round(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}
