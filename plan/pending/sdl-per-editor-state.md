# The SDL backend keeps the state of each editor apart

The rule PAR-PER-EDITOR-STATE says: "No process-global state in the editor or the
machinery it drives; one process must run many editors at once." The requirement
behind it, PR-MANY-EDITORS-ONE-PROCESS, says: "Starting, using, or stopping one
editor must have no effect on any other."

The device audit (`plan/done/device-layer-audit.md`) moved the display scale and
the uniform zoom into the `Display` of each editor. It found three more
process-global values in the SDL backend. The owner asked for a plan on
2026-09-25. While this plan was written, a larger fault came to light: the SDL
session itself is shared by every backend in the process (Part 2).

The owner deferred Part 2 on 2026-09-25: many editors in one process matter more
for the web backend than for SDL. Part 1 stays in this plan.

The font zoom `_FONT_ZOOM` has a plan of its own:
`plan/pending/font-zoom-per-editor.md`.

## Part 1: three values and one measure

### The facts

| Value | What it holds | Written by | Read by |
| --- | --- | --- | --- |
| `_LAST_HOVER_MOTION` | the time of the last pointer motion that `read_from_devices` answered with no button held | `read_from_devices` | `read_from_devices`, `wait_for_input` |
| `_PARTIAL_RENDER` | whether a window repaints only the dirty rectangle | `initialize_backend!`, from `backend.partial_render` | `_render_window!` |
| `_DEBUG_DIRTY` | whether a window outlines the dirty rectangle in red | `initialize_backend!`, from `backend.debug_dirty` | `_render_window!` |

- With two editors, the pointer motion of one editor starts the rate limit of
  the other. A hover in one window can then wait for up to 30 ms.
- `initialize_backend!` copies the two render switches of the backend that
  started last. So the settings of one editor apply to the windows of every
  editor.
- `VideoBackend.measure_text` makes a new `SdlBackend()` for each measure, with
  two dictionaries and a `Display`. `measure_sdl_text` gives the same result.

### The change

1. `SdlBackend` gets a field `last_hover_motion::Float64`, `0.0` for a new
   backend. `read_from_devices` and `wait_for_input` read and write it. The
   tests `InputCoalescingTest.jl` (3 lines) and `WaitWakeTest.jl` (1 line) set
   the field in place of the global.
2. `_render_window!` reads `partial_render` and `debug_dirty` from the backend.
   It gets the backend as its first argument, from `write_to_devices` and
   `_show_painted_window!`. `initialize_backend!` stops copying them, and the two
   globals go.
3. `VideoBackend.measure_text` calls `measure_sdl_text(text, font)`.
4. The comment in `quit_backend!(::WebBackend)` says that the web backend does
   not stop SDL because of the SDL font cache. The web backend does not use SDL
   at all, so the comment goes.

These stay, because each gives the same answer to every editor, as the
exception in PAR-PER-EDITOR-STATE allows:

- `_PROBED_DISPLAY_SCALE` and its two latches, `_EGL_AVAILABLE` and
  `_GLX_AVAILABLE`: facts of the machine, found once.
- `_font_cache`: font handles keyed by file and size.
- `_text_texture_cache`: textures keyed by renderer, text, font, size and
  colour.

The size is about 30 lines in `Sdl.jl`, `VideoBackend.jl`, `Web.jl` and two
tests.

## Part 2: the SDL session is shared by every backend (deferred)

### The facts

SDL and SDL_ttf are one session for each process: one initialization, one event
queue, one set of open fonts. Each `SdlBackend` acts as if the session were its
own.

- **A stop stops every editor.** `quit_backend!` closes every font in
  `_font_cache`, frees the text textures of every window, and calls `TTF_Quit()`
  and `SDL_Quit()`. The windows of every other editor then draw with closed
  fonts and a stopped SDL.
- **Each editor takes the input of the others.** `_poll_window_input(backend)`
  takes every event from the one SDL queue. An event for a window of another
  backend gets the window id `:none`, so the backend that polls first gets the
  event and the right editor never sees it. `wait_for_input` waits on the same
  queue, and `wake_backend!` pushes into it, so a wake of one editor can end the
  wait of another.
- The web backend already knows the first fault. Its `quit_backend!` does not
  call `TTF_Quit` or `SDL_Quit`, with a comment that the shared font cache would
  hold dangling pointers.
- No code that I found runs two SDL editors at the same time. So both faults are
  latent. But they break the requirement as it is written, and the first editor
  that opens a second SDL editor in the same process meets them.

### The options

- **(a) One session, and a count of the backends that use it.**
  - `initialize_backend!` starts SDL, SDL_ttf and the font cache when the count
    goes from 0 to 1.
  - `quit_backend!` closes only the windows and textures of its own backend. It
    closes the fonts and stops SDL only when the count goes back to 0.
  - The event queue gets a router. The backend that polls takes the events from
    SDL and puts each one in the queue of the backend that owns its window, by
    the SDL window id. It then answers from its own queue. An event with no
    window, such as `SDL_QUIT`, goes to every backend.
  - Each backend already registers a wake event type of its own, so the router
    sends a wake to the backend of its type. Today `_poll_window_input` drops
    the wake of any backend.
  - The session and the router are process-global. But each backend sees only
    its own entries, so no editor observes another. The rule needs one sentence
    for this kind of table: a process-wide resource that one library allows,
    divided among its owners.
  - The size is about 150 lines in `Sdl.jl`, and a test with two backends in one
    process.
- **(b) One `SdlBackend` for all editors.** The backend becomes the session, and
  each editor has its own windows in it. But the backend also holds state of one
  editor: its `Display`, the pending input, and the rate limit of Part 1. That
  state would have to move out again. This option is larger than (a).
- **(c) Accept one SDL editor for each process.** `initialize_backend!` throws a
  clear error when a second SDL backend starts while one is live. The rule and
  the requirement get a written exception for SDL. This option is small, but it
  gives up a requirement that the owner accepted.

My recommendation was (a), because it keeps the requirement, and the session
is the one place that knows that SDL is a single resource. The owner deferred
the decision.

## Steps

Each step is a commit in a worktree.

0. [ ] The baseline on main: `test_sdl()`, `test_video()`, and the live-window
   check of the device audit (the note `live-window-pixel-compare`).
1. [ ] Part 1, items 1 to 4, with their tests.
2. [ ] The check: the suites as on main plus the new tests, and the
   live-window check.

Part 2 needs a plan step of its own when the owner takes it up again. Its check
is a test that runs two SDL backends in one process: each gets only the input of
its own windows, and a stop of one leaves the other drawing.
