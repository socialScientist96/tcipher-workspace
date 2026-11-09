# Tcipher Workspace – changelog

## Version 2026-11cn (10 Nov 2026): time in the workspace, counted right across browsers and devices
Needs: upload `index.html` and `sw.js`; run `upgrade-2026-11cf.sql`; redeploy `work-summary-function.ts`.
- Before, each person had one "last seen", so two browsers open at once overwrote each other and the device kept flipping. Now every browser checks in twice a minute while the workspace is on screen, and each minute is kept once per person with every device that had it open. Several browsers or devices at once are all counted, never doubled.
- **Active vs. open:** a minute is active when the person typed, clicked or scrolled in the last 2 minutes.
- **Work summary** boxes: In the workspace, Active, On laptop / On phone / On tablet (with active time on hover), and Parallel browsers. Claude's summary gets these totals too.
- Still counts only the workspace itself. Work in other sites and apps comes in the next steps.

## Version 2026-11cm (9 Nov 2026): everything done on a phone shows in the work summary
Needs: upload `index.html` and `sw.js`; run `upgrade-2026-11ce.sql`; redeploy `work-summary-function.ts`.
- The app now says which device it runs on (phone, tablet or laptop) with every request, and the database keeps it with everything people do: check-ins and check-outs, chat messages, comments, task and record changes, anything created or deleted, time logged, status changes, QA test runs, meeting joins and leave requests.
- **Work summary:** a **Done on phone** total at the top; an **On phone** filter in Every detail, with a phone or tablet tag on each line; and Claude's summary lists every one of them, with times, under **Done on phone**.
- Direct messages stay private: the summary shows that one was sent from a phone, never what it said.
- Not covered: things done before this change, and work the server does by itself (Google sync, emails it sends).

## Version 2026-11cl (9 Nov 2026): PDF name, take two
Needs: upload `index.html` and `sw.js`.
- Chrome still suggested "Tcipher Technologies – Workspace": it reads the tab's title a moment after it changes. The note's name is now set just before the print window opens, so Save as PDF suggests it.
- `sw.js` was empty in 2026-11ck by mistake; restored.

## Version 2026-11ck (9 Nov 2026): the PDF is named after the note
Needs: upload `index.html` and `sw.js`.
- Save as PDF now suggests the note's name (e.g. "9 Nov Dev VONZUU Weekly Meeting With Kevin.pdf") instead of "Tcipher Technologies – Workspace". Characters a file name can't have, like ":" and "/", are left out.

## Version 2026-11cj (9 Nov 2026): branded PDF export for notes
Needs: upload `index.html` and `sw.js`.
- Export → PDF no longer prints "about:blank", the date and the web address at the page edges, and no longer opens a blank tab: the print window opens straight from the note.
- Every page has the Tcipher logo at the top ("Tcipher Technologies · Internal"), a faint Tcipher logo watermark across the middle, and a footer: "Confidential, for internal use", the export date and who exported it. The file is named after the note.

## Version 2026-11ci (9 Nov 2026): select several note blocks like Notion
Needs: upload `index.html` and `sw.js`.
- Selecting several blocks was only possible by Shift-clicking the hidden ⋮⋮ handle, so in practice it didn't work. Now, as in Notion:
  - drag from one block's text into another: the text selection turns into a block selection;
  - drag from the empty space beside the page: a box selects every block it touches;
  - Shift-click a block to extend the selection, click anywhere else to clear it;
  - in a block, **Esc** selects it; **Shift+↑** at the start or **Shift+↓** at the end selects it and the next; **Cmd/Ctrl+A** on a fully selected block selects them all.
- With blocks selected: Shift+↑/↓ grows or shrinks the selection, Cmd/Ctrl+C copies the text, Enter goes back to typing, Delete removes them, and the bar turns them into another kind, colours, duplicates or deletes them.

## Database 2026-11cd (9 Nov 2026): owners can be testers (database side)
Needs: run `upgrade-2026-11cd.sql`. No app change.
- The database refused "The people working on a task can't also be its tester" (rule C of security-fix-2.sql), so choosing yourself as tester on your own task failed even though the app offered it. Now the people working on a task can be its tester (Pick up, or choosing yourself in Tester (QA)).
- Still protected: someone working on a task can't mark it Done themselves unless they are its tester.

## Version 2026-11ch (9 Nov 2026): Improve with AI for notes
Needs: upload `index.html` and `sw.js`; redeploy `ai-assist-function.ts` (new "improve" action). Until then the button says the function needs updating.
- **Improve with AI** on note pages: Claude tidies the note into clear headings, bulleted and numbered lists, action items (with who and when) and short paragraphs, joins lines that were split mid-sentence and removes stray copy-paste characters. It keeps every fact, name, number, date and link, keeps the note's language, and doesn't add or summarise anything away. Pictures, videos, embeds and sub-pages stay in the note.
- You see **Before** and **After** side by side; nothing changes until you press **Replace with this**, and you can **Undo** right after.

## Version 2026-11cg (9 Nov 2026): fixes from the Problems list
Needs: upload `index.html` and `sw.js`.
- **Edit a development task:** an **Edit** button in the task's header (and "Edit all fields" at the bottom) opens every field: title, details, type, priority, dates, project and the rest. Hovering the title or notes now says "Click to edit". (Before, only admins had the full form.) The duplicate Convert to English button in the header is gone; it's under the title as before.
- **Note pages:** the toolbar (Back, Summarize, Share, Export) stays at the top while you scroll, with a thin line under it.
- **Paste from Google Docs, Word or a web page:** headings, bulleted and numbered lists (with their levels), checklists, quotes, code, dividers, tables (a line per row), bold, italic, underline and links come in as the matching blocks. Pictures are added to the note; if Google won't let one be copied, a note marks where it was.
- **Select several blocks:** Shift-click a block's ⋮⋮ handle to select a range (Cmd/Ctrl-click to add or remove one). A bar then lets you **Turn into**, **Color**, **Duplicate** or **Delete** them all at once. Esc clears the selection; Delete removes the selected blocks (with Undo).
- Links: an address typed and followed by Enter becomes a link right away.

## Version 2026-11cf (9 Nov 2026): clickable links and embeds in notes
Needs: upload `index.html` and `sw.js`.
- **Links work in notes:** web addresses you paste or type become links (when you leave the line), and clicking a link opens it in a new tab.
- **Embeds, like Notion:** paste a Google Drive file, Drive folder, Google Doc/Sheet/Slides or YouTube link on an empty line and choose **Embed: show it in the note** (or **Keep as a link**). Drive videos play right in the note; Docs, Sheets and folders show inside it. There's also an **Embed** block in the "/" menu and Insert below. Each embed has an "open in a new tab" link and a caption. (Viewers need access to the Drive file, as in Drive.)
- Exports: embeds become links in PDF, HTML, Word and Markdown.

## Version 2026-11ce (9 Nov 2026): approve each English change
Needs: upload `index.html` and `sw.js`.
- **Convert to English asks what to change:** every suggested change is listed on its own (the title, the details, and in notes each heading and paragraph), each with a tick. Untick anything you'd rather keep; **Replace** applies only the ticked ones ("Replace 1 of 2").
- **Development tasks** have a **Convert to English** button in the task's header (it was only in the "⋯" menu).

## Version 2026-11cc (9 Nov 2026): phone or laptop
Needs: upload `index.html` and `sw.js`; run `upgrade-2026-11cc.sql` (until then only the live "Online on …" label works; nothing breaks).
- **Online status shows the device:** "Online on laptop", "Online on phone" (or "on laptop + phone" when both are open), live, in the sidebar, chat and People. When someone is away: "Active 10 min ago on phone".
- **Check-ins remember the device:** Attendance shows "· phone" or "· laptop" next to each check-in and check-out time.
- **Work summary** (admins): time with the workspace open on each device for the day, week or month ("On laptop 6h 10m", "On phone 45m"), counted from the once-a-minute signal the app already sends while it's on screen. Only admins and people who can see attendance can read these times.
- Phone, tablet or laptop is worked out from the browser and screen (an iPad counts as a tablet; desktop computers count as laptop).

## Version 2026-11cb (9 Nov 2026): archive and delete tasks from the board
Needs: upload `index.html` and `sw.js`.
- **"⋯" on every task card** (Development board and the Tasks board): **Open**, **Archive** (or **Restore** in the Archived view) and **Delete**. It shows when you hover a card (always on phones).
- **Tasks can now be deleted** by admins and the people who manage that team's tasks (the same people the database already allowed). You're asked first. Deleting removes it for everyone with its comments and files; the database keeps a copy with its history for admins. Archiving is still the gentle option: it hides the task and you can restore it from Archived.
- Delete also appears in a task's own "⋯" menu for those people.

## Version 2026-11ca (9 Nov 2026): private clients, owners as testers, several owners
Needs: upload `index.html` and `sw.js`; run `upgrade-2026-11ca.sql` (until then clients work as before, without Team access).
- **Clients are private to the people given access.** A client, its contacts and its client-portal people are seen only by admins, people whose role includes "Sales: clients & contacts", the client's **account owner**, and people added to the client's new **Team access** list (enforced in the database). Everyone else doesn't see the client anywhere. People given access are notified, and the Clients section appears in their sidebar. The account owner can edit their client and its Team access, but can't hand it to someone else (only clients editors and admins can).
- **The people working on a development task can also be its tester:** the Tester (QA) list has the testers and a "Working on this task" group.
- **Several people on a task:** the full task form now says "Main owner" and "More owners (everyone else working on this task)" (the same people as the Owners chips on the board), and the Tasks "Anyone (owner)" filter finds a task under any of its owners, not only the first.

## Version 2026-11bz (9 Nov 2026): search messages in Chat
Needs: upload `index.html` and `sw.js`.
- **Search messages:** the Chat search box ("Search people, chats and messages") now also finds messages. Type two or more letters (or press Enter): matching messages from every chat you're in appear under **Messages**, newest first, with who sent them, which chat, when, and the words around the match highlighted. Only chats you're a member of are searched.
- **Click a result** to open that chat right at the message: older messages load as needed, and the message is centred and highlighted.
- Fixed: reading older messages, the chat could jump back to the top when someone's "seen" or a reaction arrived. It now stays where you are.

## Version 2026-11by (9 Nov 2026): admins can pass or fail a task waiting for a tester
Needs: upload `index.html` and `sw.js`.
- A Development task in QA that no tester had picked up showed only "Waiting for a tester", with no buttons for admins, so it couldn't be cleared (the database already allowed admins to decide). Admins now see **✓ Approve** and **Back to development** on it, with a note saying so.

## Version 2026-11bx (9 Nov 2026): Tasks says what needs you
Needs: upload `index.html` and `sw.js`.
- **The top of Tasks names what the sidebar number is about:** "1 task needs you", then each task with why (waiting for you to test it, waiting for your review, due today, overdue by N days), who it's from, and an **Open** button. It disappears when nothing needs you.
- Hovering the number next to Tasks in the sidebar names the tasks too (e.g. "waiting for you to review or test (TC-2218)").

## Version 2026-11bw (9 Nov 2026): fixes from the Problems list, Tasks number, notifications
Needs: upload `index.html` and `sw.js`.
- **Chat header no longer slips under the top bar.** The chat page was 44px taller than the window, so scrolling past the end of the messages moved the whole page. It now fits the window exactly, and scrolling inside the chat stays inside it.
- **Text colour in notes works again.** Colour (block menu › Color) had stopped showing after the Notion-style restyle: one of its rules overrode the colours.
- **Notes cards are square**, with the preview fading out instead of making the card tall.
- **Tasks number:** the number on Tasks counts your tasks due today or overdue and tasks waiting for your review or test. Tasks now has a **Needs you** filter showing exactly those, and clicking Tasks while it has a number opens that filter (it also opens first the first time you visit Tasks, if anything needs you).
- **Notifications** stay on screen when you open them on a scrolled-down page (desktop; phones already did).
- **Google Calendar sync** renews an expired sign-in and tries again, instead of failing with "Sign in again" after the computer wakes up.

## Version 2026-11bv (8 Nov 2026): calendars off the sidebar list
Needs: upload `index.html` and `sw.js`.
- **Calendar** and **Team calendar** are no longer listed in the sidebar (or in Recents). Both pages still work: the calendar icon at the top of the sidebar opens Calendar, and links to either page keep working.

## Version 2026-11bu (8 Nov 2026): Clients in its own sidebar group
Needs: upload `index.html` and `sw.js`.
- New **Clients** group in the sidebar, after Sales: **Clients**, **Requests & bugs** (the support tickets, including everything clients send from their portal) and **Contacts**. Clients and Contacts moved out of Sales.
- **Recents** in the sidebar shows just the last 2 places.

## Version 2026-11bt (8 Nov 2026): the client portal
Needs, in this order: upload `index.html` and `sw.js`; run `upgrade-2026-11bt.sql`; redeploy `admin-users-function.ts` (invites) and `google-sync-function.ts` (emails to clients). The app is safe before the SQL runs: the portal parts stay hidden until then.
- **Clients get their own login** at the same address. After signing in they see only their portal, never the workspace:
  - **Home:** what's waiting on them, quick buttons (report a bug, request a feature, ask a question, request a meeting), open requests, the next meeting with a Join button, and their account manager's contact details.
  - **Requests:** bugs, requirements and questions with status in plain words (Received, In progress, Waiting on you, Resolved, Closed), a conversation with the team on each, and screenshots or files (up to 10 at a time, 25 MB each). Replying to something resolved reopens it; answering "waiting on you" moves it back to In progress.
  - **Meetings:** upcoming client meetings they're invited to, with Join links. **Request a meeting** with up to three times in their own time zone; the team confirms one.
  - **Projects:** progress per project (worked out from the team's work items) and releases with notes.
  - **Files:** what the team shares with them, and files they send.
  - **Proposals:** sent proposals with amount, status and dates (drafts never show).
  - **Updates** (the bell) and **email**: replies from the team, status changes and confirmed meetings, from the notifications mailbox. **Profile:** name, phone, email updates on or off, password.
- **Inviting:** open a client › **Client portal** › pick a contact (or type a name and email) › **Invite to the portal**. Admins and the client's account owner can invite. The person gets an email with a set-password link; you can also copy the link and send it yourself. **Resend invite** and **Turn off / Turn on** per person.
- **Requests arrive as support tickets** (Reported via: Portal), assigned to the account owner, who is notified; new **Type** field (Bug / Requirement / Question) and a **Client portal** tick to hide an internal ticket from the client.
- **Replying:** comments on a client's ticket are **Internal note** by default; switch to **Reply to client** to send one to them (labelled "Sent to client"). Their messages show a "Client" label.
- **Meeting requests** show on the client: pick one of the suggested times to open a pre-filled meeting (client call, the client person invited, so they get the Google invite), or Decline with a reason. The client is told either way. Client people can also be invited to any meeting (Attendees › Client portal).
- **Files in the portal:** share contracts, designs or proposal PDFs with the client from the Client portal panel.
- **How clients are kept out of everything else** (all tested): a client login is never an active staff account (enforced in the database, even against admins), so every existing rule, list and job leaves it out; clients read and write only through portal functions that check their company on every call; each company has its own file folder; internal comments and staff notifications can never reach a client. Client logins don't appear under Admin › Users; they're managed on the client.

## Version 2026-11bs (8 Nov 2026): note pages look like Notion
Needs: upload `index.html` and `sw.js`. No database change.
- **Notion-style page:** white page (the top bar too), one reading column of 708px, and one typeface (Roboto) for the title, headings and text, as Notion uses one.
- **Notion's sizes and spacing:** title 40px bold; headings 30 / 24 / 20px bold with room above them; text 16px with 1.5 line height; a little space between paragraphs and tighter list items; numbered and bulleted lists with hanging indents; nested items indent under their parent.
- **Quiet top bar:** Back, the page path, Saved, Summarize, Convert to English, Share & details, Export and ⋯ are plain text buttons that grey on hover, in one row. On phones they become a row of icons (40px, easy to tap).
- **Outline on the right edge** (wide screens), like Notion: a short line for each heading, the current one darker. Hover to see the headings, click one to jump to it.
- Only note pages change; every other page looks as before.

## Version 2026-11br (8 Nov 2026): drop pictures exactly where you want, like Notion
Needs: upload `index.html` and `sw.js`. No database change.
- **Dragging pictures or videos in from your computer** (Finder, Desktop, another app) now shows a purple line between the blocks, exactly where they'll go, and drops them there: above the first line, between any two blocks, or below the last line. You can drop anywhere on the page, not only on the text. Several files go in one after another, in order.
- Replaces the dashed outline around the whole page, which put the picture under whichever block you were over.

## Version 2026-11bq (8 Nov 2026): moving blocks in notes, fixed
Needs: upload `index.html` and `sw.js`. No database change.
- **Drag the six dots to move a block**, rebuilt: a purple line shows exactly where it will land, and it lands there (dragging down used to put it one place lower than the line showed). The page scrolls when you drag near the top or bottom. A toggle moves with everything inside it. Esc cancels. A click on the dots still opens the block menu.
- **Works on phones and tablets** too (hold the six dots and drag with a finger); before, moving blocks only worked with a mouse.
- Fixed: dropping a file on a block also moved the first block of the note.
- Fixed: dragging selected text inside a note didn't work (and could move a block if the text was a number).
- Fixed: dragging a picture inside a note could upload it again; the dashed drop outline no longer gets stuck.

## Version 2026-11bp (8 Nov 2026): Insert below in the note block menu
Needs: upload `index.html` and `sw.js`. No database change.
- The six-dot block menu now has **Insert below**, with a side menu like Turn into and Color: **Image…** and **Video…** first (opens the file picker; the new picture goes under the block without replacing it), then every other block type (text, headings, page, lists, to-do, toggles, quote, callout, code, divider).

## Version 2026-11bo (8 Nov 2026): resize pictures and videos in notes
Needs: upload `index.html` and `sw.js`. No database change.
- **Drag to resize:** hover over a picture or video in a note page and drag the white bar on either side to make it smaller or bigger; it stays centred and shows the size while you drag. The size is saved with the note, and everyone sees it the same way. Double-click a bar to go back to full width. On phones the bars are always visible.
- Tall phone photos now start at a comfortable height instead of filling the whole column.
- HTML and PDF exports keep the size.

## Version 2026-11bn (8 Nov 2026): pictures and videos in notes
Needs: upload `index.html` and `sw.js`. No database change.
- **Add pictures and videos to note pages**, like Notion: type **/image** or **/video** (or use **Turn into**) to pick a file; **paste** a picture or screenshot straight in; or **drag and drop** pictures and videos onto the page (a dashed outline shows where they'll go). An empty line becomes the picture; otherwise it goes below.
- Each one has an optional **caption** underneath. Press Enter in a caption to keep writing below. Click a picture to open it full size. Videos play in the note.
- Anyone who can edit the note can add them; anyone who can open it can see them. They're stored like other note files (Google Drive or Supabase storage), up to 20 MB per picture and 100 MB per video. Other file types are refused, with a pointer to Share & details › Files.
- Exports: PDF and HTML include the pictures (in a downloaded HTML file, the picture links expire after a while); Word, Markdown and CSV show "[Picture: name]" with the caption.

## Version 2026-11bk (8 Nov 2026): note block handles like Notion
Needs: upload `index.html` and `sw.js`.
- The **+** and the **six-dot grip** beside each block are proper icons (18px in 24px buttons, grey, darker on hover) and sit centred on the block's first line for every type: text, headings 1–4, lists, to-dos, toggles, quotes, callouts and code.

## Version 2026-11bi (8 Nov 2026): tag people in notes; view or edit sharing; summarize notes
Needs: run `upgrade-2026-11bi.sql` (also adds the archive columns, so 11bf is no longer needed separately); redeploy `ai-assist-function.ts` (for the note summary wording); upload `index.html` and `sw.js`.
- **@ to tag in note pages:** type @ and a few letters; pick the person; their name goes into the note and they get a notification ("… tagged you in a note").
- **Share › Can view or Can edit:** people under **Can view** can open the note whatever its visibility setting; people under **Can edit** can also change its content. Only the owner can change sharing, archive or delete it (enforced in the database). New editors get a notification. The page says "you can edit" or "view only".
- **Tagging no longer gives access.** A tagged person is notified; if they can't open the note, its page says "You don't have access to this note" with **Request access**. The owner is notified and sees a bar on the note (page and popup): **Can view**, **Can edit** or **Decline**; the person is notified of the answer. One request per person per day.
- **Summarize** on every note page: Claude's short summary with key points and action items.

## Version 2026-11bh (8 Nov 2026): Back on note pages; archive and delete from lists; Archived filters
Needs: upload `index.html` and `sw.js` (Archive on notes needs `upgrade-2026-11bf.sql`).
- **Back** button at the top left of a full-page note: returns to where you came from, or to the parent page / Notes.
- **Notes list:** each of your note cards has a ••• menu: Open as page, **Archive** / Restore (with Undo), **Delete** (asks first; sub-pages go with it). Card previews show the words without the #, - and 1. markers.
- **Archived filters everywhere you can archive:** Notes › Archived, Tasks › Archived (as before), and a new **Archived** switch on the Development board (shows all archived work, however long ago it was done).

## Version 2026-11bg (8 Nov 2026): notes open as a popup first; one menu style everywhere
Needs: upload `index.html` and `sw.js`.
- **Notes open as the popup again**, with everything it had (title, text, who can see it, pin, sharing, links, comments, files). **Expand** in the popup opens the full Notion-style page. The sidebar's Notes list still opens pages directly. Editing the text in the popup updates the page's blocks too.
- **One menu style everywhere:** the task window's ••• menu (now with **Priority ›** opening to the side, Copy ID, Copy link, Summarize, Convert to English, Archive, Delete), the chat **Meet** menu and **your status** menu use the same Notion-style menu as notes.
- The notes page button reads **Convert to English**.

## Version 2026-11bf (8 Nov 2026): notes menus like Notion, Archive and Delete
Needs: run `upgrade-2026-11bf.sql` (for Archive); upload `index.html` and `sw.js`.
- **Turn into and Color open to the side** of the block menu (pointing at them is enough), with a › at the right edge, like Notion. The block menu items have icons.
- **Page menu (•••)** on every note you own: New sub-page, Copy link, **Archive** / Restore, **Delete** (asks first; sub-pages go with it).
- **Archived pages** leave the Notes list and the sidebar; find them under **Notes › Archived**. An archived page shows a bar with **Restore**. Archiving has an Undo.

## Version 2026-11be (8 Nov 2026): Claude helpers — Convert to English and Summarize
Needs: deploy `ai-assist-function.ts` as Edge Function **ai-assist**; the secret **ANTHROPIC_API_KEY** (same one as the work summary); upload `index.html` and `sw.js`.
- **Convert to English** on tasks (title and description; in the Development task view and the full task form) and on notes (title and every block). Claude rewrites Hindi, Hinglish ("ride booked ki 3 notification ayi…") or rough English as clear, proper English, keeping names, task IDs, numbers, links and formatting. You see **Now / In English side by side**; nothing changes until **Replace**, and an **Undo** follows. Chat messages are left alone.
- **Summarize** on any task (its details, history and comments) and on Home, Company overview, Tasks, the Sales and Marketing dashboards, Analytics and the Development board (what's on the screen). Opens in a window; only what you can already see is sent.
- Uses claude-opus-5-5 with server-side fallback (a declined request is retried on another model in the same call).

## Version 2026-11bd (8 Nov 2026): the whole site on one design system (Unslop)
Needs: upload `index.html` and `sw.js`.
- **One type scale everywhere:** 12.5 (IDs, counts), 13 (captions, labels), 14 (buttons, menu, secondary text), 15 (reading text), 16 (panel titles, notes), 20 (dialog titles), 26 (key figures), 28 (page titles), 36 (note titles). Poppins for headings, menu and buttons; Roboto for text. Sizes are now exactly what's set (no per-font scaling), and small text set inside pages can't fall below the scale.
- **One spacing grid (4px), three corner sizes (8 / 12 / 16), one accent** (Tcipher purple), quiet neutral surfaces, no hover lift.
- **Layout:** stat numbers fill one row instead of leaving an orphan card; side-by-side panels no longer stretch to each other's height; "+ New …" buttons use the line-icon plus.
- All design values now live in one block at the end of the stylesheet ("DESIGN SYSTEM").

## Version 2026-11bc (8 Nov 2026): notes as pages, like Notion
Needs: run `upgrade-2026-11bc.sql` (until then notes still save their text, and the page says formatting is kept for that visit only); upload `index.html` and `sw.js`.
- **Every note opens as a full page you write in directly**: a big title, then blocks. Saves by itself as you type ("Saving… / Saved", or "Saved on this device" on a bad connection).
- **Blocks:** text, headings 1–4, bulleted / numbered / to-do lists, toggle lists and toggle headings 1–3 (sections that open and close), quote, callout, code, divider, and **sub-pages** (a page inside a page).
- **Type "/"** for the block menu, or use shortcuts at the start of a line: `#`, `##`, `###`, `-`, `1.`, `[]`, `>` (toggle), `"` (quote), ```` ``` ```` (code), `---`. Tab / Shift+Tab indent; Enter on an empty list item ends the list; Ctrl/⌘+D duplicates a block; bold, italic, underline and links work with the usual keys.
- **The ⋮⋮ handle** beside each block: Turn into, Color (text and background colours), Duplicate, Move up / down, Delete; drag it to move the block.
- **Sidebar › Notes opens into the list of pages**, with sub-pages nested under their page, and **New page** at the bottom.
- **Export** any note as **PDF** (the print window, "Save as PDF"), **HTML**, **Markdown & CSV** (a .zip with both) or a **Word file** (.docx).
- Sharing, links to tasks / projects / meetings, comments and files stay under **Share & details**. Older notes open as pages too: their lines become paragraphs, lists and headings.

## Version 2026-11bb (8 Nov 2026): nothing lost on a bad connection
Needs: upload `index.html` and `sw.js`.
- **Saves that fail because of the connection are kept on the device.** Creating or editing tasks, leads, deals, clients, contacts, notes, documents, meetings, leave, attendance, comments, time logs and the other work records: if the connection drops or is too slow, the change is kept on this device, shown as saved, and a bar says "N unsynced changes · **Sync now**".
- They're sent again automatically when the connection comes back, when you return to the tab, and every 30 seconds; or right away with **Sync now**. New records get their id on the device, so sending one twice never makes a copy.
- Changes the server turns down (not allowed, invalid) still show their error as before and are never kept. If you try to close the page while offline with changes waiting, the browser asks first.

## Version 2026-11ba (8 Nov 2026): work summary for admins
Needs: run `upgrade-2026-11ba.sql`; deploy `work-summary-function.ts` as Edge Function **work-summary**; add the secret **ANTHROPIC_API_KEY** (Edge Functions › Secrets); upload `index.html` and `sw.js`.
- **Admin › Work summary:** pick a person and a day, week or month. At the top, Claude (claude-opus-5-5) writes an at-a-glance summary: done, in progress, communication, time and attendance, and what needs attention. Underneath, **every detail** as a timeline, day by day, filterable by kind, with totals (hours logged, tasks finished and worked on, comments, messages, emails, meetings, days checked in).
- Reads the person's action log, task changes, comments, time logged, attendance and status, leave, meetings joined, test runs, sales and marketing record changes, emails sent from the workspace, and messages in channels and groups. **Private direct messages are never read.**
- Summaries are saved (new table `work_summaries`, admins only), so reopening is instant; today / this week / this month refresh after 30 minutes or with **Refresh summary**. Server-side fallback is on, so a declined request is retried on another model in the same call.

## Version 2026-11az (8 Nov 2026): sidebar sections and font sizes
Needs: upload `index.html` and `sw.js`.
- **Sidebar sections** (Development & QA, Communication, Sales, Marketing, Company) each have an icon and an arrow that always shows: pointing right when closed, down when open. Their pages sit indented on a thin guide line underneath, so it's clear they belong to the section and that it can be closed.
- **Every sidebar icon is in the theme purple** (pages, sections, Home / Chat / Calendar, New task, Hide sidebar, search).
- **Font sizes:** Roboto (body text) renders about 6% larger; Poppins (headings, menu, buttons, labels) about 10% smaller.

## Version 2026-11ay (8 Nov 2026): easier to read
Needs: upload `index.html` and `sw.js`.
- **Body text is 15px** (was 14) with roomier line spacing; tables, chat messages, comments and descriptions follow.
- **Nothing below 13px:** hints, dates, meta lines, labels and small notes are lifted to 13–14px.
- **Bigger headings:** page titles 26–32px, panel titles 17px, pop-up titles 21px, task titles 26px, key figures 26px.
- Sidebar links and section names 15px.
- **Chat on phones with the keyboard open:** the chat pins itself to the visible part of the screen, so the header stays at the top and the message box sits just above the keyboard; the bottom bar steps aside while you type. Android also resizes the page for the keyboard now (`interactive-widget=resizes-content`).

## Version 2026-11ax (8 Nov 2026): Poppins and Roboto
Needs: upload `index.html` and `sw.js`.
- **Poppins** is the main font (titles, headings, menu, buttons, labels, key figures) and **Roboto** the second (body text, tables, chat, notes, fields), replacing Montserrat and Lora. Task IDs and counts keep the fixed-width font.

## Version 2026-11aw (8 Nov 2026): Lora as the second font
Needs: upload `index.html` and `sw.js`.
- **Lora** replaces Roboto as the second font: body text, descriptions, tables, chat messages, notes and everything you type. Montserrat stays the main font.

## Version 2026-11av (8 Nov 2026): Montserrat and Roboto
Needs: upload `index.html` and `sw.js`.
- **Montserrat** is the main font: page titles, headings, the sidebar menu, buttons, field labels, table headings and key figures.
- **Roboto** is the second font: body text, descriptions, tables, chat messages, notes and everything you type.
- Task IDs, counts and keyboard hints keep the fixed-width font (JetBrains Mono).

## Version 2026-11au (8 Nov 2026): white sidebar
Needs: upload `index.html` and `sw.js`.
- The sidebar's background is white (#FFFFFF), with the hairline edge separating it from the page. Layout unchanged.

## Version 2026-11at (8 Nov 2026): sidebar background
Needs: upload `index.html` and `sw.js`.
- The sidebar's background is back to the light grey from before the Notion-style change (#FBFBFB, with the same hairline edge as the rest of the app). Its layout is unchanged.

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
