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

Poll the next input envelope via the backend and translate it into
an operation. Returns `true` if an envelope was consumed (whether or
not it produced an operation), `false` when the backend had nothing
to deliver — used by `run!` to decide when to stop draining and
repaint.

The backend returns an `EventEnvelope` wrapping a backend-agnostic
event (KeyDown, KeyUp, KeyPress, MouseDown, MouseUp, MousePress,
MouseMove, MouseScroll, QuitEvent, WindowCloseRequest, …) together
with the originating `WindowDocument.id`. The envelope is passed to
the projection pipeline reader which translates it via the last
stored IoMap. The result is stored in `editor.operation`.
"""
function read!(editor::Editor)
    env = read_from_devices(editor.backend, editor.devices)
    if env === nothing
        editor.operation = nothing
        return false
    elseif env isa EventEnvelope && env.event isa QuitEvent
        editor.operation = QuitEditorOperation()
        return true
    elseif editor.iomap === nothing
        editor.operation = nothing
        return true
    else
        # The envelope carries the window_id that the screen-level
        # CopyingProjection uses to route to the right sub-iomap.
        # Single-window pipelines whose readers don't care just look
        # at env.event.
        # Some projection readers (e.g. workbench panels) pass unhandled
        # events through by returning `op` unchanged, which can be a raw
        # KeyDown/MousePress rather than an Operation. Coerce to nothing
        # so the strict `Union{Operation, Nothing}` field accepts it.
        result = projection_read(editor.projection, editor.iomap, env)
        editor.operation = result isa Operation ? result : nothing
        return true
    end
end

"""
    evaluate!(editor::Editor)

Apply the current operation to the document. Logs the operation to stdout
when it is non-nothing.
"""
function evaluate!(editor::Editor)
    editor.operation !== nothing && println("\r\e[K[operation] $(editor.operation)")
    evaluate_operation(editor.operation, editor.document)
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
    run!(editor::Editor)

Execute the read-eval-print loop. Each frame drains every available
envelope from the backend (each routed to an operation and applied)
and then repaints once. Draining avoids repaint starvation when one
window emits a burst of events.

    per frame:
      1. drain envelopes — for each: read! → evaluate!
      2. print!          — project the document to the output devices
"""
function run!(editor::Editor)
    mcp = McpServer(editor)
    mcp_start!(mcp)
    try
        while true
            perf_reset!()
            # Drain all pending envelopes this frame.
            while true
                consumed = false
                @perf_time :read_time begin
                    consumed = read!(editor)
                end
                consumed || break
                @perf_time :evaluate_time evaluate!(editor)
                perf!(editor)
            end
            @perf_time :print_time    print!(editor)
            sleep(0.01)
        end
    catch e
        e isa QuitEditorException || rethrow()
    finally
        mcp_stop!(mcp)
    end
end

"""
    run!(backend::Backend, projection, document)

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
"""
function run!(backend::Backend, projection, document)
    init!(backend)
    try
        editor = Editor(backend, document, projection,
                        Device[Screen(), Keyboard(), Mouse()])
        run!(editor)
    finally
        quit!(backend)
    end
end

end # module
