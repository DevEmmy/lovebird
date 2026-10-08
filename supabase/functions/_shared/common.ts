// Shared helpers for Lovebird edge functions (Deno runtime on Supabase).
import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2.45.4";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Friendly errors only — never leak stack traces or provider messages. */
export function errorResponse(err: unknown): Response {
  if (err instanceof HttpError) return json({ error: err.message }, err.status);
  console.error(err);
  return json({ error: "Something went wrong. Please try again." }, 500);
}

export interface Ctx {
  user: User;
  /** Client acting AS the user — RLS applies. */
  userClient: SupabaseClient;
  /** Service-role client — bypasses RLS. Use only after explicit checks. */
  admin: SupabaseClient;
}

export async function authenticate(req: Request): Promise<Ctx> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) throw new HttpError(401, "Please sign in again.");
  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) throw new HttpError(401, "Please sign in again.");
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  return { user: data.user, userClient, admin };
}

/** The caller's live circle id (via RLS-protected RPC), or a 403. */
export async function requireActiveCircle(ctx: Ctx): Promise<string> {
  const { data, error } = await ctx.userClient.rpc("current_circle_id");
  if (error || !data) throw new HttpError(403, "You need an active Love Circle for this.");
  const { data: circle } = await ctx.userClient.from("circles").select("status").eq("id", data).single();
  if (circle?.status !== "active") throw new HttpError(403, "Your Love Circle isn't active yet.");
  return data as string;
}

export function handle(fn: (req: Request) => Promise<Response>) {
  return async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
    try {
      return await fn(req);
    } catch (e) {
      return errorResponse(e);
    }
  };
}

export function clampStr(v: unknown, max: number): string {
  return typeof v === "string" ? v.slice(0, max).replace(/[\u0000-\u001f]/g, " ").trim() : "";
}
