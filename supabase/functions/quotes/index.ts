// =====================================================================
// Edge Function `quotes` — rafraîchit `quotes_cache` depuis EODHD.
//
// Déclenchée par cron chaque minute. Elle ne rafraîchit pas tout : chaque
// titre coûte un appel EODHD, et le référentiel en compte plus de mille.
// `selectForRefresh` choisit, dans un budget fixe, les titres détenus puis
// les plus anciens des places ouvertes (voir _shared/quote_budget.ts). Un
// titre consulté ou sur le point d'être acheté passe par `quote-refresh`.
// L'app ne lit que le cache.
//
// Secrets attendus :
//   EODHD_API_TOKEN            jeton EODHD (plan EOD+Intraday Extended)
//   SUPABASE_URL               injecté par la plateforme
//   SUPABASE_SERVICE_ROLE_KEY  injecté par la plateforme
//   MARKET_DATA_SECRET         secret partagé avec le planificateur
//
//   supabase secrets set EODHD_API_TOKEN=... MARKET_DATA_SECRET=...
//   supabase functions deploy quotes --no-verify-jwt
// =====================================================================

import {
  buildQuoteRows,
  buildRealTimeURL,
  chunk,
  extractFxRates,
  fxPairFor,
  parseRealTime,
  REALTIME_BATCH_SIZE,
  type RawQuote,
  type SecurityRef,
} from "../_shared/eodhd.ts";
import { selectForRefresh } from "../_shared/quote_budget.ts";
import { currentSession } from "../_shared/market_hours.ts";
import {
  assertAuthorized,
  dbConfigFromEnv,
  deleteRows,
  logRun,
  selectAllRows,
  UnauthorizedError,
  upsertRows,
} from "../_shared/db.ts";

/** Au-delà, la vue « 1 jour » n'en a plus besoin : le quotidien prend le relais. */
const INTRADAY_RETENTION_DAYS = 4;

/** Pas d'échantillonnage de la série intraday, en minutes. */
const INTRADAY_SAMPLE_MINUTES = 5;

Deno.serve(async (request: Request): Promise<Response> => {
  const startedAt = Date.now();
  const session = currentSession(new Date());

  try {
    assertAuthorized(request);
  } catch (error) {
    const status = error instanceof UnauthorizedError ? 401 : 500;
    return json({ error: (error as Error).message }, status);
  }

  const config = dbConfigFromEnv();
  const token = Deno.env.get("EODHD_API_TOKEN");
  if (!token) return json({ error: "EODHD_API_TOKEN manquant" }, 500);

  try {
    const now = new Date();
    const securities = await selectAllRows<SecurityRef>(
      config,
      "securities",
      "select=symbol,eodhd_symbol,currency&eodhd_symbol=not.is.null&order=symbol",
    );

    if (securities.length === 0) {
      return json({ session, symbols: 0, upserted: 0, note: "référentiel vide" });
    }

    // Ce qu'on sait déjà : l'âge de chaque cotation, et les titres détenus.
    const cached = await selectAllRows<{ symbol: string; fetched_at: string }>(
      config, "quotes_cache", "select=symbol,fetched_at&order=symbol");
    const fetchedAt = new Map(cached.map((row) => [row.symbol, new Date(row.fetched_at)]));
    const heldRows = await selectAllRows<{ symbol: string }>(
      config, "positions", "select=symbol&quantity=gt.0&order=symbol");
    const held = new Set(heldRows.map((row) => row.symbol));

    const selected = selectForRefresh(securities, fetchedAt, held, now);
    if (selected.length === 0) {
      await logRun(config, {
        function: "quotes", duration_ms: Date.now() - startedAt,
        symbols: 0, upserted: 0, api_calls: 0, session, error: null,
      });
      return json({ session, symbols: 0, upserted: 0, api_calls: 0, note: "rien à rafraîchir" });
    }

    // Les paires de change des devises concernées voyagent avec les titres.
    const pairs = [...new Set(selected.map((s) => fxPairFor(s.currency)).filter(
      (pair): pair is string => pair !== null))];
    const requested = [...pairs, ...selected.map((s) => s.eodhd_symbol)];
    const batches = chunk(requested, REALTIME_BATCH_SIZE);

    const quotes: RawQuote[] = [];
    for (const batch of batches) {
      const response = await fetch(buildRealTimeURL(batch, token));
      if (!response.ok) {
        throw new Error(`EODHD real-time → ${response.status} ${await response.text()}`);
      }
      quotes.push(...parseRealTime(await response.json()));
    }

    const rates = extractFxRates(quotes);
    const { rows, skipped } = buildQuoteRows(quotes, selected, rates, now);

    const upserted = await upsertRows(config, "quotes_cache", rows, "symbol");
    const fxRows = Object.entries(rates).map(([currency, rate]) => ({
      pair: `EUR${currency}`, rate, fetched_at: now.toISOString(),
    }));
    if (fxRows.length > 0) await upsertRows(config, "fx_rates", fxRows, "pair");

    // Série intraday pour la courbe « 1 jour » du portefeuille. Secondaire :
    // un échec ici ne doit pas faire échouer le rafraîchissement du cache,
    // dont dépend le moteur d'ordres.
    //
    // Un relevé toutes les cinq minutes, pas toutes les minutes : l'app
    // regroupe déjà les points par tranche de cinq minutes (PortfolioHistory
    // .bucket), et depuis l'entrée du S&P 500 le référentiel compte cinq
    // cents titres — écrire chaque minute gonflerait la table de cinq fois
    // ce que la courbe sait afficher.
    let intradayError: string | null = null;
    const minute = new Date();
    minute.setUTCSeconds(0, 0);
    const sampleIntraday = minute.getUTCMinutes() % INTRADAY_SAMPLE_MINUTES === 0;
    try {
      if (sampleIntraday) {
        await upsertRows(
          config,
          "price_intraday",
          rows.map((row) => ({ symbol: row.symbol, ts: minute.toISOString(), price: row.price })),
          "symbol,ts",
        );
      }
      const cutoff = new Date(Date.now() - INTRADAY_RETENTION_DAYS * 86_400_000);
      await deleteRows(config, "price_intraday", `ts=lt.${encodeURIComponent(cutoff.toISOString())}`);
    } catch (error) {
      intradayError = (error as Error).message;
      console.error("quotes intraday:", intradayError);
    }

    const durationMs = Date.now() - startedAt;
    await logRun(config, {
      function: "quotes",
      duration_ms: durationMs,
      symbols: selected.length,
      upserted,
      // Le coût réel : EODHD compte un appel par titre demandé, pas par requête.
      api_calls: requested.length,
      session,
      error: intradayError === null ? null : `intraday: ${intradayError}`,
    });

    // `skipped` non vide signale presque toujours un `eodhd_symbol` erroné dans
    // le seed : on le remonte au lieu de le laisser passer silencieusement.
    return json({
      session,
      symbols: selected.length,
      catalogue: securities.length,
      upserted,
      api_calls: requested.length,
      duration_ms: durationMs,
      fx: rates,
      skipped,
    });
  } catch (error) {
    const message = (error as Error).message;
    await logRun(config, {
      function: "quotes",
      duration_ms: Date.now() - startedAt,
      session,
      error: message,
    });
    console.error("quotes:", message);
    return json({ error: message }, 502);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
