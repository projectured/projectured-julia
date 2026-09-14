# Fragment of `ScreenModule`.
#
# A higher-order projection that wraps the `ScreenDocument` case of the
# type dispatcher in the main pipeline. Its printer is a passthrough to
# the inner projection (typically `ScreenToScreen`). Its reader intercepts
# `OpenWindowOperation` and `CloseWindowOperation` bubbling up from below
# and applies them to the input `ScreenDocument`; the inner stage mirrors
# the change into the projected output reactively, so the next frame renders it.
#
# Together with `TooltipDecoratorProjection`, this turns "show a tooltip"
# into "request a window via an operation; let the manager apply it" —
# the same input → operation → input → printer loop every other state
# change uses.
#
# The manager mutates only the *input* screen. `ScreenToScreen` reconciles
# the output's windows by identity (a push/remove on the input's `windows`
# cell reflows the output), re-projects a replaced window's content, and
# shares each window's metadata cells — so the output tracks the input with
# no explicit output mutation (PAR-STABLE-IOMAP-IDENTITY).
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

@iomap struct WindowManagingIoMap
    projection::WindowManagingProjection
    input::Any
    output::Any
    inner_iomap::Any
end

# ── Printer (passthrough) ────────────────────────────────────────────────

function print_document(p::WindowManagingProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    WindowManagingIoMap(p, input, inner_iomap.output, inner_iomap)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::WindowManagingProjection, recursion, change::Intent, iomap::WindowManagingIoMap)
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

read_intent(p::WindowManagingProjection, iomap::WindowManagingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Apply Open: add a new window, or update an existing one with the same id, on the
# input screen only. `ScreenToScreen` mirrors the change into the output — it
# reconciles the output's windows against the input (so a new/removed window
# reflows), re-projects a window's content when it is replaced, and shares each
# window's metadata cells — so the manager never touches the output.

function _apply_open!(iomap::WindowManagingIoMap, op::OpenWindowOperation)
    input = iomap.input
    input isa ScreenDocument || return

    # Existing window with this id → update in place.
    in_wins = input.windows
    for i in 1:length(in_wins)
        existing_in = in_wins[i]
        existing_in isa WindowDocument || continue
        existing_in.id === op.id || continue
        _update_window!(existing_in, op)
        return
    end

    # New window: construct and push; the inner stage projects the output side.
    new_in = WindowDocument(; id=op.id, title=op.title,
                              x=op.x, y=op.y,
                              width=op.width, height=op.height,
                              bg=op.bg, style=op.style,
                              auto_dismiss=op.auto_dismiss, modal=op.modal,
                              content=op.content)
    push!(in_wins, Cell(new_in))
end

function _update_window!(w::WindowDocument, op::OpenWindowOperation)
    w.title  = op.title
    w.x      = op.x
    w.y      = op.y
    w.width  = op.width
    w.height = op.height
    w.bg     = op.bg
    w.style  = op.style
    w.auto_dismiss = op.auto_dismiss
    w.modal  = op.modal
    w.content = op.content
end

# Apply Close: remove the matching window from the input; the inner stage's
# window reconcile drops it from the output.

function _apply_close!(iomap::WindowManagingIoMap, op::CloseWindowOperation)
    input = iomap.input
    input isa ScreenDocument || return

    in_wins = input.windows
    for i in 1:length(in_wins)
        existing = in_wins[i]
        existing isa WindowDocument || continue
        existing.id === op.id || continue
        deleteat!(in_wins, i)
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

function map_reference_forward(::WindowManagingProjection, iomap::WindowManagingIoMap, reference)
    map_reference_forward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
end

function map_reference_backward(::WindowManagingProjection, iomap::WindowManagingIoMap, reference)
    map_reference_backward(iomap.inner_iomap.projection, iomap.inner_iomap, reference)
end
