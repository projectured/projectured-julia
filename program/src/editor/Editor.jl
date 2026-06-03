"""
    EditorModule

The generalised Read-Eval-Print loop. Each frame: poll input via the
backend, call read! to produce a domain operation, apply the operation
to the document via evaluate!, call print! and render the updated canvas.
The latest IoMap is retained between frames so the reader has access to
the current coordinate mapping.
"""
module EditorModule

import ..ProjectionApiModule: Projection, projection_print, projection_read
import ..IoMapApiModule: IoMap
import ..DeviceModule: Device, read_from_devices, write_to_devices
import ..BackendModule: Backend, init!, quit!
import ..ScreenModule: Screen, QuitEvent
import ..ScreenDocumentModule: EventEnvelope
import ..ReactiveModule: perf_counters, perf_reset!, @perf_time
import ..DocumentModule: Document
import ..KeyboardModule: Keyboard
import ..MouseModule: Mouse
import ..OperationApiModule: Operation, evaluate_operation
import ..OperationModule: ReplaceSelectionOperation, QuitEditorOperation
import ..OperationModule: QuitEditorException
import ..McpModule: McpServer, mcp_start!, mcp_stop!

export Editor, run!

"""
    Editor(backend, document, projection, devices)

Holds the state for a read-eval-print loop:
  - `backend`    — the display/input backend (e.g. SdlBackend)
  - `document`   — the reactive document being edited
  - `projection` — the projection (or SequentialProjection)
  - `devices`    — input/output devices (e.g. window, keyboard)
  - `iomap`      — the latest IoMap from the printer (internal)
  - `operation`  — the latest operation from the reader (internal)
"""
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    iomap::Union{IoMap, Nothing}
    operation::Union{Operation, Nothing}
end

Editor(backend, document, projection, devices) = Editor(backend, document, projection, devices, nothing, nothing)

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

The backend returns an `EventEnvelope` wrapping a backend-agnostic
event (KeyDown, KeyUp, KeyPress, MouseDown, MouseUp, MousePress,
MouseMove, MouseScroll, QuitEvent, WindowCloseRequest, …) together
with the originating `WindowDocument.id`. The envelope is passed to
the projection pipeline reader which translates it via the last
stored IoMap.
"""
function read!(editor::Editor)
    while true
        env = read_from_devices(editor.backend, editor.devices)
        if env === nothing
            editor.operation = nothing
            return false
        elseif env isa EventEnvelope && env.event isa QuitEvent
            editor.operation = QuitEditorOperation()
            return true
        elseif editor.iomap === nothing
            continue
        else
            result = projection_read(editor.projection, editor.iomap, env)
            if result isa Operation
                editor.operation = result
                return true
            end
        end
    end
end

"""
    evaluate!(editor::Editor)

Apply the current operation to the document. Logs the operation to stdout
when it is non-nothing.
"""
function evaluate!(editor::Editor)
    editor.operation !== nothing && println("\r\e[K[operation] $(editor.operation)")
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
    println("\r\e[K[perf] reads=$(c[:reads]) computes=$(c[:computes]) invalidations=$(c[:invalidations]) writes=$(c[:writes]) read=$(round(rt; digits=2))ms eval=$(round(et; digits=2))ms print=$(round(pt; digits=2))ms")
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
function run!(editor::Editor; mcp::Bool=false)
    server = mcp ? McpServer(editor) : nothing
    server === nothing || mcp_start!(server)
    try
        while true
            perf_reset!()
            @perf_time :read_time     read!(editor)
            @perf_time :evaluate_time evaluate!(editor)
            @perf_time :print_time    print!(editor)
            perf!(editor)
            sleep(0.01)
        end
    catch e
        e isa QuitEditorException || rethrow()
    finally
        server === nothing || mcp_stop!(server)
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
"""
function run!(backend::Backend, projection, document; mcp::Bool=false)
    init!(backend)
    try
        devices = Device[Screen(), Keyboard(), Mouse()]
        editor = Editor(backend, document, projection, devices)
        run!(editor; mcp=mcp)
    finally
        quit!(backend)
    end
end

end # module
