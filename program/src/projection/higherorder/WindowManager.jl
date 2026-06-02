"""
    WindowManagerProjectionModule

A higher-order projection that wraps the `ScreenDocument` case of the
type dispatcher in the main pipeline. Its printer is a passthrough to
the inner projection (typically `CopyingProjection`). Its reader
intercepts `OpenWindowOperation` and `CloseWindowOperation` bubbling
up from below, mutating the input `ScreenDocument.windows` list, and
swallowing the operation so it doesn't reach `evaluate_operation`.

Together with `TooltipDecoratorProjection`, this turns "show a tooltip"
into "request a window via an operation; let the manager apply it" —
the same input → operation → input → printer loop every other state
change uses.
"""
module WindowManagerProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..IoMapApiModule: IoMap
import ..ReactiveModule: Cell
import ..ScreenDocumentModule: ScreenDocument, WindowDocument
import ..OperationModule: OpenWindowOperation, CloseWindowOperation

export WindowManagerProjection, WindowManagerProjectionIoMap

"""
    WindowManagerProjection(; inner)

Wraps `inner` (a projection over `ScreenDocument`, typically
`CopyingProjection`) and intercepts window-management operations on
the reader side.
"""
struct WindowManagerProjection <: Projection
    inner::Any
end

WindowManagerProjection(; inner) = WindowManagerProjection(inner)

struct WindowManagerProjectionIoMap <: IoMap
    projection::WindowManagerProjection
    input::Any
    output::Any
    inner_iomap::Any
end

# ── Printer (passthrough) ─────────────────────────────────────────────────

function projection_print(p::WindowManagerProjection, input, recursion, ctx)
    inner_iomap = projection_print(p.inner, input, recursion, ctx)
    WindowManagerProjectionIoMap(p, input, inner_iomap.output, inner_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function projection_read(p::WindowManagerProjection, iomap::WindowManagerProjectionIoMap, event_or_op)
    op = projection_read(p.inner, iomap.inner_iomap, event_or_op)
    if op isa OpenWindowOperation
        _apply_open!(iomap.input, op)
        return nothing
    elseif op isa CloseWindowOperation
        _apply_close!(iomap.input, op)
        return nothing
    else
        return op
    end
end

# Mutate the input ScreenDocument's windows list in place. Duplicate-id
# opens update the existing window's geometry/content rather than adding
# a second entry; closes for a missing id are silently ignored.

function _apply_open!(input, op::OpenWindowOperation)
    input isa ScreenDocument || return
    wins = input.windows
    for i in 1:length(wins)
        existing = wins[i]
        existing isa WindowDocument || continue
        existing.id === op.id || continue
        existing.title  = op.title
        existing.x      = op.x
        existing.y      = op.y
        existing.width  = op.width
        existing.height = op.height
        existing.bg     = op.bg
        existing.style  = op.style
        existing.content = op.content
        return
    end
    new_win = WindowDocument(; id=op.id, title=op.title,
                               x=op.x, y=op.y,
                               width=op.width, height=op.height,
                               bg=op.bg, style=op.style,
                               content=op.content)
    push!(wins, Cell(new_win))
end

function _apply_close!(input, op::CloseWindowOperation)
    input isa ScreenDocument || return
    wins = input.windows
    for i in 1:length(wins)
        existing = wins[i]
        existing isa WindowDocument || continue
        existing.id === op.id || continue
        deleteat!(wins, i)
        return
    end
end

# Reference mapping is a passthrough to the inner.

function map_reference_forward(::WindowManagerProjection, iomap::WindowManagerProjectionIoMap, reference)
    map_reference_forward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
end

function map_reference_backward(::WindowManagerProjection, iomap::WindowManagerProjectionIoMap, reference)
    map_reference_backward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
end

end # module
