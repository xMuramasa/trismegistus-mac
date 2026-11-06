# Trismegistus sidebar row: changes

Open `index.html`. Hashes: `#all` (default: TODAY, B and B2 side by side, 1170x1122), `#today`, `#b`, `#b-states`, `#b-narrow`, `#b2`, `#b2-states`, `#b2-narrow`.

`index-clean.html` is the earlier quiet version with its A, B and C, kept unchanged.

Contrast is WCAG, computed from the hex values. "Grey" is #666666; "white" is the selected card and the popover row. Where a fill can't reach 3:1 against its ground, its edge carries the 3:1.

## Neo-brutalist pass

Second round: shadows softened and borders thinned to 1 px. The footer is unchanged from the first round.

### Owner rules relaxed by this request

- **Rows without fills:** A floods state rows.
- **No shadows, no blur:** rows and blocks have a soft offset shadow: 4 px down and right, 8 px blur, 40% opacity. It's one `.shadow` modifier in SwiftUI.
- **Type roles:** titles are 14/800 uppercase; `APP // 10` is 24/900; labels are 800; mono is 700.
- **Flat fills:** B's approval sticker has hard-edged vertical stripes, built as a small repeating pattern, not a soft gradient.
- **Fonts:** no monospace. Ages, timers, tags and counts are Inter, replacing JetBrains Mono; only TODAY keeps it. Figures are tabular so the timer doesn't jitter (`.monospacedDigit()` in SwiftUI).
- **Row gap:** 8 px instead of 2, so shadows and stickers have room. Spacing is 60 px per row.

### Contour lines

- Same recipe as the Endfield design system: 18 closed curves, centred at 78% / 72%, three small sines, x stretched by 1.35, 181 points, strokes in #C8C8C0, every fifth curve at 0.9 opacity and the rest at 0.55.
- Two changes: strokes are 0.5 px instead of 1 px, and the radius step uses the slab's width, because its 24 px height would shrink the field to nothing.
- #C8C8C0 is the one colour outside your original token list. It comes from the Endfield system and is decorative only.
- Each section uses a slightly different wobble, so the two slabs don't repeat.
- The curves fade into the ink towards the label, reaching full strength about 70% of the way across: this keeps the label clear. It's a mask in SwiftUI, and a soft fade, so it's another departure from the no-gradient rule.

### Kept

All your colour tokens, Inter, 52 px rows, radius 0, the 3:1 floor on every ground, the four shapes (diamond, ring, cross, check), the priority order, tags (max 2 + `+N`), both menus, opening clears failed and done, 220 px minimum, and every hash at its size. TODAY is untouched.

### Sidebar and row

- Section heads are ink slabs with yellow text and Endfield contour lines to the right of the label: they turn the list's structure into a graphic element.
- `APP // 10` is a large block with yellow slashes: the header now leads the column.
- Tabs are thin outlined blocks and the current tab is solid yellow: position reads at a glance. The tab badge sits in its own ink-edged block because a bare mark fails on yellow.
- The filter is white with an ink shadow: it matches the new weight.
- The footer is a solid ink bar with the current section on yellow: it anchors the column.
- The selected card has a 1 px ink edge, a yellow frame outside it with square corner nodes and a soft glow, and a marker square before the title: taken from the reference, and yellow reads against the grey (5.17) where it never could on white.
- Hover is a 1 px ink edge with an ink shadow: the shadow shows which row is under the pointer without a fill.
- Tags are white with a 1 px ink edge: sunken chips looked weak next to the new marks.
- Titles and tags keep the shared earlier fixes: no pin glyph under PINNED, no chevron on the selected row.

### Shared contrast

| Element | On grey | On white | Text inside |
| --- | --- | --- | --- |
| Ink edge, 1 px | 3.06 | 17.58 | |
| Current tab, yellow | 5.17 | not used on white | ink on yellow 15.85 |
| Section slab, ink | 3.06 | | yellow on ink 15.85 |
| Tag | white 5.74 | ink edge 17.58 | ink on white 17.58 |

Ink on grey is 3.06, only just over the floor, and the edges are now 1 px, so they pass with no margin. Shadows are decorative and aren't counted towards the 3:1.

## B: Stickers

- Status is a square sticker breaking over the row's top-right corner: it keeps the grid-breaking move without any rotation.
- Approval ends in magenta and ink vertical stripes: it's unmistakably the top priority, a pattern survives without colour, and nothing is diagonal.
- Done has no shadow: weight still falls with priority.
- `…` stays on the tag line, so the timer never moves.
- At 220 px: stickers drop the word. Running keeps its glyph and time. Tags reduce to one chip + `+N`.

| Sticker | Edge on grey | Edge on white | Inside |
| --- | --- | --- | --- |
| Approval, magenta + stripes | ink 3.06 | ink 17.58 | ink on magenta 5.02; magenta diamond on ink cell 5.02 |
| Running, ink | ink 3.06 | ink 17.58 | white on ink 17.58; ink ring on yellow cell 15.85 |
| Failed, terminal-red | white 5.74 | ink 17.58 | white on terminal-red 5.74; terminal-red cross on white cell 5.74 |
| Done, green | ink 3.06 | ink 17.58 | ink on green 13.25; green check on ink cell 13.25 |

## Ideas taken from the reference

- Yellow frame with corner nodes and a soft glow on the selected card: the strongest "this one is active" signal in the reference.
- The owner's yellow inner border moves outside the card as that frame: the idea stays, but it is no longer an inner border.
- Marker square before the selected title and before each section label: the reference's `■ Phase` header.
- Stickers are now two-part, a glyph cell plus a body: this is the reference's yellow block and `1/12` bar. Running is a yellow cell with white digits on ink.
- No progress fill: a run has elapsed time, not a known total, so a bar would be invented data.
- Big ghost count, crosshairs, dot grid and straight hatch below the list: the reference's technical ornament, in the empty end of the column. Decorative only, and the count follows `APP // 10`.
- Left out: the large ghost lock on read-only rows (removed by the owner; the small lock after the age stays), the dark active card (your selected card stays white) and the diagonal hatch (no diagonals).

## B2: phase card colours

Same row, stickers and yellow frame as B. Only the card colours change, sampled from the reference and mapped to the nearest tokens.

- Idle rows are light paper cards: the reference's locked cards, and they turn the list into a stack of objects.
- Each card has a grey head band and a dark foot bar, 4 px each: the reference's header and bottom bar, scaled to fit 52 px.
- The selected card is ink with a yellow title and white meta: the reference's active card, and the strongest contrast with the light rows.
- The foot bar is dark-panel, not the reference's mid grey (#6A6A6A): that grey is almost the sidebar's own #666666 and would disappear.
- Stickers on the dark card get an on-steel edge: their ink edge would vanish on ink.
- Conversations with no state and not selected use regular weight, for the title, age and tags: bold is kept for headings and anything active, so a state now shows in the type as well.
- This departs from two owner rules: rows without fills, and the white selected card with white titles elsewhere.

| Element | Ground | Ratio |
| --- | --- | --- |
| Paper card | grey | 5.13 |
| Title, ink | paper | 15.71 |
| Meta, secondary | paper | 5.13 |
| Selected card, ink | grey | 3.06 |
| Yellow frame | grey | 5.17 |
| Title, yellow | ink | 15.85 |
| Meta, on-steel | ink | 14.48 |
| Sticker edge, on-steel | ink | 14.48 |
| Head band, muted | paper | 2.54, decorative |

The popover list is unchanged.

## Decision: B2

- The owner chose B2 as the direction to follow. B stays in the lab for comparison.
- The owner chose B, and asked for the stickers to be straight because diagonals are a pain to build.
- Stickers and stripes are now axis-aligned: no rotation anywhere in B, so a sticker is a plain rectangle with an offset.
- Every sticker still carries a word and a shape, so B doesn't rely on shape alone.
- A sticker still overhangs the row above by a few pixels, so give it a higher draw order than the rows.
- A and C are removed from the lab. TODAY stays as the reference.

## Measured from the screenshot, or differing from the brief

- **Selected card height:** the shipped card measures 54 px, not 52 (y 216 to 269, borders included), with 54 px spacing and no gap. TODAY reproduces that. B uses 52 + 8.
- **Terminal-red on grey:** 1.00:1, identical luminance to #666666. It's only used as a fill with a white or ink edge. Dark-panel on grey is 2.07:1 and isn't used on grey.
- **Row count:** the list has 11 rows and the header says `APP // 10`. Kept as specified; the digest is a cron conversation and may not belong in that count.
- **TODAY:** 10 rows, no digest and no tags, as in the screenshot.
- **Read-only:** the lock follows the age as the brief says. `row-states-today.png` shows it before the age, with "· read-only".
- **Full title of `xMuramasa/homelab#1`:** the screenshot truncates it. "Add the Trismegistus relay" is my placeholder ending, used only so it truncates.
- **Third tag:** the brief gives `homelab`, `relay`, +1. The hidden tag is a placeholder (`mac`).
- **Title bar:** the shading in the screenshot (#666666 to #535456) is reproduced on TODAY only.
