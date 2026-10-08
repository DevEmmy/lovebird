// POST /functions/v1/call-token   body: { video?: boolean }
// Mints a short-lived LiveKit token for room "circle-{id}" — only for live members
// of an ACTIVE circle, so nobody else can ever join a couple's call.
// Env: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
import { AccessToken } from "npm:livekit-server-sdk@2.6.1";
import { authenticate, handle, HttpError, json, requireActiveCircle } from "../_shared/common.ts";

Deno.serve(handle(async (req) => {
  const ctx = await authenticate(req);
  const circleId = await requireActiveCircle(ctx);
  const url = Deno.env.get("LIVEKIT_URL");
  const key = Deno.env.get("LIVEKIT_API_KEY");
  const secret = Deno.env.get("LIVEKIT_API_SECRET");
  if (!url || !key || !secret) throw new HttpError(503, "Voice isn't set up yet. You can still chat while you watch!");

  const { data: profile } = await ctx.userClient.from("profiles").select("display_name").eq("id", ctx.user.id).single();
  const at = new AccessToken(key, secret, {
    identity: ctx.user.id,
    name: profile?.display_name ?? "Lovebird",
    ttl: "2h",
  });
  at.addGrant({
    room: `circle-${circleId}`,
    roomJoin: true,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
    roomCreate: true,
  });
  return json({ url, token: await at.toJwt(), room: `circle-${circleId}` });
}));
