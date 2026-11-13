import { createClient } from "npm:@supabase/supabase-js@2";

let cachedAccessToken: { value: string; expiresAt: number } | null = null;

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToBytes(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "").replace(/\s/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function getGoogleAccessToken(account: {
  client_email: string; private_key: string; token_uri?: string;
}): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.value;
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64Url(new TextEncoder().encode(JSON.stringify({
    iss: account.client_email, sub: account.client_email,
    aud: account.token_uri ?? "https://oauth2.googleapis.com/token",
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    iat: now, exp: now + 3600,
  })));
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToBytes(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned),
  ));
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const response = await fetch(account.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion,
    }),
  });
  const result = await response.json();
  if (!response.ok || !result.access_token) throw new Error("Google OAuth token exchange failed");
  cachedAccessToken = {
    value: result.access_token,
    expiresAt: Date.now() + Number(result.expires_in ?? 3600) * 1000,
  };
  return cachedAccessToken.value;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405 });

  const expectedSecret = Deno.env.get("HOMAGRAM_PUSH_WEBHOOK_SECRET");
  if (!expectedSecret || req.headers.get("x-homagram-webhook-secret") !== expectedSecret) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const payload = await req.json();
    const row = payload?.record;
    if (payload?.type !== "INSERT" || payload?.table !== "notifications" ||
        payload?.schema !== "public" || !row?.id || !row?.recipient_id) {
      return Response.json({ ignored: true });
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const firebaseJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!url || !serviceKey || !firebaseJson) throw new Error("Server configuration is missing");

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: prefs } = await admin.from("user_notification_preferences")
      .select("social_enabled,messages_enabled").eq("user_id", row.recipient_id).maybeSingle();
    const messageNotification = row.type === "message_new";
    if (prefs && (messageNotification ? prefs.messages_enabled === false : prefs.social_enabled === false)) {
      return Response.json({ sent: 0, skipped: "notifications_disabled" });
    }

    const { data: devices, error } = await admin.from("user_push_tokens")
      .select("fid").eq("user_id", row.recipient_id);
    if (error) throw error;
    if (!devices?.length) return Response.json({ sent: 0, reason: "no_registered_devices" });

    const account = JSON.parse(firebaseJson);
    if (!account.project_id || !account.client_email || !account.private_key) {
      throw new Error("Firebase service account JSON is incomplete");
    }
    const accessToken = await getGoogleAccessToken(account);
    let sent = 0;
    const failures: string[] = [];

    for (const device of devices) {
      const fid = String(device.fid ?? "");
      if (!fid) continue;
      const result = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          body: JSON.stringify({ message: {
            fid,
            notification: { title: "HomaGram", body: String(row.message ?? "اعلان جدیدی دارید").slice(0, 240) },
            data: {
              notification_id: String(row.id), type: String(row.type ?? ""),
              entity_id: String(row.entity_id ?? ""), entity_type: String(row.entity_type ?? ""),
            },
            android: { priority: "high" },
          } }),
        },
      );
      if (result.ok) sent++;
      else {
        const details = await result.text();
        failures.push(`${result.status}:${details.slice(0, 160)}`);
        if (result.status === 404 || details.includes("UNREGISTERED")) {
          await admin.from("user_push_tokens").delete().eq("fid", fid);
        }
      }
    }
    return Response.json({ sent, failed: failures.length, failures });
  } catch (error) {
    console.error("Push delivery failed:", error);
    return Response.json({ error: "Push delivery failed" }, { status: 500 });
  }
});
