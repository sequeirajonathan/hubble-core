import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";
import { requireEnv, unauthorized } from "./http.ts";

/** Service-role client: bypasses RLS. Use only after authorization is settled. */
export function adminClient(): SupabaseClient {
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Client scoped to the caller's JWT: every query goes through RLS as that user. */
export function userClient(req: Request): SupabaseClient {
  const authorization = req.headers.get("authorization") ?? "";
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_ANON_KEY"), {
    global: { headers: { authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Resolves the caller from the bearer token or throws 401. */
export async function requireUser(
  req: Request,
): Promise<{ user: User; client: SupabaseClient }> {
  const header = req.headers.get("authorization") ?? "";
  if (!header.toLowerCase().startsWith("bearer ")) throw unauthorized("missing bearer token");
  const client = userClient(req);
  const { data, error } = await client.auth.getUser(header.slice(7));
  if (error || !data.user) throw unauthorized("invalid session");
  return { user: data.user, client };
}
