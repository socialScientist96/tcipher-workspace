# Tcipher Technologies Workspace

The internal workspace for Tcipher's three verticals, **Development**, **Sales** and **Marketing**, plus company-wide leave and attendance.

| File | What it is | Where it goes |
|---|---|---|
| `index.html` | The whole app (the page everyone opens) | This GitHub repo, served by GitHub Pages |
| `supabase-setup.sql` | Database, security rules, roles and settings | Run once in Supabase › SQL Editor |
| `admin-users-function.ts` | Lets the admin panel create logins and reset passwords | Supabase › Edge Functions, named `admin-users` |

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
- **Leave days, holidays, working days:** Admin panel › Company settings. The default is 12 leaves a year, with paid and sick leave sharing one pool.
- **Who changed what:** Admin panel › Activity log.

## Updating the app

Edit `index.html` (or replace it with a new version) and commit. GitHub Pages republishes within a minute or two. Your data is untouched, because it lives in Supabase.

If a new version also comes with SQL changes, run the new `supabase-setup.sql` in Supabase. It's safe to run again.

## Backups

Supabase › Table Editor can export any table to CSV. Export important tables regularly, or use a paid Supabase plan with daily backups.
