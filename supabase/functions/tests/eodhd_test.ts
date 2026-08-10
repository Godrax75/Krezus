// =====================================================================
// Tests de contrat de l'adaptateur EODHD (point 2 de la vérification du plan).
//
// Fixtures enregistrées : MC.PA, AIR.PA, MT.AS, NVDA.US — on vérifie le
// parsing des cours en EUR *et* en USD, et la conversion vers la devise de
// compte. Aucun appel réseau : le jour où EODHD change son format, ce sont
// ces tests qui doivent tomber, pas la production.
//
//   deno test --allow-read supabase/functions/tests/
// =====================================================================

import { assert, assertAlmostEquals, assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  buildEODURL,
  buildQuoteRows,
  buildRealTimeURL,
  chunk,
  convertToAccountCurrency,
  extractFxRate,
  parseEOD,
  parseRealTime,
  type SecurityRef,
  toNumber,
} from "../_shared/eodhd.ts";

const BATCH = await loadFixture("real_time_batch.json");
const SINGLE = await loadFixture("real_time_single.json");
const EOD_MC = await loadFixture("eod_mc_pa.json");

async function loadFixture(name: string): Promise<unknown> {
  const path = new URL(`./fixtures/${name}`, import.meta.url);
  return JSON.parse(await Deno.readTextFile(path));
}

/**
 * Extrait du référentiel réel. `AIR` est le cas que le seed documente : Airbus
 * est marqué `NL` côté design mais cote à Paris — le suffixe ne se déduit
 * jamais du pays.
 */
const SECURITIES: SecurityRef[] = [
  { symbol: "MC", eodhd_symbol: "MC.PA", currency: "EUR" },
  { symbol: "AIR", eodhd_symbol: "AIR.PA", currency: "EUR" },
  { symbol: "MT", eodhd_symbol: "MT.AS", currency: "EUR" },
  { symbol: "NVDA", eodhd_symbol: "NVDA.US", currency: "USD" },
];

const NOW = new Date("2026-07-25T09:20:00.000Z");

// ---------------------------------------------------------------------
// Normalisation des valeurs
// ---------------------------------------------------------------------

Deno.test("toNumber neutralise les sentinelles NA d'EODHD", () => {
  assertEquals(toNumber("NA"), null);
  assertEquals(toNumber("na"), null);
  assertEquals(toNumber(""), null);
  assertEquals(toNumber(null), null);
  assertEquals(toNumber(undefined), null);
  assertEquals(toNumber(Number.NaN), null);
  assertEquals(toNumber(Number.POSITIVE_INFINITY), null);
  assertEquals(toNumber({}), null);
});

Deno.test("toNumber accepte les nombres sérialisés en chaîne", () => {
  assertEquals(toNumber(178.45), 178.45);
  assertEquals(toNumber("178.45"), 178.45);
  assertEquals(toNumber(" 178.45 "), 178.45);
  assertEquals(toNumber(0), 0);
  assertEquals(toNumber(-3.2), -3.2);
});

// ---------------------------------------------------------------------
// Construction des URL
// ---------------------------------------------------------------------

Deno.test("buildRealTimeURL groupe tout le lot en un seul appel", () => {
  const url = new URL(buildRealTimeURL(["MC.PA", "AIR.PA", "NVDA.US"], "tok"));
  assertEquals(url.pathname, "/api/real-time/MC.PA");
  assertEquals(url.searchParams.get("s"), "AIR.PA,NVDA.US");
  assertEquals(url.searchParams.get("api_token"), "tok");
  assertEquals(url.searchParams.get("fmt"), "json");
});

Deno.test("buildRealTimeURL omet `s` pour un symbole seul", () => {
  const url = new URL(buildRealTimeURL(["NVDA.US"], "tok"));
  assertEquals(url.pathname, "/api/real-time/NVDA.US");
  assertEquals(url.searchParams.get("s"), null);
});

Deno.test("buildRealTimeURL refuse un lot vide", () => {
  assertThrows(() => buildRealTimeURL([], "tok"), RangeError);
});

Deno.test("buildEODURL demande bien la période quotidienne", () => {
  const url = new URL(buildEODURL("MC.PA", "tok", "2025-07-25"));
  assertEquals(url.pathname, "/api/eod/MC.PA");
  assertEquals(url.searchParams.get("period"), "d");
  assertEquals(url.searchParams.get("from"), "2025-07-25");
});

Deno.test("chunk découpe sans perdre d'élément", () => {
  assertEquals(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assertEquals(chunk([], 10), []);
  assertThrows(() => chunk([1], 0), RangeError);
});

// ---------------------------------------------------------------------
// Parsing temps réel
// ---------------------------------------------------------------------

Deno.test("parseRealTime lit un tableau et écarte les lignes sans cours", () => {
  const quotes = parseRealTime(BATCH);
  // DELISTED.US n'a que des "NA" → écarté.
  assertEquals(quotes.map((q) => q.code), [
    "EURUSD.FOREX",
    "MC.PA",
    "AIR.PA",
    "MT.AS",
    "NVDA.US",
  ]);
});

Deno.test("parseRealTime accepte la réponse objet d'un symbole unique", () => {
  const quotes = parseRealTime(SINGLE);
  assertEquals(quotes.length, 1);
  assertEquals(quotes[0].code, "NVDA.US");
  assertEquals(quotes[0].close, 178.45);
});

Deno.test("parseRealTime ne casse pas sur une charge utile inattendue", () => {
  assertEquals(parseRealTime(null), []);
  assertEquals(parseRealTime("erreur"), []);
  assertEquals(parseRealTime([null, 42, {}]), []);
});

Deno.test("extractFxRate isole la paire EURUSD", () => {
  assertEquals(extractFxRate(parseRealTime(BATCH)), 1.0842);
  assertEquals(extractFxRate(parseRealTime(SINGLE)), null);
});

// ---------------------------------------------------------------------
// Conversion de devise
// ---------------------------------------------------------------------

Deno.test("convertToAccountCurrency laisse l'euro intact", () => {
  assertEquals(convertToAccountCurrency(517.6, "EUR", 1.0842), { price: 517.6, fxRate: 1 });
  // Sans taux disponible, un titre en euros reste convertible.
  assertEquals(convertToAccountCurrency(517.6, "eur", null), { price: 517.6, fxRate: 1 });
});

Deno.test("convertToAccountCurrency divise le dollar par EURUSD", () => {
  const result = convertToAccountCurrency(178.45, "USD", 1.0842);
  assert(result !== null);
  assertAlmostEquals(result.price, 178.45 / 1.0842, 1e-9);
  assertEquals(result.fxRate, 1.0842);
});

Deno.test("convertToAccountCurrency refuse plutôt que d'inventer un prix", () => {
  // Un dollar sans taux → null. Écrire le cours brut ferait exécuter un ordre
  // à ~8 % du mauvais prix, silencieusement.
  assertEquals(convertToAccountCurrency(178.45, "USD", null), null);
  assertEquals(convertToAccountCurrency(178.45, "USD", 0), null);
  assertEquals(convertToAccountCurrency(100, "GBP", 1.0842), null);
});

// ---------------------------------------------------------------------
// Assemblage des lignes de cache — le contrat qui compte
// ---------------------------------------------------------------------

Deno.test("buildQuoteRows mappe les symboles de cotation vers les symboles internes", () => {
  const { rows, skipped } = buildQuoteRows(parseRealTime(BATCH), SECURITIES, 1.0842, NOW);

  assertEquals(rows.map((r) => r.symbol).sort(), ["AIR", "MC", "MT", "NVDA"]);
  // La paire de change n'est pas un titre : elle ne doit pas atterrir en cache.
  assert(!rows.some((r) => r.symbol.includes("EURUSD")));
  assertEquals(skipped, []);
});

Deno.test("buildQuoteRows garde le cours natif pour un titre en euros", () => {
  const { rows } = buildQuoteRows(parseRealTime(BATCH), SECURITIES, 1.0842, NOW);
  const mc = rows.find((r) => r.symbol === "MC")!;

  assertEquals(mc.price, 517.6);
  assertEquals(mc.price_native, 517.6);
  assertEquals(mc.currency, "EUR");
  assertEquals(mc.fx_rate, 1);
  assertEquals(mc.change_pct, 1.2322);
  assertEquals(mc.open, 512.4);
  assertEquals(mc.previous_close, 511.3);
});

Deno.test("buildQuoteRows convertit un titre en dollars vers l'euro", () => {
  const { rows } = buildQuoteRows(parseRealTime(BATCH), SECURITIES, 1.0842, NOW);
  const nvda = rows.find((r) => r.symbol === "NVDA")!;

  assertEquals(nvda.price_native, 178.45);
  assertEquals(nvda.currency, "USD");
  assertEquals(nvda.fx_rate, 1.0842);
  assertAlmostEquals(nvda.price, 178.45 / 1.0842, 1e-5);

  // Le cours converti doit être nettement sous le cours natif : c'est
  // précisément l'écart qui fausserait le calcul des parts s'il manquait.
  assert(nvda.price < nvda.price_native);

  // open et previousClose subissent la même conversion, sinon la variation
  // affichée mélangerait deux devises.
  assertAlmostEquals(nvda.open!, 176.2 / 1.0842, 1e-5);
  assertAlmostEquals(nvda.previous_close!, 175.6 / 1.0842, 1e-5);
});

Deno.test("buildQuoteRows recalcule la variation quand EODHD renvoie NA", () => {
  const { rows } = buildQuoteRows(parseRealTime(BATCH), SECURITIES, 1.0842, NOW);
  const mt = rows.find((r) => r.symbol === "MT")!;

  // change_p = "NA" dans la fixture → recalculé sur previousClose.
  const expected = ((27.82 - 27.5) / 27.5) * 100;
  assertAlmostEquals(mt.change_pct!, Number(expected.toFixed(4)), 1e-9);
});

Deno.test("buildQuoteRows respecte la contrainte CHECK de cohérence FX", () => {
  const { rows } = buildQuoteRows(parseRealTime(BATCH), SECURITIES, 1.0842, NOW);

  // La base rejette une ligne où |price - price_native / fx_rate| dépasse
  // max(price * 0.005, 0.01). L'arrondi de l'adaptateur doit tenir dedans.
  for (const row of rows) {
    const drift = Math.abs(row.price - row.price_native / row.fx_rate);
    assert(
      drift <= Math.max(row.price * 0.005, 0.01),
      `${row.symbol}: dérive ${drift} hors tolérance`,
    );
  }
});

Deno.test("buildQuoteRows horodate la cotation et l'écriture séparément", () => {
  const { rows } = buildQuoteRows(parseRealTime(BATCH), SECURITIES, 1.0842, NOW);
  const mc = rows.find((r) => r.symbol === "MC")!;

  assertEquals(mc.quoted_at, new Date(1753430400 * 1000).toISOString());
  assertEquals(mc.fetched_at, NOW.toISOString());
});

Deno.test("buildQuoteRows signale les symboles absents du référentiel", () => {
  const partial = SECURITIES.filter((s) => s.symbol !== "MT");
  const { rows, skipped } = buildQuoteRows(parseRealTime(BATCH), partial, 1.0842, NOW);

  assertEquals(skipped, ["MT.AS"]);
  assert(!rows.some((r) => r.symbol === "MT"));
});

Deno.test("buildQuoteRows écarte les titres USD si le taux manque", () => {
  const { rows, skipped } = buildQuoteRows(parseRealTime(BATCH), SECURITIES, null, NOW);

  // Les titres en euros passent, le titre en dollars est écarté plutôt
  // qu'écrit à un prix faux.
  assertEquals(rows.map((r) => r.symbol).sort(), ["AIR", "MC", "MT"]);
  assertEquals(skipped, ["NVDA.US"]);
});

// ---------------------------------------------------------------------
// Parsing de l'historique
// ---------------------------------------------------------------------

Deno.test("parseEOD préfère adjusted_close et filtre les lignes inexploitables", () => {
  const points = parseEOD("MC", EOD_MC);

  assertEquals(points, [
    { symbol: "MC", date: "2026-07-20", close: 508.9 },
    // adjusted_close (511.05) l'emporte sur close (513.2) : splits/dividendes.
    { symbol: "MC", date: "2026-07-21", close: 511.05 },
    // adjusted_close "NA" → repli sur close.
    { symbol: "MC", date: "2026-07-22", close: 511.3 },
  ]);
});

Deno.test("parseEOD ne casse pas sur une charge utile inattendue", () => {
  assertEquals(parseEOD("MC", null), []);
  assertEquals(parseEOD("MC", { error: "not found" }), []);
});
