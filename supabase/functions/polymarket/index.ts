// =====================================================================
// Edge Function `polymarket` — rafraîchit `polymarket_cache`.
//
// Cadence : toutes les 15 min. L'API Gamma est publique et sans clé, mais on
// passe quand même par le serveur — l'app ne doit pas dépendre d'un tiers à
// l'affichage, et le cache borne la charge à un appel toutes les 15 min quel
// que soit le nombre d'utilisateurs.
//
//   supabase functions deploy polymarket --no-verify-jwt
// =====================================================================

import { buildMarketsURL, parseMarkets } from "../_shared/polymarket.ts";
import {
  assertAuthorized,
  dbConfigFromEnv,
  logRun,
  UnauthorizedError,
  upsertRows,
} from "../_shared/db.ts";

/** Marchés conservés en cache — au-delà, le bloc devient illisible dans l'app. */
const MAX_ROWS = 12;

Deno.serve(async (request: Request): Promise<Response> => {
  const startedAt = Date.now();

  try {
    assertAuthorized(request);
  } catch (error) {
    const status = error instanceof UnauthorizedError ? 401 : 500;
    return json({ error: (error as Error).message }, status);
  }

  const config = dbConfigFromEnv();

  try {
    const response = await fetch(buildMarketsURL());
    if (!response.ok) {
      throw new Error(`Gamma → ${response.status} ${await response.text()}`);
    }

    const all = parseMarkets(await response.json(), new Date());
    // Tri par volume : un marché très échangé porte une probabilité plus
    // significative qu'un marché confidentiel.
    const rows = all
      .sort((a, b) => (b.volume ?? 0) - (a.volume ?? 0))
      .slice(0, MAX_ROWS);

    const upserted = await upsertRows(config, "polymarket_cache", rows, "id");

    const durationMs = Date.now() - startedAt;
    await logRun(config, {
      function: "polymarket",
      duration_ms: durationMs,
      symbols: all.length,
      upserted,
      api_calls: 1,
    });

    return json({
      matched: all.length,
      upserted,
      dropped: Math.max(0, all.length - rows.length),
      duration_ms: durationMs,
    });
  } catch (error) {
    const message = (error as Error).message;
    await logRun(config, {
      function: "polymarket",
      duration_ms: Date.now() - startedAt,
      error: message,
    });
    console.error("polymarket:", message);
    return json({ error: message }, 502);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
