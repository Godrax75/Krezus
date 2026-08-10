// =====================================================================
// Tests de contrat de l'adaptateur Polymarket.
//
// L'enjeu principal n'est pas le parsing mais le FILTRAGE : un marché dont la
// probabilité est illisible ne doit jamais atterrir en cache à 0 %, ce qui
// s'afficherait comme une prédiction ferme dans l'app.
// =====================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  buildMarketsURL,
  isRelevant,
  parseMarkets,
  parseProbability,
} from "../_shared/polymarket.ts";

const MARKETS = JSON.parse(
  await Deno.readTextFile(new URL("./fixtures/polymarket_markets.json", import.meta.url)),
);

const NOW = new Date("2026-07-25T18:00:00.000Z");

Deno.test("buildMarketsURL ne demande que les marchés ouverts", () => {
  const url = new URL(buildMarketsURL(50));
  assertEquals(url.pathname, "/markets");
  assertEquals(url.searchParams.get("active"), "true");
  assertEquals(url.searchParams.get("closed"), "false");
  assertEquals(url.searchParams.get("limit"), "50");
  assertEquals(url.searchParams.get("order"), "volume");
});

Deno.test("parseProbability accepte les deux sérialisations de Gamma", () => {
  assertEquals(parseProbability('["0.72", "0.28"]'), 0.72);
  assertEquals(parseProbability(["0.41", "0.59"]), 0.41);
  assertEquals(parseProbability([0.5, 0.5]), 0.5);
});

Deno.test("parseProbability rejette tout ce qui n'est pas une probabilité", () => {
  assertEquals(parseProbability("malformed"), null);
  assertEquals(parseProbability("[]"), null);
  assertEquals(parseProbability(null), null);
  // Hors bornes : une « probabilité » de 140 % signale une réponse cassée.
  assertEquals(parseProbability('["1.4", "-0.4"]'), null);
  assertEquals(parseProbability('["-0.1", "1.1"]'), null);
});

Deno.test("isRelevant garde la macro et les marchés actions", () => {
  assert(isRelevant("Will the Fed cut interest rates in September?"));
  assert(isRelevant("Will US inflation be above 3%?"));
  assert(isRelevant("Will the S&P 500 close above 7000?"));
  assert(isRelevant("Will the ECB hold rates?"));
});

Deno.test("isRelevant écarte le sport et la politique", () => {
  assertEquals(isRelevant("Who will win the 2026 World Cup?"), false);
  assertEquals(isRelevant("Who will be elected mayor of Paris?"), false);
});

Deno.test("parseMarkets ne conserve que les marchés exploitables", () => {
  const rows = parseMarkets(MARKETS, NOW);

  // Retenus : Fed, inflation, S&P 500, BCE.
  // Écartés : Coupe du monde (hors sujet), pétrole (prix illisible),
  // récession (probabilité hors bornes), id vide.
  assertEquals(rows.map((r) => r.id), ["512847", "512848", "512849", "512851"]);
});

Deno.test("parseMarkets normalise les champs numériques", () => {
  const rows = parseMarkets(MARKETS, NOW);
  const fed = rows.find((r) => r.id === "512847")!;

  assertEquals(fed.probability, 0.72);
  assertEquals(fed.volume, 4821993.21);
  assertEquals(fed.category, "Economics");
  assertEquals(fed.ends_at, "2026-09-18T00:00:00Z");
  assertEquals(fed.fetched_at, NOW.toISOString());
});

Deno.test("parseMarkets accepte un id numérique", () => {
  const rows = parseMarkets(MARKETS, NOW);
  // Gamma renvoie parfois l'id en nombre : il doit devenir la clé texte du cache.
  assert(rows.some((r) => r.id === "512848"));
});

Deno.test("parseMarkets respecte la contrainte CHECK du cache", () => {
  for (const row of parseMarkets(MARKETS, NOW)) {
    assert(row.probability >= 0 && row.probability <= 1, `${row.id} hors bornes`);
  }
});

Deno.test("parseMarkets ne casse pas sur une charge utile inattendue", () => {
  assertEquals(parseMarkets(null, NOW), []);
  assertEquals(parseMarkets({ error: "rate limited" }, NOW), []);
  assertEquals(parseMarkets([null, 42, {}], NOW), []);
});
