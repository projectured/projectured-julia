"""
    ConsoleBackendModule

Console backend. Renders a **Text-domain** document (`TextBlock` and its spans)
straight to a terminal (stdout), preserving the spans' colors via ANSI SGR
codes, and (interactively) translates terminal keystrokes into the
backend-agnostic events the projection readers expect. Unlike the SDL backend
it consumes the Text domain directly — the pipeline stops at `SyntaxToText` and
does **not** run `TextToGraphics`, so `write_to_devices` receives a `TextBlock`,
not a `ScreenDocument`.

## Interactivity (Phase 2) and its limits

The **geometry-free** half of caret/text editing now lives on the Text domain
(`read_gesture(::TextBlock, gesture)` in `TextModule`), so the console pipeline
gets it even though it omits `TextToGraphics`: `SyntaxToText` falls back to the
output `TextBlock`'s `read_gesture` when its operation slot is empty (the console
case). What this backend drives is therefore:

  - **Structural tree navigation** (handled by `SyntaxToText`): arrows move
    node-to-node once a whole element is selected; `Home` selects the root.
  - **`Ctrl+Space`** toggles structural ⇄ text-cursor selection.
  - **Character editing** (via the Text domain's `read_gesture`): character
    insert (`KeyPress`), `Backspace`/`Delete`, and character left/right cursor
    movement — none of which need pixel geometry.
  - **`Ctrl+C`** quits, and so does an Escape that no reader handles. ESC
    followed by a key is that key with Alt.

Still SDL-only (they need the laid-out glyph geometry): visual up/down line
movement, plain (non-Ctrl) `Home`/`End` to the visual line edges, and
click-to-position.

The selection is shown as inverse-video span colors, baked into the spans by the
`SelectionInverting` projection at the end of the console pipeline (the backend
itself does not resolve the selection or emit a reverse-video attribute).
"""
module ConsoleBackendModule

using ..BackendModule
import ..EditorModule: get_backend_name, get_backend_output
using ..EventModule
using ..StyleModule
using ..TextModule

export ConsoleBackend, render_console


include("Console.jl")

end # module
