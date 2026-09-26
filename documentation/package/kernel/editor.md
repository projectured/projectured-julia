# Editor

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

The editor ties everything together: it owns the document, the projection
pipeline, the backend, and the input devices, and runs a read-eval-print loop
that responds to user input. The implementation lives in
[source/kernel/editor/EditorModule.jl](../../../source/kernel/editor/EditorModule.jl), whose `run_editor!`
function is the entry point.

## The Editor struct

```julia
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    clock::Clock
    tools::ToolSet
    inbox::Channel{Operation}
    iomap::Union{IoMap, Nothing}
    operation::Union{Operation, Nothing}
    recognizer::GestureRecognizer
end
```

- `backend` — the display/input backend (e.g. `SdlBackend`)
- `document` — the reactive document being edited
- `projection` — the projection pipeline; typically a `ChainingProjection`
  that ends in a `GraphicsCanvas`-producing step
- `devices` — `Vector{Device}` with the screen, keyboard, and mouse
- `clock` — this editor's own animation clock (a fresh `Clock()` by default);
  `run_editor!` ticks it once per frame from wall-clock time, so an animated
  projection built against this editor reanimates independently of any other
  editor running in the same process
- `tools` — what this editor exposes to an agent: the `ToolSet` an agent loop
  drives and an MCP server publishes, empty until
  `register_default_tools!(editor.tools)` fills it. Per editor, so two editors
  in one process share neither a tool list nor an `execute_julia_code`
  namespace — see [agent.md](agent.md)
- `inbox` — what was posted from outside the editor's own task; see
  [The inbox](#the-inbox)
- `iomap` — the most recent IoMap from `print_document`; needed by
  `read_intent` to translate the next event back to a domain operation
- `operation` — the most recent operation; used by `evaluate!` and the
  per-frame log
- `recognizer` — the event → gesture recognizer that folds raw `MouseDown`/`MouseUp`
  into `MouseClick` and `KeyDown` sequences into `KeyChord`, private to this
  editor so two editors do not share chord-in-progress state
- `loop_task` — the task that runs `run_editor!`, or `nothing` while no loop
  runs; see [A call on the editor task](#a-call-on-the-editor-task)

## The Read-Eval-Print loop

`run_editor!(editor)` executes (the fault barriers around each stage elided):

```julia
while true
    if !editor.wake_pending[]                        # a pending wake skips the wait
        timeout = compute_wait_timeout(editor)       # animation, feed deadlines, timers, else Inf
        timeout > 0 && wait_for_input(editor.backend, editor.devices, timeout)
    end
    Threads.atomic_xchg!(editor.wake_pending, false) # this frame owns every wake so far
    with_performance_counters() do   # bind a fresh per-frame counter store
        set_clock_time!(editor.clock, Base.time() - t_start)  # tick the animation clock
        drain_feeds!(editor)         # the inbox first, then every registered feed
        run_frame!(editor)           # read!/evaluate! up to MAX_OPERATIONS_PER_FRAME, then print!
        perf!(editor)                # log reactive counters
        record_frame_performance!(editor, …)  # record this frame in editor.frame_measurements
    end
end
```

Between frames the editor sleeps in the backend's `wait_for_input`, and three
things end the sleep: an input event, a `wake_editor!` from any task, and the
timeout. The timeout is `FRAME_INTERVAL` while anything subscribes to the
editor's clock (an animation), else the nearest feed deadline or timer, else
`Inf`.

A timer is how a reader waits for a pattern that ends when no event arrives. The
reader answers `SetTimerOperation(name, time)`, the editor keeps the time under
the name in `editor.timers`, and a timer set again under the same name replaces
the one before. When the time comes, `read!` reads a `TimerExpire(name, time)`
before any device input. It is a bare event, because a timer belongs to no
window, and it leaves the timers when it is read. The reader checks its own state
when the event comes, so a timer that a newer event made stale needs no cancel.
The wake-pending flag starts set, so the first frame paints before the first
wait. A backend without a wait of its own sleeps one 10 ms poll slice per
call — the cadence this loop had when it slept — and that slice is also where
cooperative `@async` tasks on the thread get their turn.

`run_frame!` is what a burst of input runs through:

```julia
function run_frame!(editor)
    applied = nothing
    for _ in 1:MAX_OPERATIONS_PER_FRAME    # = 32
        read!(editor) || break             # poll devices → read_intent → editor.operation
        evaluate!(editor)                  # evaluate_operation(editor, editor.operation)
        applied = editor.operation
        editor.iomap === nothing && break  # a projection-invalidating op ends the frame early
    end
    editor.operation = applied
    print!(editor)                         # print_document → editor.iomap; render to devices
end
```

Input arrives faster than a frame can paint — a pointer in motion delivers a
`MouseMove` for as long as it moves — so `run_frame!` applies up to
`MAX_OPERATIONS_PER_FRAME` (32) operations before it repaints once, instead of
repainting after every single one. An operation that invalidates the cached
projection (a whole-root `ReplaceReferencedValueOperation` swap, say) ends the
frame early: `read!` has nothing to read the next event against until the
projection rebuilds, so remaining input waits for the next frame rather than
being discarded against a stale IoMap. Call `run_frame!` directly to drive an
editor one frame at a time — a test harness, an embedder, or a scripted
timeline that interleaves its own work between frames.

### The inbox

A frame reads the document, evaluates against it and paints it, so anything
that writes it from another task races the frame — and a computation of a cell can
not write at all. `post_operation!(editor, operation)` is the one door in:

```julia
post_operation!(editor, ReplaceSelectionOperation(path))   # from any task
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
cleanly. The MCP server is started when the loop starts, before the first
frame, and stopped in the `finally` block — see below.

#### A call on the editor task

A tool that an MCP client calls runs on the task of the server, and a turn of
the assistant streams on a task of its own. Both write what the frame shows, and
a tool call needs its answer back. `run_on_editor_task!(function_, editor)` is
their door:

```julia
text = run_on_editor_task!(() -> call_tool(editor.tools, name, args, editor), editor)
run_on_editor_task!(() -> push!(turn.parts, part), editor; wait = false)
```

1. The call posts a `RunFunctionOperation`, which holds the function and a
   channel for the answer.
2. The drain of the next frame runs the function on the editor task, and puts
   the value or the exception into the channel.
3. The calling task waits on the channel, and gets the value, or the exception
   thrown again. With `wait = false` the call only posts, and the posts of one
   task keep their order.

The function runs at once, on the calling task, when `editor.loop_task` is
`nothing` or is the calling task. So a test that drives frames by hand, and an
operation that the editor task evaluates, never wait for themselves. When the
loop ends, the calls still in the inbox run on the task that ran the loop, so no
caller waits forever. The kernel declares the function in the agent layer and
runs every target that is not an `Editor` at once; see [agent.md](agent.md).

The editor task runs no other frame while the function runs. So a tool that
runs for a second keeps the window from drawing for a second.

### The feeds

The inbox generalises to a **feed**: one registered inflow of the editor.
Every feed has the same three stations — a producer on any task writes the
feed's **store** without blocking; the store is a plain object, not a
document; and the **drain step** (`drain_changes!(feed, editor)`) moves what
is new into a target document, on the editor task, once per frame, before
`read!`. The target is a normal document, mounted in the shown tree by the
embedder, so a person opens views on it like on any document. The contract is
`FeedModule` (`Feed`, `drain_changes!`, `compute_wake_deadline`,
`attach_wake_callback!`); feeds are given at construction
(`Editor(...; feeds = Feed[…])`) and the list is fixed from then on.

A producer wakes the editor through `wake_editor!` — thread-safe, coalescing,
handed to each store as a callback at registration. A feed whose data arrives
only with frames (the frame statistics) never wakes; it answers a deadline
from `compute_wake_deadline` instead, and the wait honours the minimum.

The concrete feeds so far:

| feed | producer | store shape | target |
| --- | --- | --- | --- |
| `InboxFeed` (built-in, always first) | `post_operation!` and `run_on_editor_task!` callers | bounded queue, backpressure | the edited document |
| `MessageLogFeed` (`ProjecturedLog`) | any task that logs | ring buffer | the `MessageLog` |
| `FrameStatisticsFeed` (`ProjecturedStatistics`) | the loop itself | ring of the last 1000 frames | the `FrameStatistics` table and the `FramePlot` |
| `ReflectionFeed` (`ProjecturedReflection`) | the value, and a chevron that flags a marker | the value itself | the reflected tree of the value |

The fault store predates the feeds and stays what it is: `run_frame!` reports
it at its top, so a hand-driven frame collects its faults too; it joined only
the wake protocol (`attach_fault_wake!`). The whole rule is
`PAR-STORE-THEN-DRAIN` in
[architecture-invariants.md](../../rule/architecture-invariants.md).

### Read

`read!(editor)` pulls one gesture from `editor.recognizer`
(`pop_gesture!(editor.recognizer, () -> read_from_devices(editor.backend, editor.devices))`).
`read_from_devices(backend, devices)` polls the backend's event queue (in the
SDL case, `SDL_PollEvent`); the recognizer folds a `MouseDown`/`MouseUp` pair
into `MouseClick` and a `KeyDown` sequence into `KeyChord` before the frame
ever sees them, so a reader only ever has to match the folded gesture, not
reassemble it from raw events. The result is a `WindowInput` wrapping a
backend-agnostic event: `KeyDown`, `KeyUp`, `KeyPress`, `KeyChord`, `MouseDown`,
`MouseUp`, `MouseClick`, `MouseMove`, `MouseScroll`, or `WindowQuit`.

The window input is wrapped in an `Intent` and passed through
`read_intent(editor.projection, nothing, Intent(window_input, nothing), editor.iomap)`
— the entire pipeline walks backward, each projection contributing a translation
step until an `Operation` falls out at the document end.

Two gestures are recognized by the editor itself, *after* the pipeline has had
its chance, so a projection that explicitly binds one of these keys still wins:

- **Readability zoom** — `Ctrl` + `=`/`-`/`0` (optionally with `Shift`) zooms
  in, out, or resets; adding `Alt` scales the font only
  (`AdjustFontZoomOperation`) instead of the whole canvas
  (`AdjustZoomOperation`). Recognized regardless of what is selected.
- **Escape** closes the editor (`QuitEditorOperation`) — but only when no
  reader claimed it. A reader that binds Escape (a dialog, an insertion, the
  command palette) produces its own operation above and wins, so its Escape
  never reaches this fallback. This is why a backend must deliver Escape as an
  ordinary key rather than as a platform quit signal: a platform quit signal
  gives no reader the chance to intercept it.

### Evaluate

`evaluate_operation(editor, operation)` is a generic function with methods
defined per operation; methods reach for the document via `editor.document`. For
`ReplaceSelectionOperation` the implementation is
`replace_selection!(editor.document, op.path)` — see
[selection.md](selection.md#replacing-selection) for what that atomic,
in-place write does. For `QuitEditorOperation` it throws `QuitEditorException`.
Other operations (e.g. the generic `ReplaceReferencedValueOperation`, or
`ReplaceFocusPartOperation`) mutate the document or projection state directly.
See [the operations guide](operation.md).

### Print

If `editor.iomap` is `nothing`, `print_document(editor.projection,
editor.document)` runs the whole pipeline and stores the result. The IoMap
is then written to each output device with `write_to_devices(backend,
devices, iomap.output)`. Because every intermediate value is a reactive
`Cell`, subsequent reads only recompute the parts that were invalidated by
the operation — the rest is served from the cache.

The `iomap` is *not* invalidated at the end of a frame — its contents are
reactive and will refresh on the next read.

### An operation from a place, not a gesture

Code that is not the editor loop — a verb, a tool the assistant calls, a test —
can act at any place in the document, not only where the selection or the
pointer already is. `read_rooted_operation(editor, place, operation;
description = "")` reads `operation`, which is relative to the document that
`place` names, as an operation from the root of `editor`'s document: the
readers of `editor.projection` from the root to `place` lift it on the way out,
exactly as they lift the answer to a gesture, so a wrapper reroots it and a
sorted view maps an index back. `place` is a complete reference, from the
root. It evaluates nothing; a caller evaluates the answer with
`evaluate_operation` or posts it with `post_operation!`.

The route travels down in a fifth field of `Intent`, `route`: `nothing` for a
change that a gesture starts, and, for an operation that code already made,
the path from the current reader's input to `place`. A reader that passes the
`Intent` to a child gives it the route that remains below that child
(`follow_intent_route`) — it drops its own step, or, in a chain, maps the
route forward through the earlier stages, as the printer maps a reference.
Where the route that remains for a child is empty, that child is the place:
the parent does not call it, and takes `change.operation` as the child's
answer instead (`read_routed_intent` in
[ProjectionDefaults.jl](../../../source/kernel/projection/ProjectionDefaults.jl)).
On the way up, an answer carries no route, so the rest of the pipeline treats
it exactly as it treats the answer to a gesture.

The pane package's verbs (`focus_pane!`, `open_pane!`, `close_pane!`,
`duplicate_pane!`, `move_pane!`) use `read_rooted_operation` to carry their
edit from a pane tree to the root; see
[pane.md](../pane/pane.md#the-verbs-of-a-program).

## Running an editor

The entry point is the bootstrap overload
`run_editor!(backend, projection, document; mcp=false, mcp_instructions=nothing, mcp_host=nothing, mcp_port=nothing, devices=…, feeds=…, fault_policy=…)`:

```julia
using Projectured

backend  = SdlBackend()
document = JsonString("hello world")
proj     = ChainingProjection(
    JsonToSyntax(),
    SyntaxToText(),
    TextToGraphics(measure = FontFileMeasure()),
)

run_editor!(backend, proj, document)
```

The backend is pluggable: swap `SdlBackend()` for `WebBackend()` to run the same
editor in a browser instead of a native window (see the
[devices and backends guide](devices-and-backends.md#webbackend)), or
`ConsoleBackend()` for the terminal. Nothing else changes.

This overload is `make_editor(backend, projection, document; devices, feeds,
fault_policy)` and then `run_editor!(editor)`. `make_editor` calls
`initialize_backend!(backend)`, takes a `Vector{Device}` (default `Display()`,
`Keyboard()`, `Mouse()`), populates their physical properties from the backend
with `configure_devices!`, opens the native windows with `open_native_windows!`,
constructs the `Editor`, and prints it once. The windows
are opened before the first frame, and the document is corrected to the geometry
the window system granted: a manager may grant less than it is asked for, and it
answers only once the window exists, so a document projected first is projected
at a size the window never has and computes a second time when the answer
arrives. A window a projection opens later — a tooltip, a popup — is still
opened on demand, by `write_to_devices` against the `ScreenDocument` output (the
pipeline is expected to end in one).
`run_editor!(editor)` runs the loop, and calls `quit_backend!(editor.backend)` in
a `finally` block when the loop ends. `make_editor` quits the backend too when the
build or the print throws. Pass
`mcp=true` to start an MCP server alongside the loop, and `mcp_instructions` to
override the text the MCP server's `initialize` response sends a connecting
client (see [MCP server](#mcp-server)) — omitted, the server uses its own
default. `mcp_host` and `mcp_port` say where the server listens, and each one
that is omitted keeps the server's default, `127.0.0.1` and `9876`. A backend
that drives a different channel passes its own `devices` (the `ConsoleBackend`
uses `devices = Device[Keyboard()]` — no `Display`/`Mouse`).

A caller with work to do before the loop calls the two halves itself. It gets the
editor from `make_editor`, does its work, and then runs the loop:

```julia
editor = make_editor(backend, proj, document)
attach_fault_target!(editor.faults, log)   # hand the editor on
@async drive(editor)                       # a driver that posts its work
focus_pane!(editor, reference)             # an edit through the readers
run_editor!(editor)
```

The editor from `make_editor` has printed once, so `editor.iomap` exists, and an
edit that reads through the readers (`read_rooted_operation`, the pane verbs)
works before the loop. `make_editor` reads no input: only the loop reads the
backend. The screen package has the same pair for a window:
`make_editor(document, projection, title; backend, …)` and `run_window_editor`.

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
`LiveExample` in [the live-examples debugging section](../../guide/debugging-guide.md#live-examples-scripted-sessions-on-a-real-window).

## Devices and backends

- `Device` is an abstract type. Concrete subtypes are `Display`, `Keyboard`,
  and `Mouse` — see [the devices and backends guide](devices-and-backends.md).
- `Backend` is the abstraction over the display/input platform. There are two
  implementations: `SdlBackend` (graphics) and `ConsoleBackend` (terminal). The
  backend provides `initialize_backend!`, `quit_backend!`, and
  the per-frame device I/O `read_from_devices` / `write_to_devices`.
- Projections that need to measure text take a `measure::TextMeasure` argument
  (e.g. `TextToGraphics`); `FontFileMeasure()` of `ProjecturedStyle` is the
  usual injection, and every backend draws what it measures.
- The `ConsoleBackend` consumes the **TextBlock** domain directly (no
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

When `run_editor!` starts with `mcp=true`, it constructs an `McpServer` bound to
the editor when the loop starts, so the server serves the tools that a caller
registers between `make_editor` and `run_editor!`. It launches the server at `mcp_host` and `mcp_port`,
`http://127.0.0.1:9876/mcp` by default, via the `make_agent_server(:mcp, …)`
seam (see
[source/kernel/agent/AgentModule.jl](../../../source/kernel/agent/AgentModule.jl)). The server
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
of resending one large block. It returns what the code printed, then the value
of the last statement: whole when it is short, limited as the Julia REPL would
limit it otherwise, and trimmed to its start and its end with a note when even
that is long.

The server is stopped in the `finally` block of `run_editor!`.

## Performance counters

Each frame the editor binds a fresh counter store with `with_performance_counters()`
and calls `perf!()` after rendering, which logs

```
[perf] computes=… invalidations=… reads=… writes=… evaluate_time=…ms print_time=…ms read_time=…ms
```

when an operation was applied. Use these to find unintentional
recomputation: if a single keypress causes thousands of `computes`,
something is reading more cells than necessary.

The loop also records every frame in `editor.frame_measurements`: the frame time
always, and the counters above when they are compiled in. The store keeps the
last 1000 frames. The `FrameStatisticsFeed` shows their summaries as a table
(open a tab and type `statistics`) and their times as a plot (type
`frame plot`). `write_frame_measurements!("frames.csv", editor.frame_measurements)`
writes the frames as CSV.

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

The editor layer of the kernel is the **read-eval-print loop** described under
[The Read-Eval-Print loop](#the-read-eval-print-loop) above: it pulls together
every lower layer into the frame-by-frame drive — read from the device, evaluate
the gesture into an operation, apply the operation to the document, print the
document through the projection, tick the clock.

The layer lives in [source/kernel/editor/](../../../source/kernel/editor/):

```
EditorModule.jl    (EditorModule)    — the run_editor! loop and Editor struct
PlaybackModule.jl  (PlaybackModule)  — scripted live playback on a wall-clock timeline
```

The `GestureRecognizer` type that folds `MouseDown`/`MouseUp` into `MouseClick`
and `KeyDown` sequences into `KeyChord` lives in `gesture/` (its only
dependency is `EventModule`, no editor coupling); each `Editor` owns its own
instance in `editor.recognizer`. The animation `Clock` type lives in `clock/`
(every animated projection reads one, so the type belongs beside the engine it
depends on); each `Editor` likewise owns its own instance in `editor.clock`,
ticked once per frame with `set_clock_time!(editor.clock, Base.time() - t_start)`
— invalidating every cell that subscribed to `get_reactive_clock_time(editor.clock)`
— so two editors in the same process animate independently. What's left in
`editor/` is the loop itself and its scripted playback.

### Downward edges

- `..ProjectionModule` — `Projection`, `print_document`, `read_intent`,
  `Intent`, `IoMap`.
- `..DeviceModule` — `Device`, `Display`.
- `..BackendModule` — `Backend`, `initialize_backend!`, `quit_backend!`,
  `read_from_devices`, `write_to_devices`.
- `..EventModule` — `WindowInput`, `WindowQuit`, and the event type
  predicates (`KeyDown`, `MouseClick`, …).
- `..PerformanceModule` — the counters bumped inline in the loop.
- `..ClockModule` — `Clock`, `set_clock_time!`, `get_reactive_clock_time`.
- `..DocumentModule` — the abstract `Document` type.
- `..OperationModule` — the operation abstract + evaluate seam.
- `..GestureRecognizerModule` — the frame's gesture folding.
- `..ToolModule` — `ToolSet`, the `tools` field every `Editor` owns
  ([PAR-PER-EDITOR-STATE](../../rule/architecture-invariants.md#par-per-editor-state)).
- `..AgentModule` — the make_agent_server/start/stop seam driven by
  `Editor` when an agent server is configured.

That is nearly the full kernel — the editor is the layer that consumes
every other layer. Playback additionally depends on `EditorModule` (to
reuse the four sub-steps) and `OperationModule` (to preview
`reroot_operation` as scripted events replay).

### Testing

The per-layer editor test folder,
[test/kernel/editor/](../../../test/kernel/editor/), drives the loop against
the dependency-free `HeadlessBackend` from `ProjecturedKernelExample` — one
place the loop can be exercised without any real backend package. It covers
the printer/reader/REPL drivers and navigation (`PrinterTest.jl`,
`ReaderTest.jl`, `ReplTest.jl`, `NavigationTest.jl`, `ConstructTest.jl`), the
`Escape`-closes-unless-claimed rule (`EscapeQuitTest.jl`), the inbox
(`InboxTest.jl`), and the `run_frame!` multi-operation-per-frame batching
(`FrameDrainTest.jl`).
