"""
    EditorModule

The generalised Read-Eval-Print loop. Each frame: poll input via the
backend, call read! to produce a domain operation, apply the operation
to the document via evaluate!, call print! and render the updated canvas.
The latest IoMap is retained between frames so the reader has access to
the current coordinate mapping.
"""
module EditorModule

using ..ProjectionApiModule
using ..IntentModule
using ..IoMapModule
using ..DeviceModule
using ..BackendModule
using ..EventModule
using ..PerformanceCounterModule
using ..ClockModule
using ..PrinterContextModule
using ..DocumentModule
using ..OperationModule
# `import`, not `using`: this module adds the Editor method to the invalidation seam.
import ..OperationModule: invalidate_projection!
using ..GestureRecognizerModule
using ..ToolModule
using ..AgentServerModule

export Editor, run_editor!

"""
    Editor(backend, document, projection, devices; clock = Clock(), tools = ToolSet())

Holds the state for a read-eval-print loop:
  - `backend`    — the display/input backend (e.g. SdlBackend)
  - `document`   — the reactive document being edited
  - `projection` — the projection (or ChainingProjection)
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
                   other's namespace (AR-PER-EDITOR-STATE).
  - `iomap`      — the latest IoMap from the printer (internal)
  - `operation`  — the latest operation from the reader (internal)
  - `recognizer` — the event → gesture recogniser (internal)
"""
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    clock::Clock
    tools::ToolSet
    iomap::Union{IoMap, Nothing}
    operation::Union{Operation, Nothing}
    recognizer::GestureRecognizer
end

Editor(backend, document, projection, devices;
       clock::Clock = Clock(), tools::ToolSet = ToolSet()) =
    Editor(backend, document, projection, devices, clock, tools,
           nothing, nothing, GestureRecognizer())

# Drop the cached IoMap so the next `print!` rebuilds the projection from scratch.
# `invalidate_projection!` is a no-op for an object that caches nothing; this method
# is what an operation like a whole-root `ReplaceReferencedValueOperation` swap
# actually reaches when it runs against a real `Editor`.
invalidate_projection!(editor::Editor) = (editor.iomap = nothing)

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
        end
    end
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

Project the editor's document through its projection pipeline. The root
`PrinterContext` is minted with the editor's own `clock`, so animated cells
descendants build subscribe to this editor's clock rather than a shared one.
"""
function print!(editor::Editor)
    if editor.iomap === nothing
        ctx = with_clock(PrinterContext(), editor.clock)
        editor.iomap = print_document(editor.projection, nothing,
                                      editor.document, ctx)
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
                @performance_time :read_time     read!(editor)
                @performance_time :evaluate_time evaluate!(editor)
                @performance_time :print_time    print!(editor)
                perf!(editor)
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
needs: `Display`, `Keyboard`, `Mouse`.

Pass `mcp=true` to start an MCP server alongside the loop.

`devices` defaults to the full SDL hardware set (`Display`, `Keyboard`,
`Mouse`); backends that drive a different channel — e.g. the `ConsoleBackend`,
which has no native window or pointer — pass their own set (e.g.
`Device[Keyboard()]`).
"""
function run_editor!(backend::Backend, projection, document; mcp::Bool=false,
              devices::Vector{Device}=Device[Display(), Keyboard(), Mouse()])
    initialize_backend!(backend)
    try
        configure_devices!(backend, devices)
        editor = Editor(backend, document, projection, devices)
        run_editor!(editor; mcp=mcp)
    finally
        quit_backend!(backend)
    end
end

end # module
