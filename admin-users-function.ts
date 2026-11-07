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

// how this session signed in: "aal2" means the two-step code was entered
function aalOf(jwt: string): string {
  try { const p = jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"); return String(JSON.parse(atob(p + "===".slice((p.length + 3) % 4))).aal || "aal1"); }
  catch (_) { return "aal1"; }
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
    // an admin who has two-step sign-in must have used it in this session, so a stolen password alone can't manage users
    const { data: mine } = await admin.auth.admin.mfa.listFactors({ userId: who.user.id });
    if ((mine?.factors ?? []).some((f: { status: string }) => f.status === "verified") && aalOf(token) !== "aal2")
      return json({ error: "Enter your two-step sign-in code first: sign out, then sign in again." }, 403);

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

    if (action === "reset_mfa") {
      // for someone who lost the phone with their authenticator app: they sign in with the password until they set it up again
      const { data, error } = await admin.auth.admin.mfa.listFactors({ userId: id });
      if (error) return json({ error: error.message }, 400);
      const factors = data?.factors ?? [];
      for (const f of factors) {
        const r = await admin.auth.admin.mfa.deleteFactor({ id: f.id, userId: id });
        if (r.error) return json({ error: r.error.message }, 400);
      }
      return json({ ok: true, removed: factors.length });
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
