# Editor

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

The editor ties everything together: it owns the document, the projection
pipeline, the backend, and the input devices, and runs a read-eval-print loop
that responds to user input. The implementation lives in the nine files of
[source/kernel/editor/](../../../source/kernel/editor/), and `run_editor!` of
[EditorLoop.jl](../../../source/kernel/editor/EditorLoop.jl) is the entry point.

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
    faults::FaultStore
    fault_policy::FaultPolicy
    replaced_projection::Union{Projection, Nothing}
    feeds::Vector{Feed}
    wake_pending::Threads.Atomic{Bool}
    frame_measurements::FrameMeasurementStore
    loop_task::Union{Task, Nothing}
    timers::Dict{Symbol, Float64}
    stop_steps::Vector{Any}
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
  in one process share neither a tool list nor an `execute_julia_code!`
  namespace — see [agent.md](agent.md)
- `inbox` — what was posted from outside the editor's own task; see
  [The inbox](#the-inbox)
- `iomap` — the most recent IoMap from `print_document`; needed by
  `read_intent` to translate the next event back to a domain operation
- `operation` — the most recent operation; used by `run_evaluate_stage!` and the
  per-frame log
- `faults` — the `FaultStore` of this editor: every barrier writes to it, and
  each frame drains it; see [fault.md](../platform/fault/fault.md)
- `fault_policy` — what the barriers do with a fault. Every form that makes an
  editor starts with `make_strict_fault_policy()`, a program that a person starts
  passes `FaultPolicy()`, and `run_editor!` keeps the policy of its editor
- `replaced_projection` — the projection that the safe mode put aside, or
  `nothing` while the editor is not in the safe mode
- `feeds` — the registered inflows, drained once per frame, with the built-in
  `InboxFeed` first; see [The feeds](#the-feeds)
- `wake_pending` — set by `wake_editor!` from any task; each frame takes every
  wake posted before it
- `frame_measurements` — the `FrameMeasurementStore` of the last frames; see
  [Performance counters](#performance-counters)
- `loop_task` — the task that runs `run_editor!`, or `nothing` while no loop
  runs; see [A call on the editor task](#a-call-on-the-editor-task)
- `timers` — the timers that readers set with `SetTimerOperation`: the time of
  each, by its name; see [The Read-Eval-Print loop](#the-read-eval-print-loop)
- `stop_steps` — the functions `editor -> nothing` that run when the loop of
  `run_editor!` ends, each in its own try, after the loop answers the calls
  still waiting in the inbox; see [Running an editor](#running-an-editor). A
  wrapper of `build_editor` that installs a start step, such as the capture of
  the logger, appends its matching stop step here, so the step that undoes it
  runs when the loop ends

## The Read-Eval-Print loop

`run_editor!(editor)` executes (the fault barriers around each stage elided):

```julia
# an editor with no IoMap prints first
editor.iomap === nothing && run_print_stage!(editor)
t_start = time_ns()                          # the monotonic clock
while true
    # A pending wake skips the wait; else animation, feed deadlines, timers, else Inf.
    timeout = editor.wake_pending[] ? 0.0 : compute_wait_timeout(editor)
    if timeout > 0
        wait_for_input(editor.backend, editor.devices, timeout)
    else
        yield()                      # the turn of the other tasks of this thread
    end
    Threads.atomic_xchg!(editor.wake_pending, false) # this frame owns every wake so far
    run_with_performance_counters() do   # bind a fresh per-frame counter store
        wall_time = (time_ns() - t_start) / 1e9
        set_clock_time!(editor.clock, get_frame_clock_time(editor.backend, wall_time))
        drain_feeds!(editor)         # the inbox first, then every registered feed
        run_frame!(editor)           # run_read_stage!/run_evaluate_stage! up to MAX_OPERATIONS_PER_FRAME, then run_print_stage!
        _log_performance_counters!(editor)                # log reactive counters
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
the one before. When the time comes, `run_read_stage!` reads a `TimerExpire(name, time)`
before any device input. It is a bare event, because a timer belongs to no
window, and it leaves the timers when it is read. The reader checks its own state
when the event comes, so a timer that a newer event made stale needs no cancel.

A frame that changed what the display shows is followed by one more read. A
backend that shows windows reports such a frame as
`WindowInput(window_id, DisplayUpdate(; time))`, and its wait does not block
while one waits. A reader that keeps a part of the view as its state can find
it again then, because the view can change under a pointer that does not move. The
loop sleeps only after a frame that changed nothing. A feed that writes because
a frame happened, such as the frame statistics or a reflected value, writes at
most once per interval, so that the frames do not feed themselves.
The wake-pending flag starts set, so the first frame paints before the first
wait. A backend without a wait of its own sleeps one 10 ms poll slice per
call, and that slice is also where cooperative `@async` tasks on the thread get
their turn. A frame that does not wait yields once for the same reason.

`run_frame!` is what a burst of input runs through:

```julia
function run_frame!(editor)
    report_frame_faults!(editor)           # the faults of the last frame, before any read
    applied = nothing
    is_input_left = true
    for _ in 1:MAX_OPERATIONS_PER_FRAME    # = 32
        # poll devices → read_intent → editor.operation
        if !run_read_stage!(editor)
            is_input_left = false
            break
        end
        run_evaluate_stage!(editor)  # evaluate_operation(editor, editor.operation)
        applied = editor.operation
        editor.iomap === nothing && break  # a projection-invalidating op ends the frame early
    end
    is_input_left && (editor.wake_pending[] = true)  # the next frame does not wait
    editor.operation = applied
    run_print_stage!(editor)                         # print_document → editor.iomap; render to devices
    # then the safe mode, when the print failed in too many frames in a row
end
```

Input arrives faster than a frame can paint — a pointer in motion delivers a
`MouseMove` for as long as it moves — so `run_frame!` applies up to
`MAX_OPERATIONS_PER_FRAME` (32) operations before it repaints once, instead of
repainting after every single one. An operation that invalidates the cached
projection (a whole-root `ReplaceReferencedValueOperation` swap, say) ends the
frame early: `run_read_stage!` has nothing to read the next event against until the
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
frame, before `run_read_stage!` — so the frame paints what it just applied. This is what
anything with a loop of its own uses to reach the editor: a driver advancing a
simulation, a file watcher, an agent, a timer.

The channel is bounded (`INBOX_CAPACITY`), so a producer faster than the editor
waits rather than queueing work that will be stale before it is applied.

Posted operations go through `evaluate_operation` and not `run_evaluate_stage!`, so they
do not become `editor.operation` — that field means "what the reader made of
this frame's input", which is what `_log_performance_counters!` uses to tell a frame the user acted
in from an idle one, and what `run_evaluate_stage!` writes to the operation log.

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
`run_read_stage!`. The target is a normal document, mounted in the shown tree by the
embedder, so a person opens views on it like on any document. The contract is
`FeedModule` (`Feed`, `drain_changes!`, `compute_wake_deadline`,
`attach_wake_callback!`); feeds are given at construction
(`Editor(...; feeds = Feed[…])`) and the list is fixed from then on.

A producer wakes the editor through `wake_editor!` — thread-safe, coalescing,
handed to each store as a callback at registration. A feed whose data arrives
only with frames (the frame statistics) never wakes; it answers a deadline
from `compute_wake_deadline` instead, and the wait honours the minimum.

The concrete feeds:

| feed | producer | store shape | target |
| --- | --- | --- | --- |
| `InboxFeed` (built-in, always first) | `post_operation!` and `run_on_editor_task!` callers | bounded queue, backpressure | the edited document |
| `MessageLogFeed` (the log slice) | any task that logs | ring buffer | the `MessageLog` |
| `FrameStatisticsFeed` (the statistics slice) | the loop itself | ring of the last 1000 frames | the `FrameStatistics` table and the `FrameTimeSeries` |
| `ReflectionFeed` (the reflection slice) | the value, and a chevron that flags a marker | the value itself | the reflected tree of the value |
| `TooltipFeed` (the tooltip slice) | the probe of a window, on each pointer event | the place and the time of the last move | the inbox: at its deadline it posts the operation that the projection answers for a `PointerRest` |

The fault store is not a feed: `run_frame!` reports it at its top, so a
hand-driven frame collects its faults too. It uses only the wake protocol of the
feeds (`attach_fault_wake!`). The whole rule is
`PAR-STORE-THEN-DRAIN` in
[architecture-invariants.md](../../rule/architecture-invariants.md).

### Read

`run_read_stage!(editor)` drains input until one translates into an operation. A timer
of `editor.timers` whose time has come is read first, as a bare `TimerExpire`,
because a timer belongs to no window. Otherwise `take_from_devices!(backend,
devices)` polls the backend's event queue (in the SDL case, `SDL_PollEvent`)
for a `WindowInput` wrapping a backend-agnostic event: `KeyDown`, `KeyUp`,
`KeyPress`, `MouseDown`, `MouseUp`, `MouseMove`, `MouseScroll`, `WindowQuit`,
`WindowClose`, `WindowResize`, `WindowDefocus` or `WindowLeave`. The editor
recognizes no gesture: a projection runs the recognitions of the gesture layer,
such as the gesture tracking projection that the screen package puts around the
screen; see [gesturetracking.md](../platform/gesturetracking/gesturetracking.md).

The window input is wrapped in an `Intent` and passed through
`read_intent(editor.projection, nothing, Intent(window_input, nothing), editor.iomap)`
— the entire pipeline walks backward, each projection contributing a translation
step until an `Operation` falls out at the document end.

One gesture is recognized by the editor itself, *after* the pipeline has had
its chance, so a projection that explicitly binds it still wins:

- **Escape** closes the editor (`QuitEditorOperation`) — but only when no
  reader claimed it. A reader that binds Escape (a dialog, an insertion, the
  command palette) produces its own operation above and wins, so its Escape
  never reaches this fallback. This is why a backend must deliver Escape as an
  ordinary key rather than as a platform quit signal: a platform quit signal
  gives no reader the chance to intercept it.

The zoom and the scales are not a gesture of the editor itself: `AdjustZoomOperation`
and `AdjustScaleOperation`, and the keys that reach them, are bindings of the
`appearance` wrapper of `build_editor` (`AppearanceDocument`). An editor built
without that wrapper has no zoom keys.

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
is then written to each output device with `write_to_devices!(backend,
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
route forward through the earlier stages, as the printer maps a reference. A
gesture with a route goes on into a stage that shows the place as something
else, as far as the forward maps answer, and the deepest stage reads it first
([higher-order-projections.md](../platform/projection/higher-order-projections.md)).
Where the route that remains for a child is empty, that child is the place:
the parent does not call it, and takes `change.operation` as the child's
answer instead (`read_routed_intent` in
[ProjectionDefaults.jl](../../../source/kernel/projection/ProjectionDefaults.jl)).
On the way up, an answer carries no route, so the rest of the pipeline treats
it exactly as it treats the answer to a gesture.

A container needs no code for a route. The kernel's default reader walks the
route into the child that it names, when the IoMap of the container holds its
children: `get_child_iomaps(iomap)` names them (a `ChildrenIoMap`, a
`ContentIoMap`, and each package's own container IoMaps), and
`read_routed_child` reads the route one step at a time from the input of the
container until the node it reaches is the input of a child. A container can
hold a child through a node that has no IoMap of its own, so the walk goes on
until it reaches one. A route that reaches no child answers no operation.

A route can carry a gesture too, for one part: a tracker sends a leave to the
part that the pointer left, which is no longer under the pointer. The gesture
is then the gesture, and the operation is `nothing`. The containers pass it on
by the route and never by the position that it holds. Where the route is empty,
the child is the part, and it reads the gesture; a reader that holds no children
reads it with the rest of the route as the part. A gesture whose route ends at
a container gets no answer, unless the container has a reader of its own for
it.

The pane package's verbs (`focus_pane!`, `open_pane!`, `close_pane!`,
`duplicate_pane!`, `move_pane!`) use `read_rooted_operation` to carry their
edit from a pane tree to the root; see
[pane.md](../platform/pane/pane.md#the-verbs-of-a-program).

## The timer and the display event

A reader that waits for a pattern with no event of its own, such as a pointer
that stops moving, uses a timer. It answers `SetTimerOperation(name, time)`,
and the loop reads a bare `TimerExpire(name, time)` when that time comes,
before any device input (see [the loop above](#the-read-eval-print-loop)). A
timer set again under the same name replaces the one before, so a reader that
renews it on every event gets one `TimerExpire`, after the last one, and a
`TimerExpire` of a name that a newer event made stale matches nothing in the
reader that set it.

`DwellRecognition` of the gesture layer is the one case the kernel's default
recognitions build on this: a motion with no button held answers a deadline,
the loop turns it into a timer under the name of the recognition, and the
`TimerExpire` at that deadline goes back to `DwellRecognition` alone, which
turns it into a `MouseDwell`. See
[gesture.md](gesture.md#the-three-recognitions).

`DisplayUpdate(; time)` is the event of a display that shows a frame
different from the one before. A backend reports it, wrapped in a
`WindowInput` of the window that changed, after it draws that frame, and no
other code makes one. `run_read_stage!` reads it as it reads any other input, but no
reader has a pattern for it, so it answers no operation and the read moves on
to whatever is queued behind it, such as the move described in
[mouse-target.md](mouse-target.md#a-view-that-changes-under-a-still-pointer).
Its purpose is only to run the loop again right away instead of waiting: the
backend's own wait does not block while a `DisplayUpdate` is queued, as
[the loop above](#the-read-eval-print-loop) describes, so a frame that changed
a window is always followed by one more read before the loop sleeps.

## Running an editor

Four functions make an editor, and they differ in what they decide for the
caller:

- `make_editor(document, projection; backend, devices, feeds, fault_policy)`
  decides nothing. The caller names the backend, and no wrapper is applied. A
  test and a program that wants exact control call it.
- `make_editor_parts(document, projection; backend = nothing, feeds = Feed[],
  wrappers...)` applies the wrappers and makes no editor: it is steps 2 and 3
  of `build_editor` alone. A caller that draws the parts itself, such as a
  test or a warm-up that prints a window scene of its own, takes the document
  and the projection that the wrappers made from the answered `EditorParts`.
  With no `backend`, a wrapper that needs one, such as the window, does
  nothing. Nothing runs the start steps or the stop steps of the parts.
- `build_editor(document, projection; backend = nothing, devices, feeds,
  fault_policy, wrappers...)` chooses the backend when none is given, makes
  the parts with `make_editor_parts`, calls `make_editor`, appends the stop
  steps of the parts to `editor.stop_steps`, and runs the start steps.
  `build_editor(document; ...)` takes the projection from
  `make_document_projection(document; arguments...)`.
- `run_editor!(document, projection; wait = true, mcp = false, keywords...)` and
  `run_editor!(document; ...)` are `build_editor` and then the loop. With
  `wait = false` the call returns the editor at once, and the editor is built
  and runs on a task pinned to another thread of the default pool, because a
  backend such as SDL answers only the thread that started it. The task is
  `editor.loop_task` until the loop ends.
- `run_editor!(make::Function; wait = true, mcp = false)` is the loop of the
  editor that `make()` answers. It is for a caller whose work before the loop
  must run on the task of the loop, such as a window that declares its tools and
  opens its panes: `make` builds the editor, does that work and answers the
  editor. With `wait = false` the task of the loop calls `make`, and the call
  returns the editor once `make` returns.

The raw constructor has the same shape:
`Editor(document, projection; backend, devices, clock, tools, faults,
fault_policy, feeds)`. It builds the state and does nothing else: it starts no
backend and prints nothing, and its fault policy is strict.

```julia
using Projectured, ProjecturedPlatform, ProjecturedWeb, ProjecturedJSON

document = JsonString("hello world")
projection = ChainingProjection(
    JsonToSyntax(),
    SyntaxToText(),
    TextToGraphics(measure = FontFileMeasure()),
)

run_editor!(document, projection)                          # the one loaded backend
run_editor!(document, projection; backend = WebBackend())  # a browser
```

**The choice of the backend.** A backend package declares its type with two
seams: `get_backend_name(::Type{SdlBackend}) = :sdl`, and
`get_backend_output(::Type{SdlBackend}) = :windows`. With no `backend`,
`make_default_backend(:windows)` takes the one loaded type that draws windows.
With none, or with more than one, it raises an error that names the loaded
backends, because an order of preference would change the backend of a program
when one more package is loaded. A backend with no method of
`get_backend_output`, such as a recorder or a test double, is never chosen.

**The wrappers.** A wrapper is a keyword of `build_editor`, such as
`dragging = true`. A package declares it with methods for `Val{keyword}`:

| Seam | What it answers |
|---|---|
| `wrap_editor!(::Val{k}, layer, argument, parts::EditorParts)` | changes the document, the projection, the feeds, the start steps and the stop steps of the editor that is made, and can give the `window` wrapper a function for `EditorParts.window_wrappers`, which it puts around the screen inside the trackers, as the `tooltip` and `context_menu` wrappers do |
| `get_wrapper_layers(::Val{k})` | the layers it acts in, each with a number that orders it in the layer, as `(:document => 70,)` |
| `get_excluded_wrappers(::Val{k})` | the keywords that can not be on with it; none by default |
| `is_wrapper_default(::Val{k})` | whether it is on when the caller does not name it; off by default |
| `make_wrapper_argument(::Val{k}, argument)` | the argument as the wrapper uses it, made from the value of the keyword before anything of the editor is built; by default the value as it is |

`build_editor` makes every argument first, and `EditorParts.arguments` holds them
all, so a wrapper can read the argument of another wrapper; the kernel never reads
them. With no projection named, `make_document_projection(document; arguments...)`
gets the same arguments, so the projection and a wrapper can share an object, such
as the `Appearance` of the `appearance` wrapper. The layers are `:document`,
`:container`, `:window` and `:screen`, from the
inside out. The value of a keyword is the argument of its wrapper: `true` for the
defaults, a `NamedTuple` of options, or `false` to turn off a wrapper that is on by
default. A keyword that no loaded package declares is an error when it is on,
and is ignored when it is off.

`make_editor` calls `initialize_backend!(backend)`, takes a `Vector{Device}`
(default `Display()`, `Keyboard()`, `Mouse()`), populates their physical
properties from the backend with `configure_devices!`, opens the native windows
with `open_native_windows!`, constructs the `Editor`, and prints it once. The
windows are opened before the first frame, and the document is corrected to the
geometry the window system granted: a manager may grant less than it is asked
for, and it answers only once the window exists, so a document projected first
is projected at a size the window never has and computes a second time when the
answer arrives. A window a projection opens later — a tooltip, a popup — is
still opened on demand, by `write_to_devices!` against the `ScreenDocument`
output (the pipeline is expected to end in one).
`run_editor!(editor)` runs the loop, and in a `finally` block when the loop ends
answers every call still waiting in the inbox, runs the stop steps of
`editor.stop_steps`, each in its own try so one that throws does not stop the
steps after it, and calls `quit_backend!(editor.backend)`. The first exception
among the loop and these steps goes on to the caller. `make_editor` quits the
backend too when the build or the print throws. Pass `mcp = true` to `run_editor!(editor)` to start
an MCP server alongside the loop. The value can also be a `NamedTuple`:
`instructions` overrides the text the MCP server's `initialize` response sends a
connecting client (see [MCP server](#mcp-server)), and `host` and `port` say
where the server listens. A field that is left out keeps the server's default:
its own text, `127.0.0.1` and `9876`. A backend that
drives a different channel passes its own `devices` (the `ConsoleBackend` uses
`devices = Device[Keyboard()]` — no `Display`/`Mouse`).

A caller with work to do before the loop calls the two halves itself. It gets the
editor from `make_editor` or `build_editor`, does its work, and then runs the
loop:

```julia
editor = make_editor(document, projection; backend)
attach_fault_target!(editor.faults, log)   # hand the editor on
@async drive(editor)                       # a driver that posts its work
focus_pane!(reference; editor)             # an edit through the readers
run_editor!(editor)
```

The editor from `make_editor` has printed once, so `editor.iomap` exists, and an
edit that reads through the readers (`read_rooted_operation`, the pane verbs)
works before the loop. `make_editor` reads no input: only the loop reads the
backend. The `window` wrapper of the screen package puts the document in one
window when the backend draws windows, and `window = (; title, width, height)`
gives it a title and a size.

## Scripted live playback

`play_live!` is a sibling entry point that runs the same read-eval-print loop
but **fires a predefined timeline on a wall-clock schedule**, so a recorded
session plays out on a real window while the user watches (and can still
interact — real input is polled every frame, and Escape / window-close quits).

```julia
play_live!(document, projection, timeline; backend,
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
- `Backend` is the abstraction over the display/input platform. There are four
  implementations: `SdlBackend` (native windows), `WebBackend` (a browser page),
  `ConsoleBackend` (a terminal) and `VideoBackend` (the frames of a video file),
  and the test double `HeadlessBackend`. The backend provides
  `initialize_backend!`, `quit_backend!`, the per-frame device I/O
  `take_from_devices!` / `write_to_devices!`, and the wait between frames
  `wait_for_input` / `wake_backend!` — see
  [the devices and backends guide](devices-and-backends.md#backends).
- Projections that need to measure text take a `measure::TextMeasure` argument
  (e.g. `TextToGraphics`); `FontFileMeasure()` of the style slice is the
  usual injection, and every backend draws what it measures.
- The `ConsoleBackend` consumes the **TextBlock** domain directly (no
  `TextToGraphics`): its `write_to_devices!` renders a `TextBlock` to the terminal
  with ANSI colors, the selection encoded as inverse-video span colors by a
  `SelectionInverting` projection at the end of the pipeline, and
  `take_from_devices!` turns keystrokes into the same `KeyDown`/`KeyPress`/
  `WindowQuit` events. Because it has no screen/window layer, its pipeline adds an
  `WindowInputUnwrappingProjection` to strip the `WindowInput` that
  `ScreenToScreen` would otherwise strip. Run it with
  `run_console_example()` / `run_console_example(interactive=true)`. See
  [the devices and backends guide](devices-and-backends.md#consolebackend).

## MCP server

When `run_editor!` starts with `mcp=true`, it constructs an `McpServer` bound to
the editor when the loop starts, so the server serves the tools that a caller
registers between `make_editor` and `run_editor!`. It launches the server at the `host` and `port` of the argument,
`http://127.0.0.1:9876/mcp` by default, via the `make_agent_server(:mcp, …)`
seam (see
[source/kernel/agent/AgentInterface.jl](../../../source/kernel/agent/AgentInterface.jl)). The server
speaks JSON-RPC 2.0 via HTTP+SSE using
[ModelContextProtocol.jl](https://github.com/projectured/ModelContextProtocol.jl), a fork of the
package of JuliaSMLM.

Tools exposed by the server include `execute_julia_code` (run arbitrary
Julia in the editor process with `editor` bound and every loaded ProjecturEd
package imported), plus resource listings for guides, modules, classes, and
function documentation. The intent is that an AI assistant can inspect and
manipulate `editor.document` and `editor.projection` live.

`execute_julia_code!` runs each top-level statement in a **persistent scratch
module**, so a variable assigned in one call (`paths = search_references(…)`)
stays bound for the next — the caller can build up state incrementally instead
of resending one large block. It returns what the code printed, then the value
of the last statement: whole when it is short, limited as the Julia REPL would
limit it otherwise, and trimmed to its start and its end with a note when even
that is long.

The server is stopped in the `finally` block of `run_editor!`.

## Performance counters

Each frame the editor binds a fresh counter store with `run_with_performance_counters()`
and calls `_log_performance_counters!()` after rendering, which logs

```
[perf] computes=… invalidations=… reads=… writes=… evaluate_time=…ms print_time=…ms read_time=…ms
```

when an operation was applied. Use these to find unintentional
recomputation: if a single keypress causes thousands of `computes`,
something is reading more cells than necessary.

The loop also records every frame in `editor.frame_measurements`: the frame time
always, and the counters above when they are compiled in. The store keeps the
last 1000 frames. The `FrameStatisticsFeed` shows their summaries as a table
(open a tab and type `statistics`) and their times as a chart (type
`frame times`). `write_frame_measurements!("frames.csv", editor.frame_measurements)`
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
EditorModule.jl        (EditorModule) — the module: its docstring, imports, exports and fragments
    ├─ Editor.jl            — Editor, its constructor, the invalidation of its projection,
    │                         the editor as the start of a reference, and its fault store
    ├─ Inbox.jl             — post_operation!, wake_editor!, drain_operations!, and the
    │                         calls that another task runs on the editor task
    ├─ Feeds.jl             — InboxFeed, the timeout of the wait, the frame
    │                         measurements, and drain_feeds!
    ├─ ReadEvaluatePrint.jl — run_read_stage!, run_evaluate_stage!,
    │                         run_print_stage! and read_rooted_operation
    ├─ DocumentEdits.jl     — find_rooted_operation, insert_elements! and delete_elements!
    ├─ SafeMode.jl          — the safe mode, which shows the fault list in place of a
    │                         projection that fails
    ├─ FaultBarriers.jl     — the barrier of each stage, the report of the faults of a
    │                         frame, the limits of the fault counts, and the repairs
    └─ EditorLoop.jl        — _log_performance_counters!, run_frame!, get_frame_clock_time, run_editor! and
                              make_editor
```

Scripted playback is a layer of its own, above this one, in `playback/`.

The editor holds no gesture recognizer: the recognitions of the gesture layer
run in a projection, such as the gesture tracking projection. The animation
`Clock` type lives in `clock/` (every animated projection reads one, so the type
belongs beside the engine it depends on); each `Editor` likewise owns its own
instance in `editor.clock`, ticked once per frame with
`set_clock_time!(editor.clock, get_frame_clock_time(editor.backend, wall_time))`
— invalidating every cell that subscribed to `get_reactive_clock_time(editor.clock)`
— so two editors in the same process animate independently. What's left in
`editor/` is the loop itself.

### Downward edges

- `..ProjectionModule` — `Projection`, `print_document`, `read_intent`,
  `PrinterContext`.
- `..IntentModule` — `Intent`, the unit that `run_read_stage!` passes to the readers.
- `..IoMapModule` — `IoMap`, the type of `editor.iomap`.
- `..DeviceModule` — `Device`, `Display`.
- `..BackendModule` — `Backend`, `initialize_backend!`, `quit_backend!`,
  `take_from_devices!`, `write_to_devices!`.
- `..EventModule` — `WindowInput`, `WindowQuit`, and the event type
  predicates (`KeyDown`, `MouseDown`, …).
- `..PerformanceModule` — the counters bumped inline in the loop.
- `..ClockModule` — `Clock`, `set_clock_time!`, `get_reactive_clock_time`.
- `..DocumentModule` — the abstract `Document` type.
- `..ReferenceModule` — `Reference` and `DocumentLocator`, so a reference can
  start at an editor.
- `..SelectionModule` — `get_selection`, which a repair after a failed
  operation reads.
- `..CellModule` — `has_dependent_cells`, which says whether anything animates.
- `..OperationModule` — the operation abstract + evaluate seam.
- `..FaultModule` — the store, the policy, the barrier and the report of a
  fault.
- `..FeedModule` — `Feed` and its three generics, which the loop drives once per
  frame.
- `..ToolModule` — `ToolSet`, the `tools` field every `Editor` owns
  ([PAR-PER-EDITOR-STATE](../../rule/architecture-invariants.md#par-per-editor-state)).
- `..AgentModule` — the make_agent_server/start/stop seam driven by
  `Editor` when an agent server is configured, and `run_on_editor_task!`, which
  the editor layer answers for an `Editor`.

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
(`InboxTest.jl`), the wait between frames (`WaitTest.jl`), the feeds and the
frame measurements (`FeedsTest.jl`), the fault barriers of the loop
(`FaultBarriersTest.jl`), the edits through the readers (`DocumentEditsTest.jl`),
and the `run_frame!` multi-operation-per-frame batching (`FrameDrainTest.jl`).
The safe mode needs the fault view, so its test is in the suite of
the fault slice, in
[test/platform/fault/FaultSafeModeTest.jl](../../../test/platform/fault/FaultSafeModeTest.jl).
