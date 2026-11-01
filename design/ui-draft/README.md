# UI draft (#5)

PNG exports of the Penpot draft (file "New File 1" in Penpot's Drafts project; it uses the published Endfield Arch library). Light mode only. Inter and JetBrains Mono, the same fonts the app bundles since #33; the Tokens page and the token set "Trismegistus" hold the values of `design/tokens.json`.

- `00-controls.png`: the controls proposal (native vs custom, with notes)
- `01`-`06`: the screens from #5: menu bar glyph, popover session list (+ empty, reconnecting), chat (+ run active with the steer offer), approval (in chat, native notification), pairing (+ expired code), settings
- `07-window.png`: the main window: conversations | chat | terminal (decided 2026-10-31, #4.1)
- `07b-window-live.png`: the same window as the app draws it on 2026-10-31 (Penpot file "Trismegistus-mac", frame "07b window, live", 1600 wide): the steel top bar (`#666666` → `#35373C` → `#191919`, light text, the context meter and model menu on it, the terminal's title above the pane), the Endfield paper (0.5 pt crosses every 96×64 pt, contour lines) beside the 760 pt message column, and the ink terminal pane with `sunken` contours and orange item cards (folded by default, accent column, rounded top-right corner) (#29, #30, #31)
- `07c-window-live.png`: the window as built for #32 (frame "07c window, live"): our own flat `sunken` sidebar with the Commands row on top and News among the conversations, the selected row white with a yellow border, the steel bar across the whole window with its trailing items at the right edge (light sidebar and settings icons), the terminal's title row inside the pane, the title rule under the conversation header with its subtitle, a 700 pt message column, plain Hermes messages, key hints under the input, 24 pt between terminal cards
- `tokens.png`: the Tokens page (#33): palette and roles, the 10 text styles on Inter and JetBrains Mono, the strict spacing scale, sizes, icons, radius, stroke, opacity, shadow, motion; the same values as `design/tokens.json`, also as the Penpot token set "Trismegistus" (119 tokens; #36 added status.warn, status.bad, line.on-dark and line.outline-on-dark; #38 surface.inverse, mark.empty, marker, card.on-header and line.paper-cross)
- `07d-window-commands-log.png`: the Commands log (frame "07d window, commands log"): every tool call, no Commands / All tools filter; Failed, search and the conversation picker; each call as a conversation link plus an item card, 20 pt apart; terminal pane closed

These are a review artifact, not assets: the app draws everything in SwiftUI.
