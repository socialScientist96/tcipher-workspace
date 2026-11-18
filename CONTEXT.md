# Tcipher Workspace — working context

What this project is, how it's built and released, the rules we work by, and where things stand.
Last updated: 18 November 2026 (live version **2026-11fa**, service-worker cache **tc-shell-v117**).

> This repository is public and served by GitHub Pages, so this file is readable on the web.
> It deliberately contains **no secret values** (keys, tokens, passwords) and no personal email addresses.
> Secrets live only in Supabase › Edge Functions › Secrets and in the private files listed below, which are never committed.

---

## 1. What it is

**Tcipher Workspace** (https://internal.tcipher.com) is Tcipher Technologies' internal app: tasks and the
Development & QA board, chat, notes, calendar, meetings, leave and attendance, CRM (leads, deals, Instagram leads,
proposals, campaigns), emails through each person's Gmail, a client portal, Finance (invoices, clients & dues,
balance sheet, salaries), WhatsApp Business (built, not yet switched on) and an admin panel.

- **Owner / super admins:** Deepak Sharma and Saurabh Mishra.
- **Front end:** one file, `index.html` (about 17,000 lines: HTML, CSS and JavaScript), plus `sw.js` (service worker),
  `manifest.webmanifest`, `icons/`, `book.html` (demo booking), `privacy.html`, `terms.html`.
- **Hosting:** GitHub Pages from this repo (`main`), custom domain in `CNAME`.
- **Back end:** Supabase project `pfdnziybqaumnofjknsj` (Postgres with row-level security, Auth, Storage, Realtime,
  Edge Functions, `pg_cron`, `pg_net`). Plan: Pro.
- **Native shells:** Android app (`../tcipher-android`, Kotlin WebView, Firebase for push) and iPhone app
  (`../tcipher-ios`, WKWebView, Apple push). Both load the live site.
- **Installable web app (PWA):** the same site installs as an app on Windows, Mac, iPhone and Android (2026-11ew).

## 2. Code conventions (index.html)

- `h(tag, attrs, ...children)` builds elements. **Never pass `null` to `el.append(...)` or `replaceChildren(...)`**: it
  prints the word "null". Filter with `.filter(Boolean)` or spread conditionally.
- `MOD[route]` describes each table-backed page (fields, access, detail, actions). `rows(t)`, `byId(t, id)`, `load(t)`,
  `ensure([...])`, `upsertCache`, `updateRow`, `devSave`.
- `openDialog(title, body, footer, narrow)`, `segmented(...)`, `nbMenu(anchor, items, heading)`, `toast`, `fail`, `friendly`.
- Permissions: `isAdmin()`, `lvl(area)` (0 none, 1 view, 2 edit, 3 manage), `access(M)`. Database side: `perm(area)`,
  `can_see(tbl, id)`, `is_admin()`, `is_active_user()`.
- Live updates: the database broadcasts small signals on the private Realtime topic `ws-live` (`live_table_signal()`
  trigger); the app re-fetches only what changed (`DELTA_TABLES`, `liveRefresh`).
- A global click guard ignores a second click on the same button within 400 ms; buttons that must repeat
  (steppers, zoom) opt out with `data-multi="1"`.
- Phone layout lives in `@media (max-width:760px)` blocks. Count them after every change
  (`grep -c 'max-width:760px' index.html`, currently **24**); a drop means a merge lost phone styles.

## 3. How a release works

1. Edit `index.html` (and `sw.js` / SQL / functions as needed).
2. Bump `APP_VERSION` in `index.html` (`2026-11xx`, letters advance aa → az → ba …) and `CACHE` in `sw.js` (`tc-shell-vNNN`).
3. Syntax check: extract the largest inline `<script>` and run `node --check` on it.
4. Check the phone-style count (above).
5. Test on the local copy (section 6).
6. Commit on branch `mobile-excellence`, then **push only when the owner says "push"**:
   `git push origin mobile-excellence:main mobile-excellence`.
7. Confirm live serves the new version: `curl -s "https://internal.tcipher.com/?v=$RANDOM" | grep -o '2026-11xx'`
   and the `sw.js` cache name.

Database changes ship as `upgrade-2026-11xx.sql` files (safe to run more than once, ending with a read-only check).
**The owner runs them** in Supabase › SQL editor. **Edge Functions are deployed by the owner** (Supabase › Edge
Functions › paste the `*-function.ts` file › Deploy).

## 4. Standing rules

- Push to live only when the owner says "push". Commit locally first, then ask.
- Never type passwords or credentials into the live site. Local QA accounts on localhost are fine.
- **Private files — never commit, never show their contents:** `push-keys-PRIVATE.txt`, `push-secret-PRIVATE.sql`,
  `android-signing-PRIVATE.properties`, `tcipher-android-release.jks`, `tcipher-local-test/.env.local-PRIVATE`,
  `tcipher-local-test/qa-accounts-PRIVATE.json`.
- Don't commit `_mobile-audit.js` (test helper) or the unrelated `CHANGELOG.md` / `tracker-extension/*` /
  `tcipher-tracker.zip` changes.
- Marking a problem "Fixed" in Admin › Problems notifies the person who reported it: ask before marking other
  people's reports. Fixed notes say which version fixed it.
- Problem reports: discuss each one with the owner before fixing.
- Always syntax-check after editing `index.html`; after any merge check the phone style blocks are still there.
- Don't push internal-only documents unless the owner says so (e.g. `realtime-optimisation-2026-11.md`, the CTO
  write-up, is kept local by choice).

## 5. Secrets and setup (names only)

| Where | Secret | Used by |
|---|---|---|
| Edge Functions › Secrets | `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`, `PUSH_SECRET` | `push` (web push) |
| | `FCM_SERVICE_ACCOUNT` | `push` (Android app, Firebase) — set and working |
| | `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` | `push` (iPhone app) |
| | Google OAuth client, `GMAIL_PUSH_KEY` | `google-sync` (Calendar push, Gmail push via Pub/Sub topic `tcipher-gmail`) |
| | `LEAD_CAPTURE_KEY`, `LEAD_CAPTURE_ORIGINS` | `lead-capture` (website forms) |
| | `DRIVE_SHARE_DOMAIN` (default tcipher.com) | `files` (Google Drive storage) |
| | `META_APP_SECRET`, `META_VERIFY_TOKEN`, `META_SYSTEM_TOKEN`, `META_PAGE_ID`, `WA_PHONE_NUMBER_ID`, `WA_WABA_ID` | `meta-webhook`, `whatsapp-send` — **not set yet** |

Edge Functions in the repo: `push-function.ts`, `google-sync-function.ts`, `files-function.ts`, `lead-capture-function.ts`,
`admin-users-function.ts`, `ai-assist-function.ts`, `demo-booking-function.ts`, `work-summary-function.ts`,
`meta-webhook-function.ts`, `whatsapp-send-function.ts`.

## 6. Local testing

- Local Supabase in Docker (`supabase_db_tcipher-local-test`; run `colima start` if Docker is down) in `../tcipher-local-test`.
- Build the local site with `python3 rebuild-site.py`, serve it: `cd site && python3 -m http.server 8090 --bind 127.0.0.1`.
  Copy `icons/*.png` and `manifest.webmanifest` into `site/` if they changed (the rebuild doesn't).
- Sign in with a magic link for a QA account (`qa.admin`, `qa.mkt`, `qa.dev`, `qa.tester`, … `@tcipher.test`),
  generated from `.env.local-PRIVATE`.
- Edge Functions can be run locally with Deno and a stub for outside APIs (used for the WhatsApp functions: a harness
  that fakes Meta's Graph API). The local page's CSP must allow the harness port for browser tests.
- The built-in browser pane runs page code in an isolated world: to override `window.prompt` / `confirm`, inject a `<script>`.
- Android: `export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ANDROID_HOME=$HOME/Library/Android/sdk;
  gradle --no-daemon -q assembleRelease` in `../tcipher-android` (no `./gradlew`). APKs are copied to
  `../tcipher-workspace-main/Tcipher-Workspace-android-1.x.apk`. Use your own emulator; another session may be using
  `emulator-5554` for the vendor app.

## 7. Recent releases (newest first)

| Version | What changed |
|---|---|
| 2026-11fa | Picture viewer works on laptops (zoom bar, Cmd/Ctrl + scroll and pinch, Fit width, drag; tall screenshots open at full width; file pictures use it too). Report a problem in the laptop sidebar. |
| 2026-11ez | Install popup at the first reload on a new device (then every 5th open); "Turn on notifications" guide in the popup and on the installed app's first open. |
| 2026-11ey | Installed desktop app icon drawn to Apple's macOS template (no grey frame on macOS 26). |
| 2026-11ex | Install popup every 5th open for people who haven't installed the app. |
| 2026-11ew | Install the workspace as an app (Windows, Mac, iPhone, Android): menu item, Home card, steps per device; manifest shortcuts; "Send a test" reports each device (needs `push` redeployed — done). |
| 2026-11ev | Clearer development flow: "Stages" naming, "Now with" line, handover confirmation and 2.5 s lock, Start only on To Do (skip to QA in the … menu), QA's send-back reason under the task title. |
| 2026-11eu | WhatsApp loads only once it's switched on (no "didn't load" notice before setup). |
| 2026-11et | Admin tabs scroll on phones; phone Flow bar folds; animated welcome screen with the Midnight icon. |
| 2026-11es | WhatsApp Business inbox and Meta Lead Ads (functions, SQL, inbox page, lead/deal section). |
| 2026-11er | Premium app icon (Midnight, with "Work"). |
| 2026-11eq … ea | Dev board toolbar, Done by me, task flows, egress reduction (device file cache, Drive video player), Finance, per-person permissions, Calendar and Gmail push, live updates by broadcast. |

Android app: **1.8** (startup screen matches the web welcome screen, real version reported), APK in Downloads and
`tcipher-workspace-main`, shared by the owner.

## 8. Where things stand / open items

- **WhatsApp Business + Meta Lead Ads** — code is live but hidden. To switch on: run `upgrade-2026-11es.sql`, deploy
  `meta-webhook` (Verify JWT **off**) and `whatsapp-send` (Verify JWT **on**), add the six Meta secrets, set Meta's
  webhook to `https://pfdnziybqaumnofjknsj.supabase.co/functions/v1/meta-webhook` (fields `leadgen`, `messages`), test
  with Meta's test number, then Admin turns on **Send from the dashboard** (WhatsApp page). Blocked on Meta: accepting
  the "Tcipher Technologies" business-portfolio invite fails with "The user cannot be added to the business".
  Open question: should Instagram ad leads go to the Instagram pipeline (currently General)? Plan and owner handoff
  are in Claude Docs ("WhatsApp and Meta Lead Ads integration: technical plan").
- **Notifications** — web push (computers, iPhone Home Screen app), Firebase (Android app) and Apple (iPhone app) all
  verified on 18 Nov 2026. On Macs, Chrome must be allowed in System Settings › Notifications and Chrome kept running.
- **Install guide** — `Tcipher-App-Install-Guide.pdf` (6 pages, kept outside the repo) for the team.
- **Not built (by choice):** a signed Windows `.exe` or Mac `.dmg`; the installed web app covers both without
  code-signing certificates.
- **Housekeeping:** a leftover iPhone simulator build in `../tcipher-ios/build` shows as a crossed-out app in Launchpad;
  deleting that folder removes it (Xcode rebuilds it).
- Unconfirmed: the Google Cloud org policy (`iam.allowedPolicyMemberDomains`) restored after the Gmail push setup;
  Finance setup (billing account, signatures, salaries).
