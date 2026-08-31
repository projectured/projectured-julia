# Editor

The editor ties everything together: it owns the document, the projection
pipeline, the backend, and the input devices, and runs a read-eval-print loop
that responds to user input. The implementation lives in
[package/kernel/main/editor/Editor.jl](../../../source/kernel/editor/Editor.jl), whose `run_editor!`
function is the entry point.

## The Editor struct

```julia
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    inbox::Channel{Operation}           # operations posted from other tasks
    iomap::Union{IoMap, Nothing}        # latest output of print_document
    operation::Union{Operation, Nothing}# latest output of read_intent
end
```

- `backend` — the display/input backend (e.g. `SdlBackend`)
- `document` — the reactive document being edited
- `projection` — the projection pipeline; typically a `ChainingProjection`
  that ends in a `GraphicsCanvas`-producing step
- `devices` — `Vector{Device}` with the screen, keyboard, and mouse
- `inbox` — what was posted from outside the editor's own task; see
  [The inbox](#the-inbox)
- `iomap` — the most recent IoMap from `print_document`; needed by
  `read_intent` to translate the next event back to a domain operation
- `operation` — the most recent operation; used by `evaluate!` and the
  per-frame log

## The Read-Eval-Print loop

`run_editor!(editor)` executes:

```julia
while true
    with_performance_counters() do  # bind a fresh per-frame counter store
        drain_operations!(editor)  # apply what other tasks posted
        read!(editor)      # poll devices → read_intent → editor.operation
        evaluate!(editor)  # evaluate_operation(editor, editor.operation)
        print!(editor)     # print_document → editor.iomap; render to devices
        perf!(editor)      # log reactive counters
    end
    sleep(0.01)
end
```

### The inbox

A frame reads the document, evaluates against it and paints it, so anything
that writes it from another task races the frame — and a reactive thunk cannot
write at all. `post_operation!(editor, operation)` is the one door in:

```julia
post_operation!(editor, RefreshOperation(subject))   # from any task
```

The operation is applied by the editor's own task, at the top of the next
frame, before `read!` — so the frame paints what it just applied. This is what
anything with a loop of its own uses to reach the editor: a driver advancing a
simulation, a file watcher, an agent, a timer.

The channel is bounded (`INBOX_CAPACITY`), so a producer faster than the editor
waits rather than queueing work that will be stale before it is applied.

Posted operations go through `evaluate_operation` and not `evaluate!`, so they
do not become `editor.operation` — that field means "what the reader made of
this frame's input", which is what `perf!` uses to tell a frame the user acted
in from an idle one, and what `evaluate!` writes to the operation log.

A `QuitEditorException` thrown out of `evaluate_operation` exits the loop
cleanly. The MCP server is started before the loop and stopped in the
`finally` block — see below.

### Read

`read_from_devices(backend, devices)` polls the backend's event queue (in
the SDL case, `SDL_PollEvent`) and returns the next `WindowInput` wrapping a
backend-agnostic event: `KeyDown`, `KeyUp`, `KeyPress`, `MouseDown`, `MouseUp`,
`MousePress`, `MouseMove`, `MouseScroll`, or `WindowQuit`. The window input is then
wrapped in a `Intent` and passed through
`read_intent(editor.projection, nothing, Intent(window_input, nothing), editor.iomap)`
— the entire pipeline walks backward, each projection contributing a translation
step until an `Operation` falls out at the document end.

### Evaluate

`evaluate_operation(editor, operation)` is a generic function with methods
defined per operation; methods reach for the document via `editor.document`. For
`ReplaceSelectionOperation` the implementation is
`clear_selection!(editor.document); set_selection!(editor.document, op.path)`. For
`QuitEditorOperation` it throws `QuitEditorException`. Other operations
(e.g. the generic `ReplaceReferencedValueOperation`, or `ReplaceFocusPartOperation`) mutate
the document or projection state directly. See [the operations guide](operation.md).

### Print

If `editor.iomap` is `nothing`, `print_document(editor.projection,
editor.document)` runs the whole pipeline and stores the result. The IoMap
is then written to each output device with `write_to_devices(backend,
devices, iomap.output)`. Because every intermediate value is a reactive
`Cell`, subsequent reads only recompute the parts that were invalidated by
the operation — the rest is served from the cache.

The `iomap` is *not* invalidated at the end of a frame — its contents are
reactive and will refresh on the next read.

## Running an editor

The entry point is the bootstrap overload `run_editor!(backend, projection, document; mcp=false)`:

```julia
using Projectured

backend  = SdlBackend()
document = JsonString("hello world")
proj     = ChainingProjection(
    JsonToSyntax(),
    SyntaxToText(),
    TextToGraphics(measure = (t, f) -> sdl_measure_text(backend, t, f)),
)

run_editor!(backend, proj, document)
```

The backend is pluggable: swap `SdlBackend()` for `WebBackend()` to run the same
editor in a browser instead of a native window (see the
[devices and backends guide](devices-and-backends.md#web-backend)), or
`ConsoleBackend()` for the terminal. Nothing else changes.

This overload calls `initialize_backend!(backend)`, builds a `Vector{Device}` (default
`Display()`, `Keyboard()`, `Mouse()`), populates their physical properties from the
backend with `configure_devices!`, opens the native windows with
`open_native_windows!`, constructs the `Editor`, and runs the loop. The windows
are opened before the first frame, and the document is corrected to the geometry
the window system granted: a manager may grant less than it is asked for, and it
answers only once the window exists, so a document projected first is projected
at a size the window never has and computes a second time when the answer
arrives. A window a projection opens later — a tooltip, a popup — is still
opened on demand, by `write_to_devices` against the `ScreenDocument` output (the
pipeline is expected to end in one).
`quit_backend!(backend)` cleanup is in a `finally` block. Pass
`mcp=true` to start an MCP server alongside the loop. A backend that drives a
different channel passes its own `devices` (the `ConsoleBackend` uses
`devices = Device[Keyboard()]` — no `Display`/`Mouse`).

## Scripted live playback

`play_live!` is a sibling entry point that runs the same read-eval-print loop
but **fires a predefined timeline on a wall-clock schedule**, so a recorded
session plays out on a real window while the user watches (and can still
interact — real input is polled every frame, and Escape / window-close quits).

```julia
play_live!(backend, projection, document, timeline;
           window_id::Symbol, initial_hold=0.5,
           op_prefix=EmptyReference())
```

A *timeline* is a vector of timed entries; the present key selects the kind
(the same format `record_video` consumes, so one timeline drives both a headless
recording and live playback):

- `(event = <device event>, hold = <seconds>)` — wrapped in
  `WindowInput(window_id, event)` and run through `read_intent`, exactly
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
`ScreenToScreen` / `WindowManagingProjection` readers prepend the
`windows[i].content` steps to every operation they emit. A directly-injected
`:operation` **bypasses the reader**, so its bare-content path would be applied
to the screen root and fail. `op_prefix` (a `Reference`) closes the gap:
`play_live!` reroots each `:operation` entry through
`reroot_operation(op, steps(op_prefix))`. Pass
`op_prefix = @reference windows[1].content` when the example sits in window 1;
leave it empty (the default) for an unwrapped, single-document pipeline.

In the example packages this is wired up for you — see `play_live_example` and
`LiveExample` in [the live-examples debugging section](../../../documentation/debugging.md#live-examples-scripted-sessions-on-a-real-window).

## Devices and backends

- `Device` is an abstract type. Concrete subtypes are `Display`, `Keyboard`,
  and `Mouse` — see [the devices and backends guide](devices-and-backends.md).
- `Backend` is the abstraction over the display/input platform. There are two
  implementations: `SdlBackend` (graphics) and `ConsoleBackend` (terminal). The
  backend provides `initialize_backend!`, `quit_backend!`, `measure_text`, and
  the per-frame device I/O `read_from_devices` / `write_to_devices`.
- Projections that need to measure text take a `measure::Function` argument
  (e.g. `TextToGraphics`); the backend's `sdl_measure_text` is the usual
  injection.
- The `ConsoleBackend` consumes the **Text** domain directly (no
  `TextToGraphics`): its `write_to_devices` renders a `TextBlock` to the terminal
  with ANSI colors, the selection encoded as inverse-video span colors by a
  `SelectionInverting` projection at the end of the pipeline, and
  `read_from_devices` turns keystrokes into the same `KeyDown`/`KeyPress`/
  `WindowQuit` events. Because it has no screen/window layer, its pipeline adds an
  `WindowInputUnwrappingProjection` to strip the `WindowInput` that
  `ScreenToScreen` would otherwise strip. Run it with
  `run_console_example()` / `run_console_example(interactive=true)`. See
  [the devices and backends guide](devices-and-backends.md#consolebackend).

## MCP server

When `run_editor!` starts, it constructs an `McpServer` bound to the editor and
launches it on `http://127.0.0.1:9876/mcp` via the `make_agent_server(:mcp, …)`
seam (see
[package/kernel/main/agent/AgentServer.jl](../../../source/kernel/agent/AgentServer.jl)). The server
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

The server is stopped in the `finally` block of `run_editor!`.

## Performance counters

Each frame the editor binds a fresh counter store with `with_performance_counters()`
and calls `perf!()` after rendering, which logs

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
3. Update the relevant projection's `read_intent` to produce the
   operation from the appropriate event.

See [the operations guide](operation.md) for examples.

## The editor layer

The material above is *how* to run and script an editor. The rest of this guide
is the layer's **structure** — where the code lives and what it depends on.

Layer 17 of the kernel is the **read-eval-print loop** described under
[The Read-Eval-Print loop](#the-read-eval-print-loop) above: it pulls together
every lower layer into the frame-by-frame drive — read from the device, evaluate
the gesture into an operation, apply the operation to the document, print the
document through the projection, tick the clock.

The layer lives in [main/editor/](../../../source/kernel/editor/):

```
Editor.jl    (EditorModule)    — the run_editor! loop and Editor struct
Playback.jl  (PlaybackModule)  — scripted live playback on a wall-clock timeline
```

The gesture recognizer that synthesises `MousePress` from MouseDown/MouseUp
pairs and `KeyChord` from KeyDown sequences lives in `gesture/` (its only
dependency is `EventModule`, no editor coupling). The global animation clock
`TimeModule` lives in `cell/`
(every animated projection reads it, so it belongs beside the engine it
depends on). What's left in `editor/` is the loop and its scripted
playback. Alongside the four visible sub-steps, `read!` also folds
MouseDown/MouseUp into MousePress and KeyDown sequences into KeyChords (via
the gesture recognizer) before yielding an `WindowInput`, and
`tick_editor_time!(now)` advances the animation clock, invalidating every cell
that subscribed to `get_reactive_editor_time()`.

### Downward edges

- `..ProjectionModule` — `Projection`, `print_document`, `read_intent`,
  `Intent`, `IoMap`.
- `..DeviceModule` — `Device`, `Display`.
- `..BackendModule` — `Backend`, `initialize_backend!`, `quit_backend!`,
  `read_from_devices`, `write_to_devices`.
- `..EventModule` — `WindowInput`, `WindowQuit`, and the event type
  predicates (`KeyDown`, `MousePress`, …).
- `..PerformanceCounterModule` — the counters bumped inline in the loop.
- `..TimeModule` — `tick_editor_time!`.
- `..DocumentModule` — the abstract `Document` type.
- `..OperationModule` — the operation abstract + evaluate seam.
- `..GestureRecognizerModule` — the frame's gesture folding.
- `..ToolModule` — `ToolSet`, the `tools` field every `Editor` owns
  ([PAR-PER-EDITOR-STATE](../../../documentation/architecture-requirements.md#par-per-editor-state)).
- `..AgentServerModule` — the make_agent_server/start/stop seam driven by
  `Editor` when an agent server is configured.

That is nearly the full kernel — the editor is the layer that consumes
every other layer. Playback additionally depends on `EditorModule` (to
reuse the four sub-steps) and `OperationModule` (to preview
`reroot_operation` as scripted events replay).

### Testing

The per-layer editor test folder, [test/editor/](../../../test/kernel/editor/), drives
the loop against the dependency-free `HeadlessBackend` from
`ProjecturedKernelExample` — one place the loop can be exercised without any real backend
package, and the biggest current kernel-local test gap.
