// POST /functions/v1/delete-account   body: { confirm: "DELETE" }
// Secure account deletion (brief §41). Order matters:
//  1. End the live Love Circle through the normal RPC (partner gets the neutral notice + 30-day window).
//  2. Remove the user's own avatar files.
//  3. Delete the auth user -> cascades to profile, memberships, notifications, own reactions…
//     Shared rows authored by the user keep author_id = null (on delete set null) so the partner's
//     shared history is not ripped apart; they are purged with the circle after the window.
import { authenticate, handle, HttpError, json } from "../_shared/common.ts";

Deno.serve(handle(async (req) => {
  const ctx = await authenticate(req);
  const body = await req.json().catch(() => ({}));
  if (body?.confirm !== "DELETE") throw new HttpError(400, "Please confirm account deletion.");

  const { data: circleId } = await ctx.userClient.rpc("current_circle_id");
  if (circleId) {
    const { data: circle } = await ctx.userClient.from("circles").select("status").eq("id", circleId).single();
    if (circle?.status === "active") {
      const { error } = await ctx.userClient.rpc("end_circle", { p_circle: circleId });
      if (error) throw new HttpError(500, "Couldn't close your Love Circle. Please try again.");
    } else if (circle?.status === "pending") {
      await ctx.userClient.rpc("cancel_pending_circle", { p_circle: circleId });
    }
  }

  const { data: files } = await ctx.admin.storage.from("avatars").list(ctx.user.id);
  if (files?.length) {
    await ctx.admin.storage.from("avatars").remove(files.map((f) => `${ctx.user.id}/${f.name}`));
  }

  const { error } = await ctx.admin.auth.admin.deleteUser(ctx.user.id);
  if (error) throw new HttpError(500, "Couldn't delete your account. Please try again.");
  return json({ deleted: true });
}));
