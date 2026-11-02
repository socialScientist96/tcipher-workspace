# Tcipher Workspace – changelog

## Live now (first upload)
Three verticals (Development, Sales, Marketing), admin panel, roles, leads handoff, tasks with review, leave and attendance, logo and brand colours.

## Ready to go live: version 2026-11 (this folder)
Needs: run `upgrade-2026-11.sql` once in Supabase, then upload `index.html` to GitHub.

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
