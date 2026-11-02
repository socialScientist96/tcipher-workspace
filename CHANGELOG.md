# Tcipher Workspace – changelog

Version 1 (first upload): three verticals, admin panel, roles, leads handoff, tasks with review, leave and attendance, logo and brand colours.

## Ready to go live: version 2026-11d (this folder)
Needs: run `upgrade-2026-11d.sql` once in Supabase, then upload `index.html` to GitHub.
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
