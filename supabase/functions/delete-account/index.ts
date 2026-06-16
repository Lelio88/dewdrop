// delete-account — lets a signed-in user delete their OWN account. Required by
// the app stores for any app with accounts.
//
// The caller proves identity with their own JWT (the gateway verifies it). We
// resolve the user id from that token, then delete the auth user with the
// service-role admin API. FK `on delete cascade` removes the user's profile,
// friendships, thoughts and devices with it. A user can only ever delete
// themselves — the id comes from their token, never from the request body.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const token = (req.headers.get("Authorization") ?? "").replace(
      /^Bearer\s+/i,
      "",
    );
    if (!token) return json({ error: "no token" }, 401);

    // Resolve (and validate) the caller from their own token.
    const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${token}` },
    });
    if (!userRes.ok) return json({ error: "invalid token" }, 401);
    const id = (await userRes.json())?.id;
    if (!id) return json({ error: "no user" }, 401);

    // Delete the auth user (service role) → cascades to all their rows.
    const del = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${id}`, {
      method: "DELETE",
      headers: { apikey: SERVICE_ROLE, Authorization: `Bearer ${SERVICE_ROLE}` },
    });
    if (!del.ok) return json({ error: "delete failed" }, 500);
    return json({ deleted: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
