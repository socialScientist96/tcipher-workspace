# Tcipher Technologies Workspace

The internal workspace for Tcipher's three verticals, **Development**, **Sales** and **Marketing**, plus company-wide leave and attendance.

| File | What it is | Where it goes |
|---|---|---|
| `index.html` | The whole app (the page everyone opens), incl. your Supabase and Google settings | This GitHub repo, served by GitHub Pages |
| `supabase-setup.sql` | Database, security rules, roles and settings | Run once in Supabase › SQL Editor |
| `admin-users-function.ts` | Lets the admin panel create logins and reset passwords | Supabase › Edge Functions, named `admin-users` |
| `google-sync-function.ts` | Automatic Google Calendar sync, Meet links and Meet join import | Supabase › Edge Functions, named `google-sync` |
| `google-sync-schedule.sql` | Runs the Google sync every 10 minutes | Supabase › SQL Editor (after enabling pg_cron and pg_net) |
| `upgrade-2026-11.sql` | Upgrade for an existing workspace: scrum, Meet joins, holidays/leave, Google sync, dev tasks, notes (already run on yours) | Supabase › SQL Editor |
| `upgrade-2026-11b.sql` | Small follow-up: meetings on selected days, Saturday as a working day | Supabase › SQL Editor |
| `CHANGELOG.md` | What’s in each version, and what still needs doing to go live | Keep with the files |

All data, logins and files live in Supabase. GitHub only hosts the page.

## First-time setup

1. **Supabase project.** Create a new project at supabase.com (Mumbai region). In SQL Editor › New query, paste all of `supabase-setup.sql` and click Run.
2. **Lock sign-ups.** Authentication › Sign In / Providers: turn off “Allow new users to sign up”.
3. **Your admin login.** Authentication › Users › Add user › Create new user, with your email and a password. Tick Auto Confirm. The first account becomes the admin.
4. **User function.** Edge Functions › Deploy a new function › Via Editor. Name it `admin-users`, paste `admin-users-function.ts`, and click Deploy. Then, in the function’s settings, turn off “Verify JWT”. The code checks for an admin itself.
5. **Connect the page.** Project Settings › API Keys: copy the Project URL and the Publishable key (`sb_publishable_…`). In `index.html`, paste them into `SUPABASE_URL` and `SUPABASE_KEY` near the top of the script, then commit. Never put the secret key here.
6. **GitHub Pages.** Repo Settings › Pages › Deploy from a branch › `main` / root › Save.
7. **Your domain (optional).** In Settings › Pages › Custom domain, enter `internal.tcipher.com` and save. At your domain provider, add a CNAME record named `internal` pointing to `<your-github-username>.github.io`. When the check passes, tick “Enforce HTTPS”.
8. **Supabase URLs.** Authentication › URL Configuration: set Site URL to your live address (e.g. `https://internal.tcipher.com`) and add `https://internal.tcipher.com/**` to Redirect URLs.

## Managing it day to day (Admin panel)

- **Add a person:** Admin panel › Add user. Pick their vertical, and the role fills in automatically: Developer, QA, Sales executive or Marketing executive. Copy the login message and send it privately.
- **Promote someone to run a vertical:** give them the Development head, Sales head or Marketing head role.
- **Someone leaves:** open their user and untick “Account is on”. Their history stays.
- **Reset a password:** open the user, type a new password, and save.
- **Change what a role can do:** Admin panel › Roles & permissions.
- **Leave days, holidays, working days:** Admin panel › Company settings. The default is 12 leaves a year, with paid and sick leave sharing one pool. It resets every 1 January with no carry-over. Use “Allowance for this year only” for a different number in one year (2026 is set to 2).
- **Holidays:** add them in Company settings. Everyone sees upcoming holidays on Home, on the Leave page, and on the Holidays page.
- **Who changed what:** Admin panel › Activity log.

## Google Calendar and Meet (automatic sync)

Everyone connects Google once, using either a tcipher.com or a personal Gmail account. After that, a server function keeps their calendar in sync every 10 minutes, even when nobody has the workspace open. It:

- shows Google meetings on the workspace calendar and Home page, each with a **Join** button;
- adds workspace meetings to Google Calendar, with a Meet link and email invites;
- imports every Google Meet join, and checks people in as **Remote** when they join the morning scrum.

**A. Google Cloud (once)**
1. Go to console.cloud.google.com and create a project, e.g. `Tcipher Workspace`.
2. **APIs & Services › Library:** enable **Google Calendar API** and **Google Meet REST API**.
3. **Google Auth Platform › Branding:** add the app name, support email, and `tcipher.com` as an authorised domain.
4. **Audience:** choose **External**, because personal Gmail accounts need access too. Then set **Publishing status** to **In production**. While an app is in “Testing”, Google ends connections every 7 days. You don’t need to submit it for verification for a small team. People will see a “Google hasn’t verified this app” screen once, and click **Advanced › Go to Tcipher Workspace**.
5. **Data Access:** add the scopes `openid`, `email`, `.../auth/calendar.events` and `.../auth/meetings.space.readonly`.
6. **Clients › Create client › Web application.** Under Authorized JavaScript origins, add `https://internal.tcipher.com` and `https://<your-github-username>.github.io`. Copy the **Client ID** and **Client secret**.

**B. Supabase (once)**
1. Run `upgrade-2026-11.sql` in SQL Editor. It adds the sync tables and is safe to run again.
2. **Edge Functions › Deploy a new function › Via Editor:** name it `google-sync`, paste `google-sync-function.ts`, and click Deploy. Then turn off **Verify JWT** in its Settings tab.
3. **Edge Functions › Secrets:** add three secrets:
   - `GOOGLE_CLIENT_ID`: the Client ID
   - `GOOGLE_CLIENT_SECRET`: the Client secret
   - `CRON_SECRET`: `Q6StCwyjs7n6uHf7NOnUY3GStlvUQP_O` (or your own random text, which must match the schedule file)
4. **Database › Extensions:** enable `pg_cron` and `pg_net`. Then run `google-sync-schedule.sql` in SQL Editor, which syncs everyone every 10 minutes.

**C. The page**
Paste the Client ID into `GOOGLE_CLIENT_ID` in `index.html` and upload it to GitHub. Only the Client ID goes in the page. The Client secret stays in Supabase secrets.

Each person then clicks **Connect Google** on their Home page, or in My profile, and approves once.

## Morning scrum and attendance

- Create one meeting with type **Morning scrum**, set **Repeats** to **Every working day** (Mon–Sat), or **On selected days** and tick the days, and paste or generate its Google Meet link. Leave Attendees empty to invite everyone.
- People click **Join morning scrum** on their Home page. This opens Meet, logs the join, and checks them in as **Remote** for the day if they haven’t checked in yet.
- People who join straight from Google Calendar or Meet are imported automatically every 10 minutes, as long as the scrum’s organiser has connected Google. Every join and re-join is logged, and anyone not yet checked in that day is marked **Remote**. Organisers and admins can also click **Import joins from Google Meet** on the meeting to do it immediately.
- The **Attendance › Today’s team** view shows who joined the scrum and when.

## Tasks: IDs, tagging, checklists

- Every task gets an ID like **TC-142**. Use it in branch names and commit messages (the task shows both, with Copy buttons), and type `TC-142` in any comment or note to link to it.
- **Tag people** by typing **@** in a task’s details, a comment or a note, then picking a name from the list. Tagged people are notified and can open the task and comment, even from another vertical, but they can’t edit it. Their **Tasks › Tagged me** filter shows everything they’re tagged in.
- **Checklist:** break work into steps. Progress shows on the board card.
- **Waiting on:** pick other tasks this one depends on. The card shows “Waits on TC-…”, and the owner is notified when the last one is done.
- **Dev tasks** also have project, sprint, release, component, labels, start date, story points, branch, merge/pull request and design links.
- **Bug reports** have severity, how often it happens, environment, build version, device, steps, and expected vs actual result.
- **History** shows who changed the status, owner, reviewer, priority, dates or collaborators, and when.
- **Duplicate** copies a task, with its checklist unticked.

## Notes

- Notes are **private** by default. You can share one with specific people, your vertical (admins can see these too) or everyone. Only the author can edit; others can read, comment and attach files.
- Type **@** to tag someone. They’re notified and can open the note.
- Link a note to a task, project or meeting. Linked notes show inside that task.
- Pin notes to your Home page.

## Updating the app

Edit `index.html` (or replace it with a new version) and commit. GitHub Pages republishes within a minute or two. Your data is untouched, because it lives in Supabase.

If a new version also comes with SQL changes, run the new `supabase-setup.sql` in Supabase. It's safe to run again.

## Backups

Supabase › Table Editor can export any table to CSV. Export important tables regularly, or use a paid Supabase plan with daily backups.
