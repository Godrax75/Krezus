// =====================================================================
// Adaptateur APNs — jeton d'autorisation et envoi d'une notification.
//
// Apple accepte deux formes d'authentification : un certificat, ou un
// jeton signé avec une clé .p8. La clé est retenue ici parce qu'elle
// n'expire pas et vaut pour toutes les apps de l'équipe — un certificat
// se renouvelle chaque année, et personne ne s'en souvient à temps.
//
// Le jeton est signé en ES256 avec la WebCrypto du runtime : aucune
// dépendance, et la clé privée ne quitte jamais la mémoire du processus.
// Apple demande de le renouveler au moins toutes les heures et au plus
// une fois toutes les vingt minutes, d'où le cache.
//
// Secrets attendus :
//   APNS_KEY_P8    contenu du fichier .p8, en-têtes PEM compris
//   APNS_KEY_ID    identifiant de la clé (10 caractères)
//   APNS_TEAM_ID   identifiant d'équipe Apple Developer
//   APNS_TOPIC     identifiant de l'app (com.krezus.app)
//   APNS_ENV       « production » (défaut) ou « sandbox » pour un build Xcode
// =====================================================================

export interface ApnsConfig {
  keyP8: string;
  keyId: string;
  teamId: string;
  topic: string;
  host: string;
}

export interface ApnsAlert {
  title: string;
  body: string;
  /** Repris par l'app pour savoir où emmener celui qui touche la bannière. */
  kind: string;
  badge?: number;
}

export type ApnsResult =
  | { ok: true }
  /** Jeton inconnu d'Apple : l'app a été désinstallée, il faut l'oublier. */
  | { ok: false; expired: true; reason: string }
  | { ok: false; expired: false; reason: string };

export class ApnsNotConfigured extends Error {}

export function apnsConfigFromEnv(): ApnsConfig {
  const keyP8 = Deno.env.get("APNS_KEY_P8");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  if (!keyP8 || !keyId || !teamId) {
    throw new ApnsNotConfigured(
      "APNS_KEY_P8, APNS_KEY_ID et APNS_TEAM_ID sont requis — voir docs/push.md",
    );
  }
  const sandbox = (Deno.env.get("APNS_ENV") ?? "production") === "sandbox";
  return {
    keyP8,
    keyId,
    teamId,
    topic: Deno.env.get("APNS_TOPIC") ?? "com.krezus.app",
    host: sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com",
  };
}

/** Corps utile d'une clé .p8, débarrassé de ses en-têtes PEM. */
export function pkcs8FromPem(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0)).buffer as ArrayBuffer;
}

function base64url(bytes: Uint8Array | string): string {
  const binary = typeof bytes === "string"
    ? bytes
    : String.fromCharCode(...bytes);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

/** Jeton d'autorisation APNs (JWT ES256), valable une heure. */
export async function signApnsToken(config: ApnsConfig, now = new Date()): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8FromPem(config.keyP8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = base64url(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const payload = base64url(JSON.stringify({
    iss: config.teamId,
    iat: Math.floor(now.getTime() / 1000),
  }));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
}

/**
 * Cache du jeton : Apple refuse qu'on en demande un nouveau plus d'une fois
 * toutes les vingt minutes (erreur TooManyProviderTokenUpdates).
 */
let cached: { token: string; at: number } | null = null;

export async function apnsToken(config: ApnsConfig): Promise<string> {
  const age = cached ? Date.now() - cached.at : Infinity;
  if (cached && age < 30 * 60_000) return cached.token;
  const token = await signApnsToken(config);
  cached = { token, at: Date.now() };
  return token;
}

/** Charge utile APNs d'une notification simple. */
export function alertPayload(alert: ApnsAlert): Record<string, unknown> {
  return {
    aps: {
      alert: { title: alert.title, body: alert.body },
      sound: "default",
      ...(alert.badge === undefined ? {} : { badge: alert.badge }),
    },
    kind: alert.kind,
  };
}

export async function sendApns(
  config: ApnsConfig,
  deviceToken: string,
  alert: ApnsAlert,
): Promise<ApnsResult> {
  const response = await fetch(`${config.host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsToken(config)}`,
      "apns-topic": config.topic,
      "apns-push-type": "alert",
      // 5 = « au moment opportun » : Apple peut retarder de quelques
      // minutes pour épargner la batterie. Un rappel hebdomadaire n'a pas
      // besoin de la priorité d'un message.
      "apns-priority": "5",
      "content-type": "application/json",
    },
    body: JSON.stringify(alertPayload(alert)),
  });

  if (response.ok) return { ok: true };

  const text = await response.text();
  // 410, ou 400 BadDeviceToken : l'app n'est plus installée sur cet appareil.
  const expired = response.status === 410 || text.includes("BadDeviceToken")
    || text.includes("Unregistered");
  return { ok: false, expired, reason: `${response.status} ${text}`.trim() };
}
