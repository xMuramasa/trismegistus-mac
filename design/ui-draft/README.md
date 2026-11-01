# UI draft (#5)

PNG exports of the Penpot draft (file "New File 1" in Penpot's Drafts project; it uses the published Endfield Arch library). Light mode only; SF Pro is shown as Inter and SF Mono as JetBrains Mono, because Penpot cannot render Apple fonts.

- `00-controls.png`: the controls proposal (native vs custom, with notes)
- `01`-`06`: the screens from #5: menu bar glyph, popover session list (+ empty, reconnecting), chat (+ run active with the steer offer), approval (in chat, native notification), pairing (+ expired code), settings
- `07-window.png`: the main window: conversations | chat | terminal (decided 2026-10-31, #4.1)
- `07b-window-live.png`: the same window as the app draws it on 2026-10-31 (Penpot file "Trismegistus-mac", frame "07b window, live", 1600 wide): the steel top bar (`#666666` → `#35373C` → `#191919`, light text, the context meter and model menu on it, the terminal's title above the pane), the Endfield paper (0.5 pt crosses every 96×64 pt, contour lines) beside the 760 pt message column, and the ink terminal pane with `sunken` contours and orange item cards (folded by default, accent column, rounded top-right corner) (#29, #30, #31)

These are a review artifact, not assets: the app draws everything in SwiftUI.
