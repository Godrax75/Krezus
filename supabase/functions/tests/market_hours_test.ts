// =====================================================================
// Heures de marché — la bascule heure d'hiver / heure d'été est le seul
// endroit où un décalage codé en dur casserait le rafraîchissement.
// =====================================================================

import { assertEquals } from "jsr:@std/assert@1";
import {
  currentSession,
  isEuronextOpen,
  isUSMarketOpen,
  refreshIntervalSeconds,
  zonedTime,
} from "../_shared/market_hours.ts";

Deno.test("zonedTime résout l'heure locale, pas l'heure UTC", () => {
  // 25 juillet 2026, 09:20 UTC → 11:20 à Paris (CEST, UTC+2), un samedi.
  const summer = zonedTime(new Date("2026-07-25T09:20:00Z"), "Europe/Paris");
  assertEquals(summer.weekday, 6);
  assertEquals(summer.minutes, 11 * 60 + 20);

  // 15 janvier 2026, 09:20 UTC → 10:20 à Paris (CET, UTC+1), un jeudi.
  const winter = zonedTime(new Date("2026-01-15T09:20:00Z"), "Europe/Paris");
  assertEquals(winter.weekday, 4);
  assertEquals(winter.minutes, 10 * 60 + 20);
});

Deno.test("Euronext ouvre 09:00–17:30 heure de Paris", () => {
  // Jeudi 15 janvier 2026 (heure d'hiver, Paris = UTC+1).
  assertEquals(isEuronextOpen(new Date("2026-01-15T07:59:00Z")), false); // 08:59
  assertEquals(isEuronextOpen(new Date("2026-01-15T08:00:00Z")), true);  // 09:00
  assertEquals(isEuronextOpen(new Date("2026-01-15T16:29:00Z")), true);  // 17:29
  assertEquals(isEuronextOpen(new Date("2026-01-15T16:30:00Z")), false); // 17:30
});

Deno.test("Euronext reste fermé le week-end", () => {
  assertEquals(isEuronextOpen(new Date("2026-07-25T10:00:00Z")), false); // samedi
  assertEquals(isEuronextOpen(new Date("2026-07-26T10:00:00Z")), false); // dimanche
});

Deno.test("les bourses US ouvrent 09:30–16:00 heure de New York", () => {
  // Jeudi 15 janvier 2026 (EST, New York = UTC−5).
  assertEquals(isUSMarketOpen(new Date("2026-01-15T14:29:00Z")), false); // 09:29
  assertEquals(isUSMarketOpen(new Date("2026-01-15T14:30:00Z")), true);  // 09:30
  assertEquals(isUSMarketOpen(new Date("2026-01-15T20:59:00Z")), true);  // 15:59
  assertEquals(isUSMarketOpen(new Date("2026-01-15T21:00:00Z")), false); // 16:00
});

Deno.test("la fenêtre de décalage de mars est traitée correctement", () => {
  // Les États-Unis passent à l'heure d'été le 8 mars 2026, l'Europe le 29.
  // Entre les deux, l'écart Paris/New York est de 5 h et non 6 h : un décalage
  // codé en dur ferait croire les bourses US fermées pendant trois semaines.
  const date = new Date("2026-03-16T13:35:00Z"); // lundi
  assertEquals(zonedTime(date, "America/New_York").minutes, 9 * 60 + 35);  // EDT, UTC−4
  assertEquals(zonedTime(date, "Europe/Paris").minutes, 14 * 60 + 35);     // CET, UTC+1
  // Séance US ouverte. Avec un décalage figé à 6 h, on calculerait 08:35 à
  // New York et la fonction conclurait à tort que le marché est fermé.
  assertEquals(isUSMarketOpen(date), true);
});

Deno.test("currentSession distingue les recouvrements", () => {
  // Jeudi 15 janvier 2026, 15:00 UTC → Paris 16:00 (ouvert), New York 10:00 (ouvert).
  assertEquals(currentSession(new Date("2026-01-15T15:00:00Z")), "both");
  // 09:00 UTC → Paris 10:00 (ouvert), New York 04:00 (fermé).
  assertEquals(currentSession(new Date("2026-01-15T09:00:00Z")), "euronext");
  // 20:00 UTC → Paris 21:00 (fermé), New York 15:00 (ouvert).
  assertEquals(currentSession(new Date("2026-01-15T20:00:00Z")), "us");
  // Samedi.
  assertEquals(currentSession(new Date("2026-07-25T15:00:00Z")), "closed");
});

Deno.test("le cache continue d'être rafraîchi hors séance", () => {
  // Le moteur rejette une cotation de plus de 15 min (KR004). Un intervalle
  // hors séance supérieur à ce seuil rendrait tout ordre du soir impossible.
  assertEquals(refreshIntervalSeconds("both"), 60);
  assertEquals(refreshIntervalSeconds("closed"), 600);
  assertEquals(refreshIntervalSeconds("closed") < 15 * 60, true);
});
