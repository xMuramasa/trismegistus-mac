# Trismegistus — three-column window: changes

`index.html` hashes: `#a`, `#a2`, `#a3`, `#b` (1560×1122); `#all` (default: #a and #a2 side by side at 50 %, 1560×561); `#compare` (#a2 and #a3 side by side at 50 %, 1560×561); `#a-narrow`, `#a2-narrow`, `#a3-narrow`, `#b-narrow` (1180×1122, list column 380 px); `#a2-states`, `#a3-states` (one list column, 520×1122, a card in every state). Sections (1560×1122, #a2 and #a3): `#a2-github`, `#a2-github-check`, `#a2-agents`, `#a2-jobs`, `#a2-commands`, `#a2-telegram`, and the same with `#a3-`.

## What moved where (both variants)

| Today | Now | Why |
| --- | --- | --- |
| Bottom section icon bar (Chat, GitHub, News…, Agents, Jobs, Commands) | Labelled 40 px rows at the top of the floating section panel: Chat, GitHub 3, Agents 1, Jobs (failed mark), Commands | Labels beat bare icons; counts and marks get a fixed place; it's the macOS sidebar idiom |
| Kind tab row (`10 · →4 · ▢9 · … ⌄`) above the filter | Collapsible "Chats ⌄" group in the panel: App 10, Telegram 4, Terminal 9, One-shots 2, Cron 6, All 31 | All six kinds are visible with no "More" menu; the list column gets its height back |
| `APP // 10` + "+" in the list header | Same title, centred, between a "…" (Rename, Tags, Hand off) and the "+" | Matches the reference header: actions on both sides, title in the middle |
| `macbook · paired` above the bottom bar | Identity row at the bottom of the panel: `macbook`, status dot + `linked · hermes.lab.x-muramasa.dev`, "…" (Settings, Unpair) | One place for device, link state and pairing |
| Top bar: `● LINKED hermes.lab…` | Identity row (see above) | The link belongs to the device, not to a conversation |
| Top bar: terminal toggle | Detail header, round/square icon button (⌘⌥T) | It acts on the open conversation's run |
| Top bar: Settings | Detail header icon button (⌘,), also in the identity "…" menu | Reachable from both the conversation and the device |
| Top bar: Trismegistus wordmark, sidebar toggle | Wordmark removed (the window title is enough); sidebar toggle next to the traffic lights | Native NavigationSplitView placement |
| Chat header (ink bar with title, token meter, model picker) | White detail header: avatar + title + subtitle on the left; meter, model, terminal, settings, "…" on the right; the 4 px title rule under it | The top bar is gone, so the header carries its controls |
| "Archived" | Not shown | As asked |

Everything below the detail header (messages, `>_ 4 COMMANDS · 6.1 S` chip, composer with the run line and STEER) is kept as it is today. The only change: meta labels (`YOU // 13:42`, run times) are set in Inter with tabular figures, because the "no monospace" rule now applies.

## Variant #a: B2 skin

- Ink section panel (#191919, 1 px ink edge, 4/4/8 shadow at ink 40 %), square: it carries the B2 look the owner chose and stands out as the one floating object.
- Current section Chat is a solid yellow block with ink text: the region's single yellow mark.
- Current kind App gets a dark-panel fill, bold text and an 8 px yellow square: it's marked without a second yellow block competing with Chat.
- "Chats" group head is a dark-panel slab with a yellow square, white uppercase label and chevron: the B2 section-head language on an ink ground.
- List column on paper with white cards: a 4 px muted head band and a 4 px dark-panel foot bar, at a 60 px pitch. These are B2 cards, and the contour lines show in the gaps.
- Selected card (Swift app) is ink with a yellow uppercase title, framed in yellow 1 px at 4 px outside with 4 px square corner nodes. This is B2's selection and it reads instantly.
- PINNED / CONVERSATIONS are ink bands with a yellow square, yellow label and count, the same as in B2.
- Avatars are 36 px squares; "+" is a square. They match the square-everywhere rule.
- Detail and composer controls are square: one shape language.

## Variant #b: macOS 26 native

- The section panel is Liquid Glass: translucent white over the paper ground, with the contour lines showing through blurred, radius 16 and a 1 px white edge. Built natively, that's `.glassEffect(.regular, in: .rect(cornerRadius: 16))`.
- Current section Chat is an ink pill with white text. A yellow pill would be 1.1:1 on glass; ink keeps the selection at 3:1 or better.
- Current kind App is a white pill, bold, with an 8 px yellow square with an ink edge (the ink edge carries the contrast).
- "Chats" group head is a small grey label with a chevron, the sidebar section-header style.
- The list column is white, as in the reference. Rows have a 52 px pitch, a 40 px round avatar, and hairlines that start after the avatar.
- Selected row is an ink pill with rounded corners: the reference's filled selected row, at a usable contrast in light mode.
- "+" is a round yellow button with an ink glyph and no edge; the 17.6:1 ink glyph is the mark.
- Search field, model picker, composer input and buttons get an 8 px radius, round icon buttons and a 12 px message radius: native control shapes.
- Stickers stay square with a 1 px ink edge. They are the agreed state language, and their contrast doesn't depend on the skin.

## States

There's one sticker per conversation, strongest first: APPROVAL (magenta, diamond) > RUN (ink with a yellow ring cell, white word, yellow ticking time) > FAILED (terminal-red with a white cross cell) > DONE (green, check). Each sticker is 24 px tall with a 20 px glyph cell and a 1 px ink edge (on-steel #E9E9E9 on ink grounds). The Chat row and the App kind row show a glyph-only 20 px sticker for the strongest state (APPROVAL). Jobs shows a glyph-only FAILED.

The prototype changes states live:
- Opening a DONE or FAILED conversation marks it seen and clears it.
- Approve on Android app turns APPROVAL into RUN; Deny clears it.
- Stop ends the run.
- Sending a message starts one.

## Contrast of every new mark

Relative-luminance ratios (WCAG). Target: 3:1 for marks, 4.5:1 for text.

| Mark | Against | Ratio |
| --- | --- | --- |
| Yellow current-section block (#a) | Ink panel | 15.8:1 |
| Ink text on that block | Yellow | 15.8:1 |
| Yellow kind square (#a) | Dark-panel row fill | 11.0:1 |
| Kind square's ink edge (#b) | Glass ≈ white | ≈ 16.5:1 |
| Ink section/row pill (#b) | Glass / white | ≈ 16.5:1 / 17.6:1 |
| White text on ink pill | Ink | 17.6:1 |
| Muted counts #999 (#a) | Ink | 6.2:1 |
| Secondary counts #666 (#b) | Glass ≈ white | ≈ 5.5:1 |
| Status dot green #00FFA2 (#a) | Ink | 13.3:1 |
| Status dot terminal-green #00875A (#b) | Glass ≈ white | ≈ 4.4:1 |
| APPROVAL magenta cell / sticker | Ink panel · white (glyph-only on glass) | 5.0:1 · 3.5:1 (+ ink edge 17.6:1) |
| Ink diamond / text on magenta | Magenta | 5.0:1 |
| RUN yellow cell, ink ring | Yellow | 15.8:1 |
| RUN yellow time on ink | Ink | 15.8:1 |
| FAILED terminal-red | Ink panel · white | 3.1:1 · 5.7:1 |
| White text on terminal-red | Terminal-red | 5.7:1 |
| DONE green, ink check / text | Green | 13.3:1 (sticker edge vs white 17.6:1) |
| Sticker edge on-steel #E9E9E9 | Ink (selected rows, #a panel) | 14.5:1 |
| Selected card yellow frame + nodes (#a) | Paper | 1.0:1 on paper, but the frame sits on the ink card's edge; card vs paper 15.7:1, yellow title on ink 15.8:1 |
| "+" yellow block, ink glyph | Yellow · paper/white | glyph 15.8:1; ink edge (#a) 15.7:1 |
| Run-line square terminal-green | White composer | 4.5:1 |
| Tags #666 on sunken | Sunken | 4.6:1 |
| Focus ring blue #0040E8 / yellow on ink | White / ink | 7.2:1 / 15.8:1 |

Yellow and magenta are never text on light grounds. Yellow text appears only on ink (selected card title, PINNED bands in #a, run time).

## Decisions where the brief needed a reading

- **One yellow primary.** While the open conversation runs, STEER is the yellow action. The "+" then steps down (white square with ink edge in #a, grey circle in #b) and turns yellow again when you open an idle conversation or stop the run. This follows "Steer while a run goes takes over"; if you want "+" always yellow, it's one CSS class.
- **52 px rows vs 52 px avatar (#b).** The fixed rule "rows 52 px" wins, so the avatar is 40 px. A 52 px avatar would need a ~68 px pitch.
- **Traffic lights** are drawn neutral grey because their system colours aren't in the palette. macOS draws the real ones.
- **Inline code** (`cua-driver stop`) is set in Inter on a grey chip; monospace appears only inside code blocks and the terminal drawer.
- **Other sections and kinds:** GitHub, Agents, Jobs, Commands and the non-App kinds show an honest empty note, because the sample data covers App conversations only.

## SwiftUI mapping

- `NavigationSplitView(columnVisibility:)` with sidebar, content and detail columns.
- Sidebar: `List(selection:)` with a `Section(isExpanded:)` for Chats and `.navigationSplitViewColumnWidth(300)`.
- #b: `.glassEffect` on the sidebar container.
- #a: the sidebar background is `Color.ink`, `.shadow(color: .ink.opacity(0.4), radius: 4, x: 4, y: 4)`.
- Content column: `.navigationSplitViewColumnWidth(min: 380, ideal: 520)`.
- Stickers: an `HStack` of two fixed-height views with `.overlay(Rectangle().stroke(.ink))`.

## Which I'd pick: #a (B2 skin)

- It's the look you just approved for the sidebar, so the window and today's chat speak one language: square, ink, one yellow mark.
- Every mark sits on a fixed, opaque ground (ink panel, white card), so its contrast is guaranteed. On glass, magenta, green and yellow depend on what scrolls or sits behind the panel.
- Selection is unmistakable (ink card + yellow frame), and the 60 px cards keep the B2 rhythm.

Take from #b the white list column with the hairlines starting after the avatar if density matters: it fits about 2 more rows per screen than the cards.

## #a2: rounder corners

`#a2` is the owner's pick (#a, B2 skin) with one small radius scale applied everywhere. `#a` stays untouched for comparison. Colours, type, weights, spacing, sticker content and states are the same as in #a.

### Radius per element

| Radius | Elements |
| --- | --- |
| 16 px | Floating section panel; composer block |
| 12 px | List cards (idle, hovered, selected); code blocks; message boxes (YOU, approval card); model picker; menus |
| 16 px (12 + 4) | Selected card's yellow frame, 4 px outside the card |
| 8 px | Filter field; all buttons (icon buttons, yellow "+", STEER, stop, Approve/Deny, composer input); section rows, so the current-section block and the kind-row highlight; `>_ 4 COMMANDS` chip; PINNED / CONVERSATIONS slabs; Chats group head; menu items; tooltip and toast |
| 6 px | Stickers (full and glyph-only); tag chips; ⌘K / shortcut key hints; source avatars and the device avatar (rounded squares) |
| 0 (unchanged) | Detail header, 4 px title rule, terminal drawer: they run edge to edge, so there are no free corners to round. The 8 px yellow identity squares stay square, because at 8 px a radius would turn them into dots. |

### What the rounding forced

- **Corner nodes become corner arcs.** The 4 px square nodes would stick out of a rounded frame. I replaced them with 3 px yellow arcs, 16 px long, laid over each corner of the frame. They keep B2's "targeted" reading of the selection, where dropping them would leave a plain focus-like ring, and they follow the 16 px curve instead of fighting it.
- **Bands are clipped, not bent.** In #a, the card's 4 px muted head band and dark foot bar are borders. On a rounded box, top/bottom borders taper into the corners. In #a2 they are flat 4 px strips painted inside the card and clipped by its 12 px corners, so each band keeps full thickness and simply follows the card's curve at the ends. The card is still 56 px tall at a 60 px pitch.
- **Stickers at the card's corner.** Stickers sit on the preview line, 12 px in from the card's right edge, so they never touch the 12 px corner. Their own 6 px corners clip the glyph cell, and the 1 px edge follows the curve.
- **Composer becomes a block.** A 16 px radius on a full-width band at the window's bottom edge would show nothing, so the composer now floats 8 px in from the detail's sides and bottom, with a 1 px rule edge. That's the same 8 px inset as the section panel. Its contents and sizes are unchanged.
- **Slabs are inset.** PINNED / CONVERSATIONS span the full column in #a. In #a2 they're inset 8 px to line up with the cards, so their 8 px corners don't touch the column edges.
- **Yellow "+" is an 8 px rounded square, not a circle.** It then matches the rounded-square avatars and the other buttons; a single circle would be the only round shape in the window.
- **Shadows** (panel 4/4/8 at ink 40 %, menus) are unchanged and follow the rounded shapes.

No step on the scale needed adjusting.

## #a3: Endfield-faithful

`#a3` keeps the layout as built today: #a2 plus the tree panel. The tree runs Chats with its fold chevron, the indented kinds with App as the highlighted row, then GitHub, Agents, Jobs and Commands, with the device row at the bottom. The list, detail, composer, content and states are as in #a2. Only the skin changes, following the six game screens. #a, #a2 and #b are untouched.

### The 8 points

| # | What changed | Follows |
| --- | --- | --- |
| 1 | **No black on light grounds.** Card foot bars, ink slabs and the ink edges on stickers, tags, filter and "+" are gone. Cards, filter, buttons and the composer have 1 px grey hairlines (#D9D9D9 / #C8C8C0). The section panel is a translucent dark-panel grey (#35373C at 86–93 %) with a faint white hairline, not a black slab. Ink is left for text, plus the 26 px "T" avatar and a tiny tick on the title rule, both in dark-panel grey. | settings-rows (grey rows, hairline edges), database-list-detail (cards without outlines), mail-list (dark translucent list panel) |
| 2 | **Yellow is a line, not a fill.** The selected card stays white, with a 1.5 px yellow frame and a faint yellow glow. The current kind (App) is a slightly lighter row with a 3 px yellow bar at its left edge. Solid yellow remains only on the "+" (or on STEER while a run goes), the 56 px segment of the title rule, the WORKING progress line and the RUN tag's ring and time. | mail-list (selected "Happy Birthday" item), settings-rows (FPS row), database-list-detail (LN Tower's yellow left bar), daily-activity-list (yellow progress line) |
| 3 | **Quiet type.** Titles are Inter 500 (quiet) / 600 (state or selected), normal case, 13 px; the detail title is 14 px. Meta is 11–12 px regular grey. Uppercase only for tiny tracked labels: `// TRISMEGISTUS`, `// APP` + `10`, `// PINNED — 04`, `// CONVERSATIONS — 07`, `YOU // 13:42`, `RUN ACTIVE`. The one large numeral is the list count "10", 28 px at weight 500. No 700+ weights anywhere. | mail-list ("// MAIL", "Inbox 10/200"), settings-rows ("// SETTINGS"), daily-activity-list (the large "100") |
| 4 | **No offset shadows.** Depth comes from layers: the dark translucent panel, the lightly frosted list column (sunken grey at 42 % with the contour lines faintly through), white cards and a frosted detail header and composer. Only the selected card glows. Menus keep a soft, non-offset 24 px blur. | news-panel (layered grey panels), operator-overview (dark translucent panels over the scene), settings-rows |
| 5 | **The game's greys.** The panel steps from 93 % to 86 % dark-panel grey from top to bottom. Cards step from white to translucent white, so they read slightly lit from above. Tags and the code block are sunken grey. | database-list-detail (grey card steps), daily-activity-list (panel gradients) |
| 6 | **Fine detail, mostly functional.** `//` labels with a hairline running to the edge and a 2-digit count. Muted index numbers 01–11 on the cards (their order in the conversation list). A short diagonal hatch in the list header and on the selected card. 6 px grey bracket corners around the selected card. A thin title rule: dark tick, yellow segment, grey rest. Run metadata in the detail header (`run_7f3a2c · seq 214 · 38 ms · started 13:52`). A link latency on the device row (`· 38 ms`). A vertical tree guide line under the Chats icon. A chamfered top-right corner on the panel. The contour lines stay. | mail-list / settings-rows / daily-activity-list (`//` labels), database-list-detail ("Recently Unlocked ——", hatch marks on the cards), news-panel ("Click to Go" bracket corners, chamfered tabs), daily-activity-list ([ ] brackets), settings-rows ("Performance & Graphics" title with yellow bar and rule), every screen's "104ms UID" corner |
| 7 | **Lighter shapes.** Avatars are 26 px rounded squares (radius 4), and the detail avatar is 28 px. Status stickers become 18 px tags: a light chip with a hairline, a 2 px coloured bar on the left, a small coloured glyph and the word in tracked small caps. Buttons are thin-edged 4 px rectangles. Only the model dropdown is a full pill, like the game's dropdowns. Radii are 3–8 px: 3 px tags, 4 px cards and controls, 6 px menus, 8 px panel and composer. | mail-list (small item icons), database-list-detail (NEW tag), operator-overview ("Current" / "Preview" labels), settings-rows (pill dropdowns), news-panel (chamfer) |
| 8 | **Tighter rows.** Cards are 46 px at a 50 px pitch (#a2: 56 / 60 px). Section heads are 24 px label lines instead of 28 px slabs, and panel rows are 36 px instead of 40 px. The list now fits about 19 conversations in the window against about 15 in #a2. The airiness comes from the 8 px gaps around the panel, list and composer, not from padding inside rows. | settings-rows (dense rows), mail-list |

### Contrast of every state mark (#a3)

| Mark | Against | Ratio |
| --- | --- | --- |
| APPROVAL: magenta 2 px bar + diamond | White tag chip | 3.5:1 |
| APPROVAL / FAILED / DONE word (ink) | White chip | 17.6:1 |
| RUN: dark-panel chip | White card | 12.2:1 |
| RUN: yellow ring, bar, time | Dark-panel chip | 11.0:1 |
| RUN: white word | Dark-panel chip | 12.2:1 |
| FAILED: terminal-red bar + cross | White chip | 5.7:1 |
| DONE: terminal-green bar + check | White chip | 4.5:1 |
| Glyph-only chips in the panel (Jobs, App, folded Chats): white chip | Dark panel | ≈ 12:1 (glyphs inside as above) |
| Current kind: yellow 3 px bar | Lit panel row (≈ #494B50) | ≈ 7.9:1 |
| Selected card: grey bracket corners #666 | Frosted list ground (≈ #EBEBEB) | ≈ 4.8:1 (the yellow frame itself is ≈ 1.1:1; it's the accent, the brackets carry the 3:1) |
| Device status dot green #00FFA2 | Dark panel | ≈ 9.2:1 |
| Run-line square terminal-green | White composer | 4.5:1 |
| Panel counts #C8C8C0 / labels #E9E9E9 | Dark panel | 7.2:1 / 10.1:1 |

Magenta and yellow never appear as text on light grounds. The 2-digit card indexes are muted #999 (2.9:1 on white). They're decorative order numbers in the game's manner, not information; if you want them to count as text, they move to #666 (5.7:1).

### What #a3 loses against #a2

- **States are quieter.** At a glance, an APPROVAL in #a2 is a magenta block you can't miss. In #a3 it's a 2 px bar and a small diamond, so you have to read the list to find it. Only the dark RUN tag still jumps out.
- **Selection relies on a thin accent.** Yellow on white is about 1.1:1, so the frame and glow read as "lit" rather than as an edge. The grey bracket corners and the semibold title carry the selection. #a2's ink card is far louder.
- **Less of the chosen B2 identity.** The ink slabs, square nodes and yellow blocks that made B2 recognisable are gone; #a3 looks like the game, not like B2.
- **Translucency costs.** The panel, list column, header and composer use SwiftUI materials (`.ultraThinMaterial` / `.regularMaterial` tinted, or `.glassEffect`). Their contrast varies slightly with what's behind them, and they're more expensive to draw than #a2's flat fills.
- **Custom shapes.** The panel's chamfer needs a custom `Shape` (a rounded rect with one cut corner) instead of a plain `RoundedRectangle`. The bracket corners and hatches are small overlay views.
- **Palette substitutions:** the game's green progress bars and orange alert diamonds aren't in the palette. #a3 uses the yellow progress line instead, and doesn't use orange at all.

## Sections in the three-column layout

#a2 and #a3 now draw every section. Clicking a section or a kind in the panel switches the list and the detail inside the same variant. #a, #b and the states views are unchanged. In #a2 and #a3 the panel shows the real counts: GitHub 11 (needs check), Agents 0 (none running), and no Jobs mark (nothing failed). The content design of each section is the one agreed in the polish renders; only the skin and the column it lives in changed.

| Section | From the polish render → now | What the layout forced |
| --- | --- | --- |
| **GitHub (board)** | The sidebar list → list column: "…" (board options), `GITHUB // 14 OPEN`, refresh; the filter; repo and priority pickers; the Board / Needs-check toggle. Below that the board by status: In progress 1, Ready 1, Todo 1, Needs check 11, Done 54 (folded). The issue → detail: title, repo · status in the header, with the done/total readout, open-on-GitHub, Start conversation and **Dispatch** on the right. The Status / Priority / Tags / Agent strip and Close issue sit under the title rule. The body card holds the decisions table (first 4 of 13, "Show all") and the 0/7 checklist, with the comment box under it. | The list header's yellow "+" becomes a quiet refresh: new issues are made on GitHub, and Dispatch is the screen's one yellow action. Repo, priority and status were monospace chips in the polish render; they're Inter now. The pickers and toggle sit between the filter and the rows, so the rows start lower than in Chat. Needs check lists 7 of 11; a note says the other 4 aren't in the sample. |
| **GitHub (Needs check)** | The Needs-check inbox → list column (`NEEDS CHECK // 11`, grouped by repo). #68 → detail: the check panel on top ("On screen for Martin", 7 numbered checks with a live x/7, "From Hermes · 10 Nov 11:26", **Looks good** / note / Not right, and the explainer), then a card linking to the delegate run in Agents. | Looks good is the yellow action. Not right stays disabled until the note has text. Looks good / Not right post the result and set the status (Done / Todo) in the prototype. |
| **Agents** | The run list → list column (`AGENTS // 0 RUNNING`, the six runs newest first with model, duration and a success tag). The run → detail: header with run id, success · delegate · opus · finished 11:20 · 179 turns · 34 min, and Open issue #68 / transcript. The result card is on top, then the 9 steps, one row each, folded. | The polish render's orange steps bar and cyan edge aren't in the palette: the steps bar is an ink slab with yellow text in #a2 and a `//` label line in #a3, and each step carries a green "ok". Step titles are Inter; step output isn't in the sample, so an expanded step says where it lives. Only #68 has a result and steps; the other runs say so. |
| **Jobs** | The job list → list column (`JOBS // 5`, cadence, next run, last result, script-only / Telegram tags). The job → detail: Pause / **Run now** / Edit in the header, the three-cell readout (cadence with `0 3 * * *`, next 3 runs, last result ok), the prompt as text folded after 8 lines with "Show all". | The "+" for a new job is quiet so Run now keeps the yellow. The cron expression and the readout times were monospace; they're Inter with tabular figures now. Pause works (row and readout show "paused"). Script jobs say "Script only"; the Chile and cyber prompts aren't in the sample and say so. |
| **Commands** | The conversation list → list column ("All conversations", "Trismegistus window" 6 calls, "lab maintenance" 3 calls). The log → detail: grouped by conversation, each call a folded header row (tool, the command, exit code, duration), with One line and Failed in the header. | The polish render's orange rows aren't in the palette: rows are light, with a 3 px left edge in terminal-green (exit 0) or terminal-red (failed). The exit-127 call reads "exit 127 · not found". No times were given, so rows show duration only (approximate). Command text and output stay monospace; everything around them is Inter. The "lab maintenance" group title opens that conversation in Chat. |
| **Chat kinds** | Telegram (4) and Terminal (5 of 9 shown) get their conversations; App adds "lab maintenance" (now) and "QA" (5 d). | Telegram rows carry the lock. The open Telegram conversation's composer is read-only, with **Continue in app**; continuing removes the lock. |

Sections other than Chat have no composer; the detail scrolls to the bottom edge of the window instead.

- **#a2 section panel is now the tree, as built** (every #a2 hash): Chats with its fold chevron, its kinds indented under it, then GitHub, Agents, Jobs and Commands, with the device row at the bottom. The yellow block sits on the deepest visible current row: the current kind in Chat, Chats itself when folded, otherwise the current section. Chats shows Chat's strongest state only while folded. Ink panel, 40 px rows and B2 type are unchanged; #a3 and #b are untouched.

## #a3-m1 / #a3-m2: messages after Endfield's mission screen (#70, proposal)

Drawn by hand into the prototype (2026-11-10), not by OpenDesign: the a3 window with the chat transcript and composer replaced; the CSS is the `.msn` block, the markup `missionView()`. Both share the marks:

- **Your message is the objective:** a white band (92 %) with a 12 px state square outside it on the left: dark-panel with a tick (done), yellow with an ink edge (running), terminal-red with a cross (failed), magenta (waiting for approval). The APPROVAL tag sits on the band's top edge, like the game's "Timed".
- **The reply is the briefing:** 15 px / 1.6 text, no bubble, under a `// HERMES  13:49 · 7 min` label line. References Hermes can open (issues, files, image ids) get a 6 px yellow highlighter under ink text and weight 600.
- **Steps** are the run's tool calls as rows (10 px square, tool, the command in JetBrains Mono 12 px, duration); one folded summary row once the turn ends, expanded while it runs.
- **Results** are tiles (80 x 74, hairline, radius 4) with a 3 px foot bar per kind: terminal-green commands (all exit 0), terminal-red failures, blue references, dark-panel files, contour time and tokens. All computable from what the relay sends.
- **The composer is the Track pill:** 46 px pill with a contour hairline; attach, field, a 34 px stop circle, and STEER as a yellow 36 px pill ending in a 28 px ink ring with the arrow. While an approval waits, Once is the yellow action and STEER turns plain.

`#a3-m1` (14a, objectives) restyles the stream. `#a3-m2` (14b, mission cards) makes each turn a card: your words as its 19 px / 500 title (two lines at most), a pin line (8 px yellow square with an ink edge, `You 13:42 → Hermes 13:49 · 7 min`), a hairline, then briefing, steps and results; a 3 px left bar in the state colour; folded cards keep title, pin line and small tiles. `#a3-m2` drops the code block from the first turn so both cards fit; its style is 14a's.

## #a3-c1 / #a3-c2: chat entries as Endfield mission cards (#70, proposal)

What Martin asked for ("refactor the chat entries with the mission cards design to make them cleaner"); the `#a3-m*` transcript drafts above came from misreading his first message and are parked. Reference: his recording, `own-recording/12m14s-mission-list-dark.jpg`. CSS: the `.mcw` block; markup: `missionRow()`, `missionHead()`.

| Part | Today's a3 card | Mission card |
| --- | --- | --- |
| Card | 46 px at a 50 px pitch, index 01–11, 26 px avatar | 56 px, 12 px apart (room for the tag), white 90 %, `rule` hairline, radius 4 |
| Left edge | none | 3 px bar: yellow run, magenta approval, terminal-red failed, terminal-green done, `contour` idle |
| Source | 26 px rounded-square avatar | 30 px `contour` triangle outline with the source glyph inside in `secondary`, then a 22 px divider hairline |
| Text | title 13 px, time, preview with tags and the tag | title 14 px (500; 600 with a state or selected) + pin; preview 12 px `secondary` (+ lock when read-only); tags leave the card |
| Right edge | time on line 1 | age 11 px over a 14 x 10 hatch |
| State | 18 px tag on the preview line | 19 px pill half over the top edge: RUN yellow with an ink ring, clock and time (the game's "Timed"); APPROVAL magenta, ink text (5.0:1); FAILED / DONE white with a red cross / green check |
| Selected | white, yellow frame + glow, bracket corners | 1.5 px ink frame, yellow wash from the left (gone by 150 px), faint 135° stripes |
| Group heads | `// PINNED ——— 04` label line | 22 px yellow square, ink glyph (pin / chat), label 14 px, count, `contour` hairline under |

`#a3-c2` adds an **In progress** group on top (live run or waiting approval), under a small right-aligned label with a yellow bracket, like the game's current mission. About 13 cards fit in the window against about 19 today.
