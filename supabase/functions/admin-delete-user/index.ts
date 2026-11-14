import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization");

  if (!url || !anonKey || !serviceKey || !authorization) {
    return json(500, { error: "server_configuration_error" });
  }

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: actorResult, error: actorError } = await userClient.auth.getUser();
  const actor = actorResult.user;
  if (actorError || !actor) return json(401, { error: "unauthorized" });

  const { data: isAdmin, error: adminCheckError } = await userClient.rpc("is_current_user_admin");
  if (adminCheckError || isAdmin !== true) return json(403, { error: "admin_required" });

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const targetUserId = typeof payload.user_id === "string" ? payload.user_id.trim() : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(targetUserId)) {
    return json(400, { error: "invalid_user_id" });
  }
  if (targetUserId === actor.id) return json(400, { error: "cannot_delete_current_admin" });

  const adminClient = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: targetResult, error: targetError } = await adminClient.auth.admin.getUserById(targetUserId);
  if (targetError || !targetResult.user) return json(404, { error: "user_not_found" });

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(targetUserId);
  if (deleteError) return json(500, { error: "delete_failed", message: deleteError.message });

  return json(200, { success: true, deleted_user_id: targetUserId });
});
