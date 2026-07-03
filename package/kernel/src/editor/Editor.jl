"""
    EditorModule

The generalised Read-Eval-Print loop. Each frame: poll input via the
backend, call read! to produce a domain operation, apply the operation
to the document via evaluate!, call print! and render the updated canvas.
The latest IoMap is retained between frames so the reader has access to
the current coordinate mapping.
"""
module EditorModule

import ..ProjectionApiModule: Projection, print_document, read_intent
import ..IntentModule: Intent
import ..IoMapApiModule: IoMap
import ..DeviceApiModule: Device, read_from_devices, write_to_devices
import ..BackendApiModule: Backend, initialize_backend!, quit_backend!
import ..ScreenDeviceModule: Screen, WindowQuit
import ..ScreenDocumentModule: EventEnvelope
import ..PerformanceCounterModule: get_performance_counters, reset_performance_counters!, @performance_time
import ..TimeModule: tick_editor_time!
import ..DocumentApiModule: Document
import ..KeyboardModule: Keyboard, KeyDown
import ..MouseModule: Mouse
import ..OperationApiModule: Operation, evaluate_operation, invalidate_projection!
import ..OperationModule: ReplaceSelectionOperation, QuitEditorOperation, AdjustZoomOperation, AdjustFontZoomOperation
import ..OperationModule: QuitEditorException
import ..GestureRecognizerModule: GestureRecognizer, pop_gesture!
import ..AgentApiModule: make_agent_server, start_agent_server!, stop_agent_server!

export Editor, run_editor!

"""
    Editor(backend, document, projection, devices)

Holds the state for a read-eval-print loop:
  - `backend`    — the display/input backend (e.g. SdlBackend)
  - `document`   — the reactive document being edited
  - `projection` — the projection (or ChainingProjection)
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

# Drop the cached IoMap so the next `print!` rebuilds the projection from scratch.
# The default `invalidate_projection!` (in `OperationApiModule`) is a no-op; this
# method is what an operation like a whole-root `ReplaceReferencedValueOperation` swap
# actually reaches when it runs against a real `Editor`.
invalidate_projection!(editor::Editor) = (editor.iomap = nothing)

# ── Read-Eval-Print ──────────────────────────────────────────────────

"""
    read!(editor::Editor) -> Bool

Drain input envelopes via the backend until one translates into an
operation. Returns `true` when an operation was produced (stored in
`editor.operation`), `false` once the backend has nothing left to
deliver — used by `run_editor!` to decide when to stop draining and repaint.

Envelopes that don't yield an operation (no iomap yet, or a projection
reader that passed the event through unchanged) are silently consumed;
there's nothing to evaluate or repaint for them.

Raw backend events are first pulled through the editor's `GestureRecognizer`
(`pop_gesture!`), which is where multi-event combinations become gestures —
e.g. a `MouseDown`/`MouseUp` pair is recognised as a `MousePress` click. The
recogniser returns an `EventEnvelope` wrapping a backend-agnostic gesture
(KeyDown, KeyUp, KeyPress, MouseDown, MouseUp, MousePress, MouseMove,
MouseScroll, WindowQuit, WindowClose, …) together with the originating
`WindowDocument.id`. The envelope is passed to the projection pipeline reader
which translates it via the last stored IoMap.
"""
function read!(editor::Editor)
    while true
        env = pop_gesture!(editor.recognizer,
                            () -> read_from_devices(editor.backend, editor.devices))
        if env === nothing
            editor.operation = nothing
            return false
        elseif env isa EventEnvelope && env.event isa WindowQuit
            editor.operation = QuitEditorOperation()
            return true
        elseif editor.iomap === nothing
            continue
        else
            # Seed a nothing-change carrying the gesture (the envelope) and read
            # back the operation the reader pipeline produced.
            change = read_intent(editor.projection, nothing, Intent(env, nothing), editor.iomap)
            op = change isa Intent ? change.operation : change
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
        editor.iomap = print_document(editor.projection, editor.document)
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

# ── Main loop ──────────────────────────────────────────────────────────

"""
    run_editor!(editor::Editor; mcp::Bool=false)

Execute the read-eval-print loop. Each frame: `read!` pulls (at most)
one operation from the backend, `evaluate!` applies it, `print!`
repaints. `read!` internally swallows envelopes that don't translate
to an operation, so no outer drain is needed. The trailing `sleep`
yields to Julia's scheduler so cooperative `@async` tasks (e.g. the
MCP server) get to run between polls.

When `mcp=true`, an MCP server is started alongside the loop so external
clients can drive the editor; off by default.
"""
function run_editor!(editor::Editor; mcp::Bool=false,
              mcp_instructions::Union{AbstractString,Nothing}=nothing)
    server = if mcp
        mcp_instructions === nothing ?
            make_agent_server(:mcp, editor) :
            make_agent_server(:mcp, editor; instructions=mcp_instructions)
    else
        nothing
    end
    server === nothing || start_agent_server!(server)
    # Advance the global animation clock once per frame. `tick_editor_time!` writes the
    # clock cell, so any computed cell that subscribed via
    # `get_reactive_editor_time()` is invalidated and re-evaluated on the next pull.
    # Logical time is wall-clock seconds since the loop started.
    t_start = Base.time()
    try
        while true
            reset_performance_counters!()
            tick_editor_time!(Base.time() - t_start)
            @performance_time :read_time     read!(editor)
            @performance_time :evaluate_time evaluate!(editor)
            @performance_time :print_time    print!(editor)
            perf!(editor)
            sleep(0.01)
        end
    catch e
        e isa QuitEditorException || rethrow()
    finally
        server === nothing || stop_agent_server!(server)
    end
end

"""
    run_editor!(backend::Backend, projection, document; mcp::Bool=false)

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
function run_editor!(backend::Backend, projection, document; mcp::Bool=false,
              devices::Vector{Device}=Device[Screen(), Keyboard(), Mouse()])
    initialize_backend!(backend)
    try
        editor = Editor(backend, document, projection, devices)
        run_editor!(editor; mcp=mcp)
    finally
        quit_backend!(backend)
    end
end

end # module
