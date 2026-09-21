// =====================================================================
// Quels titres rafraîchir à cette minute ?
//
// Chaque titre demandé à l'API temps réel d'EODHD compte pour un appel,
// et le quota est de 100 000 par jour. Rafraîchir mille titres chaque
// minute l'épuisait avant midi : le cache se figeait, et plus aucun ordre
// ne passait (KR004). D'où un budget par minute, dépensé dans cet ordre :
//
//   1. les titres détenus dont la place est ouverte, chaque minute ;
//   2. les autres titres des places ouvertes, les plus anciens d'abord —
//      le catalogue tourne ainsi en continu ;
//   3. les titres d'une place fermée dont le dernier relevé date de la
//      séance : un relevé de plus, après la clôture, fixe le cours de
//      clôture. Ensuite, plus rien jusqu'à la séance suivante.
//
// Un titre ouvert dans l'app, ou sur le point d'être acheté, est rafraîchi
// à la demande par la fonction `quote-refresh` : c'est elle qui garantit un
// cours frais au moment d'un ordre, pas cette rotation.
//
// Fonction pure : testée dans tests/quote_budget_test.ts.
// =====================================================================

import { exchangeOf, isExchangeOpen } from "./market_hours.ts";
import type { SecurityRef } from "./eodhd.ts";

/** Titres rafraîchis par minute, au plus. ~50 000 appels par jour ouvré. */
export const QUOTE_BUDGET_PER_RUN = 45;

/** Un titre détenu est rafraîchi chaque minute tant que sa place est ouverte. */
const HELD_MAX_AGE_MS = 60_000;

/**
 * Les cours hors États-Unis arrivent avec quinze à vingt minutes de retard :
 * un relevé fait moins de trente minutes après la clôture peut encore dater
 * de la séance. Il en faut un dernier après ce délai.
 */
const CLOSE_SETTLE_MS = 30 * 60_000;

export function selectForRefresh(
  securities: readonly SecurityRef[],
  fetchedAt: ReadonlyMap<string, Date>,
  held: ReadonlySet<string>,
  now: Date,
  budget = QUOTE_BUDGET_PER_RUN,
): SecurityRef[] {
  const heldOpen: SecurityRef[] = [];
  const open: SecurityRef[] = [];
  const settling: SecurityRef[] = [];

  for (const security of securities) {
    const exchange = exchangeOf(security.eodhd_symbol);
    const last = fetchedAt.get(security.symbol);
    const age = last ? now.getTime() - last.getTime() : Infinity;

    if (isExchangeOpen(exchange, now)) {
      if (held.has(security.symbol)) {
        if (age >= HELD_MAX_AGE_MS) heldOpen.push(security);
      } else {
        open.push(security);
      }
      continue;
    }

    // Place fermée depuis moins de trente minutes : le dernier cours publié
    // peut encore dater de la séance. On attend.
    if (isExchangeOpen(exchange, new Date(now.getTime() - CLOSE_SETTLE_MS))) continue;

    // Place fermée : un relevé de plus si le dernier a pu saisir la séance.
    if (!last) {
      settling.push(security);
      continue;
    }
    const settledAt = new Date(last.getTime() - CLOSE_SETTLE_MS);
    if (isExchangeOpen(exchange, last) || isExchangeOpen(exchange, settledAt)) {
      settling.push(security);
    }
  }

  const oldestFirst = (a: SecurityRef, b: SecurityRef) =>
    (fetchedAt.get(a.symbol)?.getTime() ?? 0) - (fetchedAt.get(b.symbol)?.getTime() ?? 0);
  heldOpen.sort(oldestFirst);
  open.sort(oldestFirst);
  settling.sort(oldestFirst);

  return [...heldOpen, ...open, ...settling].slice(0, budget);
}
