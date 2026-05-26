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
import ..BackendModule: Backend
import ..WindowModule: QuitEvent
import ..ReactiveModule: perf_counters, perf_reset!
import ..DocumentModule: Document
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
    read!(editor::Editor)

Poll input events via the backend. The backend returns backend-agnostic
events (KeyDown, KeyUp, KeyPress, MouseDown, MouseUp, MousePress, MouseMove, MouseScroll, QuitEvent, …). Events are passed
to the projection pipeline reader which translates them into domain-specific
operations via the last stored IoMap. The result is stored in `editor.operation`.
"""
function read!(editor::Editor)
    event = read_from_devices(editor.backend, editor.devices)
    if event === nothing
        editor.operation = nothing
    elseif event isa QuitEvent
        editor.operation = QuitEditorOperation()
    elseif editor.iomap === nothing
        editor.operation = nothing
    else
        editor.operation = projection_read(editor.projection, editor.iomap, event)
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
    println("\r\e[K[perf] reads=$(c[:reads]) computes=$(c[:computes]) invalidations=$(c[:invalidations]) writes=$(c[:writes])")
end

# ── Main loop ──────────────────────────────────────────────────────────

"""
    run!(editor::Editor)

Execute the read-eval-print loop:

    loop:
      1. read!      — read device input into an operation
      2. evaluate!  — apply the operation to the document
      3. print!     — project the document to the output device
"""
function run!(editor::Editor)
    mcp = McpServer(editor)
    mcp_start!(mcp)
    try
        while true
            perf_reset!()
            read!(editor)
            evaluate!(editor)
            print!(editor)
            perf!(editor)
            sleep(0.01)
        end
    catch e
        e isa QuitEditorException || rethrow()
    finally
        mcp_stop!(mcp)
    end
end


end # module
