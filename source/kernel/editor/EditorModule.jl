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

export Editor, run_editor!, read!, evaluate!, print!, run_frame!,
       post_operation!, drain_operations!, is_editor_degraded

"""
    Editor(backend, document, projection, devices; clock = Clock(), tools = ToolSet())

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
end

# The inbox is bounded: a producer that outruns the editor should wait for it,
# not build a queue of syncs that are stale by the time they are applied.
const INBOX_CAPACITY = 64

Editor(backend, document, projection, devices;
       clock::Clock = Clock(), tools::ToolSet = ToolSet(),
       faults::FaultStore = FaultStore(),
       fault_policy::FaultPolicy = make_strict_fault_policy()) =
    Editor(backend, document, projection, devices, clock, tools,
           Channel{Operation}(INBOX_CAPACITY),
           nothing, nothing, GestureRecognizer(), faults, fault_policy)

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
"""
post_operation!(editor::Editor, operation::Operation) =
    (put!(editor.inbox, operation); operation)

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
                            () -> read_from_devices(editor.backend, editor.devices))
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

_run_barrier(body, editor::Editor, site::Symbol; origin = :editor,
             reference = nothing, fallback = nothing) =
    run_fault_barrier(body, editor.faults, editor.fault_policy, editor.backend,
                      site; origin = origin, reference = reference,
                      fallback = fallback)

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
    is_editor_degraded(editor, site) -> Bool

Whether the barrier at `site` has failed often enough in a row that the editor
is to stop calling it.

A backend that throws in `write_to_devices` throws again on the next frame, a
hundred times a second, and calling it again is worse than leaving it alone.
"""
function is_editor_degraded(editor::Editor, site::Symbol)
    limit = site === :print ? editor.fault_policy.print_failure_limit :
                              editor.fault_policy.device_failure_limit
    get_consecutive_fault_count(editor.faults, site) >= limit
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
    is_editor_degraded(editor, :device) && return nothing
    _run_barrier(editor, :device; origin = typeof(editor.backend)) do
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
end

# ── Main loop ──────────────────────────────────────────────────────────

"""
    run_editor!(editor::Editor; mcp::Bool=false)

Execute the read-eval-print loop. Each frame: `drain_operations!` applies
whatever was posted from outside, then `run_frame!` applies every operation the
backend has waiting and repaints once. `read!` internally swallows envelopes that
don't translate to an operation, so no outer drain is needed. The trailing
`sleep` yields to Julia's scheduler so
cooperative `@async` tasks (e.g. the MCP server, a simulation driver) get to
run between polls.

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
            # A fresh per-frame counter store, bound for this frame's dynamic
            # extent; the cell operations below count into it and `perf!` reads it.
            with_performance_counters() do
                set_clock_time!(editor.clock, Base.time() - t_start)
                # Every fault the last frame collected, shown before this one
                # reads anything. It runs first so a write to a log document
                # happens outside every thunk, which is the only place it may.
                _run_barrier(editor, :report) do
                    report_frame_faults!(editor)
                end
                # What was posted from outside this task, applied here so the
                # frame paints what it just applied.
                _run_barrier(editor, :evaluate) do
                    drain_operations!(editor)
                end
                run_frame!(editor)
                _run_barrier(editor, :report) do
                    perf!(editor)
                end
            end
            sleep(0.01)
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
