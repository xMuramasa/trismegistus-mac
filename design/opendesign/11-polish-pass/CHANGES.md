# Trismegistus polish pass: changes

Proposal entry: `index.html`, hashes `#chat`, `#github`, `#github-check`, `#news`, `#agents`, `#jobs`, `#commands`.
Format: change, then reason. Fixed decisions from the brief are not listed unless they alter a shipping screen.

## Whole window

- Steel detail band and 4 px title rule on all six sections: News, GitHub, Jobs and Commands each had a different header today.
- All times on a 24-hour clock (13:42, 14:03:04, 03:23): the 12-hour display was the bug behind "01:42".
- One count format, `1741`, everywhere: today's `1741` and `1.741` disagree, the defect Hermes reports in Chat.
- Sidebar rows lose the always-on `…`; pin becomes a hover toggle and pinned rows keep their pin: ten repeated dots were noise. Rename, tags and delete move to the row's right-click menu (not drawn in the prototype).
- Chevron rule applied everywhere: down on folded, up on open: today's rows mix right and down chevrons.
- Ground kept as paper with + marks and contours, marks cleared behind the Chat column: plain Hermes text sits directly on the ground.

## Chat

- Hermes' markdown lists render as real lists with hanging indent and small ink square bullets; numbered lists get mono numerals: `- ` lines read as raw source.
- Sub-items use a hollow square bullet: the two nested lines under #49 were flat today.
- Bold lead-ins and inline code as sunken mono chips: lets the eye scan by issue number.
- `>_ 2 COMMANDS · 6.7 S` chip and WORKING sit on one line above one progress track: they described the same activity in two places.
- Commands chip unfolds to item cards in place: the run's work is readable without leaving Chat.
- RUN ACTIVE strip, composer and key hints merge into one block aligned to the 700 px column: three stacked bars competed with the message area.
- Stop becomes a red-outline icon button beside Steer: a large gap separated it from the input.
- Steer is the yellow primary for the whole run; pressed with an empty field it focuses the input: today it looks disabled exactly when it matters.
- Duplicate `⌘. stop` hint removed from the WORKING line: the composer block carries it.

## GitHub issue

- `- [ ]` lines render as real checkboxes, with a live done/total readout in the header: checklists were text, progress invisible. This issue reads `0/9` because all nine items are open in the shipping data.
- Body held to 720 px with section heads (Monitors, How): long lines were hard to follow. The heads are added by the proposal; the issue text itself has none.
- URLs render as blue mono links: they are the operative content of this issue.
- Status, priority, tags and agent become one 40 px readout row: they were scattered across the header and pickers.
- Header actions: open-in-browser icon, Start conversation, Dispatch (yellow, play icon). Close issue moves to the end of the readout row: it is a state change, not a next step.

## Needs check

- Look-at text becomes a numbered list with tick boxes and a `0/5` readout: the owner can track a walk-through; the paragraph forced them to hold it in their head.
- All existing parts kept: 3 px yellow bar, magenta square + NEEDS YOUR CHECK, `from Hermes · 1 Nov 09:48`, Looks good, note field, Not right, explainer line.
- Tick boxes do not gate Looks good: they are a personal aid, not a required step.
- After Looks good or Not right the panel collapses to a one-line result and the row leaves the inbox, count updating: confirms what was posted.
- Reopen issue moves to the readout row: same reason as Close issue.

## News

- Sidebar rows reduced to feed square, feed name and time at 40 px, under the day head: every title repeated the day head and truncated. Full title stays in the detail and the accessible label.
- Feed squares use red, yellow and magenta: distinguishes Chile, Cyber and AI at a glance.
- Detail centred at 720 px: it sat left with a dead right half.
- Section heads move to the heading role with a 1 px ink rule and a story count: grey labels were weaker than the rows they headed.
- Stories fold to one summary line, chevron down: keeps the edition short to scan.
- UPDATE uses the blue outline chip, MIXED the neutral chip: tags were plain grey text.

## Agents

- Final report moves to a summary card on top with a `Build blocked` chip: the outcome was at the bottom of a dark wall, and "done" hid that the build never ran.
- Raw log becomes one tool row per call: tool icon, tool name, one-line command, duration, status: the sequence and the three failures can be read in seconds.
- Paths shown relative to the worktree, full path in the raw output: the shared prefix pushed the useful part out of view.
- Raw output folds under each step: output is evidence, not the main read.
- Hermes' narration kept as small lines between steps: it explains why the commands changed.
- Steps sit in one item card, open on load: this is the deliberate exception to "folded by default", because the steps are this screen's content.

## Jobs

- Schedule becomes a three-part readout: cadence with cron, next 3 runs, last result with time: it was a form, so reading it meant parsing inputs.
- Prompt renders as readable text, not mono, with headings, lists and code chips: `##` and `` ` `` showed as raw source.
- Prompt folds after 8 lines with Show all: one prompt took the full window.
- Pause, Run now (yellow) and Edit move to the header: there was no way to act on a job without editing it.
- Editing moves behind Edit: name, schedule, cron and prompt fields stay available, with Save as the primary.
- Sidebar meta shortened to `daily 03:00 · next 13 h · ok 10 h`: today's `daily at 03:…` truncated the most useful value.

## Commands

- One head per conversation with its count and failure count: the "Swift app ›" link repeated above every row.
- Group head stays the link to the conversation and folds its group: keeps today's jump to Chat.
- Folded header shows the command's first line: all headers looked identical without unfolding.
- Failures show `exit N` in terminal-red on a white chip in the orange header: terminal-red on orange fails contrast.
- Accent column carries meaning: cyan terminal, magenta vision_analyze, yellow other tools: scan by tool type.
- `One line` toggle next to Failed collapses cards to 28 px rows: lets the owner scan many calls.
- Header subtitle carries calls and failed counts: the filter now has a visible reason to use it.

## Departures and open points for the build

- White on ark-orange is about 3.3:1 at 12 px, under the 4.5:1 body floor: kept as owner-fixed; consider weight 600 if it reads thin.
- Body line height is 18 px on 13 px type (1.38), under the 1.5 default: chosen for the dense desktop layout; Jobs' prompt uses 20 px.
- The steel detail band runs #35373C to #191919, matching the shipping Chat header rather than the top bar's three stops.
- Traffic lights are flat dark-panel circles, matching the screenshots and staying inside the token list; the build uses the native controls.
- The running progress segment is ink, not yellow: the screen's one yellow mark stays on Steer.

## Sample data, not from the app

Not visible in the screenshots, so written to match the real content. Replace with live data in the build.

- Agents: per-step durations, the first `Grep` step's name and pattern.
- Agents sidebar: `ended 1 d ago` on rows 2 and 3.
- Commands: all first lines, outputs and exit codes; rows for Compare Open Design vs Penpot, homelab#1 and Trismegistus.
- Commands: conversation titles that were truncated are completed.
- Chat: the two command cards under the chip.
- Chat terminal pane contents.
- Needs check: inbox rows #48 (title) and #52 (end of title), and the ends of other truncated titles.
- Jobs: News publisher's next runs and all last-run times, derived from the relative times shown.
- Labels invented for empty states on rows the screenshots don't open.
