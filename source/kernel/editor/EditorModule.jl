"""
    EditorModule

The generalised Read-Eval-Print loop. Each frame: poll input via the
backend, call read! to produce a domain operation, apply the operation
to the document via evaluate!, call print! and render the updated canvas.
The latest IoMap is retained between frames so the reader has access to
the current coordinate mapping.
"""
module EditorModule

using ..ProjectionModule
using ..IntentModule
using ..IoMapModule
using ..DeviceModule
using ..BackendModule
using ..EventModule
using ..PerformanceCounterModule
using ..ClockModule
using ..DocumentModule
using ..OperationModule
using ..GestureRecognizerModule
using ..ToolModule
using ..AgentServerModule
using ..FaultModule
using ..SelectionModule
using ..ReferenceModule
using ..CellModule
using ..FeedModule
import ..FeedModule: drain_changes!

export Editor, run_editor!, read!, evaluate!, print!, run_frame!,
       post_operation!, drain_operations!, is_editor_degraded,
       is_editor_in_safe_mode, enter_safe_mode!, leave_safe_mode!,
       report_frame_faults!,
       InboxFeed, wake_editor!, drain_feeds!

"""
    Editor(backend, document, projection, devices;
           clock = Clock(), tools = ToolSet(), feeds = Feed[])

Holds the state for a read-eval-print loop:
  - `backend`    — the display/input backend (e.g. SdlBackend)
  - `document`   — the reactive document being edited
  - `projection` — the projection (or a chaining projection)
  - `devices`    — input/output devices (e.g. window, keyboard)
  - `clock`      — this editor's private animation clock (fresh `Clock()` by
                   default); `run_editor!` ticks it once per frame from OS
                   time so subscribers reanimate, independently of any other
                   editor running in the same process.
  - `tools`      — what *this* editor exposes to an agent: the `ToolSet` an agent
                   loop drives and an MCP server publishes. Empty by default;
                   `register_default_tools!(editor.tools)` fills it with the
                   built-ins on first use. Per editor, so two editors in one
                   process neither share a tool list nor evaluate code into each
                   other's namespace.
  - `inbox`      — operations posted from outside this editor's task; drained and
                   applied once per frame by `run_editor!`. See
                   [`post_operation!`](@ref).
  - `iomap`      — the latest IoMap from the printer (internal)
  - `operation`  — the latest operation from the reader (internal)
  - `recognizer` — the event → gesture recogniser (internal)
  - `faults`     — the per-editor `FaultStore` every barrier writes to, and the
                   frame drains once. Per editor, so two editors in one process
                   never read each other's faults.
  - `fault_policy` — what this editor does with a fault. **It starts strict: a
                   barrier catches nothing.** A programmatic editor — every one
                   a test builds — therefore behaves exactly as it does without
                   this feature, and a broken projection fails its test rather
                   than passing quietly. [`run_editor!`](@ref) is what turns the
                   barriers on, because a loop a person is sitting in front of
                   is the thing that must survive.
  - `replaced_projection` — the projection the safe mode put aside, or
                   `nothing` when the editor is not in the safe mode.
  - `feeds`      — the registered inflows, drained once per frame by
                   [`drain_feeds!`](@ref). The built-in [`InboxFeed`](@ref) is
                   always first; the rest is given at construction and fixed
                   from then on.
  - `wake_pending` — set by [`wake_editor!`](@ref) from any task; each frame
                   takes ownership of every wake posted before it (internal).
"""
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
    faults::FaultStore
    fault_policy::FaultPolicy
    replaced_projection::Union{Projection, Nothing}
    feeds::Vector{Feed}
    wake_pending::Threads.Atomic{Bool}
end

# The inbox is bounded: a producer that outruns the editor should wait for it,
# not build a queue of syncs that are stale by the time they are applied.
const INBOX_CAPACITY = 64

function Editor(backend, document, projection, devices;
                clock::Clock = Clock(), tools::ToolSet = ToolSet(),
                faults::FaultStore = FaultStore(),
                fault_policy::FaultPolicy = make_strict_fault_policy(),
                feeds::Vector{Feed} = Feed[])
    editor = Editor(backend, document, projection, devices, clock, tools,
                    Channel{Operation}(INBOX_CAPACITY),
                    nothing, nothing, GestureRecognizer(), faults, fault_policy, nothing,
                    Feed[InboxFeed(); feeds], Threads.Atomic{Bool}(false))
    # Registration is the one moment a feed meets its editor. The callback is
    # the only handle a producer-side store gets: a store lives below the
    # editor layer and must not name `Editor`.
    wake = () -> wake_editor!(editor)
    for feed in editor.feeds
        attach_wake_callback!(feed, wake)
    end
    # The fault store wakes the same way: a fault recorded while the editor
    # sleeps — or during the frame, from inside a thunk — reaches the log on
    # the very next frame rather than on the next unrelated event.
    attach_fault_wake!(faults, wake)
    editor
end

# Drop the cached IoMap so the next `print!` rebuilds the projection from scratch.
# `invalidate_projection!` is a no-op for an object that caches nothing; this method
# is what an operation like a whole-root `ReplaceReferencedValueOperation` swap
# actually reaches when it runs against a real `Editor`.
OperationModule.invalidate_projection!(editor::Editor) = (editor.iomap = nothing)

# ── The inbox ─────────────────────────────────────────────────────────
#
# The one door into a running editor from outside its own task. A frame reads the
# document, evaluates against it and paints it, so anything that writes it from
# another task races the frame — and a reactive thunk cannot write at all
# (PAR-NO-WRITE-IN-THUNK). An operation posted here is applied by the editor's own
# task at a defined point in the frame, which is the same guarantee an operation
# from the reader already has.

"""
    post_operation!(editor, operation) -> operation

Hand `editor` an operation to apply on its next frame. Thread-safe, and the only
supported way for anything outside the editor's task — a driver advancing a
simulation, a file watcher, an agent, a timer — to change what it shows.

Blocks once `INBOX_CAPACITY` operations are waiting, so a producer faster than
the editor is slowed down rather than allowed to queue work that will be stale
before it is applied.

Wakes the editor after the `put!`, so a posted operation is applied on the
next frame rather than on the next tick of a timer.
"""
post_operation!(editor::Editor, operation::Operation) =
    (put!(editor.inbox, operation); wake_editor!(editor); operation)

"""
    wake_editor!(editor) -> Nothing

Ask `editor` to run a frame now. Thread-safe, non-blocking and coalescing:
any number of calls before the next frame cost one frame, because the frame
takes the whole flag at once. [`post_operation!`](@ref) calls it after
`put!`; a feed's producer-side store calls it through the callback
[`attach_wake_callback!`](@ref) gave it.

The flag is the truth and the backend wake is only the kick that ends a wait
in progress. Only the false-to-true transition kicks, so the backend holds at
most one pending wake however often producers call this. A kick a frame
happens to consume costs nothing: the flag still skips the next wait.
"""
function wake_editor!(editor::Editor)
    Threads.atomic_xchg!(editor.wake_pending, true) && return nothing
    wake_backend!(editor.backend)
    nothing
end

"""
    drain_operations!(editor) -> Int

Apply every operation waiting in the inbox and answer how many there were.
Called once per frame by `run_editor!`, before `read!`, so the frame paints what
it just applied.

Applied through `evaluate_operation` rather than [`evaluate!`](@ref): posted
operations do not become `editor.operation`, because that field means "what the
reader made of this frame's input" and is what `perf!` uses to tell a frame in
which the user did something from an idle one. It also keeps a sync arriving ten
times a second out of the operation log.
"""
function drain_operations!(editor::Editor)
    count = 0
    while isready(editor.inbox)
        evaluate_operation(editor, take!(editor.inbox))
        count += 1
    end
    count
end

# ── The feeds ─────────────────────────────────────────────────────────
#
# The generalisation of the inbox: every registered inflow of this editor,
# drained at the same point of the frame the inbox is. The contract lives in
# `FeedModule`; the inbox is the one feed the editor always has.

"""
    InboxFeed

The built-in queue feed over `editor.inbox`. Always first in `editor.feeds`,
so a posted operation applies before any other feed writes its target
document.
"""
struct InboxFeed <: Feed end

drain_changes!(::InboxFeed, editor::Editor) = drain_operations!(editor)

# How long the editor may sleep while something subscribes to its clock. One
# tick per sleep, so an animation advances at the cadence the polling loop
# had. With no subscriber the clock does not tick and the editor sleeps to
# the nearest feed deadline, or forever.
const FRAME_INTERVAL = 0.01

"""
    compute_wait_timeout(editor) -> Float64

How long the next wait may block: `FRAME_INTERVAL` while anything subscribes
to the editor's clock, bounded further by every feed's
`compute_wake_deadline`, and `Inf` when nothing asks to come back. A stale
subscriber the collector has not swept yet keeps the animation bound for a
few more frames; each of them drains nothing and repaints nothing.
"""
function compute_wait_timeout(editor::Editor)
    timeout = has_dependents(getfield(editor.clock, :time)) ? FRAME_INTERVAL : Inf
    for feed in editor.feeds
        deadline = compute_wake_deadline(feed)
        deadline === nothing && continue
        deadline < timeout && (timeout = deadline)
    end
    timeout
end

"""
    drain_feeds!(editor) -> Int

Drain every registered feed, in registration order, and answer how many
items moved in total. Runs once per frame on the editor task, inside the
`:evaluate` barrier of [`run_editor!`](@ref), before `read!` — so the frame
paints what its feeds just wrote.
"""
function drain_feeds!(editor::Editor)
    count = 0
    for feed in editor.feeds
        count += drain_changes!(feed, editor)
    end
    count
end

# ── Read-Eval-Print ──────────────────────────────────────────────────

"""
    read!(editor::Editor) -> Bool

Drain input window inputs via the backend until one translates into an
operation. Returns `true` when an operation was produced (stored in
`editor.operation`), `false` once the backend has nothing left to
deliver — used by `run_editor!` to decide when to stop draining and repaint.

Window inputs that don't yield an operation (no iomap yet, or a projection
reader that passed the event through unchanged) are silently consumed;
there's nothing to evaluate or repaint for them.

Raw backend events are first pulled through the editor's `GestureRecognizer`
(`pop_gesture!`), which is where multi-event combinations become gestures —
e.g. a `MouseDown`/`MouseUp` pair is recognised as a `MousePress` click. The
recogniser returns an `WindowInput` wrapping a backend-agnostic gesture
(KeyDown, KeyUp, KeyPress, MouseDown, MouseUp, MousePress, MouseMove,
MouseScroll, WindowQuit, WindowClose, …) together with the originating
`WindowDocument.id`. The window input is passed to the projection pipeline reader
which translates it via the last stored IoMap.
"""
function read!(editor::Editor)
    while true
        window_input = pop_gesture!(editor.recognizer,
                            () -> _read_from_devices_guarded(editor))
        if window_input === nothing
            editor.operation = nothing
            return false
        elseif window_input isa WindowInput && window_input.event isa WindowQuit
            editor.operation = QuitEditorOperation()
            return true
        elseif editor.iomap === nothing
            continue
        else
            # Seed a nothing-change carrying the gesture (the window input) and read
            # back the operation the reader pipeline produced.
            change = read_intent(editor.projection, nothing, Intent(window_input, nothing), editor.iomap)
            op = change isa Intent ? change.operation : change
            if op isa Operation
                editor.operation = op
                return true
            end
            # Editor-global readability zoom, recognised *after* the pipeline so a
            # projection that explicitly binds these keys (e.g. clipboard add/remove
            # on Ctrl+=/-) still wins when active.
            z = _zoom_operation(window_input)
            if z !== nothing
                editor.operation = z
                return true
            end
            # Escape closes the editor, but only when nothing else wanted it. A
            # reader that binds Escape — a dialog, an insertion, the command palette
            # — produced an operation above and won, so its Escape never reaches
            # here. This is why a backend must deliver Escape as a key rather than
            # as a quit: a quit cannot be declined.
            if _is_quit_gesture(window_input)
                # In the safe mode, Escape means "out of this", not "out of the
                # editor". The quit gesture goes back to its usual meaning as
                # soon as the projection is back.
                leave_safe_mode!(editor) && continue
                editor.operation = QuitEditorOperation()
                return true
            end
        end
    end
end

"""
    _is_quit_gesture(window_input) -> Bool

Is this the bare Escape that closes the editor? Modified Escape is left alone, so
a chord stays available to a projection.
"""
function _is_quit_gesture(window_input)
    window_input isa WindowInput || return false
    event = window_input.event
    event isa KeyDown || return false
    event.key === :escape || return false
    m = event.modifiers
    !(m.ctrl || m.shift || m.alt || m.meta)
end

"""
    _zoom_operation(window_input) -> Operation or nothing

Map a Ctrl-modified `=`/`-`/`0` key gesture to a readability-zoom operation:
`Ctrl` (optionally with Shift, so `Ctrl++` also works) → uniform
[`AdjustZoomOperation`](@ref); add `Alt` → font-only [`AdjustFontZoomOperation`](@ref).
`=`/`+` zooms in (+1), `-` out (-1), `0` resets (0). Returns `nothing` for
anything else. Recognised at the editor level so zoom works regardless of what
is selected.
"""
function _zoom_operation(window_input)
    window_input isa WindowInput || return nothing
    ev = window_input.event
    ev isa KeyDown || return nothing
    m = ev.modifiers
    (m.ctrl && !m.meta) || return nothing
    delta = ev.key === :equals ? 1  :
            ev.key === :minus  ? -1 :
            ev.key === :zero   ? 0  : nothing
    delta === nothing && return nothing
    m.alt ? AdjustFontZoomOperation(delta) : AdjustZoomOperation(delta)
end


# An editor is what keeps faults, and this is how code that holds one without
# being able to name its type reaches them. The kernel's agent layer drives a
# tool against a target it knows only as `Any`.
FaultModule.get_fault_store(editor::Editor) = editor.faults
FaultModule.get_fault_policy(editor::Editor) = editor.fault_policy


# ── The safe mode ────────────────────────────────────────────────────────────
#
# The last guarantee: the editor always shows something. When the printer has
# failed on every frame for long enough that no repair helped, the projection is
# put aside and one that draws the fault list takes its place. At worst a person
# reads what went wrong instead of looking at a window that stopped moving.
#
# The kernel draws nothing itself, so it asks through `make_safe_mode_projection`
# and does nothing when nothing answers.

"""
    is_editor_in_safe_mode(editor) -> Bool

Whether the editor put its projection aside and is showing the fault list.
"""
is_editor_in_safe_mode(editor::Editor) = editor.replaced_projection !== nothing

"""
    enter_safe_mode!(editor) -> Bool

Put the projection aside and show the fault list instead. Answers whether it
happened: nothing answered `make_safe_mode_projection`, or the editor was
already in the safe mode, and it did not.
"""
function enter_safe_mode!(editor::Editor)
    is_editor_in_safe_mode(editor) && return false
    projection = make_safe_mode_projection(editor.faults)
    projection isa Projection || return false
    editor.replaced_projection = editor.projection
    editor.projection = projection
    invalidate_projection!(editor)
    # The count that brought us here is spent. A fault in the safe mode itself
    # must be able to raise a fresh one.
    reset_consecutive_fault_count!(editor.faults, :print)
    @warn "[fault] the printer failed too often in a row; showing the fault list. Press Escape to go back."
    true
end

"""
    leave_safe_mode!(editor) -> Bool

Put the projection back. Answers whether the editor was in the safe mode.
"""
function leave_safe_mode!(editor::Editor)
    is_editor_in_safe_mode(editor) || return false
    editor.projection = editor.replaced_projection
    editor.replaced_projection = nothing
    invalidate_projection!(editor)
    reset_consecutive_fault_count!(editor.faults, :print)
    true
end

# Called once per frame, after the paint. Entering is what the print-failure
# limit means, and it is also what bounds a substitute that can not be printed:
# that one re-raises every frame, so the count climbs and this puts a stop to it.
_consider_safe_mode!(editor::Editor) =
    is_editor_degraded(editor, :print) && enter_safe_mode!(editor)

# ── The fault barriers ───────────────────────────────────────────────────────
#
# One barrier per stage of the frame. Each one answers its fallback rather than
# the exception, so a stage that fails costs that stage and not the editor.
# `editor.fault_policy` decides whether any of them catches at all; a programmatic
# editor starts strict, and `run_editor!` is what turns them on.

# What a barrier answers when it caught. A sentinel rather than `nothing`,
# because `nothing` is a value a stage may answer for itself.
struct _BarrierFailed end
const _BARRIER_FAILED = _BarrierFailed()

_run_barrier(body, editor::Editor, site::Symbol; counter::Symbol = site,
             origin = :editor, reference = nothing, fallback = nothing) =
    run_fault_barrier(body, editor.faults, editor.fault_policy, editor.backend,
                      site; counter = counter, origin = origin,
                      reference = reference, fallback = fallback)

"""
    report_frame_faults!(editor) -> Int

Hand every fault the last frame collected to whatever shows it, and answer how
many there were.

Call it once per frame, before anything reads the projection. This is the one
place a fault is reported on the console, because it is the one place that knows
which records are new — a printer's fault arrives here too, recorded from inside
a thunk that could not report anything itself.
"""
function report_frame_faults!(editor::Editor)
    records = drain_faults!(editor.faults)
    for record in records
        report_fault!(editor.faults, editor.fault_policy, editor.backend, record)
    end
    length(records)
end

"""
    is_editor_degraded(editor, counter) -> Bool

Whether the work counted under `counter` has failed often enough in a row that
the editor is to stop doing it.

A backend that throws in `write_to_devices` throws again on the next frame, a
hundred times a second, and calling it again is worse than leaving it alone.

The two halves of the device seam count apart — `:device_write` and
`:device_read` — because they fail apart. With one counter between them, a read
that works resets the count a write that failed just raised, and nothing ever
trips.
"""
function is_editor_degraded(editor::Editor, counter::Symbol)
    limit = counter === :print ? editor.fault_policy.print_failure_limit :
                                 editor.fault_policy.device_failure_limit
    get_consecutive_fault_count(editor.faults, counter) >= limit
end

# The input half of the device seam. A backend that throws here throws again on
# the next frame, a hundred times a second, so the fault is counted at the
# `:device` site and the seam is left alone once it passes its limit. An editor
# whose input is gone still paints, which is what lets a person see why.
function _read_from_devices_guarded(editor::Editor)
    is_editor_degraded(editor, :device_read) && return nothing
    _run_barrier(editor, :device; counter = :device_read,
                 origin = typeof(editor.backend)) do
        read_from_devices(editor.backend, editor.devices)
    end
end

# An inverse reads the state the change starts from, so it is taken BEFORE the
# change is applied. Taking one can itself fail, and a way back that could not be
# worked out is `nothing` — a truthful answer, not an error.
function _make_operation_inverse(editor::Editor, operation)
    operation === nothing && return nothing
    try
        make_inverse_operation(editor.document, operation)
    catch
        nothing
    end
end

# What the editor does to itself after an operation failed half way.
function _repair_after_operation_fault!(editor::Editor, inverse)
    # Repair 0 — take the change back, where there is a way back. A
    # `CompoundOperation` has none: its way back is built member by member, and
    # only `evaluate_invertible_operation!` does that interleave.
    if inverse !== nothing
        try
            evaluate_operation(editor, inverse)
        catch
            # The way back failed too. The document stands as it is, and the
            # two repairs below still run.
        end
    end
    # Repair 1 — re-print from scratch. A change that failed half way often
    # leaves the reactive graph inconsistent, and a fresh print rebuilds it.
    invalidate_projection!(editor)
    # Repair 2 — a selection that no longer resolves is the usual reason a
    # printer then fails on every frame that follows.
    _repair_selection!(editor)
    nothing
end

function _repair_selection!(editor::Editor)
    try
        path = get_selection(editor.document)
        path === nothing && return nothing
        is_valid_reference(editor.document, path) && return nothing
        clear_selection!(editor.document)
        @warn "[fault] the selection did not survive a failed operation and was cleared"
    catch
        # A document that can not even be asked where its selection is has
        # nothing this repair can do for it.
    end
    nothing
end

"""
    evaluate!(editor::Editor)

Apply the current operation to the document. Logs the operation when it is
non-nothing.
"""
function evaluate!(editor::Editor)
    # Log via @info, not a raw println: the assistant runs `execute_julia_code` on
    # a concurrent task that globally redirects `stdout`/`stderr` to a pipe (and
    # closes it), so a raw write to the live global stdout from this loop can land
    # in that closed pipe and crash. The logger writes to the stream captured at
    # startup, which the redirect leaves untouched.
    editor.operation !== nothing && @info "[operation] $(editor.operation)"
    operation = editor.operation
    editor.fault_policy.is_barrier_enabled ||
        return evaluate_operation(editor, operation)
    inverse = _make_operation_inverse(editor, operation)
    answer = _run_barrier(editor, :evaluate;
                          origin = operation === nothing ? :nothing : typeof(operation),
                          fallback = _BARRIER_FAILED) do
        evaluate_operation(editor, operation)
    end
    answer === _BARRIER_FAILED || return answer
    _repair_after_operation_fault!(editor, inverse)
    nothing
end

"""
    print!(editor::Editor)

Project the editor's document through its projection pipeline. The root
`PrinterContext` is minted with the editor's own `clock`, so animated cells
descendants build subscribe to this editor's clock rather than a shared one.

It also carries the editor's own document under `:root`. A projection deep in
the tree cannot reach the root any other way, and one that shows something about
the whole editor — where the selection is, which tabs are open — needs it.
"""
function print!(editor::Editor)
    if editor.iomap === nothing
        # The store rides down with the context. A projection barrier deep in
        # the tree records into it from inside a thunk, where it can write no
        # cell and reach no editor. `PrinterContext` itself does not change.
        ctx = with_property(
                  with_property(with_clock(PrinterContext(), editor.clock),
                                :root, editor.document),
                  :fault_store, editor.faults)
        editor.iomap = print_document(editor.projection, nothing,
                                      editor.document, ctx)
    end
    is_editor_degraded(editor, :device_write) && return nothing
    _run_barrier(editor, :device; counter = :device_write,
                 origin = typeof(editor.backend)) do
        write_to_devices(editor.backend, editor.devices, editor.iomap.output)
    end
end

# ── Performance logging ───────────────────────────────────────────────

"""
    perf!(editor::Editor)

Log reactive performance counters for the current frame. Only prints
when the editor processed a non-nothing operation.
"""
function perf!(editor::Editor)
    PERFORMANCE_COUNTERS_ENABLED || return
    editor.operation === nothing && return
    c = get_performance_counters()
    # The per-stage timing keys are the editor's own (recorded via `@performance_time`
    # below), not seeded by the reactive engine, so read them defensively: a frame
    # that ran no stage yet leaves them absent.
    rt = get(c, :read_time, 0) / 1e6
    et = get(c, :evaluate_time, 0) / 1e6
    pt = get(c, :print_time, 0) / 1e6
    # @info (not raw println) so this never writes to the global stdout the
    # assistant's `execute_julia_code` may have redirected to a now-closed pipe.
    @info "[perf] reads=$(c[:reads]) computes=$(c[:computes]) invalidations=$(c[:invalidations]) writes=$(c[:writes]) read=$(round(rt; digits=2))ms eval=$(round(et; digits=2))ms print=$(round(pt; digits=2))ms"
end

# ── One frame ─────────────────────────────────────────────────────────

# How many operations one frame may apply before it must repaint. A pointer in
# motion delivers input for as long as it moves, so an unbounded drain would put
# off the repaint for as long as the reader keeps moving the mouse. The bound is
# what makes a frame finite. It is high enough that ordinary input never reaches
# it, and whatever is left waits for the next frame.
const MAX_OPERATIONS_PER_FRAME = 32

"""
    run_frame!(editor::Editor)

Run one read-eval-print frame: apply everything the backend has waiting, then
repaint once. `run_editor!` runs this once per tick; call it directly to drive an
editor one frame at a time — a test harness, an embedder, or a scripted timeline
that interleaves its own work between frames.

`read!` answers one operation, so the frame loops it. Input arrives faster than a
frame can paint, and a frame that applied a single operation made a burst of
input cost one frame — plus one `sleep` — for each step in it. That is what made
a hover highlight fall behind a pointer crossing several widgets. At most
`MAX_OPERATIONS_PER_FRAME` operations are applied before the repaint.

An operation that dropped the cached projection (a whole-root swap calls
`invalidate_projection!`) ends the frame. `read!` reads against the stored IoMap
and *discards* an input it has none for, so input behind such a swap has to wait
for the repaint that rebuilds the projection, or it would be thrown away.

The loop leaves the last applied operation in `editor.operation`. `read!` clears
that field when the input runs out, and `perf!` reads it to tell a frame that did
something from an idle one.
"""
function run_frame!(editor::Editor)
    # Every fault the last frame collected, shown before this one reads
    # anything. It belongs to the frame rather than to the loop above it: a
    # driver that steps frames by hand — a playback, a test — must collect its
    # faults too. It runs first because a write to a log document has to happen
    # outside every thunk, and this is the one point in a frame that is.
    _run_barrier(editor, :report) do
        report_frame_faults!(editor)
    end
    applied = nothing
    for _ in 1:MAX_OPERATIONS_PER_FRAME
        # A reader that throws is a reader that declined: the gesture is lost,
        # the frame goes on, and the fault says which reader lost it.
        has_input = @performance_time :read_time _run_barrier(editor, :read;
                                                              fallback = false) do
            read!(editor)
        end
        has_input || break
        @performance_time :evaluate_time evaluate!(editor)
        applied = editor.operation
        editor.iomap === nothing && break     # repaint before reading anything else
    end
    editor.operation = applied
    @performance_time :print_time _run_barrier(editor, :print;
                                               origin = typeof(editor.projection)) do
        print!(editor)
    end
    _consider_safe_mode!(editor)
end

# ── Main loop ──────────────────────────────────────────────────────────

"""
    run_editor!(editor::Editor; mcp::Bool=false)

Execute the read-eval-print loop. Between frames the editor sleeps in
`wait_for_input`, and three things end the sleep: an input event, a
[`wake_editor!`](@ref) from any task, or the timeout
[`compute_wait_timeout`](@ref) answers — the animation bound while the clock
has subscribers, the nearest feed deadline, else never. Each frame:
`drain_feeds!` moves what producers posted or stored from outside — the
inbox first, then every registered feed — then `run_frame!` applies every
operation the backend has waiting and repaints once. `read!` internally
swallows envelopes that don't translate to an operation, so no outer drain
is needed.

A backend without a real wait sleeps one 10 ms poll slice per call (the
`BackendDefaults` fallback), which also gives cooperative `@async` tasks
(e.g. the MCP server, a simulation driver) their turn on this thread.

When `mcp=true`, an MCP server is started alongside the loop so external
clients can drive the editor; off by default.
"""
function run_editor!(editor::Editor; mcp::Bool=false,
              mcp_instructions::Union{AbstractString,Nothing}=nothing,
              on_start=nothing,
              fault_policy::FaultPolicy=FaultPolicy())
    # This is the moment the barriers go on. An `Editor` starts strict, so every
    # editor a test builds behaves as it does without this feature and a broken
    # projection fails its test. A loop a person sits in front of is the thing
    # that must survive instead, and this is that loop. Pass
    # `make_strict_fault_policy()` to run it without barriers.
    editor.fault_policy = fault_policy
    server = if mcp
        mcp_instructions === nothing ?
            make_agent_server(:mcp, editor) :
            make_agent_server(:mcp, editor; instructions=mcp_instructions)
    else
        nothing
    end
    server === nothing || start_agent_server!(server)
    # The editor exists now, and this is the first moment anything outside can
    # have it. What needs to reach a running editor — a driver that will post
    # its work, a watcher, a client — is handed it here, once, before any frame.
    on_start === nothing || on_start(editor)
    # Advance this editor's private animation clock once per frame; subscribers
    # via `get_reactive_clock_time(editor.clock)` re-evaluate on the next pull.
    # Logical time is wall-clock seconds since the loop started.
    t_start = Base.time()
    try
        while true
            # A wake posted since the last frame took ownership skips the
            # wait: the flag is the truth, whatever became of the backend
            # kick. The wait itself ends on input, on a kick, or at the
            # timeout — and a backend with no wait of its own polls in 10 ms
            # slices here, exactly as this loop did when it slept.
            if !editor.wake_pending[]
                timeout = compute_wait_timeout(editor)
                timeout > 0 && wait_for_input(editor.backend, editor.devices, timeout)
            end
            # The frame takes ownership of every wake posted before it;
            # a wake that arrives from here on belongs to the next frame.
            Threads.atomic_xchg!(editor.wake_pending, false)
            # A fresh per-frame counter store, bound for this frame's dynamic
            # extent; the cell operations below count into it and `perf!` reads it.
            with_performance_counters() do
                set_clock_time!(editor.clock, Base.time() - t_start)
                # What was posted or stored from outside this task, applied
                # here so the frame paints what its feeds just wrote.
                _run_barrier(editor, :evaluate) do
                    drain_feeds!(editor)
                end
                run_frame!(editor)
                _run_barrier(editor, :report) do
                    perf!(editor)
                end
            end
        end
    catch e
        e isa QuitEditorException || rethrow()
    finally
        server === nothing || stop_agent_server!(server)
    end
end

"""
    run_editor!(backend::Backend, projection, document; mcp::Bool=false,
                mcp_instructions=nothing)

Bootstrap overload: initialise the backend, wire up an `Editor` with
the given projection and document, and run the read-eval-print loop
above. The pipeline is expected to produce a `ScreenDocument` so the
backend can reconcile native windows against it; pipelines whose
output is a bare `GraphicsCanvas` go unrendered (use `write_image`
for offscreen).

The native windows are opened before the first frame, by
`open_native_windows!`, which also corrects `document` to the geometry the
window system granted. A window system may grant less than it was asked for, and
it answers only once the window exists; a document projected before that answer
is projected at a size the window never has, and the answer then arrives as a
resize that computes the whole document again. `Editor.devices` only carries the
hardware kinds the editor needs: `Display`, `Keyboard`, `Mouse`.

Pass `mcp=true` to start an MCP server alongside the loop.

`devices` defaults to the full SDL hardware set (`Display`, `Keyboard`,
`Mouse`); backends that drive a different channel — e.g. the `ConsoleBackend`,
which has no native window or pointer — pass their own set (e.g.
`Device[Keyboard()]`).

`on_start(editor)` runs once, after the editor is built and before the first
frame. It is how something that will post operations gets hold of the editor to
post them to, since this overload is what constructs it.
"""
function run_editor!(backend::Backend, projection, document; mcp::Bool=false,
              mcp_instructions::Union{AbstractString,Nothing}=nothing,
              devices::Vector{Device}=Device[Display(), Keyboard(), Mouse()],
              on_start=nothing)
    initialize_backend!(backend)
    try
        configure_devices!(backend, devices)
        # Before the first projection, so the document is laid out once, at the
        # size the window system granted rather than at the size it was asked
        # for. Nothing has read a cell yet, so the correction invalidates
        # nothing.
        open_native_windows!(backend, document)
        editor = Editor(backend, document, projection, devices)
        run_editor!(editor; mcp=mcp, mcp_instructions=mcp_instructions, on_start=on_start)
    finally
        quit_backend!(backend)
    end
end

end # module
