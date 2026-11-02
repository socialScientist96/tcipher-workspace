# Tcipher Workspace – changelog

## Ready to go live: version 2026-11h (this folder)
Needs:
1. Run `upgrade-2026-11h.sql` in Supabase.
2. In Google Cloud, enable the Gmail API and add the Gmail scopes.
3. Redeploy `google-sync-function.ts`.
4. Upload `index.html` and `privacy.html`.
- **Email from your own Gmail:**
  - on Leads, Instagram leads, Deals, Clients, Contacts and Proposals (with the PDF attached)
  - offer letter and onboarding emails for new joinees, and an Emails page for writing to anyone (optionally saved as a lead)
  - templates; replies (only to emails sent from the workspace) shown on the record, with notifications and threaded replies
- **Admins mark attendance:** present, half day or absent for anyone on any day, with times and a note. The person is notified, and only admins can change it after.
- **Left menu:** the logo and your name stay fixed; only the links scroll.

## Version 2026-11g (live 2 Nov 2026)
Needs: run `upgrade-2026-11g.sql` in Supabase, then upload `index.html`. Optional: deploy `lead-capture-function.ts` for website forms.
- **Sales and Marketing CRM**, from the old marketing app:
  - lead numbers, lead type, priority, tags, alternate phone, address, zone, follow-up and last contacted
  - the **Instagram leads** pipeline (10 stages), with website form answers, page URL and UTM tags
  - Call, WhatsApp, Email and SMS buttons that log each contact, call outcomes and duration, linked tasks, Info/Action/Escalation comments, and permanent history
  - deals get a Meeting stage and Mark won / Mark lost / Reopen; duplicate warnings; an Analytics page with funnels and breakdowns
- **CSV import and export** on 11 Sales and Marketing lists: automatic column matching, Indian dates and amounts, skip/update/add for duplicates, a preview, problem rows you can download, and templates.
- **Website form endpoint** (`lead-capture`) so tcipher.com forms create or update leads.
- **Large lists:** every list now loads past 1,000 rows (Supabase’s per-request limit), and big board columns show 60 cards with “Show more”.

## Fix 2026-11f (index.html + google-sync function)
- Google connections and synced events now load (they were asked to sort by a column those tables don’t have, so “Connected” never showed). Upload `index.html`.
- The sync function now records every sync failure and shows it in My profile and Admin › Google. Redeploy `google-sync-function.ts`.

Version 1 (first upload): three verticals, admin panel, roles, leads handoff, tasks with review, leave and attendance, logo and brand colours.

## Ready to go live: version 2026-11e (this folder)
Needs: upload `index.html`, `privacy.html` and `terms.html` to GitHub. No database change.
- **Google Client ID added** to index.html (Google features switch on once the `google-sync` function is deployed in Supabase).
- **privacy.html / terms.html** for Google’s consent screen.
- **Menu highlights on every tab:** a red number for things due or needing you (overdue tasks, reviews, follow-ups, approvals, posts due, tickets, today’s meetings, “!” if you haven’t checked in), and a purple “new” count for things added by others since you last opened that tab. Opening a tab clears its “new” count. Hover a badge to see what it counts.

## Version 2026-11d (live 2 Nov 2026)
- **Team calendar:** everyone’s Google meetings, workspace meetings and leave, by person and day (week or day view, filter by vertical). Full details for everyone, a Join button on every Meet, and “In a meeting”, “Not connected” and “Sync problem” markers.
- **Admin panel › Google:** who’s connected, their Google account, last sync and any problems. Remind one person or everyone; the reminder notification opens Connect Google in one click.

## Version 2026-11c (uploaded 2 Nov 2026; run `upgrade-2026-11c.sql` if not done)
- **Task rules (Admin panel › Task rules):** choose task handlers per vertical. Handlers edit everything and archive. People on a task (owner, collaborators, reviewer) can update its status, checklist, blocked flag and code links; there’s a switch to turn this off, and reviewers can always approve or send back. Everyone else creates tasks, views, comments and attaches files. All of this is enforced by the database.
- **No deleting tasks:** handlers archive instead. Archived tasks leave the boards, appear under Tasks › Archived, and can be restored.
- **Complete, permanent history** for every task: every field (with before/after for the description), checklist steps, labels, dependencies, comments, files, archive and restore. Nobody can edit or delete it. Comments on tasks can only be removed by an admin, and that’s recorded too. Changes to the task rules appear in the activity log.

## Live since 2 Nov 2026: version 2026-11b
- Fix for saving with optional dropdowns left empty, meetings on selected days, Saturday as a working day.
- **Fix:** saving with an optional dropdown left empty (e.g. bug severity on a normal task, service on a deal, channel on a campaign) failed with “null value … violates not-null constraint”. Fixed everywhere. Every module’s create and edit is now tested against the real database rules.
- **Meetings:** “Repeats › On selected days” with Mon–Sun tick boxes. Google Calendar invites follow the same days.
- **Saturday is a working day:** the scrum runs Mon–Sat, and leave counts Mon–Sat (change in Company settings).

## Live since 2 Nov 2026: version 2026-11
(`upgrade-2026-11.sql` run, `index.html` uploaded)

- **Smoother:** no loading flash between pages, every section preloads, the sidebar keeps its scroll position, instant drag-and-drop, single redraw after saving, gentle transitions.
- **Morning scrum:** a repeating meeting with a **Join morning scrum** button on Home. Joining logs it and checks you in as **Remote**. Attendance is remote-first (Remote, Client site, On-site).
- **Meeting joins:** every Join click is logged, and Google Meet joins are imported. Each meeting has a “Who joined” list.
- **Holidays:** upcoming holidays on Home, on the Leave page, and on a new Holidays page.
- **Leave:** resets every 1 January with no carry-over, and leave crossing New Year is split by year. 2026 allowance: 2 days; from 2027: 12.
- **Google Calendar and Meet (once the Google setup is done):**
  - Connect once, then calendars sync automatically every 10 minutes.
  - Google meetings show on the calendar and on Home with **Join** buttons.
  - Workspace meetings are added to Google Calendar with a Meet link and invites.
  - Meet joins are imported automatically.
- **Dev tasks:**
  - TC-### IDs, @tagging with suggestions (tagged people can view and comment), and a “Tagged me” filter
  - checklists, “waiting on” dependencies, branch and commit helpers, MR/PR and design links
  - component, labels, release, start date, full bug reports, history and duplicate
- **Notes:** private or shared, @tagging, linked to tasks, projects and meetings, pinned to Home.
- **Fixes:** tagging “@Harsh” no longer also notifies Harshita.

## Optional, when ready: Google
Google Cloud project, the `google-sync` function and its secrets, and `google-sync-schedule.sql`. See the README. Then put the Client ID in `index.html`.
