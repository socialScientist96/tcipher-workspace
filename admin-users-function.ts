// Supabase Edge Function: admin-users
// Lets admins create logins, reset passwords, turn accounts off and on, and delete accounts
// from the workspace's admin panel. Paste this into Supabase > Edge Functions >
// Deploy a new function > Via Editor, name it exactly: admin-users
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function secretKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    if (keys && keys.default) return keys.default;
  } catch (_) { /* fall back to the legacy key */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // Who is calling? Must be a signed-in, active admin.
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Sign in again to manage users." }, 401);
    const { data: who, error: whoErr } = await admin.auth.getUser(token);
    if (whoErr || !who?.user) return json({ error: "Your session has expired. Sign in again." }, 401);
    const { data: me } = await admin.from("profiles").select("is_admin,is_active").eq("id", who.user.id).single();
    if (!me?.is_admin || !me?.is_active) return json({ error: "Only admins can manage users." }, 403);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");

    if (action === "create") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      const full_name = String(body.full_name ?? "").trim();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Enter a valid email address." }, 400);
      if (password.length < 8) return json({ error: "Passwords need at least 8 characters." }, 400);
      if (!full_name) return json({ error: "Enter the person’s name." }, 400);

      const { data, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { full_name },
      });
      if (error) return json({ error: error.message }, 400);
      const id = data.user!.id;

      const profile: Record<string, unknown> = { full_name };
      for (const k of ["title", "phone", "vertical", "role_id", "joined_on", "color"]) {
        if (body[k] !== undefined && body[k] !== "") profile[k] = body[k];
      }
      if (typeof body.is_admin === "boolean") profile.is_admin = body.is_admin;
      const { error: pErr } = await admin.from("profiles").update(profile).eq("id", id);
      if (pErr) return json({ id, warning: "Login created, but profile details weren’t saved: " + pErr.message });
      return json({ id });
    }

    const id = String(body.id ?? "");
    if (!id) return json({ error: "Missing user id." }, 400);

    if (action === "set_password") {
      const password = String(body.password ?? "");
      if (password.length < 8) return json({ error: "Passwords need at least 8 characters." }, 400);
      const { error } = await admin.auth.admin.updateUserById(id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (action === "set_active") {
      if (id === who.user.id && !body.active) return json({ error: "You can’t turn off your own account." }, 400);
      const { error } = await admin.auth.admin.updateUserById(id, { ban_duration: body.active ? "none" : "876000h" });
      if (error) return json({ error: error.message }, 400);
      await admin.from("profiles").update({ is_active: !!body.active }).eq("id", id);
      return json({ ok: true });
    }

    if (action === "delete") {
      if (id === who.user.id) return json({ error: "You can’t delete your own account." }, 400);
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500);
  }
});
