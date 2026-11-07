# Tcipher Workspace – changelog

## Version 2026-11as (8 Nov 2026): dropdown arrows and sidebar headings
Needs: upload `index.html` and `sw.js`.
- **Every dropdown** has its own arrow 12px in from the right edge, with room so the text never runs under it (smaller dropdowns 8px; status chips 6px).
- **Sidebar section headings** (Development & QA, Communication, Sales, Marketing, Company) are larger (14px) and semi-bold.

## Version 2026-11ar (8 Nov 2026): Notion-style sidebar
Needs: upload `index.html` and `sw.js`. No database or function changes.
- **Sidebar in the style of Notion:** warm off-white, a line icon beside every page, quiet section labels with a chevron to open and close each team's section.
- **Search box** at the top narrows the menu as you type; Enter opens the first match, Esc clears it. **Ctrl+K / ⌘K** jumps to it from anywhere.
- **Home, Chat and Calendar shortcuts** under the search, with the chat's unread count.
- **Recents:** the last pages you opened (kept in this browser only).
- **New task** button at the top of the sidebar; **hide the sidebar** on a computer with the panel button or **Ctrl+\\ / ⌘\\** (the menu button brings it back; remembered per browser).

## Version 2026-11aq (8 Nov 2026): phones, tablets and slow connections
Needs: upload `index.html` and `sw.js`. No database or function changes.
- **Bottom bar on phones and small tablets:** the menu and notifications sit at the bottom, within thumb reach. Notifications open just above the bar instead of over the page.
- **Pop-up windows on phones slide up from the bottom**, leave the top of the page visible, and keep their buttons at the bottom (the main button full width, last).
- **Everything you tap on a touch screen is at least 44px**; form fields use 16px text so iPhones don't zoom in; number, phone, email and web fields bring up the matching keyboard (no autocorrect or auto-capitals in them).
- **Phone numbers are tappable** everywhere they show (People cards, person details, leads, contacts, clients); Call and SMS open the phone app directly (SMS links were blocked before).
- **Calendar on touch screens:** each day is one big button with coloured dots; tapping it lists the day's items.
- **Chat on phones:** icon-only header buttons, the message box gets the full width with tools and Send below it, and the chat stops above the bottom bar. Tap a message to show reply / react / delete (they no longer squeeze every bubble).
- **No sideways page scrolling**; wide tables and boards scroll inside their own box. The Report a problem tab moves into the menu on touch screens.
- **No jumps while loading:** chat pictures get a fixed box before they arrive; fonts that arrive late no longer reflow the page; pictures load lazily.
- **Slow connections:** the database and library connections open early; an unused copy of the logo was removed.

## Version 2026-11ap (8 Nov 2026): design pass
Needs: upload `index.html` and `sw.js`. No database or function changes.
- **Quieter look, same app.** Neutral greys for the frame; Tcipher violet only for main buttons, the page you're on and key highlights. Weights 400–600, sentence-case labels (no more all-caps headings), one radius scale, no hover lift.
- **Light sidebar** with a dark-lettered version of the logo.
- **Home** is titled by the day; check-in sits in a plain card (no purple banner or greeting).
- **Line icons instead of emoji** in buttons, chat tools, file types and menus (emoji in messages and reactions are unchanged).
- **Task IDs as small mono keycaps** (JetBrains Mono), also used for counts.
- Sign-in page: near-black side panel without the decorative circle.
- Method after "unslop" by Damir Sokolovsky (@heydamir), CC BY 4.0; icons from Lucide (ISC).

## Version 2026-11ao (7 Nov 2026): two-step sign-in and sign-in CAPTCHA
Needs: upload `index.html` and `sw.js`; deploy `admin-users-function.ts` and `google-sync-function.ts`; run `upgrade-2026-11ao.sql`.
- **Two-step sign-in** (authenticator app codes): set up in My profile › Two-step sign-in. When it's on, sign-in asks for the 6-digit code. Admins see a reminder in the Admin panel until they turn it on.
- **Admins who use it get admin rights only after entering the code** (database, admin-users and google-sync all check), so a stolen admin password alone can't reach the admin panel. Admins who haven't set it up yet work as before.
- **Admin › Users › edit a person › Reset two-step sign-in**, for someone who lost their phone.
- **Sign-in CAPTCHA (Cloudflare Turnstile)**, off until a site key is set in `TURNSTILE_SITE_KEY` (index.html) and the secret key in Supabase › Authentication › Attack Protection. Set the site key and publish first, then turn it on in Supabase.

## Version 2026-11an (7 Nov 2026): browser security policy and tamper checks
Needs: upload `index.html` and `sw.js`.
- **Security policy (CSP)** in the page: code and data may only come from / go to this site, Supabase, Google (sign-in, Drive, Docs viewer) and the three library CDNs. A stolen session can no longer be sent to another site. **Using a new outside site in the code means adding it to the policy at the top of index.html.**
- **Tamper checks (SRI)** on the Supabase library (both sources), the screenshot library and the Excel library: a changed copy is refused.
- Links to other sites no longer carry the full page address (referrer policy).

## Version 2026-11am (7 Nov 2026): security fixes, notification emails restored
Needs: deploy `google-sync-function.ts` (Edge Functions › google-sync), then upload `index.html` and `sw.js`.
- **Notification emails restored.** The google-sync deployed on 7 Nov came from an older copy without the sending-mailbox code, so emails had stopped. Rebuilt: connect/test/disconnect the sending mailbox (admins only); every 2 minutes unread notifications over 2 minutes old are emailed to people not in the app (as chosen in My profile, to work and personal email; items from the last 3 hours); replies are posted back as a chat message or comment **only when sent from that person's own address**.
- **Unsafe links blocked everywhere:** links that come from data may only be web, email or phone links (a `javascript:` link in a meeting or task could otherwise take over the session of whoever clicked it). Tabs opened for files and Meets can't steer the workspace tab.
- **google-sync:** another person's Google account is used only by that person or an admin (before, naming a colleague as a meeting's Google organiser let anyone edit or cancel their real calendar events); email attachments must be files the sender can see; Cc addresses are checked.
- **The scheduled-job secret is no longer in this repo** (`google-sync-schedule.sql` shows `<CRON_SECRET>`).

## Version 2026-11al (7 Nov 2026): works on slow connections
Needs: upload `index.html` and the new `sw.js` (both at the site root). No database changes.
- **Opens fast on repeat visits, even offline:** `sw.js` keeps the app's own files (the page, the Supabase library, fonts) on the device. The page is always fetched fresh first; the saved copy is used if the network takes over 4 seconds or is down. Your data is never stored by it. To turn it off, delete `sw.js` from the site.
- **Time limits on every database request:** reading waits up to 20 s for the server (and is retried by the library), saving up to 60 s and is never repeated automatically. Before, a stalled request left "Loading…" on screen forever.
- **"Slow connection…" and "You're offline" notices** at the bottom left.
- **Starting up on a bad connection** shows "Loading the workspace…", then "Can't reach the server… Trying again shortly" with a **Try again** button, instead of a blank page or the "Contact your admin" (account turned off) screen.
- **Lighter update check:** asks only whether the page changed, instead of downloading the whole app (~230 KB) every 5 minutes.
- **On 2G/3G or data-saver connections,** pages load only what they show (no loading ahead in the background).
- **Backup source for the Supabase library** (unpkg) if the main one (jsDelivr) doesn't load.

## Ready to go live: version 2026-11m (this folder)
Needs: run `upgrade-2026-11k.sql`, then `upgrade-2026-11m.sql`, in Supabase (both are safe to run again), then upload `index.html`.
- **Instant chat that really is instant:** the workspace now signs in to Supabase’s live connection and uses **private channels**, one per conversation plus one per person. The database itself sends the “new message” and “new notification” signals. This works whether or not the project allows public live channels. The backup check runs every 2 seconds on Chat.
- **● Live / Connecting…** at the top of each chat, so it’s clear whether messages are arriving instantly.
- **Notification sound:** a soft chime for new messages and notifications, and a quieter pop in the chat you’re reading. Switch it off in My profile › Sounds.
- **Start from unread:** conversations open at the first unread message, under a red **New messages** line; **↓ Jump to latest** appears when you scroll up, and shows **↓ New message** when one arrives.
- **New version available:** when a newer version is uploaded, the workspace offers a **Reload now** bar, so nobody is stuck on an old copy.

## Version 2026-11l (live 3 Nov 2026)
- **Menu:** sections all start closed; clicking a section’s name always opens or closes it (including the one you’re on); several can be open at once; remembered.
- **💬 WhatsApp in direct chats**, next to ✉️ Email: opens WhatsApp with that person’s number (from My profile).
- Fixes the live problem where chat messages only appeared after a click.

### Also in this release (from 2026-11k)
- **Instant chat:** new messages, edits, “… is typing” and “Seen” arrive over the live connection, with no refresh. A backup check every few seconds covers a dropped connection.
- **Chat bubbles:** yours on the right in purple, everyone else on the left with their picture, and names in groups and channels.
- **Chat notifications:** direct and group messages and @mentions notify people. The database creates them, one per conversation, updated until read; opening the chat clears it.
- **Loaders on every button:** a click that starts something slow shows a spinner, and double clicks are ignored, so nothing is saved twice.
- If live updates can’t connect, it’s recorded automatically in Admin panel › Problems.
- Tested: all 19 automated suites, plus real-browser checks at laptop and phone size.

## Version 2026-11j (live 3 Nov 2026)
Needs:
1. Run `upgrade-2026-11i.sql` in Supabase.
2. Redeploy `google-sync-function.ts`.
3. Run `google-sync-schedule.sql` again (adds the every-minute reply check).
4. Upload `index.html`.
- **Chat**, under the new **Communication** menu with Emails and Announcements: channels, direct messages and group chats; @mentions; editing; kept permanently; text only, with **Send by email** for files.
- **Online dots and last active** for everyone; **Home › Messages** with unread chats and email replies.
- **Collapsible menu sections**, which show their totals when closed and remember what you opened.
- **Admins mark leave** for anyone, approved straight away.
- **Email replies** checked every minute (only conversations started from the workspace).
- **Problem reporting:** automatic error capture, the **🐞 Report a problem** button, and **Admin panel › Problems** with **Copy for Claude**.
- **Fixes:**
  - @ tagging list hidden at the bottom of dialogs
  - admin-added leave saved under the wrong person
  - starting a direct message failed
  - dashboards scrolling sideways on laptops
  - phone layout of the report button and attendance check-in
- White logo in the menu and on the sign-in screen.
- The @ name list opens above the box you’re typing in.
- Fix: a stray “null” on Problems cards.
- Tested: all 17 automated suites; every page as all 7 roles at phone, tablet, laptop and large-monitor sizes; very long names, titles and links.

## Version 2026-11h (live 3 Nov 2026)
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
