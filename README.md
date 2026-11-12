# Tcipher Technologies Workspace

The internal workspace for Tcipher's three verticals, **Development**, **Sales** and **Marketing**, plus company-wide leave and attendance.

| File | What it is | Where it goes |
|---|---|---|
| `index.html` | The whole app (the page everyone opens), incl. your Supabase and Google settings | This GitHub repo, served by GitHub Pages |
| `supabase-setup.sql` | Database, security rules, roles and settings | Run once in Supabase › SQL Editor |
| `schema-live-2026-11-07.sql` | The full live database structure (7 Nov 2026), including upgrades that were never saved as files | Reference, or run after `supabase-setup.sql` on a new database |
| `export-schema.sql` | Prints the live structure, to refresh the file above | Supabase › SQL Editor, then Export › Download CSV |
| `admin-users-function.ts` | Lets the admin panel create logins and reset passwords | Supabase › Edge Functions, named `admin-users` |
| `google-sync-function.ts` | Automatic Google Calendar sync, Meet links and Meet join import | Supabase › Edge Functions, named `google-sync` |
| `google-sync-schedule.sql` | Runs the Google sync every 10 minutes | Supabase › SQL Editor (after enabling pg_cron and pg_net) |
| `upgrade-2026-11.sql` | Upgrade for an existing workspace: scrum, Meet joins, holidays/leave, Google sync, dev tasks, notes (already run on yours) | Supabase › SQL Editor |
| `upgrade-2026-11b.sql` | Small follow-up: meetings on selected days, Saturday as a working day (already run on yours) | Supabase › SQL Editor |
| `upgrade-2026-11c.sql` | Task rules, archive instead of delete, permanent task history | Supabase › SQL Editor |
| `upgrade-2026-11d.sql` | Team calendar: everyone sees each other’s Google events | Supabase › SQL Editor |
| `upgrade-2026-11g.sql` | Sales and Marketing CRM: lead numbers, Instagram pipeline, form answers, call outcomes, history | Supabase › SQL Editor |
| `upgrade-2026-11h.sql` | Email from your Gmail, and admin-marked attendance | Supabase › SQL Editor |
| `upgrade-2026-11i.sql` | Chat (channels, direct messages, groups), online status, problem reports | Supabase › SQL Editor |
| `upgrade-2026-11k.sql` | Chat notifications, live updates for chat, “Seen” | Supabase › SQL Editor |
| `upgrade-2026-11m.sql` | Instant updates on private live channels (signed in) | Supabase › SQL Editor |
| `lead-capture-function.ts` | Optional: website forms post leads straight into the workspace | Supabase › Edge Functions, named `lead-capture` |
| `demo-booking-function.ts` | The public demo booking page (`book.html`): free times and booking | Supabase › Edge Functions, named `demo-booking`, **Verify JWT off** |
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

Each person then clicks **Connect Google** on their Home page, or in My profile, and approves once. In **Admin panel › Google** you can see who’s connected and send reminders. Everyone’s meetings appear on the **Team calendar**.

## Morning scrum and attendance

- Create one meeting with type **Morning scrum**, set **Repeats** to **Every working day** (Mon–Sat), or **On selected days** and tick the days, and paste or generate its Google Meet link. Leave Attendees empty to invite everyone.
- People click **Join morning scrum** on their Home page. This opens Meet, logs the join, and checks them in as **Remote** for the day if they haven’t checked in yet.
- People who join straight from Google Calendar or Meet are imported automatically every 10 minutes, as long as the scrum’s organiser has connected Google. Every join and re-join is logged, and anyone not yet checked in that day is marked **Remote**. Organisers and admins can also click **Import joins from Google Meet** on the meeting to do it immediately.
- The **Attendance › Today’s team** view shows who joined the scrum and when.

## Chat, online status and the Communication menu

- **Communication › Chat:** channels (#general for everyone, plus #development, #sales and #marketing for each team and admins), **direct messages** with anyone, and **group chats**.
  - Start a group with **+ New group**. The person who creates it can rename it and add or remove people; anyone can leave.
  - Type **@** to tag someone; they’re notified. Press **Enter** to send, **Shift + Enter** for a new line.
  - Edit your own messages (they show “edited”). Messages can’t be deleted and are kept permanently.
  - Text and links only. To send a file, use **✉️ Email** or **💬 WhatsApp** at the top of a direct chat (WhatsApp needs the person’s phone number in My profile).
  - Messages appear **instantly**, with no refresh: your messages on the right, others’ on the left. You’ll see **“… is typing”**, and **Seen** under your last message in a direct chat.
  - Direct and group messages, and @mentions, create a **notification** (one per conversation, updated until you read it), with a soft **sound**. Turn the sound off in My profile › Sounds.
  - Opening a conversation takes you to the first message you haven’t read, marked with a red **New messages** line. If you scroll up, **↓ Jump to latest** brings you back.
  - **● Live** at the top of a chat means messages are arriving instantly.
- **Online and last active:** a green dot on anyone who’s online, and “Active 5 min ago” when they’re not. This shows on People, in chat, and wherever photos appear.
- **Home › Messages:** your unread chats and new email replies, and who’s online.
- **Menu sections open and close.** They all start closed; click a section’s name to open or close it, and keep several open at once. The workspace remembers how you left them, and a closed section shows its red (due) and “new” counts.

## Problem reporting

- **🐞 Report a problem:** the tab on the right side of every page (in the menu on phones). Describe what happened and add a screenshot; you can paste one with Cmd/Ctrl + V. The page, browser and your last few clicks are included automatically.
- **Automatic capture:** unexpected errors are recorded on their own, once each, with the technical details.
- **Admin panel › Problems:** everything reported or caught, with repeats grouped. **📋 Copy for Claude** copies all open problems; paste them into a chat with Claude to have them fixed. **Mark fixed** tells the person who reported it.

## Admins: marking leave for someone

**Company › Leave › + New leave request:** choose the **Employee**, the type and the dates. It’s approved straight away, and the person is notified.

## Email from your own Gmail

Send email from the workspace, from your own Gmail or tcipher.com address:
- **Leads, Instagram leads, Deals, Clients and Contacts:** the ✉️ Email button, plus an **Emails** list on each record.
- **Proposals:** the **✉️ Email this proposal** button. The PDF is attached automatically, and the proposal is marked Sent.
- **New joinees (admins):** People › open the person › **✉️ Offer letter** or **✉️ Onboarding email**. Upload the offer letter in the email (only you and admins can see it), and attach company documents such as the handbook.
- **Sales and Marketing › Emails:** every email you’ve sent and the replies, plus **New email** to anyone. Tick “Save as lead” to keep the conversation on a lead.

**Replies:** only replies to emails sent from the workspace are picked up. New mail is checked **every minute**, with a full check every 10 minutes; you can also click **Check for replies**. They show on the record, you’re notified, and you can reply in the same conversation. Nothing else in your inbox is read.

**Templates:** Emails › Templates (admins). Placeholders such as {first_name}, {company} and {my_signature} are filled in automatically.

**Setup (once):**
1. **Google Cloud › APIs & Services › Library:** enable the **Gmail API**.
2. **Google Auth Platform › Data Access › Add or remove scopes:** add `.../auth/gmail.send` and `.../auth/gmail.readonly`, then **Save**.
3. **Supabase › Edge Functions › google-sync:** replace the code with the new `google-sync-function.ts` and deploy.
4. Everyone: **My profile › Reconnect to allow email**, and tick the Gmail boxes on Google’s screen.

## Attendance marked by admins

**Attendance › Mark attendance** (or **Mark** / **Edit** on anyone’s row): choose the person, the day, **Present, Half day or Absent**, where they worked, and check-in and check-out times. The person is notified. Once a day is marked by an admin, only an admin can change it.

## Sales and Marketing CRM

- **Leads** and **Instagram leads** (Sales and Marketing menus). Every lead gets a number like **LD-0042**, plus lead type, priority, tags, alternate phone, address, zone, next follow-up and “last contacted”. Lead types and zones are set in **Admin panel › Company settings**.
- **Instagram leads** have their own stages: Lead › Called › Picked up › Qualified › Demo booked › Demo done › Follow up › Closed, Unqualified or Ghosted. Website form answers (any number of questions, page URL, UTM tags) show on the lead.
- **Inside a lead or deal:** Call, WhatsApp, Email and SMS buttons (they open your phone, WhatsApp or email and log it); a communication log with call outcomes and duration; linked tasks with **+ Follow-up**; comments typed Info, Action needed or Escalation (escalations notify the heads); and a permanent **History**.
- **Deals** have a Meeting stage, plus **Mark won**, **Mark lost** (asks why) and **Reopen**.
- **Duplicates:** a new lead or deal with the same email or phone as an existing one gets a warning first.
- **Analytics** (Sales and Marketing menus): leads, Instagram and deals funnels with conversion between stages; leads by source, type, priority, owner and zone; win rate, won value and average deal.

## CSV import and export

Leads, Instagram leads, Pipeline (deals), Clients, Contacts, Activities, Proposals, Campaigns, Content calendar, SEO keywords and Social media each have **Import CSV** and **Export CSV** at the top.

1. **Import CSV** › choose the file (from Excel or Google Sheets: File › Download › CSV).
2. Columns are matched to fields automatically (for example “Mobile Number” goes to Phone, and “Deal Value” goes to Budget). Change any match, or choose “Don’t import”.
3. Choose what happens to rows that match something already here (same email or phone; or the same name for clients, campaigns and keywords): **Skip**, **Update** or **Add anyway**.
4. Check the preview, then click **Import**. Rows with problems are listed with the reason, and you can download them to fix and re-import.

It understands Indian formats: dates as 15/11/2026, 2026-11-15 or 15 Nov 2026; amounts as ₹1,50,000, 1.5L, 2.5 lakh, 50k or 1 cr; people by name or email; options in any capitals. For leads, columns that don’t match a field are kept on the lead as extra answers. **Download a template** gives the right column names.

## Website forms (optional): send tcipher.com form submissions straight into Leads

1. **Supabase › Edge Functions › Deploy a new function › Via Editor**, name it `lead-capture`, paste `lead-capture-function.ts`, and deploy. Then turn off **Verify JWT** in its Settings.
2. **Edge Functions › Secrets:** add `LEAD_CAPTURE_KEY` = any long random text (never commit it here). Optionally add `LEAD_CAPTURE_ORIGINS` = `https://tcipher.com,https://www.tcipher.com` so only your site can post.
3. On the website form, send the submission like this:

```js
fetch("https://pfdnziybqaumnofjknsj.supabase.co/functions/v1/lead-capture", {
  method: "POST",
  headers: { "Content-Type": "application/json", "x-api-key": "<your LEAD_CAPTURE_KEY>" },
  body: JSON.stringify({
    name: "Priya Sharma", email: "priya@shop.in", phone: "+91 98765 43210",
    pipeline: "Instagram",                       // or "General"
    page_url: location.href,
    hp: form.website.value,                      // a hidden, empty "website" field: bots fill it in and are ignored
    utm: { source: "instagram", medium: "paid", campaign: "ai_guide" },
    whatsapp_consent: form.whatsapp_ok.checked,  // a checkbox: "You can message me on WhatsApp"
    form: { name: "ai_design_guide", title: "AI Design Skills guide",
            fields: [ { key: "ai_website", label: "Is your website AI-generated?", value: "Partly" } ] }
  })
});
```

Add a checkbox to the form such as `<label><input type="checkbox" name="whatsapp_ok"> You can message me on WhatsApp</label>` and send it as `whatsapp_consent`. When it's ticked and a phone is given, the lead shows “Agreed to WhatsApp messages” with the date and form, which WhatsApp Business requires before you message someone.

If the same email or phone submits again in the same pipeline, the new answers are added to the existing lead instead of creating a duplicate. Marketing (and Sales, for Instagram) are notified of every new website lead, unless more than 15 arrive within 10 minutes (then they're saved without a notification each). One address can send at most 5 submissions in 10 minutes. Only http(s) page addresses are kept.

## Task rules (who handles tasks)

Go to **Admin panel › Task rules** and tick the **task handlers** for each vertical. Admins are always handlers.

| Who | What they can do |
|---|---|
| Task handlers (per vertical) | Change anything on that vertical’s tasks, assign people, set dates and priority, archive and restore |
| People on a task (owner, collaborators, reviewer) | Update status, checklist, blocked flag and code links. Can be switched off in Task rules. Reviewers can always approve or send back. |
| Everyone else | Create tasks in their own vertical, view them, comment, attach files |
| Nobody | Delete tasks (archive instead), edit or delete task history |

Comments on tasks can only be removed by an admin, and that’s recorded in the task’s history.

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
