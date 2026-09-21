// =====================================================================
// Edge Function `quotes` — rafraîchit `quotes_cache` depuis EODHD.
//
// Déclenchée par cron : toutes les 60 s en séance, toutes les 10 min hors
// séance (voir refreshIntervalSeconds). L'app ne lit que le cache.
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
  extractFxRate,
  FX_PAIR,
  parseRealTime,
  REALTIME_BATCH_SIZE,
  type RawQuote,
  type SecurityRef,
} from "../_shared/eodhd.ts";
import { currentSession } from "../_shared/market_hours.ts";
import {
  assertAuthorized,
  dbConfigFromEnv,
  deleteRows,
  logRun,
  selectRows,
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
    const securities = await selectRows<SecurityRef>(
      config,
      "securities",
      "select=symbol,eodhd_symbol,currency&eodhd_symbol=not.is.null",
    );

    if (securities.length === 0) {
      return json({ session, symbols: 0, upserted: 0, note: "référentiel vide" });
    }

    // La paire de change voyage avec le premier lot : sans elle, aucun titre
    // en dollars ne peut être converti, et ils seraient tous écartés.
    const batches = chunk(securities.map((s) => s.eodhd_symbol), REALTIME_BATCH_SIZE);
    batches[0] = [FX_PAIR, ...batches[0]];

    const quotes: RawQuote[] = [];
    for (const batch of batches) {
      const response = await fetch(buildRealTimeURL(batch, token));
      if (!response.ok) {
        throw new Error(`EODHD real-time → ${response.status} ${await response.text()}`);
      }
      quotes.push(...parseRealTime(await response.json()));
    }

    const eurUsd = extractFxRate(quotes);
    const { rows, skipped } = buildQuoteRows(quotes, securities, eurUsd, new Date());

    const upserted = await upsertRows(config, "quotes_cache", rows, "symbol");
    if (eurUsd !== null) {
      await upsertRows(
        config,
        "fx_rates",
        [{ pair: "EURUSD", rate: eurUsd, fetched_at: new Date().toISOString() }],
        "pair",
      );
    }

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
      symbols: securities.length,
      upserted,
      api_calls: batches.length,
      session,
      error: intradayError === null ? null : `intraday: ${intradayError}`,
    });

    // `skipped` non vide signale presque toujours un `eodhd_symbol` erroné dans
    // le seed : on le remonte au lieu de le laisser passer silencieusement.
    return json({
      session,
      symbols: securities.length,
      upserted,
      api_calls: batches.length,
      duration_ms: durationMs,
      eur_usd: eurUsd,
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
