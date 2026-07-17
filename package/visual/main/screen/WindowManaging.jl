"""
    WindowManagingProjectionModule

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
module WindowManagingProjectionModule

import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..IoMapApiModule: IoMap
import ..CellModule: Cell
import ..ScreenDocumentModule: ScreenDocument, WindowDocument, OpenWindowOperation, CloseWindowOperation, ResizeWindowOperation
import ..EventModule: WindowResize, WindowClose, WindowDefocus
import ..EventModule: WindowInput
import ..OperationModule: CompoundOperation

export WindowManagingProjection, WindowManagingProjectionIoMap

"""
    WindowManagingProjection(; inner)

Wraps `inner` (a projection over `ScreenDocument`, typically
`CopyingProjection`) and intercepts window-management operations on
the reader side.
"""
struct WindowManagingProjection <: Projection
    inner::Any
end

WindowManagingProjection(; inner) = WindowManagingProjection(inner)

struct WindowManagingProjectionIoMap <: IoMap
    projection::WindowManagingProjection
    input::Any
    output::Any
    inner_iomap::Any
    recursion::Any
    ctx::Any
end

# ── Printer (passthrough; remembers recursion + ctx for the reader) ──────

function print_document(p::WindowManagingProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    WindowManagingProjectionIoMap(p, input, inner_iomap.output, inner_iomap, recursion, ctx)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::WindowManagingProjection, recursion, change::Intent, iomap::WindowManagingProjectionIoMap)
    window_input = change.gesture
    # Modality: while a modal window is open, only it receives input. Drop any
    # window input routed to a different window — base content gets no events, with no
    # per-widget input swallowing (this reuses the existing window_id routing). A
    # modal window is dismissed by an explicit choice (Esc / button / backdrop),
    # never by focus-lost, so it is opened with auto_dismiss=false.
    if window_input isa WindowInput
        modal = _modal_window(iomap.input)
        (modal !== nothing && window_input.window_id !== modal.id) && return Intent(change.gesture, nothing)
    end
    # A window resize is a window-management concern owned here: resolve the
    # window by id (no coordinate mapping needed) and emit a
    # ResizeWindowOperation, before the inner copier ever sees the window input.
    if window_input isa WindowInput && window_input.event isa WindowResize
        win = _find_window(iomap.input, window_input.window_id)
        win === nothing && return Intent(change.gesture, nothing)
        return Intent(change.gesture,
                      ResizeWindowOperation(win, window_input.event.width, window_input.event.height))
    end
    # The native window close button (SDL_WINDOWEVENT_CLOSE / web close) arrives
    # as a WindowClose carrying the window id. Resolve the window and
    # remove it from both input and output here — the same dual-mutation the
    # manager performs for a CloseWindowOperation bubbling up from below, so the
    # close is owned in one place rather than relying on evaluate_operation.
    if window_input isa WindowInput && window_input.event isa WindowClose
        win = _find_window(iomap.input, window_input.window_id)
        win === nothing && return Intent(change.gesture, nothing)
        _apply_close!(iomap, CloseWindowOperation(window_input.window_id))
        return Intent(change.gesture, nothing)
    end
    # Losing focus dismisses only a popup (`auto_dismiss`), so the pointer acting
    # elsewhere closes a dropdown/menu but never the default window or a tooltip.
    if window_input isa WindowInput && window_input.event isa WindowDefocus
        win = _find_window(iomap.input, window_input.window_id)
        (win !== nothing && win.auto_dismiss === true) || return Intent(change.gesture, nothing)
        _apply_close!(iomap, CloseWindowOperation(window_input.window_id))
        return Intent(change.gesture, nothing)
    end

    inner = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    return _apply_window_ops(iomap, change, inner)
end

# Intercept window-management operations bubbling up from below and apply them
# (the manager mutates both the input screen and the mirrored output). A window
# op may be bundled with document edits in a `CompoundOperation` — e.g. picking a
# dropdown option writes the value AND closes the popup — so unpack it: apply the
# Open/Close ops here and pass any remaining ops upward for `evaluate_operation`.
function _apply_window_ops(iomap, change, inner)
    op = inner.operation
    if op isa OpenWindowOperation
        _apply_open!(iomap, op)
        return Intent(change.gesture, nothing)
    elseif op isa CloseWindowOperation
        _apply_close!(iomap, op)
        return Intent(change.gesture, nothing)
    elseif op isa CompoundOperation
        rest = Any[]
        for o in op.operations
            if o isa OpenWindowOperation
                _apply_open!(iomap, o)
            elseif o isa CloseWindowOperation
                _apply_close!(iomap, o)
            else
                push!(rest, o)
            end
        end
        isempty(rest) && return Intent(change.gesture, nothing)
        length(rest) == 1 && return Intent(change.gesture, rest[1])
        return Intent(change.gesture, CompoundOperation(rest))
    else
        return inner
    end
end

read_intent(p::WindowManagingProjection, iomap::WindowManagingProjectionIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Apply Open: add a new window (or update an existing one with the same
# id) on both the input and the output. The output side requires
# projecting the new WindowDocument through the same recursion that
# produced the rest of the output.

function _apply_open!(iomap::WindowManagingProjectionIoMap, op::OpenWindowOperation)
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
                              auto_dismiss=op.auto_dismiss, modal=op.modal,
                              content=op.content)
    new_iomap = print_child(iomap.recursion, new_in, iomap.ctx)
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
    w.auto_dismiss = op.auto_dismiss
    w.modal  = op.modal
    if project_content
        # Re-project the new content for the output side.
        content_iomap = print_child(recursion, op.content, ctx)
        w.content = content_iomap.output
    else
        w.content = op.content
    end
end

# Apply Close: remove the matching window from both input and output.

function _apply_close!(iomap::WindowManagingProjectionIoMap, op::CloseWindowOperation)
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

# Find the WindowDocument with the given id on the manager's input screen.
function _find_window(screen, id::Symbol)
    screen isa ScreenDocument || return nothing
    for w in screen.windows
        w isa WindowDocument && w.id === id && return w
    end
    nothing
end

# The open modal window, if any (at most one is expected). While it is open the
# reader routes input only to it.
function _modal_window(screen)
    screen isa ScreenDocument || return nothing
    for w in screen.windows
        w isa WindowDocument && w.modal === true && return w
    end
    nothing
end

# ── Reference mapping (passthrough) ──────────────────────────────────────

function map_reference_forward(::WindowManagingProjection, iomap::WindowManagingProjectionIoMap, reference)
    map_reference_forward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
end

function map_reference_backward(::WindowManagingProjection, iomap::WindowManagingProjectionIoMap, reference)
    map_reference_backward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
end

end # module
