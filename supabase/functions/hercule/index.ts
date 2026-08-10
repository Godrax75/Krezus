// =====================================================================
// Edge Function `hercule` — chat pédagogique adossé à la Claude API.
//
// Appelée par l'app avec le JWT de l'utilisateur. Contrairement à `quotes` et
// `history` (déclenchées par cron), celle-ci est face utilisateur : elle
// vérifie l'identité, décompte le quota en base, puis appelle le modèle.
//
// La clé Anthropic reste ici. Elle n'entre jamais dans le binaire iOS — un
// jeton dans une app est extractible en quelques minutes.
//
// Secrets attendus :
//   ANTHROPIC_API_KEY          clé Claude API
//   SUPABASE_URL               injecté par la plateforme
//   SUPABASE_SERVICE_ROLE_KEY  injecté par la plateforme
//
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy hercule          (JWT vérifié : pas de --no-verify-jwt)
// =====================================================================

import Anthropic from "npm:@anthropic-ai/sdk";

import {
  buildMessages,
  buildSystemBlocks,
  extractAnswer,
  HERCULE_EFFORT,
  HERCULE_MODEL,
  type HerculeContext,
  type HerculeTurn,
  HISTORY_TURNS,
  MAX_OUTPUT_TOKENS,
  RefusalError,
} from "../_shared/hercule.ts";
import {
  authenticatedUserId,
  callFunction,
  dbConfigFromEnv,
  PostgresError,
  selectRows,
  UnauthorizedError,
} from "../_shared/db.ts";

Deno.serve(async (request: Request): Promise<Response> => {
  const config = dbConfigFromEnv();
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "ANTHROPIC_API_KEY manquant" }, 500);

  let userId: string;
  try {
    userId = await authenticatedUserId(config, request);
  } catch (error) {
    const status = error instanceof UnauthorizedError ? 401 : 500;
    return json({ error: (error as Error).message }, status);
  }

  let question: string;
  try {
    const body = await request.json() as { question?: unknown };
    if (typeof body.question !== "string" || body.question.trim().length === 0) {
      return json({ error: "Question manquante" }, 400);
    }
    question = body.question.trim();
  } catch {
    return json({ error: "Corps de requête illisible" }, 400);
  }

  try {
    // Le quota est vérifié une première fois ici pour éviter un appel au
    // modèle (payant) qui serait de toute façon rejeté à l'écriture. Le
    // contrôle qui fait foi reste celui de `record_hercule_exchange`, qui
    // s'exécute sous verrou.
    const [quota] = await selectRows<{ is_premium: boolean; remaining: number }>(
      config,
      "rpc/hercule_quota",
      `p_user=${encodeURIComponent(userId)}`,
    );
    if (quota && !quota.is_premium && quota.remaining <= 0) {
      return json({ error: "quota_exhausted", remaining: 0 }, 429);
    }

    const [context] = await selectRows<HerculeContext>(
      config,
      "v_hercule_context",
      `select=*&user_id=eq.${encodeURIComponent(userId)}`,
    );
    if (!context) return json({ error: "Profil introuvable" }, 404);

    const history = await selectRows<HerculeTurn>(
      config,
      "hercule_messages",
      `select=role,content&user_id=eq.${encodeURIComponent(userId)}` +
        `&order=created_at.desc&limit=${HISTORY_TURNS * 2}`,
    );

    const client = new Anthropic({ apiKey });
    const response = await client.messages.create({
      model: HERCULE_MODEL,
      max_tokens: MAX_OUTPUT_TOKENS,
      output_config: { effort: HERCULE_EFFORT },
      system: buildSystemBlocks(context),
      // `history` arrive du plus récent au plus ancien (index sur created_at) ;
      // le modèle attend l'ordre chronologique.
      messages: buildMessages(history.reverse(), question),
    });

    const answer = extractAnswer(response);

    const [recorded] = await callFunction<Array<{ remaining: number }>>(
      config,
      "record_hercule_exchange",
      { p_user: userId, p_question: question, p_answer: answer },
    );

    return json({
      answer,
      remaining: recorded?.remaining ?? null,
      is_premium: context.is_premium,
    });
  } catch (error) {
    if (error instanceof PostgresError && error.code === "KR050") {
      return json({ error: "quota_exhausted", remaining: 0 }, 429);
    }
    if (error instanceof PostgresError && error.code === "KR051") {
      return json({ error: "invalid_message" }, 400);
    }
    if (error instanceof RefusalError) {
      // Un refus du modèle n'est pas une panne : on rend un message
      // utilisable plutôt qu'une erreur technique.
      return json({
        answer:
          "Je préfère ne pas répondre à cette demande. Pose-moi plutôt une question sur " +
          "le fonctionnement des marchés — ce que mesure un ratio, comment se lit un cours, " +
          "pourquoi un secteur bouge.",
        remaining: null,
        refused: true,
      });
    }

    const message = (error as Error).message;
    console.error("hercule:", message);
    return json({ error: message }, 502);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
