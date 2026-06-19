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

// The fixed style lists the app offers (mirror of thought_style.dart). The
// sender can only pick from these — any other value is ignored, so a push the
// RECIPIENT sees can never contain arbitrary attacker-controlled text.
// Mirror of kThoughtEmojis in thought_style.dart — keep byte-for-byte in sync.
const ALLOWED_EMOJIS = new Set([
  "",
  // Cœurs & tendresse
  "💭", "💗", "💖", "💕", "💛", "🤍", "🫶", "🥰", "🤗",
  // Fleurs & nature douce
  "🌸", "🌼", "🌷", "🌻", "💐", "🍀", "🍃", "🦋",
  // Ciel & lumière
  "✨", "💫", "🌟", "🌠", "⭐", "☀️", "🌙", "🌈", "☁️",
  // Cosy
  "🫧", "☕",
]);
// Mirror of kThoughtBodies in thought_style.dart — keep byte-for-byte in sync.
const ALLOWED_BODIES = new Set([
  "%s a pensé à toi",
  "%s pense fort à toi",
  "%s t'envoie une pensée",
  "%s a une pensée pour toi",
  "Une pensée de %s",
  "Tu es dans les pensées de %s",
  "%s t'envoie de la douceur",
  "%s pense à toi en ce moment",
  "Un petit coucou de %s",
  "Une douce pensée de %s",
  "%s ne t'oublie pas",
  "%s t'envoie de bonnes ondes",
  "%s t'envoie un câlin",
]);

interface Thought {
  id: string;
  sender_id: string;
  recipient_id: string;
  is_anonymous: boolean;
  group_id?: string | null;
}

Deno.serve(async (req) => {
  // Only the DB webhook (service_role) may call this — otherwise anyone with the
  // public anon key could spam push notifications. We trust the JWT role claim
  // because the function gateway (verify_jwt) has already verified the signature.
  if (!callerIsServiceRole(req)) {
    return json({ error: "forbidden" }, 403);
  }
  try {
    const payload = await req.json();
    const t: Thought = payload.record;
    if (!t?.recipient_id) return json({ ok: false, reason: "no record" });

    const recipient = (await rest(
      `profiles?id=eq.${t.recipient_id}&select=notifications_enabled,quiet_start,quiet_end,quiet_tz`,
    ))[0];
    // Master push switch (Settings toggle): when off, never push to this user.
    if (recipient && recipient.notifications_enabled === false) {
      return json({ skipped: "notifications disabled" });
    }
    // Quiet hours no longer SKIP the push — they deliver it SILENTLY (no sound,
    // no vibration). The grouped notifications pile up quietly, so the user sees
    // "X pensées" when they wake — no catch-up cron needed.
    const silent = recipient
      ? inQuietHours(
        recipient.quiet_start as number | null,
        recipient.quiet_end as number | null,
        recipient.quiet_tz as string | null,
      )
      : false;

    // Always read the sender's profile: even an anonymous thought keeps the
    // sender's chosen style (lead emoji / phrasing / tail emoji), just with
    // « Quelqu'un » instead of their name.
    const sender = (await rest(
      `profiles?id=eq.${t.sender_id}&select=display_name,handle,thought_style`,
    ))[0];
    let name = "Quelqu'un";
    if (!t.is_anonymous && sender) {
      name = sender.display_name?.length ? sender.display_name : `@${sender.handle}`;
    }

    const devices = await rest(`devices?user_id=eq.${t.recipient_id}&select=token`);
    if (!devices.length) return json({ sent: 0, reason: "no devices" });
    if (!FIREBASE_SERVICE_ACCOUNT) {
      return json({ error: "FIREBASE_SERVICE_ACCOUNT not set" });
    }

    // No server-side throttle in v2: every pensée is delivered as a data message
    // and the app GROUPS them (one child per sender) + alerts only once. So we
    // never drop a pensée — the grouping replaces the old 1-push-per-60s cap.
    const sa = JSON.parse(FIREBASE_SERVICE_ACCOUNT);
    const accessToken = await getAccessToken(sa);
    // Validate the sender-controlled style against the fixed lists before it
    // reaches the recipient's notification.
    const style = (sender?.thought_style ?? {}) as {
      lead?: string;
      body?: string;
      tail?: string;
    };
    const safeBody = style.body && ALLOWED_BODIES.has(style.body)
      ? style.body
      : "%s a pensé à toi";
    const safeLead = style.lead && ALLOWED_EMOJIS.has(style.lead)
      ? style.lead
      : "";
    const safeTail = style.tail !== undefined && ALLOWED_EMOJIS.has(style.tail)
      ? style.tail
      : "✨";
    // A group pensée notifies each member "<X> a pensé au groupe <Y>" and groups
    // under the GROUP (one child per group). An individual pensée uses the
    // sender's custom phrase and groups under the sender (anonymous → "anon").
    let label = name;
    let senderKey = t.is_anonymous ? "anon" : t.sender_id;
    let phrase = safeBody.replace("%s", name);
    if (t.group_id) {
      const grp = (await rest(`groups?id=eq.${t.group_id}&select=name`))[0];
      label = (grp?.name as string | undefined) ?? "un groupe";
      senderKey = `g_${t.group_id}`;
      phrase = `${name} a pensé au groupe`;
    }
    const body = [safeLead, phrase, safeTail]
      .filter((x) => x && x.length)
      .join(" ");

    const data: Record<string, string> = {
      type: "thought",
      sender_key: senderKey,
      label,
      message: body,
      silent: silent ? "1" : "0",
    };
    let sent = 0;
    for (const d of devices) {
      if (await sendFcm(sa.project_id, accessToken, d.token, data)) sent++;
    }
    return json({ sent });
  } catch (e) {
    console.error("send-thought-push error:", e);
    return json({ error: "internal_error" }, 500);
  }
});

// True only for a service_role caller. Accepts the exact service-role env key
// (covers any format) OR a JWT whose `role` claim is service_role (the legacy
// key the DB webhook sends). The gateway already verified the signature, so the
// role claim is trustworthy; the public anon key (role "anon") is rejected.
function callerIsServiceRole(req: Request): boolean {
  const auth = req.headers.get("Authorization") ?? "";
  if (auth === `Bearer ${SERVICE_ROLE}`) return true;
  const token = auth.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return false;
  const part = token.split(".")[1];
  if (!part) return false;
  try {
    const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
    const pad = b64.length % 4 ? "=".repeat(4 - (b64.length % 4)) : "";
    return JSON.parse(atob(b64 + pad)).role === "service_role";
  } catch {
    return false;
  }
}

async function rest(query: string): Promise<Array<Record<string, unknown>>> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${query}`, {
    headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${SERVICE_ROLE}` },
  });
  return res.ok ? await res.json() : [];
}

function inQuietHours(
  start: number | null,
  end: number | null,
  tz: string | null,
): boolean {
  if (start == null || end == null) return false;
  const h = currentHour(tz);
  return start <= end ? h >= start && h < end : h >= start || h < end;
}

// The recipient's current hour (0-23) in their IANA timezone (DST-correct via
// Intl). Falls back to UTC when the timezone is missing or invalid.
function currentHour(tz: string | null): number {
  if (!tz) return new Date().getUTCHours();
  try {
    const s = new Intl.DateTimeFormat("en-GB", {
      timeZone: tz,
      hour: "2-digit",
      hourCycle: "h23",
    }).format(new Date());
    const h = Number.parseInt(s, 10);
    return Number.isNaN(h) ? new Date().getUTCHours() : h % 24;
  } catch {
    return new Date().getUTCHours();
  }
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
  data: Record<string, string>,
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
        message: {
          token,
          // DATA-ONLY: the app builds the grouped "DewDrop" notification itself
          // (one child per sender + a single alerting summary). `priority: high`
          // wakes the background handler even when the app is killed.
          data,
          android: { priority: "high" },
        },
      }),
    },
  );
  if (res.ok) return true;
  // FCM returns 404 / UNREGISTERED for stale tokens — prune them so the devices
  // table doesn't accumulate dead tokens (and we stop retrying them).
  if (res.status === 404) {
    await fetch(
      `${SUPABASE_URL}/rest/v1/devices?token=eq.${encodeURIComponent(token)}`,
      {
        method: "DELETE",
        headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${SERVICE_ROLE}` },
      },
    );
  }
  return false;
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
