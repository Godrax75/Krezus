// =====================================================================
// Budget de rafraîchissement : quels titres interroger à cette minute.
// Un titre de trop, mille fois par jour, et le quota EODHD tombe.
// =====================================================================

import { assertEquals } from "jsr:@std/assert@1";
import { selectForRefresh } from "../_shared/quote_budget.ts";
import { exchangeOf, isExchangeOpen } from "../_shared/market_hours.ts";
import { convertToAccountCurrency, extractFxRates, fxPairFor } from "../_shared/eodhd.ts";
import type { SecurityRef } from "../_shared/eodhd.ts";

const sec = (symbol: string, eodhd: string, currency = "EUR"): SecurityRef =>
  ({ symbol, eodhd_symbol: eodhd, currency });

// Mardi 15 septembre 2026, 11:00 à Paris (09:00 UTC) : Paris ouvert,
// New York fermé (05:00), Tokyo fermé depuis 15:30 (18:00 à Tokyo).
const PARIS_MORNING = new Date("2026-09-15T09:00:00Z");

Deno.test("exchangeOf lit la place dans le suffixe EODHD", () => {
  assertEquals(exchangeOf("MC.PA"), "PA");
  assertEquals(exchangeOf("AAPL.US"), "US");
  assertEquals(exchangeOf("7203.TSE"), "TSE");
});

Deno.test("chaque place a ses horaires", () => {
  assertEquals(isExchangeOpen("PA", PARIS_MORNING), true);
  assertEquals(isExchangeOpen("US", PARIS_MORNING), false);
  assertEquals(isExchangeOpen("LSE", PARIS_MORNING), true);   // 10:00 à Londres
  assertEquals(isExchangeOpen("TSE", PARIS_MORNING), false);  // 18:00 à Tokyo
  assertEquals(isExchangeOpen("TSE", new Date("2026-09-15T01:00:00Z")), true); // 10:00
});

Deno.test("les titres détenus passent d'abord, puis les plus anciens", () => {
  const securities = [sec("MC", "MC.PA"), sec("AI", "AI.PA"), sec("OR", "OR.PA")];
  const fetched = new Map([
    ["MC", new Date("2026-09-15T08:58:00Z")],
    ["AI", new Date("2026-09-15T08:40:00Z")],
    ["OR", new Date("2026-09-15T08:50:00Z")],
  ]);
  const picked = selectForRefresh(securities, fetched, new Set(["MC"]), PARIS_MORNING, 2);
  assertEquals(picked.map((s) => s.symbol), ["MC", "AI"]);
});

Deno.test("un titre détenu tout juste relevé attend la minute suivante", () => {
  const securities = [sec("MC", "MC.PA")];
  const fetched = new Map([["MC", new Date("2026-09-15T08:59:30Z")]]);
  assertEquals(selectForRefresh(securities, fetched, new Set(["MC"]), PARIS_MORNING).length, 0);
});

Deno.test("une place fermée n'est relevée qu'une fois après la clôture", () => {
  // Apple, relevé pendant la séance de la veille (19:00 UTC = 15:00 à New York).
  const during = new Map([["AAPL", new Date("2026-09-14T19:00:00Z")]]);
  const apple = [sec("AAPL", "AAPL.US", "USD")];
  assertEquals(selectForRefresh(apple, during, new Set(), PARIS_MORNING).length, 1);

  // Relevé une heure après la clôture : plus rien à faire jusqu'à l'ouverture.
  const after = new Map([["AAPL", new Date("2026-09-14T21:00:00Z")]]);
  assertEquals(selectForRefresh(apple, after, new Set(), PARIS_MORNING).length, 0);
});

Deno.test("juste après la clôture, on laisse passer le retard de cotation", () => {
  // Paris a fermé à 17:30 (15:30 UTC) ; il est 15:45 UTC.
  const justClosed = new Date("2026-09-15T15:45:00Z");
  const fetched = new Map([["MC", new Date("2026-09-15T15:20:00Z")]]);
  assertEquals(selectForRefresh([sec("MC", "MC.PA")], fetched, new Set(), justClosed).length, 0);
  // Trente minutes plus tard, le dernier relevé est dû.
  const settled = new Date("2026-09-15T16:05:00Z");
  assertEquals(selectForRefresh([sec("MC", "MC.PA")], fetched, new Set(), settled).length, 1);
});

Deno.test("le budget borne le nombre de titres par minute", () => {
  const many = Array.from({ length: 200 }, (_, i) => sec(`S${i}`, `S${i}.PA`));
  assertEquals(selectForRefresh(many, new Map(), new Set(), PARIS_MORNING, 45).length, 45);
});

Deno.test("les pence de Londres sont convertis via la livre", () => {
  assertEquals(fxPairFor("GBX"), "EURGBP.FOREX");
  assertEquals(fxPairFor("EUR"), null);
  assertEquals(fxPairFor("jpy"), "EURJPY.FOREX");
  // 1 € = 0,85 £ ; 8 500 pence = 85 £ = 100 €.
  const converted = convertToAccountCurrency(8500, "GBX", { GBP: 0.85 });
  assertEquals(Math.round(converted!.price * 1e6) / 1e6, 100);
  assertEquals(convertToAccountCurrency(100, "CHF", {}), null);
});

Deno.test("extractFxRates lit toutes les paires présentes", () => {
  const rates = extractFxRates([
    { code: "EURUSD.FOREX", close: 1.1, open: null, previousClose: null, changePct: null, timestamp: null },
    { code: "EURGBP.FOREX", close: 0.85, open: null, previousClose: null, changePct: null, timestamp: null },
    { code: "MC.PA", close: 600, open: null, previousClose: null, changePct: null, timestamp: null },
  ]);
  assertEquals(rates, { USD: 1.1, GBP: 0.85 });
});
