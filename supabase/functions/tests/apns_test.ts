// =====================================================================
// Jeton APNs — la signature est le seul endroit où une erreur ne se voit
// pas : Apple répond 403 sans dire pourquoi.
// =====================================================================

import { assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1";
import {
  alertPayload,
  apnsConfigFromEnv,
  ApnsNotConfigured,
  pkcs8FromPem,
  signApnsToken,
} from "../_shared/apns.ts";

/** Clé P-256 de test, au format .p8 d'Apple. */
async function testKeyPem(): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const body = btoa(String.fromCharCode(...pkcs8)).match(/.{1,64}/g)!.join("\n");
  return `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----\n`;
}

Deno.test("pkcs8FromPem retire les en-têtes et les retours à la ligne", async () => {
  const pem = await testKeyPem();
  const bytes = new Uint8Array(pkcs8FromPem(pem));
  assertEquals(bytes.length > 100, true);
  // Une clé PKCS#8 commence par une séquence ASN.1.
  assertEquals(bytes[0], 0x30);
});

Deno.test("le jeton porte la clé, l'équipe et une signature vérifiable", async () => {
  const pem = await testKeyPem();
  const token = await signApnsToken(
    { keyP8: pem, keyId: "ABC1234567", teamId: "TEAM123456", topic: "com.krezus.app", host: "" },
    new Date("2026-09-22T10:00:00Z"));

  const [header, payload, signature] = token.split(".");
  const decode = (part: string) =>
    JSON.parse(atob(part.replaceAll("-", "+").replaceAll("_", "/")));

  assertEquals(decode(header), { alg: "ES256", kid: "ABC1234567" });
  assertEquals(decode(payload), { iss: "TEAM123456", iat: 1790071200 });
  // ES256 : deux entiers de 32 octets, encodés sans remplissage base64url.
  assertEquals(atob(signature.replaceAll("-", "+").replaceAll("_", "/")).length, 64);
  assertEquals(/[+/=]/.test(token), false);
});

Deno.test("la charge utile porte le type, pour le routage côté app", () => {
  const payload = alertPayload({ title: "Tes 300 €", body: "Ouvre Krezus", kind: "bonus" });
  assertEquals(payload.kind, "bonus");
  const aps = payload.aps as Record<string, unknown>;
  assertEquals(aps.alert, { title: "Tes 300 €", body: "Ouvre Krezus" });
  assertEquals("badge" in aps, false);
  assertEquals((alertPayload({ title: "a", body: "b", kind: "bonus", badge: 3 }).aps as Record<string, unknown>).badge, 3);
});

Deno.test("sans clé déposée, la configuration échoue en le disant", async () => {
  const saved = Deno.env.get("APNS_KEY_P8");
  Deno.env.delete("APNS_KEY_P8");
  try {
    const error = await assertRejects(
      () => Promise.resolve().then(apnsConfigFromEnv), ApnsNotConfigured);
    assertStringIncludes(error.message, "APNS_KEY_P8");
  } finally {
    if (saved) Deno.env.set("APNS_KEY_P8", saved);
  }
});
