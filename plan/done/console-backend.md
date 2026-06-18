# Console backend (render the Text domain to the terminal)

## Goal

Add a new `Backend` — `ConsoleBackend` — that renders a **Text-domain**
document (`TextText` and its spans) straight to the terminal (stdout),
and run the `json_example` document + projection through it.

The key difference from the SDL path is that the console backend consumes
the **Text** domain directly and does **not** go through the
graphics/rendering step (`TextToGraphics`). The existing json pipeline is

```
JsonToSyntax → SyntaxToText → TextToGraphics   (→ GraphicsCanvas, rendered by SDL)
```

The console pipeline drops the final `TextToGraphics` step ("the GraphicsToText
step" in the request was a typo — there is no `GraphicsToText` projection; the
step being removed is `TextToGraphics`, which turns Text into Graphics):

```
JsonToSyntax → SyntaxToText                     (→ TextText, rendered by ConsoleBackend)
```

So `ConsoleBackend.write_to_devices` receives a `TextText` instead of a
`ScreenDocument`/`GraphicsCanvas`.

**Color is preserved.** The Text-domain spans carry their own
`font_color`/`fill_color` (set by `SyntaxToText` — keywords, punctuation,
literals each get a color). The console backend must keep these colors,
translating them to ANSI SGR codes, so the terminal output is colored the same
way the SDL window is — not plain monochrome text. This is a firm requirement,
not a nice-to-have.

## Why this is clean

- `SyntaxToText` already flattens the JSON syntax tree to a linear sequence
  of styled spans (`TextString`, `TextNewline`, `TextSpacing`, …) — exactly
  what a terminal wants.
- `TextToString` ([program/src/projection/primitive/TextToString.jl](../../program/src/projection/primitive/TextToString.jl))
  already shows how to flatten a `TextText` into a plain `String` (concatenate
  `TextString.content`, emit `\n` for `TextNewline`). The console renderer is
  essentially the same walk, plus optional ANSI styling, written straight to
  stdout instead of into an IoMap.
- The `Backend`/`Device` split ([guide/devices-and-backends.md](../../guide/devices-and-backends.md))
  is designed for exactly this: a new backend needs only `init!`, `quit!`,
  `measure_text`, `read_from_devices`, `write_to_devices`. Projection code is
  untouched.

## Scope / milestones

### Phase 1 — render-only (primary deliverable) ✅ DONE

A `ConsoleBackend` that prints the `TextText` output of the json pipeline to
the terminal once / each frame. No input handling yet.

**Implemented.** `run_console_example()` renders the JSON example to the
terminal with the solarized colors carried by the spans (keys blue, string
values green with yellow quotes, numbers magenta, delimiters gray). Verified:
stripping the ANSI codes from the colored output reproduces the plain output
byte-for-byte, and the wrong-output-type guard fires as expected.

Implementation decisions made during the build:
- **`color_default` → terminal default.** Default-black is only used by the
  empty zero-length boundary-marker spans (nothing to print), so the renderer
  emits a truecolor foreground only for a *meaningful* color (a `StyleColor`
  that is not `color_default`) and otherwise leaves the terminal's own
  foreground — avoiding black-on-dark. Backgrounds emit whenever `fill_color`
  is a `StyleColor`. Reset (`\e[0m`) is written after any styled span.
- **`clear` defaults to off for the one-shot runner** (`run_console_example`
  passes `clear=false`) so the output appends instead of wiping the
  scrollback. The backend still supports `clear=true` for an in-place repaint
  loop. Clear is gated on `ansi` (no control codes when ANSI is disabled).
- **Hard newlines inside `TextString.content` are preserved verbatim** (they
  pass straight through `print`), in addition to `TextNewline` spans.
- **`run_console_example` is keyword-based** (`document`, `projection`, `ansi`,
  `clear`) rather than `Example`-based, and does a one-shot render (no `run!`
  loop yet — a loop with no input just repaints the same frame).

- [x] **New file** `program/src/backend/Console.jl`, module `ConsoleBackendModule`.
  - `struct ConsoleBackend <: Backend` (holds an output `IO`, default
    `stdout`; a flag for whether ANSI styling is enabled; nothing else for
    phase 1).
  - `init!(::ConsoleBackend)` / `quit!(::ConsoleBackend)` — no-ops for phase 1
    (raw-mode terminal setup is phase 2).
  - `measure_text(::ConsoleBackend, text, font)` — the console pipeline never
    calls it (no `TextToGraphics` to lay out), but the interface requires the
    method. Return a character-cell estimate: `(length(text), 1)`.
  - `write_to_devices(::ConsoleBackend, devices, text::TextText)` — the
    renderer. Walk `text.elements`, dispatch per span:
    - `TextString` → write `content[]`, wrapped in ANSI SGR codes derived from
      the span's `font_color`/`fill_color` (see "ANSI styling" below). Color
      preservation is required.
    - `TextNewline` → write `"\n"`.
    - `TextSpacing` → write spaces (size is in pixels; approximate, or ignore
      for phase 1).
    - `TextGraphics` → ignore (or a placeholder glyph) — out of scope for a
      text console.
    Before writing the frame, emit an ANSI clear+home (`"\e[2J\e[H"`) so the
    document repaints in place rather than scrolling; on a non-TTY `IO` skip
    the control codes and just print. Flush at the end.
  - Add a `write_to_devices(::ConsoleBackend, devices, output)` fallback that
    errors with a clear message if the pipeline output is not a `TextText`
    (mirrors the SDL backend's `error("… expected GraphicsCanvas")`), so a
    miswired pipeline (e.g. one that still ends in `TextToGraphics`) fails loud.

- [x] **ANSI styling** (helper in the same file) — **required**, this is what
  preserves the Text domain's colors. Map a `StyleColor`
  (`red`/`green`/`blue`/`alpha` ∈ [0,1], so scale each component by 255) to a
  24-bit ANSI foreground code `"\e[38;2;{r};{g};{b}m"` and background
  `"\e[48;2;…m"`; reset with `"\e[0m"` after each styled span so colors don't
  bleed into the next span. Emit the foreground code whenever the span's
  `font_color` is set; emit the background code whenever `fill_color` is set;
  skip a code only when its color is `nothing` (treat `color_default` as a
  normal color and still emit it, or map it to reset — decide during impl).
  Provide an `ansi=false` switch on `ConsoleBackend` that suppresses all SGR
  codes for piping to a non-TTY/plain-text sink, but the **default is colored
  output**. Terminals without truecolor support degrade by ignoring the codes.

- [x] **Register the backend** in [program/src/Projectured.jl](../../program/src/Projectured.jl)
  alongside the SDL include/`using`, and re-export `ConsoleBackend`.

- [x] **Console pipeline + runner** in the example package
  (`example/src/projection/Json.jl` or a small new
  `example/src/Console.jl`):
  - `make_json_console_projection_example()` =
    `SequentialProjection(RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()))` — i.e. the existing json projection
    **minus** the trailing `TextToGraphics`. No `measure` argument needed.
  - `run_console_example(example=json_example)` — build the document +
    console projection, `projection_print` it, and either:
    - print once (simplest verification), or
    - drive `run!(ConsoleBackend(), projection, document)` for the loop.
    Do **not** wrap in `ScreenDocument`/`WindowDocument` — the console renders
    the bare `TextText`. (The multi-window `run_example` path is SDL-specific.)

### Phase 2 — interactive input (optional, deferred)

Make the console editable so the read-eval-print loop is meaningful.

- [ ] `init!` puts the terminal into raw mode (no line buffering, no echo);
  `quit!` restores it. (Julia: `REPL.TerminalMenus`/`ccall` to `tcsetattr`, or
  shell out to `stty raw -echo` / `stty sane`.)
- [ ] `read_from_devices(::ConsoleBackend, devices)` — read bytes from stdin,
  translate to the backend-agnostic events the readers already expect:
  - printable byte → `KeyPress(char)`.
  - ESC `[` sequences → `KeyDown(:left/:right/:up/:down, Modifiers())`.
  - Enter/Backspace/Tab → `KeyDown(:return/:backspace/:tab, …)`.
  - `Ctrl-C` / `Esc` → `QuitEvent()`.
  Wrap in an `EventEnvelope` (the editor's `read!` unwraps `env.event`); since
  there is no `WindowDocument`, use a sentinel/`:console` id. Return `nothing`
  when no byte is available (non-blocking poll).
- [ ] Render the caret: `SyntaxToText`/the Text domain carry a `selection`;
  decide how to show it in the terminal (e.g. reverse-video the cursor cell,
  or print the path). Mouse events are not applicable to a plain console —
  omit `Mouse`.
- [ ] Adjust the `run!` bootstrap (or the console runner) so
  `devices = Device[Keyboard()]` only — `Screen`/`Mouse` are SDL concepts.
  Confirm `editor.iomap.output` is the `TextText` and that `read!` tolerates a
  non-`Screen` device set.

## Open questions / decisions to confirm during implementation

1. **Frame model.** Phase 1 can be a one-shot print (verify the renderer) or
   the full `run!` loop. Recommend starting one-shot, then wiring `run!` once
   Phase 2 input exists — a `run!` loop with no input just repaints the same
   frame.
2. **`run!` device list.** The current `run!(backend, projection, document)`
   bootstrap hard-codes `Device[Screen(), Keyboard(), Mouse()]`
   ([program/src/editor/Editor.jl:197](../../program/src/editor/Editor.jl#L197)).
   For the console we want a different device set. Either add a `devices`
   keyword to the bootstrap `run!`, or have `run_console_example` construct the
   `Editor` directly. Prefer the keyword so both backends share the bootstrap.
3. **`write_to_devices` output type.** Confirm the editor passes
   `editor.iomap.output` (the `TextText`), not a `Cell`. `print!` calls
   `write_to_devices(backend, devices, editor.iomap.output)`; the SDL path
   receives a concrete `ScreenDocument`, so the console should receive a
   concrete `TextText`. Verify and unwrap a `Cell` defensively if needed.

## Verification

- Phase 1: `run_console_example(json_example)` (or the one-shot printer) prints
  the JSON document as **colored** styled text to the terminal, matching the
  structure that `print_example("json")` / the SDL window shows — minus pixel
  layout. Eyeball that keywords/punctuation/literals carry the same colors the
  SDL window uses (the colors come from the same `font_color`/`fill_color` on
  the spans).
- Compare against `TextToString` output for the same pipeline (sans
  `TextToGraphics`) to confirm the underlying character stream matches once the
  ANSI SGR codes are stripped (`ansi=false`).
- No new test target is strictly required for Phase 1 (it is I/O to stdout),
  but a smoke test that asserts the flattened string equals the
  `TextToString` projection's output of the same `TextText` would lock in the
  contract cheaply.

## Files touched

- **New:** `program/src/backend/Console.jl`
- **Edit:** `program/src/Projectured.jl` (include + export)
- **New/Edit:** `example/src/projection/Json.jl` (console projection) and/or a
  small `example/src/Console.jl` (`run_console_example`)
- **Edit (Phase 2):** `program/src/editor/Editor.jl` (`devices` keyword on the
  bootstrap `run!`)
- **Doc:** add a "Console" row/section to
  [guide/devices-and-backends.md](../../guide/devices-and-backends.md) once it
  works.
