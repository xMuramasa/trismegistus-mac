# trismegistus-mac: spec v1.1 (2026-10-31)

A native macOS companion for Hermes Agent, living in the menu bar. It talks to the Trismegistus relay
(`xMuramasa/trismegistus`, deployed at `hermes.lab.x-muramasa.dev`) over the same WebSocket protocol as the Android
app, so the relay needs no changes. Scope mirrors the phone app: replies, live tool progress, approvals for risky
commands, session list. Martin's laptop is the target; nothing is distributed.

## Decisions

- **Native Swift, not a wrapped web build.** Expo's web export in Tauri/Electron was rejected (a web UI in a window).
  Expo has no supported desktop targets; Linux has none at all. The relay and the phone app already share no code,
  only the protocol, so a native client per platform is the same pattern.
- **Menu bar app** (`MenuBarExtra` with the window style), not a Dock app: a companion that shows progress and asks
  for approvals belongs in the menu bar. SwiftUI, macOS 26 only (Martin's machine), Swift 6 strict concurrency.
  Plus a **main window** (decided 2026-10-31, #4) for long work: conversations | chat, with a terminal under it. The popover stays for
  a glance and approvals and opens the window. Opening the app yourself (Finder, Spotlight, the Dock, or again while
  it runs) opens the window; a launch at login stays in the menu bar (`SMAppService` login items don't carry
  `keyAELaunchedAsLogInItem`, so a launch within a minute of Finder's, which starts with each login session, counts
  as one). Automatic termination is disabled, so macOS
  never quits it quietly while no window is open; Settings has Quit (⌘Q).
- **Design:** the UI draft in Penpot (#5, exports in `design/ui-draft/`), approved by Martin on 2026-10-31 for the
  beta. Endfield design language (paper and ink, yellow for the one primary action, hairlines, key-hint strip; square
  edges until #68; since #69 the window wears **a3**, Endfield-faithful, with its own small radii: `Radius.tag` 3 state
  tags, tags, key caps; `control` 4 cards, rows, buttons, fields, avatars, panel rows; `s` 6 menus; `m` 8 the section
  panel; `pill` 15 the model dropdown; the chat's transcript and composer keep #68's `l` 12 / `xl` 16 until their own
  redesign; edge-to-edge bands and the 8 pt identity squares stay square), **light mode only** (forced at launch with `NSApp.appearance = .aqua`, so a Mac in dark mode doesn't turn system-colored text white on paper), **Inter and JetBrains Mono**, bundled (SIL OFL; #33; Inter up to Black for the B2 sidebar, #65). Every colour, spacing, type role, size, radius, stroke, opacity, shadow and motion value comes from `design/tokens.json` through `scripts/gen-tokens.py` into TrismegistusUI's generated `Tokens.swift` (`Ink.*` roles, `Palette.*`, `Space.*`, `.typeRole(_:)`, `Size.*`, …); `scripts/check-tokens.sh` fails on a stale `Tokens.swift` or a raw literal in a view. Spacing is a strict scale (2, 4, 8, 12, 16, 20, 24, 32, 40). Native controls
  with an Endfield surface; custom views only for content and identity (see the Controls page). Colors come from the
  Endfield palette (`endfield-dotfiles/theme/palette.json`), copied into an asset catalog. Buttons carry a trailing SF
  Symbol; obvious actions (copy, new, send, stop, retry, open window, terminal) are icon-only with the word as tooltip
  and accessibility label; Once / Session / Deny, Pair, Unpair and Steer keep their words. Session sources are icons.
- **Two targets in one repo.** `TrismegistusKit` is a Swift package: protocol types, the relay client (WebSocket +
  REST), reconnect/replay, the state model. Pure Swift, no UI, no dependencies beyond Foundation. `App/` is the
  SwiftUI app and depends on it. The split is what makes the server useful: the Kit's tests run over SSH with
  `swift test`; only the app layer needs Xcode.
- **Protocol types are hand-written `Codable` enums**, discriminated on `type` (and `kind` for events), not
  generated. 14 message types and 13 event kinds is small, and generators handle `oneOf` poorly in Swift. The
  contract is enforced by tests, not by a generator: every file in `protocol/examples/valid/` must decode and
  round-trip; every `invalid/` file must either fail to decode or be listed in `Tests/.../relay-enforced.txt` with
  the schema constraint that only the relay checks (lengths, patterns). `protocol/` is a copy of the trismegistus
  repo's folder (`scripts/sync-protocol.sh`); a test compares sha256s and fails when the copy is stale.
- **Pairing:** `trismegistus-relay pair --name macbook` prints a QR and a code. The Mac has no camera flow: paste the
  code (or the QR's payload) into the pairing sheet. The token goes in the **login Keychain** (`kSecClassGenericPassword`,
  local to the Mac, never synced), never in UserDefaults, logs or the repo.
- **Notifications:** `UserNotifications` from the open socket (approval requested, run finished, run failed). No push
  service: the Mac holds its own connection. **Run alerts** (#66): only runs the relay sees (prompts from the Mac or
  the S21, Telegram chats continued in the app; not Telegram-direct, terminal or cron runs), from any device. A run that
  finishes or fails while nobody looks at its conversation (open in the window's Chat or the popover's chat, the app
  active or the popover key, that window on screen and not covered) marks it **done** or **failed** (`Unseen` in the
  Kit; failed outranks done and stays after a later success; a stopped run makes nothing) and plays its sound. Opening
  the conversation is the only way to clear a mark (no "Mark as read"); it clears every part of the thread. Marks are
  local to this Mac (UserDefaults `notifications.unseen`) and survive a restart: the app records `trackedUntil` every
  30 s while connected and at quit, and after the launch's first list load gives a done mark, without sound, to app
  conversations active more than 5 s after it (the first launch ever marks nothing), leaving those still running to
  their run's end; a gap of more than 75 s in that record while the app runs (the Mac asleep, the relay unreachable) is
  caught up the same way at the next list load once connected again; list loads drop marks of
  conversations that left the list. Sounds go through notifications, so Focus and System Settings apply: one
  notification per sound, the banner with its sound while nothing of the app is on screen (run banners only then;
  approval banners always), else the sound alone (presented with `.sound` only and removed from Notification Center 2 s
  later). At most one run sound per 2 s (`SoundGate`); approval sounds are never dropped. A chosen system sound is
  copied from `/System/Library/Sounds` into the container's `Library/Sounds` (where `UNNotificationSound(named:)` looks)
  when picked and before it plays.
- **Xcode project generated by xcodegen** from a committed `App/project.yml`; the `.xcodeproj` is git-ignored.
  xcodegen 2.46.0 is installed from its GitHub release zip (checksum checked) in `~/.local/opt/xcodegen`, with a
  wrapper at `~/.local/bin/xcodegen` (no Homebrew on the Mac).
- **Signing: Martin's Personal Team `22GV3A4KF8`** (free, his personal Apple ID; set up 2026-10-31). Never the work
  team whose Apple Development identity is also on the Mac, and no `DEVELOPMENT_TEAM` in `project.yml`. Over SSH
  the signing key can't be used (`codesign`: errSecInternalComponent), so `scripts/mac-build.sh --install` signs
  ad-hoc and installs `~/.local/bin/trismegistus-open` (`scripts/mac-open.sh`). Martin runs that in his own Terminal
  instead of opening the app: it re-signs the app with the team's Apple Development certificate (dylibs first,
  entitlements kept) unless it already carries the team, then opens it; `--check` reports what it would do and works
  over SSH. With a team signature the Keychain "Always Allow" and the login item survive rebuilds (an ad-hoc
  signature changes with every build). The token stays in the login keychain; no provisioning profile is needed for
  the sandbox and network entitlements.
- **Build loop:** Hermes on optiplex, over `ssh mac`: `scripts/mac-build.sh` syncs the worktree to its own cache dir,
  runs `xcodegen generate` and `xcodebuild` (compile check, unsigned); `--install` builds ad-hoc signed and copies the
  `.app` into `~/Applications/`. Martin opens the app himself (the script never launches it). Kit tests run with
  `scripts/linux-test.sh` and `scripts/mac-test.sh`. The Mac is kept awake by caffeinate.
- Tracking: GitHub Issues on this repo plus the "Work" project. Direct commits to `main`, `Fixes #N`.

## Architecture

```
TrismegistusKit/
  Sources/TrismegistusKit/
    Protocol/      Message.swift (ClientMessage, ServerMessage enums), Event.swift (kind + data), Codable glue
    Relay/         RelayClient (actor): connect, auth, subscribe, send; URLSessionWebSocketTask; ping every 25 s,
                   drop after 2 missed pongs (mirrors the relay); reconnect with backoff (1 s doubling to 30 s);
                   resubscribe from the last seq per session; replay_gap → reload history over REST
                   RelayREST: sessions list/create/rename/delete, messages (same endpoints the phone uses)
    State/         SessionStore (@Observable): sessions, per-session event list, run status, pending approvals,
                   dedupe by (session_id, seq); the rules from trismegistus issues #10/#11 (replay_gap filter,
                   late history) implemented and tested here from day one
    Keychain/      TokenStore protocol + KeychainTokenStore + InMemoryTokenStore (tests)
    Terminal/      TerminalLink (actor): one shell over `/api/terminal`, read one frame at a time with `next()`;
                   TerminalSocket: the socket with binary frames and close codes
  Tests/TrismegistusKitTests/
    ContractTests  (examples round-trip), RelayClientTests (against an in-process WebSocket fake serving recorded
    frames: auth → ready, subscribe → replay → live, ping/pong, drop → reconnect → resubscribe), StoreTests
App/
  project.yml, Trismegistus/ (App.swift with MenuBarExtra, MenuView, SessionList, ChatView, ApprovalBanner,
  PairingSheet, SettingsView, NotificationCenter glue), Resources/
protocol/            copy of xMuramasa/trismegistus protocol/ (schema.json + examples)
scripts/             sync-protocol.sh, mac-build.sh (the SSH build loop, run from optiplex)
```

## Surfaces (v1)

- **Menu bar icon:** state in the glyph (a template image: shape, never colour): disconnected (outline), connected
  idle, a run in progress (bars), an approval waiting (dot), a run failed unseen (a cross where the dot sits), a run
  finished unseen (a check there; #66, design 12 `#menubar`). Priority: disconnected, approval, running, failed, done.
  Click opens the popover.
- **Popover:** session list (name, source icon, read-only lock, last activity, RUN / APPROVAL stickers) → chat view:
  messages, foldable tool rows with duration and error flag, subagent rows, the answer rendered as Markdown, a working
  indicator, a composer; `⌘↩` sends. One run per session: a prompt during a run offers "send as steer". Header:
  connection status, open window, settings. Empty and reconnecting states as drawn.
- **Composer** (#47, popover and window): a multi-line plain-text editor (`NSTextView`). Return and ⇧↩ insert a
  newline, `⌘↩` sends or steers (the button's shortcut; with Send disabled it does nothing), Esc stays the popover's
  Back. Spell check on; smart quotes and dashes, text replacement and auto-correct off (prompts carry commands and
  code); rich text pastes as plain, ⌘V with an image still goes to the tray, dropped text lands in it. It grows from
  one line to 10 lines in the window and 6 in the popover, then scrolls inside, and shrinks back as text goes. A
  grabber on its top edge drags it taller, up to half the chat column; that height is its minimum (kept in the window,
  `composer.height`) until a double-click on the grabber. Sending trims only leading and trailing whitespace. The
  protocol caps text at 32,768 characters (Unicode scalars): from 30,000 a counter `30,512 / 32,768` shows under it,
  red over the cap, where Send is disabled.
- **Main window: three columns** (#68, design 13 `#a2` in `design/opendesign/13-three-column/`, skinned `#a3` in #69; our own layout,
  `WindowColumns`, not `NavigationSplitView`): a floating **section panel**, the **list column** and the **detail**, and
  in Chat the terminal drawer under the detail (`⌘⌥T`, #64). The title bar is transparent over a full-size content view
  (`.hiddenTitleBar`) and there is **no top bar**: the window's buttons sit in the panel's top row (moved there by
  `TrafficLights`), the sidebar toggle at its top-right; the link moved to the device row, the terminal toggle and
  Settings into the detail headers. The panel (#69) is translucent dark-panel grey (93 % at the top to 86 % at the
  bottom) with a faint white hairline, `m` corners and its top-right corner cut at 45°, no shadow; 300 pt, 8 pt in from
  the window's top, left and bottom. Under the top row a `// TRISMEGISTUS ——— v0.9` label line, then a **tree** of 36 pt
  rows (icon, label in Inter 13/500 on-steel, what it says at the right in contour grey; Martin, 2026-11-10): **Chats**
  first (white, 600), with a chevron beside it that folds its children (`window.chatsOpen`), then the kinds indented
  under it along a vertical hairline under its icon: App, Telegram, Terminal, One-shots, Cron, any other source by name
  and All, with counts and a glyph-only tag of their strongest state; picking a kind elsewhere switches to Chat. Then
  GitHub (Needs-check count), Agents (running count), Jobs (failed mark) and Commands. The deepest current row you can
  see is **lit** (white at 10 %, white 600 text) with a 3 pt yellow bar at its left edge: the current kind while in Chat,
  Chats itself while folded (it then shows Chat's strongest state), else the section. The window's ground under panel and
  list is the contour paper (`EndfieldBackdrop`). The **device row** at the bottom (28 pt avatar, `macbook` 13/600, a dot with `linked · <host>`, `connecting · …` or `offline · …`,
  and `…` with Settings and Unpair, which opens Settings' confirmation through `settings.confirmUnpair`). Hiding the
  panel (its toggle, View menu, ⌃⌘S) leaves list and detail; the list header then keeps room for the window's buttons
  and the toggle. The list column is lightly frosted (sunken at 42 %), 380–720 pt (520 by default, `window.listWidth`, dragged at its rule), and
  gives way to keep the detail 484 pt wide, so at a 1180 pt window it is 380. **Five sections** (#41, #57): Chat,
  GitHub, Agents, Jobs, Commands, picked in the panel or with ⌘1…⌘5 (View menu; tooltips `Chat (⌘1)` …). Each section
  has its own list (a header with the title centred, `// APP` in tracked caps then the count as the one large numeral,
  28/500, and the section's actions at the right; a filter with its `⌘K` key cap, which ⌘K focuses; arrow keys move the
  selection) and detail. Chat's header has `…` (Rename, Tags, Hand off for the open conversation) at the left and the
  yellow `+` at the right, which steps down to a thin-edged white button while the open conversation runs (Steer is the
  yellow action then). Every detail starts with the frosted `DetailHeader` (52 pt: 28 pt avatar, title 14/600 and
  subtitle 11 pt on the left; its readings and actions, then the terminal and Settings buttons, on the right; under it
  the 2 pt title rule, edge to edge: rule grey with an 8 pt dark-panel tick and, after a 4 pt gap, a 56 pt yellow
  segment). Details: Chat the conversations (pin, rename, tags, delete, new)
  and the conversation; GitHub the Work board by status (repo, priority and list-kind pickers, Done folded) and the
  issue; Agents the runs and the agent's detail: the result on top, then the run's steps as tool rows; Jobs the
  jobs (+ New job; rows `daily 03:00 · next 13 h · ok 10 h`) and the job's detail (a pinned header with Pause, Run now and
  Edit; a readout of cadence, the next 3 runs and the last result; the prompt as Markdown folded at 160 pt; the runs;
  the settings), or the form in its place while editing (24-hour time picker); Commands "All conversations" and the conversations with matching
  calls (the filter is the log's search) and the log (failed-only in its header). Each section keeps its own selection
  (`window.section`, `window.selection.<section>`; Chat keeps `window.selectedSession`). Opening a conversation from
  GitHub, Agents, Jobs, Commands or a notification switches to Chat with it selected. The list column's ground is sunken
  at 42 % (`surface.sidebar`) with ink text (`text.on-sidebar`, `text.on-sidebar-secondary`); every row there is a card
  (below), Chat's a mission card (#72), the other sections' with their own content. The daily feed runs are ordinary read-only
  cron conversations, listed like every other cron run (the news itself is read at news.lab.x-muramasa.dev).
  The GitHub issue (#59): the header with `done/total` of the body's task list, a readout row (Status and
  Priority menus for a manager, Tags, Agent, Close/Reopen), then body and comments through the Markdown renderer in a
  720 pt column with read-only task boxes. An issue in Needs check opens with Hermes' "look at" lines as a numbered
  tick list (ticks are a local aid, kept per issue while the app runs, never sent and never required) above Looks
  good / Not right; after either it folds to one line until the issue leaves Needs check.
  **Chat kinds** (#48): in the window the panel's Chats group (above), and the list header names the kind
  (`TELEGRAM // 4`). The popover keeps a row of bare icon tabs under its header: APP `macwindow`, TELEGRAM
  `paperplane`, TERMINAL `terminal`, MORE `ellipsis.circle` ▾, each with its count, the current one with an ink bar and
  a dot on the icon (magenta while an approval waits, green while a run goes). Tooltips carry the full name.
  The list shows the chosen kind only, by Hermes' `source`: **APP** `api_server` (the default), **TELEGRAM**
  `telegram`, **TERMINAL** `cli` and `tui`; the **MORE** menu has One-shots (`oneshot`), Cron, any other source by its
  name and All (in the popover, with a MORE entry chosen its icon and count take MORE's place, `⚡ 6 ▾`). The header count is the tab's; an
  empty tab says `No conversations from the terminal`. A pinned conversation shows only in its own tab (pinned first
  there). ⌘K filters within the tab; when it finds nothing there but matches elsewhere a row `2 more in TELEGRAM ›`
  switches tab. A tab is marked by its conversations' strongest state (approval > running > failed > done, the last two unseen run
  ends, #66; MORE shows the strongest among its entries): in the popover a dot for approval and running, the cross or
  check for failed and done. Opening a conversation
  from a notification, Jobs, GitHub, Agents or Commands switches to its kind's tab (All stays All), + New makes an app
  conversation and switches to APP, and a tab switch keeps the open conversation in the detail until another is
  picked. A Telegram chat continued in the app is an app conversation (APP, its Telegram part folded above). The
  popover's list has the same tabs and follows the window's (one choice, `chat.kind`).
  The Commands section's conversation list is not filtered. The chat keeps messages and answers; each run shows one chip (`>_ 4 COMMANDS · 6.1 s · 1 failed`) that unfolds the run's cards in place (#58); Hermes' answers render lists, task lists and headings, and the input sits in one composer block with the run line above it.
  The chip's context menu has "Show in Commands", which opens Commands with this conversation selected. In the window
  the composer is a floating block (`xl`, a 1 pt rule edge, 8 pt in from the detail's sides and bottom; in the popover
  a band with a rule on top); messages and code blocks have `l` corners, the chip `m`. **No mono outside code blocks
  and the terminal drawer** (#68): `YOU // 13:42`, `HERMES // …`, run times, the run line and its key caps are Inter
  with tabular figures; inline code is an Inter chip on sunken.
  The **Commands** section lists recent calls across conversations, grouped by conversation with the newest first (filters: failed, conversation,
  search; One line, on by default, shows each call as a row), synced incrementally and cached per relay in the app's Caches (deleted on unpair). It is not
  a shell; a call's card shows `$ command`, then output, exit code and duration. Live output arrives when a command
  finishes and is cut at 4,000 characters; past calls come from the Hermes history (every source, output in full).
  The **terminal drawer** (#64) is a real shell on optiplex, as the user Hermes runs as, in `~`, streamed over the relay
  (`/api/terminal`, trismegistus#31); the app starts no local process. The detail header's terminal button and `⌘⌥T` (View menu) toggle it
  under the composer at the detail's full width, Chat only: elsewhere the button is disabled with "The terminal pane is
  Chat only". SwiftTerm's `TerminalView` fed by `TerminalLink`: `xterm-256color`, selection, copy, paste, 10,000 lines of
  scrollback, `dark-panel` ground, `on-steel` text, yellow cursor, the 16 ANSI colours from `color.role.ansi`, JetBrains
  Mono 12 (the font's own line height: SwiftTerm has no line spacing). 200 pt tall; dragging the top edge sets 120–480 pt
  (`window.terminalHeight`). One shell per app run: hiding the drawer or closing the window keeps it, and unpairing ends
  it. The drawer stays closed at launch, so no shell starts until it is asked for. When the shell ends a muted line says so (`[shell ended · exit 0]`, `[connection lost]`,
  `[terminal closed by the server: access ended]`) and the next Return or the next open starts a new one; the app never
  reconnects a shell on its own. A refusal shows the relay's message as it is, plus the `systemctl --user start
  trismegistus-term` fix for `unavailable` and `not_configured`.
- **The a3 skin** (#69, design 13 `#a3` and `#a3-<section>` in `design/opendesign/13-three-column/`, Martin
  2026-11-10; it replaced B2 (#65, #68) in the window): no black on light grounds (ink is for text), yellow as a line
  rather than a fill (the `+`, the title rule's segment, the lit row's bar, the RUN tag), quiet type (titles Inter
  13/500, 600 for a state, the selection or the current row; uppercase only for tracked `//` labels, 10/600/0.14 em; no
  weight above 600 in the window, tested), no offset shadows (depth from layers: the dark panel, the frosted list, white
  cards, the frosted detail header). Inter only, with tabular figures for data (`.monospacedDigit()`), so the ticking
  clock keeps its width. The filter is white with a rule hairline and `control` corners (blue while focused) and a sunken
  `⌘K` key cap; icon-only actions are thin-edged `control` buttons (white at 70 % in the list, bare in a header), the
  `+` yellow with a yellow edge and a glow under the pointer. Section heads are 24 pt `// PINNED ——— 04` label lines (a
  contour hairline runs to the 2-digit count); since #72 the chat list has its own heads (below). Until #72 a
  conversation was a 46 pt **card** at a 50 pt pitch (`SessionRowView` in the list column; the mission card replaced it), `control` corners,
  white stepping from 94 % to 72 % (lit from above) with a contour hairline; on it the muted 2-digit index (its place in
  the list), a 26 pt source avatar (the app's `T` on dark-panel, Telegram on blue, the terminal on dark-panel, cron on
  sunken), the title and the 11 pt age, then the list's `preview` as the relay sends it (only when the conversation has a
  title), the tags (sunken `tag` chips, 10 pt, at most 2 + `+N`), the state tag and the pin or lock. The other sections'
  rows are the same cards around their own content. Hover: white with a contour edge. The **selection**: the card white,
  a 1.5 pt yellow frame with a faint glow, 6 pt grey bracket corners 6 pt outside it and a short diagonal hatch on its
  top edge (the list header has one too); its cell is 8 pt taller each side for them (a `List` clips each row), and
  opaque strips in the list's ground over the List's 8 pt margins hide macOS's selection highlight there. A card has no
  `…` of its own (the list header's acts on the open conversation); right-click has the full menu. A **state tag** says
  the state: 18 pt, a light chip with a rule hairline and `tag` corners, a 2 pt bar in the state's colour at its left
  edge, the small glyph in that colour (diamond, ring, cross, check) and the word in tracked caps: APPROVAL magenta,
  FAILED terminal-red, DONE terminal-green; RUN is the dark-panel chip with a yellow bar, ring and time. Word plus shape
  always; VoiceOver reads the row as `Android app, approval waiting, 2 h, read-only, pinned`. Glyph-only tags (16 pt)
  mark the panel's rows. The popover stays white with its yellow bar and its fonts, with the same tags on its rows'
  corners (the shared part), the `…` on the tag line and the pin after the age.
  **The chat list as mission cards** (#72, design 13 `#a3-c2`, render 15b, after Endfield's mission list; Martin
  2026-11-10): each conversation is a `MissionCard` 56 pt tall, 10 pt in from the list's sides, 12 pt apart, white at
  90 % with a rule hairline and `control` corners, a 3 pt bar at its left edge (yellow running, magenta approval,
  terminal-red failed, terminal-green done, contour otherwise); a contour triangle (point down) with the source glyph in
  its upper part (the app's `T`, Telegram, the terminal, cron), a divider, the title 14 pt (500; 600 with a state or
  selected) with the pin, the preview 12 pt with the lock when read-only; the age over a short hatch at the right. **No
  tags and no index on the card** (tags stay in the filter and the detail header). The state is a 19 pt pill half over
  the top edge, 10 pt in from the right: RUN yellow with an ink ring, the clock and the ticking time; APPROVAL magenta
  with ink text; FAILED / DONE white with a red cross / green check (a run that ended unseen, #66; the panel's Chats
  and kind rows and the popover's rows and tags carry the same states). Hover: white with a contour
  edge and a soft shadow. Selected: a 1.5 pt ink frame with a 0.5 pt ring and a soft shadow, a yellow wash from the left
  edge (gone by 150 pt) over faint 135° stripes, the triangle and divider in ink. Each card's row holds the pill's room
  above the card (a `List` clips each row); the selected one's is 8 pt deeper for its shadow. Groups: **In progress** on
  top while any conversation waits for an approval or runs (approvals first, then runs, each most recent first, pinned
  or not; `SessionListing.groups`), headed by a small right-aligned `In progress` with a contour line to its left and a
  yellow bracket; then **Pinned** and **Conversations**, each under a head with a 22 pt yellow square holding its ink
  glyph (pin, chat bubble), the label 14/500, the count and a contour hairline under it. With nothing live the group is
  absent. The panel's counts, the kind filter, the context menu, selection, keyboard and drag are as before
  (`conversationChrome`). The popover keeps #69's rows, heads and tags.
  The other sections in a3: `//` labels on their cards (`// RESULT`, `// PROMPT`, a comment's author), section cards
  white at 88 % with a rule hairline and `control` corners, the segmented control (GitHub's Board / Needs check) white
  with the chosen part ink and underlined in 2 pt yellow, the Needs-check panel's 2 pt yellow top line with a faint glow,
  a run's steps under a `// 9 STEPS` label line (no orange header, no accent column), job readouts and times in Inter,
  Commands' one-line calls as light rows 4 pt apart with a 3 pt terminal-green or terminal-red left edge (the command
  itself stays mono), status chips as light tags with a coloured bar, and buttons as thin-edged `control` rectangles in
  tracked caps (`hairlineControls`: on in the list column, the detail headers, the sections' details and the chat).
  **The chat in a3** (#71, design 13 `#a3`, render 13e-a3-chat): the transcript and the composer sit straight on the
  backdrop (no paper column). Labels `YOU // 13:42`, `HERMES // 13:49` tracked 10/600/0.14 em, `secondary`; your
  message 14 pt on white at 85 % with a rule hairline, `control` corners, 8 x 12 in; Hermes' reply 14 pt with no box,
  list bullets 4 pt `secondary` squares, inline code Inter on sunken (square: a text background can't be rounded). Code
  blocks sunken with a rule hairline and `control` corners, JetBrains Mono (code is the one mono exception), a shell
  prompt's `$` terminal-green and a shell comment line `secondary`. The commands chip white at 70 % with a rule hairline,
  `control` corners, 10/600/0.12 em; its unfolded item cards keep their look. WORKING tracked, then on the same line a
  2 pt `rule` track with a yellow segment (30 %) going to and fro, parked at the start under Reduce Motion. The approval
  block white with a rule hairline and `control` corners, no yellow bar and no shadow; Once the yellow action, Session
  white with a `secondary` edge, Deny a red outline. The composer floats 8 pt in, white at 82 % with a rule hairline and
  `m` corners; its run line tracked after a 6 pt square; the field's edge `contour` with `control` corners; Stop with a
  rule edge. The popover's chat keeps #68's look. The window has no custom menus, tooltips or toasts: those are AppKit's.
  Departures from the token rules, by design: cards have fills; translucent tinted fills rather than materials (nothing
  scrolls under the panel, the list or the header, and a material's blur would wipe out the contour lines the list is
  meant to show faintly); the glows (`selection-glow`, `check-glow`, `plus-glow`); the 50 pt pitch. A `.shadow` goes on
  the fill alone: on a stack it is one shadow per child.
- **Thinking and effort** (#74, design 16 `#16a`, `#16d`, `#16-states` in `design/opendesign/16-qol/`; relay
  trismegistus#32): in the window's chat a finished turn with stored thinking (the history's `reasoning` on assistant
  messages) gets a `∴ THINKING · N STEPS ⌄` chip under its answer, in the commands chip's style and before it (N: the
  turn's assistant messages with thinking; no chip without any: effort Off, a model that doesn't think, older
  conversations). It unfolds a panel (white at 80 %, rule hairline, `control` corners): one row per step, `01`, the
  thought (13 pt secondary, 1.45 line height, folded to 3 lines with an underlined `more`) and what it led to
  (`→ terminal · <its argument in short>`, `→ terminal, read_file · 3 calls`, `→ answer`), split by `#ECECEC` hairlines.
  Folded by default; each fold holds while the conversation stays open. During a run the WORKING line goes on with
  `· thinking: "<first line of the newest stored thought>"`, one line cut at its tail: the runs API doesn't stream
  thinking, so the store fetches the end of the history 1 s after the last `tool.completed` (one fetch at a time,
  the live timeline untouched); the chip comes when the run ends and the history reloads. The `∴` is the system font's
  (Inter has none). **Effort** is its own pill right of the model's in the window header (`∴ High ⌄`, `∴ Default` in
  secondary when nothing is chosen), only for app conversations whose model has `reasoning != false`: a native menu
  with one Effort section (Default "Hermes' setting", Off "no thinking", Low, Medium, High, Extra high, Max; notes under
  the names, a native menu having no trailing text) and a disabled "Applies from the next message."; wire values `null`,
  `none`, `low`, `medium`, `high`, `xhigh`, `max` (`PUT /api/sessions/:id/effort`, loaded with the session models
  from `GET /api/session-efforts`, set optimistically with rollback). Fast mode stays out (it bills extra usage on
  Claude plans); the popover keeps its model text; a handoff doesn't copy the effort. **Narrow windows:** the header
  (`FittedHeader`) keeps the title 120 pt where it can: first the context meter shows only its percentage, then the
  model pill drops `claude-`; the effort pill and the icon buttons never hide. At 1560 pt that holds; at 1180 pt (a
  484 pt detail) both steps leave the title about 20 pt.
- **Markdown:** prose with `AttributedString(markdown:)`; fenced code blocks are split out and drawn as views with a
  language label and a copy button.
- **Images** (#43, #44, #45; relay trismegistus#25, #26): a message takes up to 4 images by drop onto the chat column, the
  📎 button (open panel) or ⌘V; a tray above the input shows them. The drop target is an AppKit view over the whole
  column (SwiftUI's `onDrop` sits behind the scroll view, the selectable text and the field, so AppKit never offered
  it a drag), registered for files, file promises (Photos, some browser drags: received into a temporary folder, 20 s at most, a
  failed one shows an error cell; a file or image data on the drag wins over a promise) and image data but not text,
  and letting clicks through. While a drag is over it
  the column dims under a paper veil, a yellow frame opens from the centre and a card says what a drop does (`3
  IMAGES`, `2 OF 3 FIT // UP TO 4`, other files skipped, `GOES WITH YOUR NEXT MESSAGE` during a run); it turns red
  with the reason when nothing can be attached (`IMAGES ONLY`, `UP TO 4 PER MESSAGE`, `THIS DEVICE CAN ONLY VIEW`,
  `READ-ONLY CONVERSATION`). Reduce Motion: fades only. They are resized (longest edge 2048 px) and
  re-encoded before upload (EXIF and GPS dropped), uploaded to `POST /api/attachments`, then sent with the `prompt`
  (`attachments`); steers stay text only, so images wait in the tray during a run. Messages show their images (one
  within 320×240 pt, 2–4 in a grid; Quick Look on click); history images come from the relay's `attachments` on user
  messages (Hermes keeps only a `[screenshot]` line, which is hidden). Hermes' `MEDIA:<path>` answer lines and
  Telegram's `[Image attached at: <path>]` notes load through `GET /api/sessions/{id}/media`. Images are cached in the
  app's Caches (deleted on unpair). Viewer devices can't attach.
- **Row status for every conversation:** the client subscribes to every listed session (the relay allows 64 per
  socket), so RUN and APPROVAL marks and approval notifications work for conversations that are not open.
- **Approval banner:** at the top of the chat and as a notification: command, description, buttons Once / Session
  / Deny (`always` is never offered, as in the protocol). **Click-only, no keyboard shortcuts** (2026-10-31, changed
  from the draft's ↩ / ⌘⌫): macOS fires key equivalents before the focused text field, so Return or ⌘⌫ typed in the
  steer field would answer the approval. Approving from the Mac runs commands on optiplex, same
  trust level as the phone.
- **Settings:** relay URL, device name, connection status, unpair, launch at login (`SMAppService`), Notifications.
  Since #66 (design 12 `#settings`, `#settings-menu`) the section heads are ink slabs with yellow tracked caps, and
  Notifications is a table: BANNER and SOUND over a sunken head band, one row each for Approval requests, Run finished
  and Run failed with a switch, a native Sound pop-up (None, Default, then the 14 macOS sounds: Basso, Blow, Bottle,
  Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink) and ▶ (`NSSound`; Default plays the alert
  sound), a dark foot bar, then two captions (run banners only while the app isn't on screen; Focus and System Settings
  apply). Keys: `notifications.approvalRequests`, `notifications.runFinishedWhileClosed`, `notifications.runFailed`
  (absent: as run finished), `notifications.sound.approval|finished|failed` (defaults Default, Glass, Basso; while
  `sound.approval` is absent, the old `notifications.approvalSound` off reads as None). Settings is Inter throughout.
- **Pairing sheet:** first launch; paste the code; shows the relay URL from the QR payload. A paired Mac has no terminal
  yet: turn it on once on optiplex, for a manager device, with `docker exec trismegistus-relay trismegistus-relay devices
  terminal macbook on`, and start the helper with `systemctl --user start trismegistus-term`.

Not in v1: dark mode, multiple relays, streaming deltas (the relay has streaming off), Sparkle updates, Linux
(a Quickshell module in endfield-dotfiles is the Linux plan, not this repo), Windows.

## Security

- Token only in the Keychain; `RelayClient` takes it as a value and never logs it. Log lines carry ids and kinds,
  never message text or approval commands.
- TLS to `hermes.lab.x-muramasa.dev` (tailnet-only name, Caddy certificate); ATS defaults, no exceptions.
- The app is sandboxed with the network-client entitlement and read-only access to the files the user picks or drops (`com.apple.security.files.user-selected.read-only`, for attaching images, #43); nothing else.
- The terminal drawer is a shell on optiplex, with everything the user Hermes runs as can do there. It needs a manager
  device holding a per-device grant, off by default, which the relay checks at open and every 2 s after. To turn it off
  on optiplex: `devices terminal macbook off` (closes the shell within 2 s), or `devices revoke macbook` to un-pair the
  device altogether (through `docker exec trismegistus-relay trismegistus-relay …`). The stream is never logged by the
  app or the relay, and a program on the host can't write the Mac's clipboard (OSC 52 is dropped).

## Phases

| # | Phase | Done when |
|---|---|---|
| 1 | Kit: protocol types, contract tests, RelayClient against a fake, SessionStore | `swift test` green on the Mac over SSH; every valid example round-trips; the fake exercises auth, replay, live events, approval, ping/pong, reconnect; no dependencies. |
| 2 | App: menu bar popover and main window (conversations, chat, terminal pane), pairing, settings; build loop | `scripts/mac-build.sh` builds, installs and launches the app on the Mac; Martin pairs it against the real relay, sends a prompt from the menu bar and watches its commands in the terminal pane. |
| 3 | Approvals and notifications, launch at login | An approval raised by Hermes on optiplex is answered from the Mac notification; a completed run notifies when the popover is closed. |

Each phase: Claude Code (Opus) writes the code from a brief; Hermes verifies on the Mac over SSH, commits and pushes;
the report goes on the phase's issue. Phase 1 can run entirely from optiplex except the final `swift test` on the Mac.

## Decided (2026-10-31, #4 and #5)

1. Popover **and** a main window (conversations | chat | terminal).
2. Approval notifications play the default sound; a Settings toggle turns it off (since #66 a Sound menu per event:
   None turns it off).
3. Markdown with code blocks drawn as views with a copy button.
