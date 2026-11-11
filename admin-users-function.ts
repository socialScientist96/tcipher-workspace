// Supabase Edge Function: admin-users
// Lets admins create logins, reset passwords, turn accounts off and on, and delete accounts
// from the workspace's admin panel. Paste this into Supabase > Edge Functions >
// Deploy a new function > Via Editor, name it exactly: admin-users
//
// Client portal (2026-11bt): admins and a client's account owner can also
//   invite_client  — create (or re-send) a portal login for someone at that client and email them a set-password link
//   client_access  — turn a portal login off or on
// A portal login is never a staff login: the database keeps it out of everything except the portal.
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

const APP_URL = Deno.env.get("APP_URL") ?? "https://internal.tcipher.com/";
const randomPassword = () => Array.from(crypto.getRandomValues(new Uint8Array(24)), (b) => b.toString(16).padStart(2, "0")).join("");

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

    // Who is calling? Must be a signed-in, active staff member (admin for everything except the client portal actions).
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Sign in again to manage users." }, 401);
    const { data: who, error: whoErr } = await admin.auth.getUser(token);
    if (whoErr || !who?.user) return json({ error: "Your session has expired. Sign in again." }, 401);
    const { data: me } = await admin.from("profiles").select("is_admin,is_active,client_id,full_name").eq("id", who.user.id).single();
    if (!me?.is_active || me?.client_id) return json({ error: "Only the team can manage users." }, 403);
    // an admin who has two-step sign-in must have used it in this session, so a stolen password alone can't manage users
    if (me.is_admin) {
      const { data: mine } = await admin.auth.admin.mfa.listFactors({ userId: who.user.id });
      if ((mine?.factors ?? []).some((f: { status: string }) => f.status === "verified") && aalOf(token) !== "aal2")
        return json({ error: "Enter your two-step sign-in code first: sign out, then sign in again." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");

    // ---------- client portal: admins, or the client's account owner ----------
    const mayManageClient = async (clientId: string) => {
      if (me.is_admin) return true;
      const { data: c } = await admin.from("clients").select("owner_id").eq("id", clientId).maybeSingle();
      return !!c && c.owner_id === who.user.id;
    };
    if (action === "invite_client") {
      const client_id = String(body.client_id ?? "");
      const email = String(body.email ?? "").trim().toLowerCase();
      const full_name = String(body.full_name ?? "").trim().slice(0, 120);
      const phone = String(body.phone ?? "").trim().slice(0, 40);
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Enter a valid email address." }, 400);
      if (!full_name) return json({ error: "Enter the person’s name." }, 400);
      const { data: client } = await admin.from("clients").select("id,name,owner_id").eq("id", client_id).maybeSingle();
      if (!client) return json({ error: "That client wasn’t found." }, 400);
      if (!(await mayManageClient(client_id))) return json({ error: "Only admins and this client’s account owner can invite people to the portal." }, 403);

      // the same email may already have a login
      const { data: existing } = await admin.from("profiles").select("id,client_id").ilike("email", email.replace(/[\\%_]/g, (c) => "\\" + c)).limit(1).maybeSingle();
      let id = existing?.id as string | undefined;
      if (existing && !existing.client_id) return json({ error: "This email belongs to a team login, so it can’t be a client login." }, 400);
      if (existing && existing.client_id !== client_id) return json({ error: "This email already has a portal login for another client." }, 400);
      if (!id) {
        const { data, error } = await admin.auth.admin.createUser({ email, password: randomPassword(), email_confirm: true, user_metadata: { full_name } });
        if (error) return json({ error: error.message }, 400);
        id = data.user!.id;
      }
      // the database turns this into a portal-only login (never active as staff)
      const { error: pErr } = await admin.from("profiles").update({ full_name, ...(phone ? { phone } : {}), client_id, portal_active: true, email_notifications: "all" }).eq("id", id);
      if (pErr) return json({ error: "The login was created, but couldn’t be linked to the client: " + pErr.message }, 400);
      await admin.auth.admin.updateUserById(id, { ban_duration: "none" });

      const { data: link, error: lErr } = await admin.auth.admin.generateLink({ type: "recovery", email, options: { redirectTo: APP_URL } });
      if (lErr) return json({ error: "The login is ready, but the invite link couldn’t be made: " + lErr.message }, 400);
      const url = link.properties?.action_link ?? "";
      // emailed by the notification mailbox within a few minutes (the same way all notification emails go out)
      await admin.from("notifications").insert({ user_id: id,
        title: "You’re invited to the Tcipher client portal",
        body: (me.full_name || "The Tcipher team") + " invited you to follow " + client.name + "’s requests, bugs, meetings and projects with Tcipher in one place.\n\n" +
          "1. Set your password with this link (it works once, for a limited time): " + url + "\n" +
          "2. After that, sign in any time at " + APP_URL + " with " + email + ".\n\nIf the link has expired, ask " + (me.full_name || "your contact at Tcipher") + " to send a new invite." });
      return json({ ok: true, id, link: url, resent: !!existing });
    }
    if (action === "client_access") {
      const id = String(body.id ?? "");
      const { data: p } = await admin.from("profiles").select("id,client_id").eq("id", id).maybeSingle();
      if (!p || !p.client_id) return json({ error: "That isn’t a portal login." }, 400);
      if (!(await mayManageClient(p.client_id))) return json({ error: "Only admins and this client’s account owner can change portal access." }, 403);
      const on = !!body.on;
      const { error } = await admin.auth.admin.updateUserById(id, { ban_duration: on ? "none" : "876000h" });
      if (error) return json({ error: error.message }, 400);
      await admin.from("profiles").update({ portal_active: on }).eq("id", id);
      return json({ ok: true });
    }

    // everything below: admins only
    if (!me.is_admin) return json({ error: "Only admins can manage users." }, 403);

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

    // (2026-11cy) change someone's work email: their sign-in email and the address shown everywhere
    if (action === "set_email") {
      const email = String(body.email ?? "").trim().toLowerCase();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Enter a valid email address." }, 400);
      const { data: taken } = await admin.from("profiles").select("id").ilike("email", email).neq("id", id).limit(1);
      if (taken && taken.length) return json({ error: "Someone else already uses that email." }, 400);
      const { error } = await admin.auth.admin.updateUserById(id, { email, email_confirm: true });
      if (error) return json({ error: error.message }, 400);
      const { error: pErr } = await admin.from("profiles").update({ email }).eq("id", id);
      if (pErr) return json({ ok: true, warning: "Sign-in email changed, but the profile wasn’t updated: " + pErr.message });
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
