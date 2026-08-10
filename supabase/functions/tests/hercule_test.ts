// =====================================================================
// Tests d'Hercule — prompt, contexte, lecture de réponse.
//
// Deux choses comptent ici et ne se voient pas à l'exécution :
//   1. le prompt système interdit explicitement la recommandation sur titre
//      nommé — c'est ce qui permet à Krezus d'exister sans agrément CIF ;
//   2. le contexte envoyé au modèle ne contient aucun montant.
// Un test qui tombe sur ces deux points vaut mieux qu'une relecture.
// =====================================================================

import { assert, assertEquals, assertStringIncludes, assertThrows } from "jsr:@std/assert@1";
import {
  buildContextText,
  buildMessages,
  buildSystemBlocks,
  extractAnswer,
  HERCULE_MODEL,
  type HerculeContext,
  HISTORY_TURNS,
  RefusalError,
  SYSTEM_PROMPT,
} from "../_shared/hercule.ts";

const CONTEXT: HerculeContext = {
  username: "louis",
  xp: 120,
  rank_level: 1,
  streak_days: 5,
  is_premium: false,
  investor_archetype: "L'Explorateur",
  lessons_done: 3,
  lessons_total: 27,
  holdings: [
    { symbol: "NVDA", name: "Nvidia", sector: "Semi-conducteurs" },
    { symbol: "AI", name: "Air Liquide", sector: "Gaz industriels" },
  ],
};

// ---------------------------------------------------------------------
// Contrainte réglementaire
// ---------------------------------------------------------------------

Deno.test("le prompt interdit explicitement la recommandation sur titre nommé", () => {
  const prompt = SYSTEM_PROMPT.toLowerCase();

  // L'interdiction doit être formulée, pas seulement sous-entendue par le ton.
  assertStringIncludes(prompt, "jamais");
  assert(
    prompt.includes("quoi acheter") || prompt.includes("acheter ou vendre"),
    "l'interdiction d'orienter un achat ou une vente doit être explicite",
  );
  assertStringIncludes(prompt, "prédiction");
  // Décrire une entreprise reste permis : sans cette nuance, Hercule refuserait
  // aussi d'expliquer ce que fait une société, ce qui le rendrait inutile.
  assertStringIncludes(prompt, "décrire n'est pas recommander");
});

Deno.test("le prompt impose un registre pédagogique et une porte de sortie", () => {
  const prompt = SYSTEM_PROMPT.toLowerCase();
  assertStringIncludes(prompt, "argent fictif");
  // Un refus sec sans alternative laisserait l'utilisateur dans le vide.
  assertStringIncludes(prompt, "propose");
});

Deno.test("le modèle retenu est celui du plan", () => {
  // Le plan fixe Sonnet 5 pour tenir le budget de 20–50 $/mois du chat.
  assertEquals(HERCULE_MODEL, "claude-sonnet-5");
});

// ---------------------------------------------------------------------
// Contexte — ce qui part chez le fournisseur du modèle
// ---------------------------------------------------------------------

Deno.test("le contexte n'expose aucun montant", () => {
  const text = buildContextText(CONTEXT).toLowerCase();

  for (const leak of ["€", "$", "solde", "centime", "valeur du portefeuille"]) {
    assert(!text.includes(leak), `le contexte expose « ${leak} » : ${text}`);
  }
  // « eur »/« usd » comme code devise, en mot entier — la sous-chaîne seule
  // matcherait « conducteurs » ou « explorateur ».
  assert(!/\b(eur|usd)\b/.test(text), "le contexte cite un code devise");
  // Aucune suite de chiffres suivie d'un symbole monétaire.
  assert(!/\d[\d\s.,]*\s*(€|\$)/.test(text), "le contexte contient un montant");
});

Deno.test("le contexte transmet les titres détenus pour personnaliser les exemples", () => {
  const text = buildContextText(CONTEXT);
  assertStringIncludes(text, "Nvidia");
  assertStringIncludes(text, "Air Liquide");
  assertStringIncludes(text, "Semi-conducteurs");
  assertStringIncludes(text, "L'Explorateur");
  assertStringIncludes(text, "3 leçon(s) terminée(s) sur 27");
});

Deno.test("un portefeuille vide change la consigne d'exemples", () => {
  const text = buildContextText({ ...CONTEXT, holdings: [] });
  assertStringIncludes(text, "Portefeuille encore vide");
  assert(!text.includes("Titres détenus"), "ne doit pas annoncer des titres inexistants");
});

Deno.test("le niveau ajuste la densité d'explication", () => {
  assertStringIncludes(
    buildContextText({ ...CONTEXT, lessons_done: 0 }),
    "Grand débutant",
  );
  assertStringIncludes(
    buildContextText({ ...CONTEXT, lessons_done: 14 }),
    "bonnes bases",
  );
});

// ---------------------------------------------------------------------
// Blocs système et cache
// ---------------------------------------------------------------------

Deno.test("le prompt stable précède le contexte et porte seul le point de cache", () => {
  const blocks = buildSystemBlocks(CONTEXT);

  assertEquals(blocks.length, 2);
  assertEquals(blocks[0].text, SYSTEM_PROMPT);
  // Le cache est un préfixe : marquer le bloc variable ne partagerait rien
  // entre deux utilisateurs.
  assertEquals(blocks[0].cache_control?.type, "ephemeral");
  assertEquals(blocks[1].cache_control, undefined);
});

// ---------------------------------------------------------------------
// Historique
// ---------------------------------------------------------------------

Deno.test("buildMessages ajoute la question à la fin", () => {
  const messages = buildMessages(
    [
      { role: "user", content: "C'est quoi un dividende ?" },
      { role: "assistant", content: "Une part des bénéfices reversée." },
    ],
    "  Et un PER ?  ",
  );

  assertEquals(messages.length, 3);
  assertEquals(messages[2], { role: "user", content: "Et un PER ?" });
});

Deno.test("buildMessages borne l'historique", () => {
  const long: Array<{ role: "user" | "assistant"; content: string }> = [];
  for (let i = 0; i < 40; i++) {
    long.push({ role: i % 2 === 0 ? "user" : "assistant", content: `m${i}` });
  }

  const messages = buildMessages(long, "question");
  assert(messages.length <= HISTORY_TURNS * 2 + 1, `${messages.length} messages`);
});

Deno.test("buildMessages commence toujours par un message utilisateur", () => {
  // Une troncature au milieu d'un tour peut faire commencer l'historique par
  // une réponse ; l'API rejette ce cas.
  const messages = buildMessages(
    [
      { role: "assistant", content: "réponse orpheline" },
      { role: "user", content: "vraie question" },
    ],
    "suite",
  );
  assertEquals(messages[0].role, "user");
  assertEquals(messages[0].content, "vraie question");
});

// ---------------------------------------------------------------------
// Lecture de la réponse
// ---------------------------------------------------------------------

Deno.test("extractAnswer concatène les blocs texte", () => {
  const answer = extractAnswer({
    stop_reason: "end_turn",
    content: [
      { type: "text", text: "Le PER compare " },
      { type: "thinking", text: "(ne doit pas apparaître)" },
      { type: "text", text: "le prix au bénéfice." },
    ],
  });
  assertEquals(answer, "Le PER compare le prix au bénéfice.");
});

Deno.test("extractAnswer vérifie stop_reason avant de lire content", () => {
  // Sur un refus, `content` peut être vide : indexer content[0] planterait.
  assertThrows(
    () => extractAnswer({ stop_reason: "refusal", content: [] }),
    RefusalError,
  );
  assertThrows(
    () => extractAnswer({ stop_reason: "end_turn", content: [] }),
    RefusalError,
  );
});
