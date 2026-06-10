"""
    WindowManagerProjectionModule

A higher-order projection that wraps the `ScreenDocument` case of the
type dispatcher in the main pipeline. Its printer is a passthrough to
the inner projection (typically `CopyingProjection`). Its reader
intercepts `OpenWindowOperation` and `CloseWindowOperation` bubbling
up from below, applying them to *both* the input `ScreenDocument` and
the projected output, so the next frame's reconciler sees the change.

Together with `TooltipDecoratorProjection`, this turns "show a tooltip"
into "request a window via an operation; let the manager apply it" —
the same input → operation → input → printer loop every other state
change uses.

The manager has to mutate the *output* explicitly because
`CopyingProjection` builds its `CellVector` of children eagerly at
print time: a later push to the input's `windows` cell would not
propagate to the output. The manager therefore stores the outer
`recursion` projection and `ctx` it was called with, and re-runs the
recursion on each new window to produce the output side.
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
    recursion::Any
    ctx::Any
end

# ── Printer (passthrough; remembers recursion + ctx for the reader) ──────

function projection_print(p::WindowManagerProjection, recursion, input, ctx)
    inner_iomap = projection_print(p.inner, recursion, input, ctx)
    WindowManagerProjectionIoMap(p, input, inner_iomap.output, inner_iomap, recursion, ctx)
end

# ── Reader ────────────────────────────────────────────────────────────────

function projection_read(p::WindowManagerProjection, iomap::WindowManagerProjectionIoMap, event_or_op)
    op = projection_read(p.inner, iomap.inner_iomap, event_or_op)
    if op isa OpenWindowOperation
        _apply_open!(iomap, op)
        return nothing
    elseif op isa CloseWindowOperation
        _apply_close!(iomap, op)
        return nothing
    else
        return op
    end
end

# Apply Open: add a new window (or update an existing one with the same
# id) on both the input and the output. The output side requires
# projecting the new WindowDocument through the same recursion that
# produced the rest of the output.

function _apply_open!(iomap::WindowManagerProjectionIoMap, op::OpenWindowOperation)
    input = iomap.input
    output = iomap.output
    input isa ScreenDocument || return
    output isa ScreenDocument || return

    # Existing window with this id → update in place on both sides.
    in_wins = input.windows
    out_wins = output.windows
    for i in 1:length(in_wins)
        existing_in = in_wins[i]
        existing_in isa WindowDocument || continue
        existing_in.id === op.id || continue
        _update_window!(existing_in, op)
        # Output window with the same index/id (assumes 1:1 ordering — the
        # invariant the printer establishes and that this code maintains).
        if i <= length(out_wins)
            existing_out = out_wins[i]
            if existing_out isa WindowDocument
                _update_window!(existing_out, op; project_content=true,
                                recursion=iomap.recursion, ctx=iomap.ctx)
            end
        end
        return
    end

    # New window: construct input side, project to get output side, push both.
    new_in = WindowDocument(; id=op.id, title=op.title,
                              x=op.x, y=op.y,
                              width=op.width, height=op.height,
                              bg=op.bg, style=op.style,
                              content=op.content)
    new_iomap = projection_print(iomap.recursion, iomap.recursion, new_in, iomap.ctx)
    new_out = new_iomap.output

    push!(in_wins, Cell(new_in))
    push!(out_wins, Cell(new_out))
end

function _update_window!(w::WindowDocument, op::OpenWindowOperation;
                         project_content::Bool = false,
                         recursion = nothing, ctx = nothing)
    w.title  = op.title
    w.x      = op.x
    w.y      = op.y
    w.width  = op.width
    w.height = op.height
    w.bg     = op.bg
    w.style  = op.style
    if project_content
        # Re-project the new content for the output side.
        content_iomap = projection_print(recursion, recursion, op.content, ctx)
        w.content = content_iomap.output
    else
        w.content = op.content
    end
end

# Apply Close: remove the matching window from both input and output.

function _apply_close!(iomap::WindowManagerProjectionIoMap, op::CloseWindowOperation)
    input = iomap.input
    output = iomap.output
    input isa ScreenDocument || return
    output isa ScreenDocument || return

    in_wins = input.windows
    out_wins = output.windows
    for i in 1:length(in_wins)
        existing = in_wins[i]
        existing isa WindowDocument || continue
        existing.id === op.id || continue
        deleteat!(in_wins, i)
        i <= length(out_wins) && deleteat!(out_wins, i)
        return
    end
end

# ── Reference mapping (passthrough) ──────────────────────────────────────

function map_reference_forward(::WindowManagerProjection, iomap::WindowManagerProjectionIoMap, reference)
    map_reference_forward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
end

function map_reference_backward(::WindowManagerProjection, iomap::WindowManagerProjectionIoMap, reference)
    map_reference_backward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
end

end # module
