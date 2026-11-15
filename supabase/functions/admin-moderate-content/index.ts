import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const url = Deno.env.get("SUPABASE_URL"), anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"), authorization = req.headers.get("Authorization");
  if (!url || !anonKey || !serviceKey || !authorization) return json(500, { error: "server_configuration_error" });
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: actorResult, error: actorError } = await userClient.auth.getUser();
  const actor = actorResult.user;
  if (actorError || !actor) return json(401, { error: "unauthorized" });
  const { data: isAdmin, error: adminCheckError } = await userClient.rpc("is_current_user_admin");
  if (adminCheckError || isAdmin !== true) return json(403, { error: "admin_required" });
  let payload: Record<string, unknown>;
  try { payload = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const action = typeof payload.action === "string" ? payload.action : "";
  const targetUserId = typeof payload.user_id === "string" ? payload.user_id.trim() : "";
  const postId = typeof payload.post_id === "string" ? payload.post_id.trim() : "";
  const adminClient = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  async function audit(target: string | null, name: string, metadata: Record<string, unknown>) {
    const { error } = await adminClient.rpc("admin_record_moderation_action", { p_actor_id: actor.id, p_target_user_id: target, p_action: name, p_metadata: metadata });
    if (error) throw error;
  }
  async function notify(target: string, message: string, entityId: string | null = null) {
    const { error } = await adminClient.from("notifications").insert({
      recipient_id: target, actor_id: actor.id, type: "moderation_notice",
      entity_id: entityId, entity_type: "moderation", message: message.slice(0, 1000),
    });
    return !error;
  }
  if (action === "delete_post") {
    if (!uuidPattern.test(postId)) return json(400, { error: "invalid_post_id" });
    const { data: post, error: readError } = await adminClient.from("posts").select("id,author_id,media_path,cover_path").eq("id", postId).maybeSingle();
    if (readError || !post) return json(404, { error: "post_not_found" });
    const { error: deleteError } = await adminClient.from("posts").delete().eq("id", postId);
    if (deleteError) return json(500, { error: "post_delete_failed", message: deleteError.message });
    const paths = [post.media_path, post.cover_path].filter((x): x is string => typeof x === "string" && x.length > 0);
    let storageCleanup = true;
    if (paths.length) { const { error } = await adminClient.storage.from("post-media").remove(paths); storageCleanup = !error; }
    const notificationSent = await notify(post.author_id, "یکی از محتواهای شما پس از بررسی مدیران، به دلیل مغایرت با مقررات هماگرام حذف شد. برای پیگیری یا ارائه توضیح، با پشتیبانی در ارتباط باشید.", postId);
    await audit(post.author_id, "content_removed_by_admin", { content_type: "post_or_reel", content_id: postId, storage_cleanup: storageCleanup });
    return json(200, { success: true, deleted_post_id: postId, storage_cleanup: storageCleanup, notification_sent: notificationSent });
  }
  if (!uuidPattern.test(targetUserId)) return json(400, { error: "invalid_user_id" });
  if (targetUserId === actor.id && (action === "ban_user" || action === "warn_user")) return json(400, { error: "cannot_moderate_self" });
  const { data: targetResult, error: targetError } = await adminClient.auth.admin.getUserById(targetUserId);
  if (targetError || !targetResult.user) return json(404, { error: "user_not_found" });
  const { data: protectedAccount, error: protectedError } = await adminClient.rpc("admin_is_protected_account", { p_user_id: targetUserId });
  if (protectedError) return json(500, { error: "protection_check_failed" });
  if (protectedAccount === true) return json(403, { error: "protected_admin_account" });
  if (action === "remove_profile_content") {
    const { data: profile, error: profileReadError } = await adminClient.from("profiles")
      .select("avatar_path").eq("id", targetUserId).maybeSingle();
    if (profileReadError || !profile) return json(404, { error: "profile_not_found" });
    const { error: profileUpdateError } = await adminClient.from("profiles")
      .update({ bio: null, website_url: null, avatar_path: null, updated_at: new Date().toISOString() })
      .eq("id", targetUserId);
    if (profileUpdateError) return json(500, { error: "profile_cleanup_failed" });
    let avatarCleanup = true;
    if (typeof profile.avatar_path === "string" && profile.avatar_path.length > 0) {
      const { error } = await adminClient.storage.from("avatars").remove([profile.avatar_path]);
      avatarCleanup = !error;
    }
    const notificationSent = await notify(targetUserId,
      "اطلاعات نمایشی پروفایل شما پس از بررسی مدیران، به دلیل مغایرت با مقررات هماگرام پاک‌سازی شد. می‌توانید اطلاعات مجاز را دوباره ثبت کنید.");
    await audit(targetUserId, "profile_content_removed_by_admin", { avatar_cleanup: avatarCleanup });
    return json(200, { success: true, avatar_cleanup: avatarCleanup, notification_sent: notificationSent });
  }

  if (action === "warn_user") {
    const message = typeof payload.message === "string" ? payload.message.trim() : "";
    if (message.length < 8 || message.length > 900) return json(400, { error: "invalid_warning_message" });
    const notificationSent = await notify(targetUserId, message);
    if (!notificationSent) return json(500, { error: "warning_delivery_failed" });
    await audit(targetUserId, "user_warned_by_admin", { message });
    return json(200, { success: true, notification_sent: true });
  }
  if (action === "ban_user") {
    const duration = typeof payload.duration === "string" ? payload.duration : "168h";
    if (!new Set(["24h", "168h", "720h", "876000h"]).has(duration)) return json(400, { error: "invalid_ban_duration" });
    const { error } = await adminClient.auth.admin.updateUserById(targetUserId, { ban_duration: duration });
    if (error) return json(500, { error: "ban_failed", message: error.message });
    const label = duration === "24h" ? "۲۴ ساعت" : duration === "168h" ? "۷ روز" : duration === "720h" ? "۳۰ روز" : "به‌صورت بلندمدت";
    const notificationSent = await notify(targetUserId, `دسترسی حساب شما به دلیل نقض مقررات هماگرام برای ${label} مسدود شد. برای درخواست بازبینی با پشتیبانی تماس بگیرید.`);
    await audit(targetUserId, "user_banned_by_admin", { duration });
    return json(200, { success: true, notification_sent: notificationSent });
  }
  if (action === "unban_user") {
    const { error } = await adminClient.auth.admin.updateUserById(targetUserId, { ban_duration: "none" });
    if (error) return json(500, { error: "unban_failed", message: error.message });
    const notificationSent = await notify(targetUserId, "محدودیت دسترسی حساب شما توسط تیم هماگرام برداشته شد.");
    await audit(targetUserId, "user_unbanned_by_admin", {});
    return json(200, { success: true, notification_sent: notificationSent });
  }
  return json(400, { error: "unsupported_action" });
});
