# Trismegistus — three-column window: changes

`index.html` hashes: `#a`, `#a2`, `#b` (1560×1122); `#all` (default: #a and #a2 side by side at 50 %, 1560×561); `#a-narrow`, `#a2-narrow`, `#b-narrow` (1180×1122, list column 380 px); `#a2-states` (one list column, 520×1122, a card in every state).

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
