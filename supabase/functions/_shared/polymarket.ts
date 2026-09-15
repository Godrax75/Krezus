// =====================================================================
// Adaptateur Polymarket (API Gamma publique, sans clé, ~60 req/min).
//
// Fonctions pures, sans I/O — testables sur fixtures comme l'adaptateur EODHD.
//
// Cadre d'usage : les probabilités sont affichées à titre INFORMATIF. L'app
// n'expose aucun lien vers la plateforme de paris (guideline App Store 4.7),
// et le bloc ne doit jamais être présenté comme une prévision de Krezus.
// =====================================================================

export const GAMMA_BASE = "https://gamma-api.polymarket.com";

/**
 * Marchés retenus : macro et marchés actions, pas la politique ni le sport.
 * Le filtrage se fait sur le libellé faute de taxonomie stable côté Gamma.
 */
export const TOPIC_PATTERNS: readonly RegExp[] = [
  /\b(fed|federal reserve|interest rate|rate cut|rate hike)\b/i,
  /\b(inflation|cpi|recession|gdp)\b/i,
  /\b(s&p|nasdaq|dow|stock market|equities)\b/i,
  /\b(ecb|european central bank|euro)\b/i,
  /\b(oil|opec|gold)\b/i,
];

export interface PredictionRow {
  id: string;
  question: string;
  probability: number;
  volume: number | null;
  ends_at: string | null;
  category: string | null;
  fetched_at: string;
}

export function buildMarketsURL(limit = 100): string {
  const url = new URL(`${GAMMA_BASE}/markets`);
  url.searchParams.set("active", "true");
  url.searchParams.set("closed", "false");
  url.searchParams.set("limit", String(limit));
  // Les marchés les plus échangés sont les plus informatifs ; les marchés
  // confidentiels ont des probabilités très bruitées. Gamma ignore
  // `order=volume` (champ texte) sans erreur : seul `volumeNum` trie vraiment.
  url.searchParams.set("order", "volumeNum");
  url.searchParams.set("ascending", "false");
  return url.toString();
}

export function toNumber(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

/**
 * Gamma sérialise `outcomePrices` tantôt en tableau, tantôt en chaîne JSON.
 * La première valeur correspond au résultat « Yes ».
 */
export function parseProbability(raw: unknown): number | null {
  let values: unknown = raw;
  if (typeof raw === "string") {
    try {
      values = JSON.parse(raw);
    } catch {
      return null;
    }
  }
  if (!Array.isArray(values) || values.length === 0) return null;

  const probability = toNumber(values[0]);
  if (probability === null) return null;
  if (probability < 0 || probability > 1) return null;
  return probability;
}

export function isRelevant(question: string): boolean {
  return TOPIC_PATTERNS.some((pattern) => pattern.test(question));
}

/**
 * Ne garde que les marchés macro/actions exploitables. Un marché sans
 * probabilité lisible est écarté plutôt qu'affiché à 0 %, ce qui se lirait
 * comme une prédiction ferme.
 */
export function parseMarkets(payload: unknown, now: Date): PredictionRow[] {
  if (!Array.isArray(payload)) return [];
  const fetchedAt = now.toISOString();
  const rows: PredictionRow[] = [];

  for (const entry of payload) {
    if (entry === null || typeof entry !== "object") continue;
    const market = entry as Record<string, unknown>;

    const id = typeof market.id === "string"
      ? market.id
      : toNumber(market.id) !== null ? String(market.id) : "";
    if (id === "") continue;

    const question = typeof market.question === "string" ? market.question.trim() : "";
    if (question === "" || !isRelevant(question)) continue;

    const probability = parseProbability(market.outcomePrices);
    if (probability === null) continue;

    rows.push({
      id,
      question,
      probability,
      volume: toNumber(market.volume),
      ends_at: typeof market.endDate === "string" ? market.endDate : null,
      category: typeof market.category === "string" ? market.category : null,
      fetched_at: fetchedAt,
    });
  }

  return rows;
}
