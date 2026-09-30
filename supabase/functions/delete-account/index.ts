// delete-account — lets a signed-in user delete their OWN account. Required by
// the app stores for any app with accounts.
//
// The caller proves identity with their own JWT (the gateway verifies it). We
// resolve the user id from that token, then delete the auth user with the
// service-role admin API. FK `on delete cascade` removes the user's profile,
// friendships, thoughts and devices with it. A user can only ever delete
// themselves — the id comes from their token, never from the request body.
//
// Browsers may call it from ONE origin only: the web deletion page
// (docs/suppression-compte.html, GitHub Pages under dewdrop.heianenterprise.com), which Google Play
// requires for apps with accounts. CORS is no protection here — the Bearer
// token is — so allowing an origin grants nothing by itself; it only lets that
// page read the answer. The mobile app sends no Origin and is unaffected.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Moving the web page to another host means changing this origin AND the page.
const WEB_ORIGIN = "https://dewdrop.heianenterprise.com";

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  // CORS preflight from the web page (it sends Authorization + apikey).
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  // Only POST. A GET in a phishing link must never be able to trigger a
  // deletion just because the client attached the session automatically.
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405, cors);
  try {
    const token = (req.headers.get("Authorization") ?? "").replace(
      /^Bearer\s+/i,
      "",
    );
    if (!token) return json({ error: "no token" }, 401, cors);

    // Resolve (and validate) the caller from their own token.
    const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${token}` },
    });
    if (!userRes.ok) return json({ error: "invalid token" }, 401, cors);
    const id = (await userRes.json())?.id;
    if (!id) return json({ error: "no user" }, 401, cors);

    // Delete the auth user (service role) → cascades to all their rows.
    const del = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${id}`, {
      method: "DELETE",
      headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${SERVICE_ROLE}` },
    });
    if (!del.ok) return json({ error: "delete failed" }, 500, cors);
    return json({ deleted: true }, 200, cors);
  } catch (e) {
    console.error("delete-account error:", e);
    return json({ error: "internal_error" }, 500, cors);
  }
});

/** CORS headers for the web deletion page; none for any other origin. */
function corsHeaders(req: Request): Record<string, string> {
  const headers: Record<string, string> = { Vary: "Origin" };
  if (req.headers.get("Origin") !== WEB_ORIGIN) return headers;
  return {
    ...headers,
    "Access-Control-Allow-Origin": WEB_ORIGIN,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Max-Age": "600",
  };
}

function json(
  obj: unknown,
  status = 200,
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", ...extra },
  });
}
