import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-homagram-webhook-secret",
};

let cachedAccessToken: { value: string; expiresAt: number } | null = null;

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToBytes(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function getGoogleAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
  token_uri?: string;
}): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.value;
  }

  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64Url(new TextEncoder().encode(JSON.stringify({
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    iat: now,
    exp: now + 3600,
  })));
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned),
  ));
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const tokenResponse = await fetch(serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const tokenBody = await tokenResponse.json();
  if (!tokenResponse.ok || !tokenBody.access_token) {
    throw new Error(`Google OAuth token exchange failed (${tokenResponse.status})`);
  }
  cachedAccessToken = {
    value: tokenBody.access_token,
    expiresAt: Date.now() + Number(tokenBody.expires_in ?? 3600) * 1000,
  };
  return cachedAccessToken.value;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405, headers: corsHeaders });
  }

  const expectedSecret = Deno.env.get("HOMAGRAM_PUSH_WEBHOOK_SECRET");
  const suppliedSecret = req.headers.get("x-homagram-webhook-secret");
  if (!expectedSecret || suppliedSecret !== expectedSecret) {
    // Safe diagnostics only: never log or return either secret.
    console.warn("Webhook authentication diagnostic", {
      expectedSecretPresent: Boolean(expectedSecret),
      suppliedSecretPresent: suppliedSecret !== null,
      expectedLength: expectedSecret?.length ?? 0,
      suppliedLength: suppliedSecret?.length ?? 0,
      exactMatch: Boolean(expectedSecret && suppliedSecret === expectedSecret),
    });
    return Response.json({ error: "Unauthorized" }, { status: 401, headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const row = payload?.record;
    if (payload?.type !== "INSERT" || payload?.table !== "notifications" ||
        payload?.schema !== "public" || !row?.id || !row?.recipient_id) {
      return Response.json({ ignored: true }, { status: 200, headers: corsHeaders });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const firebaseJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!supabaseUrl || !serviceRoleKey || !firebaseJson) {
      throw new Error("Required server configuration is missing");
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: preference } = await admin
      .from("user_notification_preferences")
      .select("social_enabled,messages_enabled")
      .eq("user_id", row.recipient_id)
      .maybeSingle();

    const isMessage = ["message_new", "support_message", "support_reply"].includes(String(row.type ?? ""));
    if (preference && (isMessage ? preference.messages_enabled === false : preference.social_enabled === false)) {
      return Response.json({ skipped: "notifications_disabled" }, { status: 200, headers: corsHeaders });
    }

    const { data: installations, error: installationsError } = await admin
      .from("user_push_tokens")
      .select("fid")
      .eq("user_id", row.recipient_id);
    if (installationsError) throw installationsError;
    if (!installations?.length) {
      return Response.json({ sent: 0, reason: "no_registered_devices" }, { status: 200, headers: corsHeaders });
    }

    const serviceAccount = JSON.parse(firebaseJson);
    if (!serviceAccount.project_id || !serviceAccount.client_email || !serviceAccount.private_key) {
      throw new Error("Firebase service account JSON is incomplete");
    }
    const accessToken = await getGoogleAccessToken(serviceAccount);
    const title = "HomaGram";
    const body = String(row.message ?? "اعلان جدیدی دارید").slice(0, 240);
    let sent = 0;
    const failures: string[] = [];

    for (const installation of installations) {
      const fid = String(installation.fid ?? "");
      if (!fid) continue;
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(serviceAccount.project_id)}/messages:send`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              fid,
              notification: { title, body },
              data: {
                notification_id: String(row.id),
                type: String(row.type ?? ""),
                entity_id: String(row.entity_id ?? ""),
                entity_type: String(row.entity_type ?? ""),
              },
              android: { priority: "high" },
            },
          }),
        },
      );
      if (response.ok) {
        sent++;
      } else {
        const errorText = await response.text();
        failures.push(`${response.status}:${errorText.slice(0, 180)}`);
        if (response.status === 404 || errorText.includes("UNREGISTERED")) {
          await admin.from("user_push_tokens").delete().eq("fid", fid);
        }
      }
    }

    return Response.json({ sent, failed: failures.length, failures }, {
      status: 200,
      headers: corsHeaders,
    });
  } catch (error) {
    console.error("Push delivery failed:", error);
    return Response.json({ error: "Push delivery failed" }, {
      status: 500,
      headers: corsHeaders,
    });
  }
});
