// POST /functions/v1/ai-assist
// AI that ASSISTS the couple (brief §44). Privacy: only the structured
// parameters the user typed into the form are sent to the model — never
// chat messages, diary entries or photos.
//
// Body: { mode: "date_ideas" | "conversation_starters" | "challenge" | "gift_ideas" | "surprise_date" | "recap_story", input: {...} }
// Env:  ANTHROPIC_API_KEY (required), LOVEBIRD_AI_MODEL (default claude-sonnet-5-5), LOVEBIRD_AI_DAILY_LIMIT (default 30)

import { authenticate, clampStr, handle, HttpError, json, requireActiveCircle } from "../_shared/common.ts";

type Mode = "date_ideas" | "conversation_starters" | "challenge" | "gift_ideas" | "surprise_date" | "recap_story";
const MODES: Mode[] = ["date_ideas", "conversation_starters", "challenge", "gift_ideas", "surprise_date", "recap_story"];

const SYSTEM = `You are Lovebird's assistant, helping a couple spend quality time together.
Rules:
- Be warm, playful and practical. Ideas must be doable with what the couple described.
- Respect budget and currency exactly; never suggest spending more than the stated budget.
- If they are long-distance, every idea must work over video/voice with both partners at home in different places.
- Keep everything consensual, kind and safe. No sexual content, no alcohol-centred ideas unless asked, no risky stunts.
- Never pretend to be a partner or replace their relationship; you help them connect with each other.
- Output ONLY valid JSON matching the requested schema. No markdown.`;

function buildPrompt(mode: Mode, input: Record<string, unknown>): { prompt: string; schema: string } {
  const s = (k: string, max = 120) => clampStr(input[k], max);
  switch (mode) {
    case "date_ideas":
    case "surprise_date": {
      const count = mode === "surprise_date" ? 1 : 5;
      return {
        prompt: `Create ${count} date idea(s).
Budget: ${s("budget", 30) || "flexible"} ${s("currency", 3)}
Location: ${s("location") || "unspecified"}
Distance: ${input["long_distance"] ? "long-distance (different places)" : "same place"}
Time available: ${s("time", 40) || "an evening"}
Setting: ${s("setting", 20) || "any"}
Mood: ${s("mood", 40) || "romantic"}
Food preference: ${s("food", 80) || "none"}
Energy level: ${s("energy", 20) || "medium"}
Wants to spend money: ${input["spend_money"] === false ? "no — free ideas only" : "ok within budget"}
Extra notes: ${s("notes", 300)}`,
        schema: `{"ideas":[{"title":string,"summary":string,"steps":[string],"estimated_cost":string,"duration":string,"why_its_fun":string,"lovebird_activity":"play"|"watch"|"read"|"talk"|"create"|"date"|null}]}`,
      };
    }
    case "conversation_starters":
      return {
        prompt: `Give 8 conversation starters for a couple. Mood: ${s("mood", 40) || "curious"}. Depth: ${s("depth", 20) || "mixed"}. Avoid anything that could start a fight unless depth is "deep", and even then be gentle.`,
        schema: `{"questions":[{"text":string,"tone":"light"|"deep"|"funny"|"romantic"}]}`,
      };
    case "challenge":
      return {
        prompt: `Create one fun couple challenge they can do ${input["long_distance"] ? "over a video call" : "together"} in ${s("time", 30) || "15 minutes"}. Vibe: ${s("mood", 40) || "playful"}.`,
        schema: `{"title":string,"instructions":[string],"how_to_win":string,"bonus":string}`,
      };
    case "gift_ideas":
      return {
        prompt: `Suggest 6 thoughtful gift ideas. Budget: ${s("budget", 30)} ${s("currency", 3)}. Partner likes: ${s("likes", 300)}. Occasion: ${s("occasion", 60) || "just because"}. Delivery: ${input["long_distance"] ? "must be sendable/deliverable or digital" : "in person"}. Include at least two that cost nothing.`,
        schema: `{"gifts":[{"title":string,"description":string,"estimated_cost":string,"personal_touch":string}]}`,
      };
    case "recap_story": {
      // Only aggregate counts — no private content.
      const stats = JSON.stringify(input["stats"] ?? {}).slice(0, 1500);
      return {
        prompt: `Write a short, warm year-in-review for a couple using ONLY these statistics: ${stats}. Names: ${s("names", 60)}. 3–4 sentences, celebratory, never comparing them to other couples, no invented events.`,
        schema: `{"title":string,"story":string}`,
      };
    }
  }
}

async function callModel(prompt: string, schema: string): Promise<unknown> {
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) throw new HttpError(503, "AI ideas aren't switched on yet. Try the built-in ideas instead.");
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("LOVEBIRD_AI_MODEL") ?? "claude-sonnet-5-5",
      max_tokens: 1500,
      system: SYSTEM,
      messages: [{ role: "user", content: `${prompt}\n\nRespond with JSON exactly matching: ${schema}` }],
    }),
  });
  if (!res.ok) {
    console.error("model error", res.status, await res.text());
    throw new HttpError(502, "Lovebird couldn't think of ideas right now. Please try again.");
  }
  const body = await res.json();
  const text: string = body?.content?.find((c: { type: string }) => c.type === "text")?.text ?? "";
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    throw new HttpError(502, "Lovebird got a little tongue-tied. Please try again.");
  }
}

Deno.serve(handle(async (req) => {
  const ctx = await authenticate(req);
  const circleId = await requireActiveCircle(ctx);

  const body = await req.json().catch(() => ({}));
  const mode = body?.mode as Mode;
  if (!MODES.includes(mode)) throw new HttpError(400, "Unknown request.");
  const input = (body?.input && typeof body.input === "object") ? body.input as Record<string, unknown> : {};

  // Per-circle daily quota (cost + abuse control).
  const limit = Number(Deno.env.get("LOVEBIRD_AI_DAILY_LIMIT") ?? "30");
  const today = new Date().toISOString().slice(0, 10);
  const { data: usage } = await ctx.admin.from("ai_usage").select("count").eq("circle_id", circleId).eq("day", today).maybeSingle();
  if ((usage?.count ?? 0) >= limit) {
    throw new HttpError(429, "You two have used today's AI ideas. The built-in ideas are always available!");
  }
  await ctx.admin.from("ai_usage").upsert({ circle_id: circleId, day: today, count: (usage?.count ?? 0) + 1 });

  const { prompt, schema } = buildPrompt(mode, input);
  const result = await callModel(prompt, schema);
  return json({ mode, result });
}));
