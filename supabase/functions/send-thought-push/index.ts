// send-thought-push — sends an FCM push ("X a pensé à toi") when a thought is
// inserted. Triggered by a Supabase database webhook on INSERT into
// public.thoughts. Respects the recipient's quiet hours and the anonymity flag.
//
// Required secret: FIREBASE_SERVICE_ACCOUNT = the Firebase service-account JSON
// (string). SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// Known limitation: quiet hours are compared in UTC (no per-user timezone yet).

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FIREBASE_SERVICE_ACCOUNT = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");

interface Thought {
  id: string;
  sender_id: string;
  recipient_id: string;
  is_anonymous: boolean;
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const t: Thought = payload.record;
    if (!t?.recipient_id) return json({ ok: false, reason: "no record" });

    const recipient = (await rest(
      `profiles?id=eq.${t.recipient_id}&select=quiet_start,quiet_end`,
    ))[0];
    if (recipient && inQuietHours(recipient.quiet_start, recipient.quiet_end)) {
      return json({ skipped: "quiet hours" });
    }

    let name = "Quelqu'un";
    if (!t.is_anonymous) {
      const s = (await rest(
        `profiles?id=eq.${t.sender_id}&select=display_name,handle`,
      ))[0];
      if (s) name = s.display_name?.length ? s.display_name : `@${s.handle}`;
    }

    const devices = await rest(`devices?user_id=eq.${t.recipient_id}&select=token`);
    if (!devices.length) return json({ sent: 0, reason: "no devices" });
    if (!FIREBASE_SERVICE_ACCOUNT) {
      return json({ error: "FIREBASE_SERVICE_ACCOUNT not set" });
    }

    const sa = JSON.parse(FIREBASE_SERVICE_ACCOUNT);
    const accessToken = await getAccessToken(sa);
    const body = `${name} a pensé à toi ✨`;

    let sent = 0;
    for (const d of devices) {
      if (await sendFcm(sa.project_id, accessToken, d.token, body)) sent++;
    }
    return json({ sent });
  } catch (e) {
    return json({ error: String(e) });
  }
});

async function rest(query: string): Promise<Array<Record<string, unknown>>> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${query}`, {
    headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${SERVICE_ROLE}` },
  });
  return res.ok ? await res.json() : [];
}

function inQuietHours(start: number | null, end: number | null): boolean {
  if (start == null || end == null) return false;
  const h = new Date().getUTCHours();
  return start <= end ? h >= start && h < end : h >= start || h < end;
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sendFcm(
  projectId: string,
  accessToken: string,
  token: string,
  body: string,
): Promise<boolean> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: { token, notification: { title: "DewDrop", body } },
      }),
    },
  );
  return res.ok;
}

// --- Google OAuth2 access token from a service account (RS256 JWT) ----------
async function getAccessToken(sa: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned =
    `${enc({ alg: "RS256", typ: "JWT" })}.` +
    `${enc({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })}`;

  const key = await importKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:
      "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" + jwt,
  });
  return (await res.json()).access_token;
}

async function importKey(pem: string): Promise<CryptoKey> {
  const der = Uint8Array.from(
    atob(
      pem
        .replace(/-----BEGIN PRIVATE KEY-----/, "")
        .replace(/-----END PRIVATE KEY-----/, "")
        .replace(/\s+/g, ""),
    ),
    (c) => c.charCodeAt(0),
  );
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
