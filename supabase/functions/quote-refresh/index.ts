// =====================================================================
// Edge Function `quote-refresh` — rafraîchit, à la demande de l'app, la
// cotation d'un titre qu'on consulte ou qu'on s'apprête à acheter.
//
// Le cron `quotes` ne peut plus tout rafraîchir chaque minute : le
// référentiel dépasse mille titres, et chaque titre coûte un appel EODHD.
// C'est donc ici que se garantit un cours frais au moment d'un ordre — le
// moteur refuse une cotation de plus de quinze minutes (KR004).
//
// Trois garde-fous sur le quota :
//   - un titre relevé il y a moins d'une minute n'est pas redemandé ;
//   - cinq titres au plus par appel ;
//   - trente titres par minute et par utilisateur.
// Le change vient de `fx_rates` (tenu par le cron) : il ne coûte un appel
// que s'il manque ou date de plus d'une heure.
//
//   supabase functions deploy quote-refresh
//
// Corps : { "symbols": ["MC", "AAPL"] }
// =====================================================================

import {
  buildQuoteRows,
  buildRealTimeURL,
  extractFxRates,
  fxPairFor,
  parseRealTime,
  type SecurityRef,
} from "../_shared/eodhd.ts";
import {
  authenticatedUserId,
  dbConfigFromEnv,
  selectRows,
  UnauthorizedError,
  upsertRows,
} from "../_shared/db.ts";

const MAX_SYMBOLS_PER_CALL = 5;
const MAX_PER_USER_PER_MINUTE = 30;
const FRESH_MS = 60_000;
const FX_MAX_AGE_MS = 60 * 60_000;

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") return json({ error: "POST attendu" }, 405);

  const config = dbConfigFromEnv();
  const token = Deno.env.get("EODHD_API_TOKEN");
  if (!token) return json({ error: "EODHD_API_TOKEN manquant" }, 500);

  let userId: string;
  try {
    userId = await authenticatedUserId(config, request);
  } catch (error) {
    const status = error instanceof UnauthorizedError ? 401 : 500;
    return json({ error: (error as Error).message }, status);
  }

  let symbols: string[];
  try {
    const body = await request.json() as { symbols?: unknown };
    symbols = Array.isArray(body.symbols)
      ? [...new Set(body.symbols.filter((s): s is string => typeof s === "string" && s.length <= 16))]
      : [];
  } catch {
    return json({ error: "Corps JSON invalide" }, 400);
  }
  if (symbols.length === 0 || symbols.length > MAX_SYMBOLS_PER_CALL) {
    return json({ error: `Entre 1 et ${MAX_SYMBOLS_PER_CALL} symboles` }, 400);
  }

  try {
    const now = new Date();
    const inList = symbols.map((s) => `"${s.replaceAll('"', "")}"`).join(",");

    // Déjà frais : rien à dépenser.
    const cached = await selectRows<{ symbol: string; fetched_at: string }>(
      config, "quotes_cache", `select=symbol,fetched_at&symbol=in.(${inList})`);
    const freshAt = new Map(cached.map((row) => [row.symbol, new Date(row.fetched_at).getTime()]));
    const stale = symbols.filter((s) => now.getTime() - (freshAt.get(s) ?? 0) >= FRESH_MS);
    if (stale.length === 0) return json({ refreshed: 0, api_calls: 0 });

    // Plafond par utilisateur, sur la minute glissante.
    const since = new Date(now.getTime() - 60_000).toISOString();
    const recent = await selectRows<{ id: number }>(
      config, "quote_refresh_requests",
      `select=id&user_id=eq.${userId}&created_at=gte.${encodeURIComponent(since)}`);
    if (recent.length + stale.length > MAX_PER_USER_PER_MINUTE) {
      return json({ error: "Trop de demandes, réessaie dans une minute" }, 429);
    }

    const securities = await selectRows<SecurityRef>(
      config, "securities",
      `select=symbol,eodhd_symbol,currency&eodhd_symbol=not.is.null&symbol=in.(${
        stale.map((s) => `"${s.replaceAll('"', "")}"`).join(",")})`);
    if (securities.length === 0) return json({ refreshed: 0, api_calls: 0 });

    // Le change en base, s'il est récent ; sinon il voyage avec les titres.
    const stored = await selectRows<{ pair: string; rate: number; fetched_at: string }>(
      config, "fx_rates", "select=pair,rate,fetched_at");
    const rates: Record<string, number> = {};
    for (const row of stored) {
      if (now.getTime() - new Date(row.fetched_at).getTime() < FX_MAX_AGE_MS) {
        rates[row.pair.replace(/^EUR/, "")] = Number(row.rate);
      }
    }
    const missingPairs = [...new Set(securities.map((s) => fxPairFor(s.currency))
      .filter((pair): pair is string => pair !== null)
      .filter((pair) => !(pair.slice(3, 6) in rates)))];

    const requested = [...missingPairs, ...securities.map((s) => s.eodhd_symbol)];
    const response = await fetch(buildRealTimeURL(requested, token));
    if (!response.ok) {
      throw new Error(`EODHD real-time → ${response.status} ${await response.text()}`);
    }
    const quotes = parseRealTime(await response.json());
    Object.assign(rates, extractFxRates(quotes));

    const { rows } = buildQuoteRows(quotes, securities, rates, now);
    const refreshed = await upsertRows(config, "quotes_cache", rows, "symbol");
    await upsertRows(config, "quote_refresh_requests",
      securities.map((s) => ({ user_id: userId, symbol: s.symbol })), "id");

    return json({ refreshed, api_calls: requested.length });
  } catch (error) {
    const message = (error as Error).message;
    console.error("quote-refresh:", message);
    return json({ error: message }, 502);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
