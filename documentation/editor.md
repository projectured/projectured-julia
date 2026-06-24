# Editor

The editor ties everything together: it owns the document, the projection
pipeline, the backend, and the input devices, and runs a read-eval-print loop
that responds to user input. The implementation lives in
[program/src/editor/Editor.jl](../package/kernel/src/editor/Editor.jl), whose `run!`
function is the entry point.

## The Editor struct

```julia
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    iomap::Union{IoMap, Nothing}        # latest output of projection_print
    operation::Union{Operation, Nothing}# latest output of projection_read
end
```

- `backend` — the display/input backend (e.g. `SdlBackend`)
- `document` — the reactive document being edited
- `projection` — the projection pipeline; typically a `SequentialProjection`
  that ends in a `GraphicsCanvas`-producing step
- `devices` — `Vector{Device}` with the screen, keyboard, and mouse
- `iomap` — the most recent IoMap from `projection_print`; needed by
  `projection_read` to translate the next event back to a domain operation
- `operation` — the most recent operation; used by `evaluate!` and the
  per-frame log

## The Read-Eval-Print loop

`run!(editor)` executes:

```julia
while true
    perf_reset!()
    read!(editor)      # poll devices → projection_read → editor.operation
    evaluate!(editor)  # evaluate_operation(editor, editor.operation)
    print!(editor)     # projection_print → editor.iomap; render to devices
    perf!(editor)      # log reactive counters
    sleep(0.01)
end
```

A `QuitEditorException` thrown out of `evaluate_operation` exits the loop
cleanly. The MCP server is started before the loop and stopped in the
`finally` block — see below.

### Read

`read_from_devices(backend, devices)` polls the backend's event queue (in
the SDL case, `SDL_PollEvent`) and returns the next `EventEnvelope` wrapping a
backend-agnostic event: `KeyDown`, `KeyUp`, `KeyPress`, `MouseDown`, `MouseUp`,
`MousePress`, `MouseMove`, `MouseScroll`, or `QuitEvent`. The envelope is then
wrapped in a `Change` and passed through
`projection_read(editor.projection, nothing, Change(env, nothing), editor.iomap)`
— the entire pipeline walks backward, each projection contributing a translation
step until an `Operation` falls out at the document end.

### Evaluate

`evaluate_operation(editor, operation)` is a generic function with methods
defined per operation; methods reach for the document via `editor.document`. For
`ReplaceSelectionOperation` the implementation is
`clear_selection!(editor.document); set_selection!(editor.document, op.path)`. For
`QuitEditorOperation` it throws `QuitEditorException`. Other operations
(e.g. the generic `ReplaceReferencedValue`, or `ReplaceFocusPartOperation`) mutate
the document or projection state directly. See [the operations guide](operations.md).

### Print

If `editor.iomap` is `nothing`, `projection_print(editor.projection,
editor.document)` runs the whole pipeline and stores the result. The IoMap
is then written to each output device with `write_to_devices(backend,
devices, iomap.output)`. Because every intermediate value is a reactive
`Cell`, subsequent reads only recompute the parts that were invalidated by
the operation — the rest is served from the cache.

The `iomap` is *not* invalidated at the end of a frame — its contents are
reactive and will refresh on the next read.

## Running an editor

The entry point is the bootstrap overload `run!(backend, projection, document; mcp=false)`:

```julia
using Projectured

backend  = SdlBackend()
document = JsonString("hello world")
proj     = SequentialProjection(
    JsonToSyntax(),
    SyntaxToText(),
    TextToGraphics(measure = (t, f) -> sdl_measure_text(backend, t, f)),
)

run!(backend, proj, document)
```

The backend is pluggable: swap `SdlBackend()` for `WebBackend()` to run the same
editor in a browser instead of a native window (see the
[devices and backends guide](devices-and-backends.md#web-backend)), or
`ConsoleBackend()` for the terminal. Nothing else changes.

This overload calls `init!(backend)`, builds a `Vector{Device}` (default
`Screen()`, `Keyboard()`, `Mouse()`), constructs the `Editor`, and runs the
loop. Native windows are not pre-allocated — the backend opens them on demand
the first time `write_to_devices` sees a `ScreenDocument` output (the pipeline is
expected to end in one). `quit!(backend)` cleanup is in a `finally` block. Pass
`mcp=true` to start an MCP server alongside the loop. A backend that drives a
different channel passes its own `devices` (the `ConsoleBackend` uses
`devices = Device[Keyboard()]` — no `Screen`/`Mouse`).

## Scripted live playback

`play_live!` is a sibling entry point that runs the same read-eval-print loop
but **fires a predefined timeline on a wall-clock schedule**, so a recorded
session plays out on a real window while the user watches (and can still
interact — real input is polled every frame, and Escape / window-close quits).

```julia
play_live!(backend, projection, document, timeline;
           window_id::Symbol, initial_hold=0.5,
           op_prefix=EmptyReferencePath())
```

A *timeline* is a vector of timed entries; the present key selects the kind
(the same format `record_video` consumes, so one timeline drives both a headless
recording and live playback):

- `(event = <device event>, hold = <seconds>)` — wrapped in
  `EventEnvelope(window_id, event)` and run through `projection_read`, exactly
  like live input.
- `(operation = <Operation | doc -> op>, hold = <seconds>)` — a domain
  `Operation` (or a thunk evaluated at fire time) injected **straight into
  `evaluate_operation`**, skipping the reader. This expresses actions with no
  single device-event trigger (seed a selection, scroll, swap focus/document).

`hold` is the dwell after an entry. In `record_video` it becomes a frame count
(video time); here it becomes a wall-clock delay before the next entry. Entry
`i` fires at `initial_hold + Σ hold[1..i-1]` seconds; at most one scheduled
entry is applied per frame, so each resulting state is visible.

### Rooting injected operations: `op_prefix`

A timeline is authored in the **bare-content** domain (the document the example
projects, the same coordinates `record_video` uses). When the example is wrapped
in a window for live playback, the live document root is a `ScreenDocument`, not
the content. `:event` entries are rerooted automatically — the
`ScreenToScreen` / `WindowManagerProjection` readers prepend the
`windows[i].content` steps to every operation they emit. A directly-injected
`:operation` **bypasses the reader**, so its bare-content path would be applied
to the screen root and fail. `op_prefix` (a `ReferencePath`) closes the gap:
`play_live!` reroots each `:operation` entry through
`prepend_steps_to_op(op, steps(op_prefix))`. Pass
`op_prefix = @reference windows[1].content` when the example sits in window 1;
leave it empty (the default) for an unwrapped, single-document pipeline.

In the example layer this is wired up for you — see `play_live_example` and
`LiveExample` in [the live-examples debugging section](debugging.md#live-examples-scripted-sessions-on-a-real-window).

## Devices and backends

- `Device` is an abstract type. Concrete subtypes are `Screen`, `Keyboard`,
  and `Mouse` — see [the devices and backends guide](devices-and-backends.md).
- `Backend` is the abstraction over the display/input platform. There are two
  implementations: `SdlBackend` (graphics) and `ConsoleBackend` (terminal). The
  backend provides `init!`, `quit!`, and `measure_text`; `read_from_devices` /
  `write_to_devices` are the `Device` interface.
- Projections that need to measure text take a `measure::Function` argument
  (e.g. `TextToGraphics`); the backend's `sdl_measure_text` is the usual
  injection.
- The `ConsoleBackend` consumes the **Text** domain directly (no
  `TextToGraphics`): its `write_to_devices` renders a `TextText` to the terminal
  with ANSI colors, the selection encoded as inverse-video span colors by a
  `SelectionInverting` projection at the end of the pipeline, and
  `read_from_devices` turns keystrokes into the same `KeyDown`/`KeyPress`/
  `QuitEvent` events. Because it has no screen/window layer, its pipeline adds an
  `EnvelopeUnwrappingProjection` to strip the `EventEnvelope` that
  `ScreenToScreen` would otherwise strip. Run it with
  `run_console_example()` / `run_console_example(interactive=true)`. See
  [the devices and backends guide](devices-and-backends.md#consolebackend).

## MCP server

When `run!` starts, it constructs an `McpServer` bound to the editor and
launches it on `http://127.0.0.1:9876/mcp` (see
[program/src/editor/Mcp.jl](../package/kernel/src/editor/Mcp.jl)). The server
speaks JSON-RPC 2.0 via HTTP+SSE using
[ModelContextProtocol.jl](https://github.com/JuliaModelContextProtocol/ModelContextProtocol.jl).

Tools exposed by the server include `execute_julia_code` (run arbitrary
Julia in the editor process with `editor` bound and `using Projectured`
preloaded), plus resource listings for guides, modules, classes, and
function documentation. The intent is that an AI assistant can inspect and
manipulate `editor.document` and `editor.projection` live.

`execute_julia_code` runs each top-level statement in a **persistent scratch
module**, so a variable assigned in one call (`paths = search_references(…)`)
stays bound for the next — the caller can build up state incrementally instead
of resending one large block. It returns the repr of the last value plus any
captured stdout/stderr.

The server is stopped in the `finally` block of `run!`.

## Performance counters

Each frame the editor calls `perf_reset!()` before reading input and
`perf!()` after rendering, which logs

```
[perf] reads=… computes=… invalidations=… writes=…
```

when an operation was applied. Use these to find unintentional
recomputation: if a single keypress causes thousands of `computes`,
something is reading more cells than necessary.

## Adding new operations

If you introduce a new editing operation, you need to:

1. Define a struct subtyping `Operation`.
2. Add an `evaluate_operation(editor, op::YourOp)` method (reach for the
   document via `editor.document`).
3. Update the relevant projection's `projection_read` to produce the
   operation from the appropriate event.

See [the operations guide](operations.md) for examples.
