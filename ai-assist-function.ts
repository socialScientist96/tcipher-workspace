// Supabase Edge Function: ai-assist
// Two helpers for everyone signed in to the workspace, both written by Claude:
//   action "english"   — rewrites a task's or a note's text (Hindi, Hinglish or rough English) in clear, proper English.
//                        Nothing is saved here: the app shows the result side by side and saves only if you press Replace.
//   action "summarize" — a short summary of a task (its details, comments and history) or of a dashboard page.
// The app sends only what the person can already see on their screen.
//
// Deploy: Supabase > Edge Functions > Deploy a new function > Via Editor, name it exactly: ai-assist
// Needs the secret ANTHROPIC_API_KEY (Edge Functions > Secrets), the same one the work-summary function uses.
import { createClient } from "npm:@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
function secretKey(): string {
  try { const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"); if (keys && keys.default) return keys.default; } catch (_) { /* legacy key */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}
const MAX = 60000;   // characters of text per request (a long note or a busy dashboard fits easily)

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    const db = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false, autoRefreshToken: false } });
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Sign in again." }, 401);
    const { data: who, error: whoErr } = await db.auth.getUser(token);
    if (whoErr || !who?.user) return json({ error: "Your session has expired. Sign in again." }, 401);
    const { data: me } = await db.from("profiles").select("is_active").eq("id", who.user.id).single();
    if (!me?.is_active) return json({ error: "Your account is turned off." }, 403);
    if (!Deno.env.get("ANTHROPIC_API_KEY")) return json({ error: "Claude isn't set up yet: an admin needs to add the ANTHROPIC_API_KEY secret in Supabase › Edge Functions › Secrets." }, 503);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");
    const client = new Anthropic();
    const ask = async (system: string, user: string, schema?: Record<string, unknown>) => {
      // fallbacks: if Claude declines, the API re-runs the request on a fallback model in the same call
      const stream = client.beta.messages.stream({
        model: "claude-opus-5-5",
        max_tokens: 16000,
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: schema ? { effort: "low", format: { type: "json_schema", schema } } : { effort: "low" },
        system,
        messages: [{ role: "user", content: user }],
      });
      const msg = await stream.finalMessage();
      if (msg.stop_reason === "refusal") throw new Error("Claude couldn't do this one.");
      if (msg.stop_reason === "max_tokens") throw new Error("That's too long to do in one go.");
      return msg.content.filter((b) => b.type === "text").map((b) => (b as { text: string }).text).join("").trim();
    };

    try {
      if (action === "english") {
        // title + a list of pieces (task description, or each block of a note), each with an id; html keeps <b>, <i>, <a> etc.
        const title = String(body.title ?? "").slice(0, 2000);
        const pieces = (Array.isArray(body.pieces) ? body.pieces : []).slice(0, 400).map((p: { id: unknown; html: unknown }) => ({ id: String(p.id), html: String(p.html ?? "") }));
        const size = title.length + pieces.reduce((n: number, p: { html: string }) => n + p.html.length, 0);
        if (!title && !pieces.length) return json({ error: "There's no text to convert." }, 400);
        if (size > MAX) return json({ error: "That's too long to convert in one go." }, 413);
        const out = await ask(
          "You turn workplace text into clear, proper English for Tcipher Technologies, a software company in India. " +
          "The text may be in Hindi (Devanagari), Hinglish (Hindi written in English letters, for example 'ride booked ki 3 notification ayi'), or rough English. " +
          "Rewrite each piece in natural, correct English with the same meaning. Keep it about as short as the original; don't add facts or explanations. " +
          "Keep exactly as they are: people's and product names, task IDs like TC-2230, numbers, amounts, dates, URLs, code, and any HTML tags (<b>, <i>, <u>, <s>, <code>, <a href>, <br>) around the same words. " +
          "Text that is already good English stays the same. An empty piece stays empty. Return every piece with its id.",
          JSON.stringify({ title, pieces }),
          { type: "object", additionalProperties: false, required: ["title", "pieces"], properties: {
            title: { type: "string" },
            pieces: { type: "array", items: { type: "object", additionalProperties: false, required: ["id", "html"], properties: { id: { type: "string" }, html: { type: "string" } } } } } });
        const parsed = JSON.parse(out);
        // only the ids that were sent come back
        const ids = new Set(pieces.map((p: { id: string }) => p.id));
        return json({ title: String(parsed.title ?? title), pieces: (parsed.pieces ?? []).filter((p: { id: string }) => ids.has(String(p.id))) });
      }

      if (action === "summarize") {
        const kind = body.kind === "dashboard" ? "dashboard" : body.kind === "note" ? "note" : "task";
        const name = String(body.title ?? "").slice(0, 300);
        const text = String(body.text ?? "");
        if (!text.trim()) return json({ error: "There's nothing to summarize." }, 400);
        if (text.length > MAX) return json({ error: "That's too much to summarize in one go." }, 413);
        const system = kind === "note"
          ? "You summarize one note from Tcipher Technologies' workspace for a busy teammate. Use only what the note says. " +
            "Format: plain text, sections as lines starting with '## ', bullets as lines starting with '- '. Sections: At a glance (one or two sentences: what the note is about), Key points (the most important ideas, decisions or facts), Action items (to-dos, owners and dates, only if there are any). " +
            "Write in English even if the note mixes in Hindi. Under 200 words. Use **bold** only for names and key terms."
          : kind === "task"
          ? "You summarize one work item from Tcipher Technologies' workspace for a busy teammate. Use only the facts given. " +
            "Format: plain text, sections as lines starting with '## ', bullets as lines starting with '- '. Sections: At a glance (one or two sentences: what it is and where it stands), " +
            "What happened (key changes and decisions, newest last), Open questions (only if there are any), Next step. Write in English even if the input mixes in Hindi. Under 180 words. Use **bold** only for task IDs and names."
          : "You summarize a dashboard from Tcipher Technologies' workspace for a manager at a glance. The input is the text on the screen. Use only those facts; don't invent numbers. " +
            "Format: plain text, sections as lines starting with '## ', bullets as lines starting with '- '. Sections: At a glance (two sentences), What stands out (the 3–5 most important numbers or items), Needs attention (overdue, stuck or empty areas; skip if nothing). Under 180 words. Use **bold** only for names and key figures.";
        const summary = await ask(system, (name ? "Title: " + name + "\n\n" : "") + text);
        return json({ summary });
      }
      return json({ error: "Unknown action." }, 400);
    } catch (e) {
      if (e instanceof Anthropic.AuthenticationError) return json({ error: "The ANTHROPIC_API_KEY secret isn't valid. An admin can check it in Supabase › Edge Functions › Secrets." }, 502);
      if (e instanceof Anthropic.RateLimitError) return json({ error: "Claude is busy right now. Try again in a minute." }, 429);
      if (e instanceof Anthropic.APIError) return json({ error: "Claude couldn't be reached (" + e.status + "). Try again in a minute." }, 502);
      return json({ error: (e as Error)?.message || "Claude couldn't be reached. Try again in a minute." }, 502);
    }
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500);
  }
});
