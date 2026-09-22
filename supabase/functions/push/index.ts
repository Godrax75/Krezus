// =====================================================================
// Edge Function `push` — envoie les rappels par notification.
//
// Déclenchée par cron (0026) : lundi 9 h à Paris, quand les 300 € de la
// semaine sont remis en jeu, et samedi 11 h pour ceux qui ne sont pas
// encore passés. Le versement ne se cumule pas : une semaine sans
// ouverture est perdue, et sans rappel la récompense ne profite qu'à ceux
// qui y pensaient déjà.
//
// La fonction ne décide de rien : `weekly_bonus_targets` (SQL) sait qui a
// consenti, qui n'a pas touché son versement et qui n'a pas déjà reçu ce
// rappel. Ici, on signe, on envoie, on note.
//
//   supabase functions deploy push --no-verify-jwt
//
// Paramètre : campaign=weekly_bonus | weekly_bonus_last_chance
// =====================================================================

import {
  apnsConfigFromEnv,
  ApnsNotConfigured,
  sendApns,
} from "../_shared/apns.ts";
import {
  assertAuthorized,
  callFunction,
  dbConfigFromEnv,
  logRun,
  UnauthorizedError,
} from "../_shared/db.ts";

/** Montant rappelé, en euros. Doit suivre `weekly_bonus_cents` (0021). */
const WEEKLY_EUROS = 300;

interface Target {
  user_id: string;
  locale: string;
  token: string;
  platform: string;
}

/** Textes des deux rappels, dans les deux langues de l'app. */
const MESSAGES: Record<string, Record<string, { title: string; body: string }>> = {
  weekly_bonus: {
    fr: {
      title: `Tes ${WEEKLY_EUROS} € de la semaine`,
      body: "Ouvre Krezus pour les récupérer et place-les avant la fin de la semaine.",
    },
    en: {
      title: `Your €${WEEKLY_EUROS} for the week`,
      body: "Open Krezus to collect them, and put them to work before the week is out.",
    },
  },
  weekly_bonus_last_chance: {
    fr: {
      title: `${WEEKLY_EUROS} € t'attendent encore`,
      body: "Ils disparaissent dimanche soir : ils ne se reportent pas sur la semaine suivante.",
    },
    en: {
      title: `€${WEEKLY_EUROS} are still waiting`,
      body: "They vanish on Sunday night — they don't carry over to next week.",
    },
  },
};

Deno.serve(async (request: Request): Promise<Response> => {
  const startedAt = Date.now();

  try {
    assertAuthorized(request);
  } catch (error) {
    const status = error instanceof UnauthorizedError ? 401 : 500;
    return json({ error: (error as Error).message }, status);
  }

  const campaign = new URL(request.url).searchParams.get("campaign") ?? "weekly_bonus";
  const messages = MESSAGES[campaign];
  if (!messages) return json({ error: `Campagne inconnue : ${campaign}` }, 400);

  const config = dbConfigFromEnv();

  let apns;
  try {
    apns = apnsConfigFromEnv();
  } catch (error) {
    // Tant que la clé APNs n'est pas déposée, on le dit franchement plutôt
    // que de laisser un cron échouer en silence chaque lundi.
    const message = (error as Error).message;
    await logRun(config, { function: "push", duration_ms: Date.now() - startedAt, error: message });
    return json({ error: message }, error instanceof ApnsNotConfigured ? 503 : 500);
  }

  try {
    const targets = await callFunction<Target[]>(config, "weekly_bonus_targets", {
      p_campaign: campaign,
    });

    let sent = 0;
    let dropped = 0;
    const failures: string[] = [];
    // Un compte peut avoir plusieurs appareils : le rappel part sur chacun,
    // mais ne s'inscrit au journal qu'une fois.
    const notified = new Set<string>();

    for (const target of targets) {
      const text = messages[target.locale] ?? messages.fr;
      const result = await sendApns(apns, target.token, {
        title: text.title,
        body: text.body,
        kind: "bonus",
      });

      if (result.ok) {
        sent++;
        if (!notified.has(target.user_id)) {
          notified.add(target.user_id);
          // La même chose dans la boîte de l'app : une bannière balayée
          // d'un doigt ne doit pas emporter l'information avec elle.
          await callFunction(config, "notify", {
            p_user_id: target.user_id,
            p_kind: "bonus",
            p_title: text.title,
            p_body: text.body,
          });
          await callFunction(config, "record_push_campaign", {
            p_user_id: target.user_id,
            p_campaign: campaign,
          });
        }
      } else if (result.expired) {
        dropped++;
        await callFunction(config, "drop_device_token", { p_token: target.token });
      } else {
        failures.push(`${target.user_id}: ${result.reason}`);
      }
    }

    const durationMs = Date.now() - startedAt;
    await logRun(config, {
      function: "push",
      duration_ms: durationMs,
      symbols: targets.length,
      upserted: sent,
      error: failures.length > 0 ? failures.slice(0, 5).join(" | ") : null,
    });

    return json({
      campaign,
      targets: targets.length,
      sent,
      dropped_tokens: dropped,
      duration_ms: durationMs,
      failures: failures.slice(0, 5),
    });
  } catch (error) {
    const message = (error as Error).message;
    await logRun(config, { function: "push", duration_ms: Date.now() - startedAt, error: message });
    console.error("push:", message);
    return json({ error: message }, 502);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
