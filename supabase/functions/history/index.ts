// =====================================================================
// Edge Function `history` — alimente `price_history` (courbes 1M / 1A / Tout).
//
// Déclenchée une fois par jour après clôture. Contrairement au temps réel,
// l'endpoint EOD ne prend qu'un symbole par appel : 82 titres = 82 appels,
// négligeable sur un quota de 100 000/jour mais à garder sous la limite de
// 1 000/min — d'où la concurrence bornée.
//
//   supabase functions deploy history --no-verify-jwt
//
// Paramètres (query string) :
//   days=400     profondeur d'historique (défaut 400 ≈ 1 an de séances + marge,
//                jusqu'à 20 000 ≈ 55 ans pour rejouer les crises passées)
//   symbols=MC,AI  restreint à quelques titres (rattrapage ciblé)
//   part=0/4     ne traite qu'une part du catalogue (un titre sur quatre) :
//                le cron quotidien en lance quatre, à quelques minutes
//                d'intervalle
// =====================================================================

import {
  buildEODURL,
  fxPairFor,
  parseEOD,
  type HistoryPoint,
  type SecurityRef,
} from "../_shared/eodhd.ts";
import {
  assertAuthorized,
  dbConfigFromEnv,
  logRun,
  selectAllRows,
  UnauthorizedError,
  upsertRows,
} from "../_shared/db.ts";

/** Appels EODHD simultanés. 4 tient largement sous les 1 000/min du plan. */
const CONCURRENCY = 4;

Deno.serve(async (request: Request): Promise<Response> => {
  const startedAt = Date.now();

  try {
    assertAuthorized(request);
  } catch (error) {
    const status = error instanceof UnauthorizedError ? 401 : 500;
    return json({ error: (error as Error).message }, status);
  }

  const config = dbConfigFromEnv();
  const token = Deno.env.get("EODHD_API_TOKEN");
  if (!token) return json({ error: "EODHD_API_TOKEN manquant" }, 500);

  const params = new URL(request.url).searchParams;
  const days = clamp(Number(params.get("days") ?? 400), 1, 20000);
  const only = (params.get("symbols") ?? "")
    .split(",").map((s) => s.trim()).filter((s) => s.length > 0);
  const part = parsePart(params.get("part"));

  try {
    const catalogue = await selectAllRows<SecurityRef>(
      config,
      "securities",
      "select=symbol,eodhd_symbol,currency&eodhd_symbol=not.is.null&order=symbol",
    );
    let securities = catalogue;
    if (only.length > 0) {
      const wanted = new Set(only.map((s) => s.toUpperCase()));
      securities = securities.filter((s) => wanted.has(s.symbol.toUpperCase()));
    } else if (part !== null) {
      // Une part du catalogue, pour tenir dans le temps d'exécution d'une
      // fonction et sous la limite de 1 000 appels par minute d'EODHD.
      securities = securities.filter((_, index) => index % part.count === part.index);
    }

    const from = isoDate(new Date(Date.now() - days * 86_400_000));
    const failures: string[] = [];
    let upserted = 0;
    let apiCalls = 0;

    for (const group of chunkArray(securities, CONCURRENCY)) {
      const results = await Promise.all(group.map(async (security) => {
        apiCalls++;
        try {
          const response = await fetch(buildEODURL(security.eodhd_symbol, token, from));
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          return parseEOD(security.symbol, await response.json());
        } catch (error) {
          failures.push(`${security.symbol}: ${(error as Error).message}`);
          return [] as HistoryPoint[];
        }
      }));

      // Un upsert par groupe plutôt qu'un seul à la fin : la charge utile
      // complète (82 titres × 400 points) dépasserait la limite de corps de
      // requête de PostgREST.
      const points = results.flat();
      upserted += await upsertRows(config, "price_history", points, "symbol,date");
    }

    // Clôtures de change, pour convertir chaque titre au taux de sa propre
    // date dans la courbe du portefeuille : une paire par devise du
    // catalogue, un appel chacune. Une seule part s'en charge.
    if (part === null || part.index === 0) {
      const pairs = [...new Set(catalogue.map((s) => fxPairFor(s.currency))
        .filter((pair): pair is string => pair !== null))];
      for (const pair of pairs) {
        apiCalls++;
        const name = pair.replace(".FOREX", "");
        try {
          const response = await fetch(buildEODURL(pair, token, from));
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          const fx = parseEOD(name, await response.json())
            .map((point) => ({ pair: name, date: point.date, rate: point.close }));
          upserted += await upsertRows(config, "fx_history", fx, "pair,date");
        } catch (error) {
          failures.push(`${name}: ${(error as Error).message}`);
        }
      }
    }

    const durationMs = Date.now() - startedAt;
    await logRun(config, {
      function: "history",
      duration_ms: durationMs,
      symbols: securities.length,
      upserted,
      api_calls: apiCalls,
      error: failures.length > 0 ? failures.join(" | ") : null,
    });

    return json({
      symbols: securities.length,
      upserted,
      api_calls: apiCalls,
      duration_ms: durationMs,
      from,
      failures,
    });
  } catch (error) {
    const message = (error as Error).message;
    await logRun(config, {
      function: "history",
      duration_ms: Date.now() - startedAt,
      error: message,
    });
    console.error("history:", message);
    return json({ error: message }, 502);
  }
});

function chunkArray<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.min(Math.max(value, min), max);
}

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** « 1/4 » -> { index: 1, count: 4 }. */
function parsePart(raw: string | null): { index: number; count: number } | null {
  const match = /^(\d+)\/(\d+)$/.exec(raw ?? "");
  if (!match) return null;
  const index = Number(match[1]);
  const count = Number(match[2]);
  return count > 0 && index < count ? { index, count } : null;
}
