// =====================================================================
// Hercule — construction du prompt et lecture de la réponse.
//
// Vit côté serveur : la clé Anthropic ne doit jamais entrer dans le binaire
// iOS. Aucune I/O ici — c'est ce qui rend le prompt testable sur fixtures,
// et surtout ce qui rend la contrainte réglementaire vérifiable par un test
// plutôt que par une relecture.
// =====================================================================

/** Modèle retenu au plan (budget 20–50 $/mois pour brief + chat). */
export const HERCULE_MODEL = "claude-sonnet-5";

/**
 * Le chat est conversationnel : la latence prime sur la profondeur de
 * raisonnement. `low` reste très correct sur Sonnet 5 pour de l'explication.
 */
export const HERCULE_EFFORT = "low";

export const MAX_OUTPUT_TOKENS = 1024;

/** Tours de conversation renvoyés au modèle (2 messages par tour). */
export const HISTORY_TURNS = 8;

/**
 * Colonne vertébrale du personnage ET garde-fou réglementaire.
 *
 * Krezus n'a pas le statut de conseiller en investissement (CIF). Une
 * recommandation personnalisée d'achat sur titre nommé relèverait du conseil
 * en investissement et exposerait le produit. Cette contrainte n'est pas une
 * préférence de ton : c'est la raison pour laquelle l'app peut exister sans
 * agrément. Elle est vérifiée par un test.
 *
 * Ce bloc est stable d'un utilisateur à l'autre : il est placé en tête et
 * marqué pour le cache, le contexte personnel venant après.
 */
export const SYSTEM_PROMPT = `Tu es Hercule, le compagnon pédagogique de Krezus, une application française qui apprend la bourse avec de l'argent fictif.

# Qui tu es
Tu expliques comment fonctionnent les marchés à des gens qui débutent, souvent jeunes, souvent intimidés par le sujet. Tu es chaleureux et direct, jamais condescendant. Tu tutoies. Tu écris en français courant, sans jargon inutile — et quand un terme technique est nécessaire, tu le définis en passant.

# Ce que tu fais
- Tu expliques des mécanismes : ce qu'est un dividende, pourquoi un cours bouge, ce que mesure un PER, ce qu'implique la diversification.
- Tu rattaches les explications à ce que la personne possède déjà dans son portefeuille fictif, parce qu'un exemple concret vaut trois paragraphes abstraits.
- Tu réponds court. Trois à cinq phrases suffisent presque toujours. Si la question est vaste, tu donnes l'essentiel et tu proposes de creuser un point précis.
- Tu utilises des chiffres publics et vérifiables quand ils éclairent le propos.

# Ce que tu ne fais jamais
Tu ne dis jamais à quelqu'un quoi acheter ou vendre. C'est une limite absolue, pas une précaution de style.

Concrètement, tu ne produis jamais :
- une recommandation d'achat ou de vente sur un titre nommé (« achète Nvidia », « vends Air Liquide », « c'est le moment d'entrer sur LVMH ») ;
- une opinion déguisée en analyse (« à ce niveau de prix, ce serait dommage de passer à côté ») ;
- une prédiction de cours, même prudente (« ça devrait remonter », « le potentiel est là ») ;
- un jugement sur la qualité d'un portefeuille présenté comme un conseil d'action.

Si on te demande explicitement quoi acheter, tu le refuses clairement et sans détour, en une phrase, puis tu proposes ce que tu peux réellement faire : expliquer comment se juge une entreprise, ce que mesure un ratio, comment raisonner sur un horizon de placement. Tu ne t'excuses pas longuement et tu ne fais pas la morale — tu redonnes la main.

Tu peux parfaitement décrire les caractéristiques d'une entreprise (son métier, son secteur, son dividende historique, sa volatilité passée) : décrire n'est pas recommander. La ligne est franchie dès que tu suggères une action à faire.

# Sur l'argent fictif
Les portefeuilles de Krezus sont en argent fictif. Tu le rappelles quand c'est utile, sans le répéter à chaque message. Personne ne perd d'argent réel ici — c'est justement ce qui permet d'apprendre en se trompant.

# Format
Réponds en texte simple. Pas de titres, pas de listes à puces sauf si la question appelle vraiment une énumération. Pas de Markdown lourd. Tu parles, tu ne rédiges pas un rapport.`;

/** Contexte de l'utilisateur, tel que renvoyé par `v_hercule_context`. */
export interface HerculeContext {
  username: string | null;
  xp: number;
  rank_level: number;
  streak_days: number;
  is_premium: boolean;
  investor_archetype: string | null;
  lessons_done: number;
  lessons_total: number;
  holdings: Array<{ symbol: string; name: string; sector: string | null }>;
}

export interface HerculeTurn {
  role: "user" | "assistant";
  content: string;
}

export interface TextBlock {
  type: "text";
  text: string;
  cache_control?: { type: "ephemeral" };
}

/**
 * Résume le contexte en texte.
 *
 * Ne contient **aucun montant** : ni valeur de portefeuille, ni solde, ni
 * somme investie. Hercule explique des mécanismes — savoir que quelqu'un
 * détient Nvidia suffit à personnaliser un exemple ; savoir combien il y a mis
 * n'apporte rien et enverrait une donnée patrimoniale à un tiers.
 */
export function buildContextText(context: HerculeContext): string {
  const lines: string[] = ["# Ce que tu sais de la personne"];

  if (context.username) lines.push(`Pseudo : ${context.username}.`);
  lines.push(
    `Progression : ${context.xp} XP, rang ${context.rank_level} sur 6, ` +
      `${context.lessons_done} leçon(s) terminée(s) sur ${context.lessons_total}, ` +
      `série de ${context.streak_days} jour(s).`,
  );

  if (context.investor_archetype) {
    lines.push(`Tempérament d'investisseur déclaré : ${context.investor_archetype}.`);
  }

  if (context.holdings.length > 0) {
    const held = context.holdings
      .map((h) => (h.sector ? `${h.name} (${h.sector})` : h.name))
      .join(", ");
    lines.push(`Titres détenus dans son portefeuille fictif : ${held}.`);
    lines.push(
      "Appuie-toi sur ces titres pour illustrer tes explications — c'est plus parlant qu'un exemple générique.",
    );
  } else {
    lines.push(
      "Portefeuille encore vide : évite les exemples qui supposent une position, et reste sur des cas généraux.",
    );
  }

  // Le niveau ajuste la densité d'explication, pas le fond.
  if (context.lessons_done === 0) {
    lines.push(
      "Grand débutant : définis chaque terme technique dès la première occurrence.",
    );
  } else if (context.lessons_done >= 10) {
    lines.push(
      "A déjà de bonnes bases : tu peux aller plus vite sur les fondamentaux.",
    );
  }

  return lines.join("\n");
}

/**
 * Blocs système : le prompt stable d'abord (marqué pour le cache), le
 * contexte personnel ensuite.
 *
 * L'ordre compte. Le cache est un préfixe : tout octet qui change invalide la
 * suite. Le contexte varie à chaque utilisateur, donc il doit venir APRÈS le
 * point de cache, sinon rien ne se partage entre deux conversations.
 *
 * Note : Sonnet 5 exige 1 024 tokens minimum pour qu'un préfixe soit
 * réellement mis en cache. En deçà, l'écriture est simplement ignorée — sans
 * erreur. Vérifier `usage.cache_read_input_tokens` avant de conclure que le
 * cache fonctionne.
 */
export function buildSystemBlocks(context: HerculeContext): TextBlock[] {
  return [
    { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
    { type: "text", text: buildContextText(context) },
  ];
}

/**
 * Historique + question. On ne renvoie que les derniers tours : au-delà, le
 * coût grimpe sans que la conversation y gagne, un chat pédagogique ayant
 * rarement besoin de se souvenir de vingt échanges.
 */
export function buildMessages(
  history: readonly HerculeTurn[],
  question: string,
): HerculeTurn[] {
  const trimmed = history.slice(-HISTORY_TURNS * 2);

  // L'API exige que le premier message soit de l'utilisateur ; un historique
  // tronqué au milieu d'un tour peut commencer par une réponse.
  while (trimmed.length > 0 && trimmed[0].role !== "user") trimmed.shift();

  return [...trimmed, { role: "user", content: question.trim() }];
}

export class RefusalError extends Error {}

/**
 * Extrait le texte de la réponse.
 *
 * `stop_reason` est vérifié AVANT de lire `content` : sur un refus la liste
 * peut être vide, et indexer `content[0]` planterait au lieu de produire un
 * message utilisable.
 */
export function extractAnswer(response: {
  stop_reason?: string | null;
  content?: Array<{ type: string; text?: string }>;
}): string {
  if (response.stop_reason === "refusal") {
    throw new RefusalError("Le modèle a décliné cette demande.");
  }

  const text = (response.content ?? [])
    .filter((block) => block.type === "text" && typeof block.text === "string")
    .map((block) => block.text as string)
    .join("")
    .trim();

  if (text.length === 0) {
    throw new RefusalError("Réponse vide du modèle.");
  }
  return text;
}
