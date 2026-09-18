// =====================================================================
// Accès PostgREST minimal, en service role.
//
// Pas de `supabase-js` ici : ces fonctions ne font que lire une table et
// upserter en masse. La dépendance n'apporterait rien et empêcherait de
// typechecker les fonctions hors ligne.
//
// La clé service role contourne RLS — elle ne doit exister que dans les
// secrets de la fonction, jamais dans le dépôt ni dans l'app.
// =====================================================================

export interface DbConfig {
  url: string;
  serviceRoleKey: string;
}

export function dbConfigFromEnv(): DbConfig {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url) throw new Error("SUPABASE_URL manquant");
  if (!serviceRoleKey) throw new Error("SUPABASE_SERVICE_ROLE_KEY manquant");
  return { url: url.replace(/\/$/, ""), serviceRoleKey };
}

function headers(config: DbConfig, extra: Record<string, string> = {}): HeadersInit {
  return {
    apikey: config.serviceRoleKey,
    Authorization: `Bearer ${config.serviceRoleKey}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

export async function selectRows<T>(
  config: DbConfig,
  table: string,
  query: string,
): Promise<T[]> {
  const response = await fetch(`${config.url}/rest/v1/${table}?${query}`, {
    headers: headers(config),
  });
  if (!response.ok) {
    throw new Error(`select ${table} → ${response.status} ${await response.text()}`);
  }
  return await response.json() as T[];
}

/**
 * Upsert en masse. `onConflict` doit nommer la contrainte d'unicité, sinon
 * PostgREST insère et échoue sur la clé primaire.
 */
export async function upsertRows(
  config: DbConfig,
  table: string,
  rows: readonly unknown[],
  onConflict: string,
): Promise<number> {
  if (rows.length === 0) return 0;
  const response = await fetch(
    `${config.url}/rest/v1/${table}?on_conflict=${encodeURIComponent(onConflict)}`,
    {
      method: "POST",
      headers: headers(config, {
        Prefer: "resolution=merge-duplicates,return=minimal",
      }),
      body: JSON.stringify(rows),
    },
  );
  if (!response.ok) {
    throw new Error(`upsert ${table} → ${response.status} ${await response.text()}`);
  }
  return rows.length;
}

/**
 * Suppression filtrée. `filter` est une condition PostgREST déjà encodée,
 * par exemple `ts=lt.2026-01-01T00:00:00Z` : sans filtre, PostgREST
 * refuserait de toute façon de vider la table.
 */
export async function deleteRows(
  config: DbConfig,
  table: string,
  filter: string,
): Promise<void> {
  const response = await fetch(`${config.url}/rest/v1/${table}?${filter}`, {
    method: "DELETE",
    headers: headers(config, { Prefer: "return=minimal" }),
  });
  if (!response.ok) {
    throw new Error(`delete ${table} → ${response.status} ${await response.text()}`);
  }
}

/**
 * Le journal ne doit jamais faire échouer un rafraîchissement réussi : une
 * écriture d'observabilité qui casse la fonction qu'elle observe est pire que
 * pas de journal du tout.
 */
export async function logRun(
  config: DbConfig,
  entry: Record<string, unknown>,
): Promise<void> {
  try {
    await fetch(`${config.url}/rest/v1/market_data_runs`, {
      method: "POST",
      headers: headers(config, { Prefer: "return=minimal" }),
      body: JSON.stringify(entry),
    });
  } catch (error) {
    console.error("market_data_runs: écriture impossible", error);
  }
}

/**
 * Les fonctions sont déclenchées par cron, pas par un utilisateur. On exige un
 * secret partagé propre plutôt que la clé service role : elle circulerait dans
 * un en-tête à chaque appel et fuiterait dans les logs du planificateur.
 */
export function assertAuthorized(request: Request): void {
  const expected = Deno.env.get("MARKET_DATA_SECRET");
  if (!expected) throw new Error("MARKET_DATA_SECRET manquant");

  const provided = request.headers.get("x-market-data-secret") ?? "";
  if (!timingSafeEqual(provided, expected)) {
    throw new UnauthorizedError("secret invalide");
  }
}

export class UnauthorizedError extends Error {}

/**
 * Identifie l'utilisateur derrière un appel venant de l'app.
 *
 * On résout le jeton auprès de Supabase Auth plutôt que de décoder le JWT
 * localement : une signature non vérifiée laisserait n'importe qui se déclarer
 * propriétaire d'un autre compte, et donc consommer son quota ou lire ses
 * conversations.
 */
export async function authenticatedUserId(
  config: DbConfig,
  request: Request,
): Promise<string> {
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new UnauthorizedError("Jeton d'authentification manquant");
  }

  const response = await fetch(`${config.url}/auth/v1/user`, {
    headers: { apikey: config.serviceRoleKey, Authorization: authorization },
  });
  if (!response.ok) {
    throw new UnauthorizedError("Jeton d'authentification invalide");
  }

  const user = await response.json() as { id?: string };
  if (!user.id) throw new UnauthorizedError("Utilisateur introuvable");
  return user.id;
}

/** Appelle une fonction Postgres exposée par PostgREST (`/rpc/<nom>`). */
export async function callFunction<T>(
  config: DbConfig,
  name: string,
  args: Record<string, unknown>,
): Promise<T> {
  const response = await fetch(`${config.url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new PostgresError(`rpc ${name} → ${response.status} ${body}`, body);
  }
  return body.length > 0 ? JSON.parse(body) as T : (null as T);
}

/**
 * Erreur PostgREST portant le code SQLSTATE, pour que l'appelant puisse
 * distinguer un quota épuisé (KR050) d'une panne.
 */
export class PostgresError extends Error {
  readonly code: string;
  constructor(message: string, rawBody: string) {
    super(message);
    try {
      this.code = (JSON.parse(rawBody) as { code?: string }).code ?? "";
    } catch {
      this.code = "";
    }
  }
}

/** Comparaison à temps constant — évite de révéler le secret octet par octet. */
function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const bufA = encoder.encode(a);
  const bufB = encoder.encode(b);
  if (bufA.length !== bufB.length) return false;
  let diff = 0;
  for (let i = 0; i < bufA.length; i++) diff |= bufA[i] ^ bufB[i];
  return diff === 0;
}
