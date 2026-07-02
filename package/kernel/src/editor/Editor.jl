"""
    EditorModule

The generalised Read-Eval-Print loop. Each frame: poll input via the
backend, call read! to produce a domain operation, apply the operation
to the document via evaluate!, call print! and render the updated canvas.
The latest IoMap is retained between frames so the reader has access to
the current coordinate mapping.
"""
module EditorModule

import ..ProjectionApiModule: Projection, projection_print, projection_read, Change
import ..IoMapApiModule: IoMap
import ..DeviceModule: Device, read_from_devices, write_to_devices
import ..BackendModule: Backend, init!, quit!
import ..ScreenModule: Screen, QuitEvent
import ..ScreenDocumentModule: EventEnvelope
import ..PerformanceCounterModule: perf_counters, perf_reset!, @perf_time
import ..EditorTimeModule: tick!
import ..DocumentModule: Document
import ..KeyboardModule: Keyboard, KeyDown
import ..MouseModule: Mouse
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationModule: ReplaceSelectionOperation, QuitEditorOperation, AdjustZoomOperation, AdjustFontZoomOperation
import ..OperationModule: QuitEditorException
import ..OperationRerootingModule: prepend_steps_to_op
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, EmptyReferencePath
import ..GestureRecognizerModule: GestureRecognizer, next_gesture!
import ..AgentModule: make_agent_server, agent_server_start!, agent_server_stop!

export Editor, run!, play_live!

"""
    Editor(backend, document, projection, devices)

Holds the state for a read-eval-print loop:
  - `backend`    — the display/input backend (e.g. SdlBackend)
  - `document`   — the reactive document being edited
  - `projection` — the projection (or SequentialProjection)
  - `devices`    — input/output devices (e.g. window, keyboard)
  - `iomap`      — the latest IoMap from the printer (internal)
  - `operation`  — the latest operation from the reader (internal)
  - `recognizer` — the event → gesture recogniser (internal)
"""
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    iomap::Union{IoMap, Nothing}
    operation::Union{Operation, Nothing}
    recognizer::GestureRecognizer
end

Editor(backend, document, projection, devices) =
    Editor(backend, document, projection, devices, nothing, nothing, GestureRecognizer())

# ── Read-Eval-Print ──────────────────────────────────────────────────

"""
    read!(editor::Editor) -> Bool

Drain input envelopes via the backend until one translates into an
operation. Returns `true` when an operation was produced (stored in
`editor.operation`), `false` once the backend has nothing left to
deliver — used by `run!` to decide when to stop draining and repaint.

Envelopes that don't yield an operation (no iomap yet, or a projection
reader that passed the event through unchanged) are silently consumed;
there's nothing to evaluate or repaint for them.

Raw backend events are first pulled through the editor's `GestureRecognizer`
(`next_gesture!`), which is where multi-event combinations become gestures —
e.g. a `MouseDown`/`MouseUp` pair is recognised as a `MousePress` click. The
recogniser returns an `EventEnvelope` wrapping a backend-agnostic gesture
(KeyDown, KeyUp, KeyPress, MouseDown, MouseUp, MousePress, MouseMove,
MouseScroll, QuitEvent, WindowCloseRequest, …) together with the originating
`WindowDocument.id`. The envelope is passed to the projection pipeline reader
which translates it via the last stored IoMap.
"""
function read!(editor::Editor)
    while true
        env = next_gesture!(editor.recognizer,
                            () -> read_from_devices(editor.backend, editor.devices))
        if env === nothing
            editor.operation = nothing
            return false
        elseif env isa EventEnvelope && env.event isa QuitEvent
            editor.operation = QuitEditorOperation()
            return true
        elseif editor.iomap === nothing
            continue
        else
            # Seed a nothing-change carrying the gesture (the envelope) and read
            # back the operation the reader pipeline produced.
            change = projection_read(editor.projection, nothing, Change(env, nothing), editor.iomap)
            op = change isa Change ? change.operation : change
            if op isa Operation
                editor.operation = op
                return true
            end
            # Editor-global readability zoom, recognised *after* the pipeline so a
            # projection that explicitly binds these keys (e.g. clipboard add/remove
            # on Ctrl+=/-) still wins when active.
            z = _zoom_operation(env)
            if z !== nothing
                editor.operation = z
                return true
            end
        end
    end
end

"""
    _zoom_operation(env) -> Operation or nothing

Map a Ctrl-modified `=`/`-`/`0` key gesture to a readability-zoom operation:
`Ctrl` (optionally with Shift, so `Ctrl++` also works) → uniform
[`AdjustZoomOperation`](@ref); add `Alt` → font-only [`AdjustFontZoomOperation`](@ref).
`=`/`+` zooms in (+1), `-` out (-1), `0` resets (0). Returns `nothing` for
anything else. Recognised at the editor level so zoom works regardless of what
is selected.
"""
function _zoom_operation(env)
    env isa EventEnvelope || return nothing
    ev = env.event
    ev isa KeyDown || return nothing
    m = ev.modifiers
    (m.ctrl && !m.meta) || return nothing
    delta = ev.key === :equals ? 1  :
            ev.key === :minus  ? -1 :
            ev.key === :zero   ? 0  : nothing
    delta === nothing && return nothing
    m.alt ? AdjustFontZoomOperation(delta) : AdjustZoomOperation(delta)
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
    evaluate_operation(editor, editor.operation)
end

"""
    print!(editor::Editor)

Project the editor's document through its projection pipeline.
"""
function print!(editor::Editor)
    if editor.iomap === nothing
        editor.iomap = projection_print(editor.projection, editor.document)
    end
    write_to_devices(editor.backend, editor.devices, editor.iomap.output)
end

# ── Performance logging ───────────────────────────────────────────────

"""
    perf!(editor::Editor)

Log reactive performance counters for the current frame. Only prints
when the editor processed a non-nothing operation.
"""
function perf!(editor::Editor)
    editor.operation === nothing && return
    c = perf_counters()
    rt = c[:read_time] / 1e6
    et = c[:evaluate_time] / 1e6
    pt = c[:print_time] / 1e6
    # @info (not raw println) so this never writes to the global stdout the
    # assistant's `execute_julia_code` may have redirected to a now-closed pipe.
    @info "[perf] reads=$(c[:reads]) computes=$(c[:computes]) invalidations=$(c[:invalidations]) writes=$(c[:writes]) read=$(round(rt; digits=2))ms eval=$(round(et; digits=2))ms print=$(round(pt; digits=2))ms"
end

# ── Main loop ──────────────────────────────────────────────────────────

"""
    run!(editor::Editor; mcp::Bool=false)

Execute the read-eval-print loop. Each frame: `read!` pulls (at most)
one operation from the backend, `evaluate!` applies it, `print!`
repaints. `read!` internally swallows envelopes that don't translate
to an operation, so no outer drain is needed. The trailing `sleep`
yields to Julia's scheduler so cooperative `@async` tasks (e.g. the
MCP server) get to run between polls.

When `mcp=true`, an MCP server is started alongside the loop so external
clients can drive the editor; off by default.
"""
function run!(editor::Editor; mcp::Bool=false,
              mcp_instructions::Union{AbstractString,Nothing}=nothing)
    server = if mcp
        mcp_instructions === nothing ?
            make_agent_server(:mcp, editor) :
            make_agent_server(:mcp, editor; instructions=mcp_instructions)
    else
        nothing
    end
    server === nothing || agent_server_start!(server)
    # Advance the global animation clock once per frame. `tick!` writes
    # EDITOR_TIME, so any computed cell that subscribed via
    # `reactive_editor_time()` is invalidated and re-evaluated on the next pull.
    # Logical time is wall-clock seconds since the loop started.
    t_start = Base.time()
    try
        while true
            perf_reset!()
            tick!(Base.time() - t_start)
            @perf_time :read_time     read!(editor)
            @perf_time :evaluate_time evaluate!(editor)
            @perf_time :print_time    print!(editor)
            perf!(editor)
            sleep(0.01)
        end
    catch e
        e isa QuitEditorException || rethrow()
    finally
        server === nothing || agent_server_stop!(server)
    end
end

"""
    run!(backend::Backend, projection, document; mcp::Bool=false)

Bootstrap overload: initialise the backend, wire up an `Editor` with
the given projection and document, and run the read-eval-print loop
above. The pipeline is expected to produce a `ScreenDocument` so the
backend can reconcile native windows against it; pipelines whose
output is a bare `GraphicsCanvas` go unrendered (use `write_image`
for offscreen).

Native windows are not pre-allocated here — the backend opens them
on demand the first time `write_to_devices` sees a `ScreenDocument`
output. `Editor.devices` only carries the hardware kinds the editor
needs: `Screen`, `Keyboard`, `Mouse`.

Pass `mcp=true` to start an MCP server alongside the loop.

`devices` defaults to the full SDL hardware set (`Screen`, `Keyboard`,
`Mouse`); backends that drive a different channel — e.g. the `ConsoleBackend`,
which has no native window or pointer — pass their own set (e.g.
`Device[Keyboard()]`).
"""
function run!(backend::Backend, projection, document; mcp::Bool=false,
              devices::Vector{Device}=Device[Screen(), Keyboard(), Mouse()])
    init!(backend)
    try
        editor = Editor(backend, document, projection, devices)
        run!(editor; mcp=mcp)
    finally
        quit!(backend)
    end
end

# ── Scripted live playback ───────────────────────────────────────────────

# Walk a reference path into a tuple of steps (outermost first), for rerooting.
_path_to_steps(::EmptyReferencePath) = ()
function _path_to_steps(path::ConcreteReferencePath)
    steps = Any[]
    cur = path
    while cur isa ConcreteReferencePath
        push!(steps, cur.head)
        cur = cur.tail
    end
    Tuple(steps)
end

"""
    _timeline_operation(editor::Editor, entry, window_id::Symbol, op_prefix::Tuple) -> Operation or nothing

Turn one timeline entry into an operation, mirroring `read!`. An entry carrying
`event` is wrapped in `EventEnvelope(window_id, event)` and run through the
reader pipeline (the same path live input takes), which already roots the
resulting operation in the document root. An entry carrying `operation` is taken
directly — either an `Operation` value or a `doc -> op` thunk evaluated against
the current `editor.document` — and its reference path is rerooted by
`op_prefix` (the steps from the document root to the wrapped content), since a
directly-injected operation bypasses the reader's rerooting. Returns `nothing`
when nothing applies.
"""
function _timeline_operation(editor::Editor, entry, window_id::Symbol, op_prefix::Tuple)
    # An `await` entry (see `timed_await`) is a pure pause: it injects no
    # operation. The live loop renders and yields every frame, so an async turn
    # already kicked off by a prior ENTER streams in live during its dwell.
    haskey(entry, :await) && return nothing
    if haskey(entry, :operation)
        op = entry.operation isa Function ? entry.operation(editor.document) : entry.operation
        op isa Operation || return nothing
        return isempty(op_prefix) ? op : prepend_steps_to_op(op, op_prefix)
    else
        editor.iomap === nothing && return nothing
        env = EventEnvelope(window_id, entry.event)
        change = projection_read(editor.projection, nothing, Change(env, nothing), editor.iomap)
        op = change isa Change ? change.operation : change
        return op isa Operation ? op : nothing
    end
end

"""
    play_live!(editor::Editor, timeline; window_id::Symbol, initial_hold::Real=0.5,
               op_prefix::ReferencePath=EmptyReferencePath())

Run the read-eval-print loop while firing a predefined `timeline` on a
wall-clock schedule, so the user watches the scripted session unfold in a real
window. Entry `i` fires `initial_hold + Σ hold[1..i-1]` seconds after start;
`hold` is the dwell after the entry is applied (the same field used by
[`record_video`](@ref), so one timeline drives both the headless recording and
this live playback).

Each entry carries either an `event` (wrapped in an `EventEnvelope` for
`window_id` and run through the reader, like live input) or an `operation` (a
domain `Operation` value, or a `doc -> op` thunk, injected straight into the
evaluator). At most one scheduled entry is applied per frame, so each resulting
state is visible. Real user input is still polled every frame, so the user can
interact and the window-close button / Escape quits cleanly. After the last
entry the window stays live and interactive.

`op_prefix` reroots directly-injected `operation` entries: a timeline authored
in the bare-content domain (the same coordinates the recorder uses) needs its
operation paths prefixed by the steps from the live document root to that
content (e.g. `windows[1].content` when the example is wrapped in a window).
Event entries are unaffected — the reader already roots them.
"""
function play_live!(editor::Editor, timeline; window_id::Symbol, initial_hold::Real=0.5,
                    op_prefix::ReferencePath=EmptyReferencePath())
    n = length(timeline)
    prefix_steps = _path_to_steps(op_prefix)
    # fire_at[i]: seconds from start at which entry i is applied.
    fire_at = Vector{Float64}(undef, n)
    acc = Float64(initial_hold)
    for i in 1:n
        fire_at[i] = acc
        acc += Float64(timeline[i].hold)
    end
    start = time()
    next = 1
    try
        while true
            perf_reset!()
            @perf_time :read_time read!(editor)
            # When no real-input operation is pending and the next scheduled
            # entry is due, inject it. Real input wins the frame; the scheduled
            # entry retries on the following frame.
            if editor.operation === nothing && next <= n && (time() - start) >= fire_at[next]
                editor.operation = _timeline_operation(editor, timeline[next], window_id, prefix_steps)
                next += 1
            end
            @perf_time :evaluate_time evaluate!(editor)
            @perf_time :print_time    print!(editor)
            perf!(editor)
            sleep(0.01)
        end
    catch e
        e isa QuitEditorException || rethrow()
    end
end

"""
    play_live!(backend::Backend, projection, document, timeline;
               window_id::Symbol, initial_hold::Real=0.5)

Bootstrap overload: initialise the backend, wire up an `Editor`, and run the
scripted live loop above. Like [`run!`](@ref), the pipeline is expected to
produce a `ScreenDocument` so the backend opens a real window; `window_id` is the
`WindowDocument.id` scripted events are routed to.
"""
function play_live!(backend::Backend, projection, document, timeline;
                    window_id::Symbol, initial_hold::Real=0.5,
                    op_prefix::ReferencePath=EmptyReferencePath())
    init!(backend)
    try
        devices = Device[Screen(), Keyboard(), Mouse()]
        editor = Editor(backend, document, projection, devices)
        play_live!(editor, timeline; window_id=window_id, initial_hold=initial_hold,
                   op_prefix=op_prefix)
    finally
        quit!(backend)
    end
end

end # module
