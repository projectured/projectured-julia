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
    WindowManagingIoMap(p, input, Cell(@computation inner_iomap.output), inner_iomap)
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
    # A person resizes a placed window with a frame, so it also takes a fixed
    # placement at the place where it stands: a placement that reads the size would
    # move the window under the hand of the person.
    if window_input isa WindowInput && window_input.event isa WindowResize
        win = _find_window(iomap.input, window_input.window_id)
        win === nothing && return Intent(change.gesture, nothing)
        resize = ResizeWindowOperation(win, window_input.event.width, window_input.event.height)
        (is_window_placed(win) && has_window_frame(win)) || return Intent(change.gesture, resize)
        shown = _find_window(unwrap_cell(get_iomap_output(iomap)), window_input.window_id)
        shown === nothing && return Intent(change.gesture, resize)
        fixed = make_fixed_placement(shown.x, shown.y; minimum_size = shown.minimum_size,
                                     maximum_size = shown.maximum_size)
        return Intent(change.gesture,
                      CompoundOperation(Any[resize,
                                            ReplaceViewStateOperation(
                                                ReplaceReferencedValueOperation(win, "placement", fixed))]))
    end
    # The native window close button (SDL_WINDOWEVENT_CLOSE / web close) arrives
    # as a WindowClose carrying the window id. Resolve the window and
    # remove it from both input and output here — the same dual-mutation the
    # manager performs for a CloseWindowOperation bubbling up from below, so the
    # close is owned in one place rather than relying on evaluate_operation.
    if window_input isa WindowInput && window_input.event isa WindowClose
        win = _find_window(iomap.input, window_input.window_id)
        win === nothing && return Intent(change.gesture, nothing)
        given_back = _apply_close!(iomap, CloseWindowOperation(window_input.window_id))
        return Intent(change.gesture, given_back)
    end
    # Losing focus dismisses only a popup (`auto_dismiss`), so the pointer acting
    # elsewhere closes a dropdown/menu but never the default window or a tooltip.
    # A `:popup` never holds the focus, which stays in the window under it, so a
    # loss of focus of any other window closes every `:popup`. A closed window that
    # holds the selection gives it back.
    if window_input isa WindowInput && window_input.event isa WindowDefocus
        win = _find_window(iomap.input, window_input.window_id)
        given_back = if win !== nothing && win.auto_dismiss === true
            _apply_close!(iomap, CloseWindowOperation(window_input.window_id))
        else
            _join_window_answers(something(_close_popup_windows!(iomap; style = :popup), Any[]))
        end
        return Intent(change.gesture, given_back)
    end
    # A press in a window that is not a popup closes every popup, and the press
    # goes on to that window: a press on another menu name closes the open menu
    # and opens its own. The selection that a closed popup gives back comes first,
    # so a selection that the press makes wins.
    given_back = Any[]
    if window_input isa WindowInput && window_input.event isa MouseDown
        win = _find_window(iomap.input, window_input.window_id)
        (win !== nothing && win.auto_dismiss === true) ||
            (given_back = something(_close_popup_windows!(iomap), Any[]))
    end
    # A bare Escape closes the open popups and goes no further. The keyboard of a
    # `:popup` stays in the window under it, and there an `EscapeQuittingProjection`
    # quits on an Escape that no reader claims, so the answer is an operation that
    # does nothing, or the selection that a closed popup gives back.
    if window_input isa WindowInput && _is_bare_escape(window_input.event)
        closed = _close_popup_windows!(iomap)
        closed === nothing ||
            return Intent(change.gesture, something(_join_window_answers(closed), DoNothingOperation()))
    end

    inner = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    answer = _apply_window_ops(iomap, change, inner)
    isempty(given_back) ||
        (answer = Intent(answer.gesture, _join_window_answers(given_back, Any[answer.operation])))
    answer = Intent(answer.gesture, _take_pointer_shape(answer.operation, iomap.input))
    window_input isa WindowInput || return answer
    _keep_pointer_shape(iomap.input, window_input.event, answer)
end

# The answer with each `ChangeScreenPointerShapeOperation` in it, bare or marked as
# view state, made a write of `pointer_shape` of the input screen, which a history
# does not record.
_take_pointer_shape(operation, screen) = operation
_take_pointer_shape(operation::ChangeScreenPointerShapeOperation, screen) =
    _write_pointer_shape(screen, operation.shape)
_take_pointer_shape(operation::ReplaceViewStateOperation, screen) =
    get_wrapped_operation(operation) isa ChangeScreenPointerShapeOperation ?
        _take_pointer_shape(get_wrapped_operation(operation), screen) : operation
function _take_pointer_shape(operation::CompoundOperation, screen)
    members = Any[_take_pointer_shape(member, screen) for member in operation.operations]
    all(member === original for (member, original) in zip(members, operation.operations)) ?
        operation : CompoundOperation(members)
end

_write_pointer_shape(screen, shape) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(screen, "pointer_shape", shape))

# A shape that the screen keeps ends at a release, or at a move with no button
# held, which shows a release that the window did not get: a part that is gone
# before its drag ends never answers its `DragEnd`. The write comes first, so a
# shape that the answer itself says wins.
function _keep_pointer_shape(screen, event, answer::Intent)
    screen isa ScreenDocument && screen.pointer_shape !== nothing || return answer
    (event isa MouseUp || is_move_without_button(event)) || return answer
    clear = _write_pointer_shape(screen, nothing)
    operation = answer.operation
    Intent(answer.gesture, operation === nothing ? clear : CompoundOperation(Any[clear, operation]))
end

# Intercept window-management operations bubbling up from below and apply them
# (the manager mutates both the input screen and the mirrored output). A window
# op may be bundled with document edits in a `CompoundOperation` — e.g. picking a
# dropdown option writes the value AND closes the popup — so unpack it: apply the
# Open/Close ops here and pass any remaining ops upward for `evaluate_operation`.
#
# A close that gives the selection back puts that selection first, so a selection
# that the rest of the answer makes, such as the one of a press in another window or
# of a choice, comes after it and wins. An open that takes the selection puts the
# selection of the new window last.
function _apply_window_ops(iomap, change, inner)
    op = inner.operation
    operations = op isa CompoundOperation ? op.operations : Any[op]
    any(o -> o isa Union{OpenWindowOperation, CloseWindowOperation}, operations) || return inner
    given_back, rest, taken = Any[], Any[], Any[]
    for o in operations
        if o isa OpenWindowOperation
            selection = _apply_open!(iomap, o)
            selection === nothing || push!(taken, selection)
        elseif o isa CloseWindowOperation
            selection = _apply_close!(iomap, o)
            selection === nothing || push!(given_back, selection)
        else
            push!(rest, o)
        end
    end
    Intent(change.gesture, _join_window_answers(given_back, rest, taken))
end

# The operations in order, without the ones that are `nothing`, as one answer:
# `nothing` for none, one alone, or a compound.
function _join_window_answers(parts::Vector...)
    kept = Any[o for part in parts for o in part if o !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

read_intent(p::WindowManagingProjection, iomap::WindowManagingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# Apply Open: add a new window, or update an existing one with the same id, on the
# input screen only. `ScreenToScreen` mirrors the change into the output — it
# reconciles the output's windows against the input (so a new/removed window
# reflows), re-projects a window's content when it is replaced, and shares each
# window's metadata cells — so the manager never touches the output.

_apply_open!(iomap::WindowManagingIoMap, op::OpenWindowOperation) =
    _open_screen_window!(iomap.input, op)

# Answers the selection of the place that the window opens with, or `nothing`.
function _open_screen_window!(screen, op::OpenWindowOperation)
    screen isa ScreenDocument || return nothing
    op = _place_dialog_at_main_window(screen, op)

    # Existing window with this id → update in place. A window that a placement
    # places has a computed place in the output, and a window with no placement
    # shares its place with the output, so a window that changes between the two
    # is a new window in the same slot. A window that holds the selection already
    # keeps the selection that it gives back.
    in_wins = screen.windows
    for i in 1:length(in_wins)
        existing_in = in_wins[i]
        existing_in isa WindowDocument || continue
        existing_in.id === op.id || continue
        before = _holds_screen_selection(screen, i) ? existing_in.selection_before : copy_reference(get_selection(screen))
        if is_window_placed(existing_in) == (op.placement !== nothing)
            _update_window!(existing_in, op)
        else
            in_wins[i] = _make_opened_window(screen, op)
        end
        return _take_window_selection(in_wins[i], op, before)
    end

    # New window: construct and push; the inner stage projects the output side.
    before = copy_reference(get_selection(screen))
    push!(in_wins, Cell(_make_opened_window(screen, op)))
    _take_window_selection(in_wins[end], op, before)
end

# The selection of the place `op.selection` in the content of `window`, which the
# window keeps `before`, a copy of the selection of the screen, because the steps of
# a selection change in place, to give back; or `nothing`
# when the window opens with no selection.
function _take_window_selection(window::WindowDocument, op::OpenWindowOperation, before)
    op.selection === nothing && return nothing
    window.selection_before = before
    SelectDocumentOperation(window, concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                                                      op.selection))
end

# Whether the selection of `screen` is in its window `i`.
_holds_screen_selection(screen::ScreenDocument, i::Int) =
    _get_window_step_index(get_selection(screen), length(screen.windows)) == i

# A dialog that names no place of its own and that no window opened, as one that a
# callback opens, stands at the center of the first window of the screen, the main
# window.
function _place_dialog_at_main_window(screen::ScreenDocument, op::OpenWindowOperation)
    _is_unplaced_dialog(op) || return op
    isempty(screen.windows) && return op
    main = screen.windows[1]
    (main isa WindowDocument && main.id !== op.id) || return op
    _place_at_window_center(op, main.id)
end

_make_opened_window(screen::ScreenDocument, op::OpenWindowOperation) =
    WindowDocument(; id=op.id, title=op.title,
                     x=op.x, y=op.y,
                     width=op.width, height=op.height,
                     minimum_size=op.minimum_size, maximum_size=op.maximum_size,
                     bg=op.bg === nothing ? _get_screen_background(screen) : op.bg,
                     style=op.style,
                     auto_dismiss=op.auto_dismiss, modal=op.modal,
                     placement=op.placement,
                     content=op.content)

# The background of `screen` that a new window shares: the cell of the background
# of its first window, which the appearance computes, or the fixed default for a
# screen with no window.
function _get_screen_background(screen::ScreenDocument)
    windows = screen.windows
    isempty(windows) && return DEFAULT_BG
    first_window = windows[1]
    first_window isa WindowDocument ? getfield(first_window, :bg) : DEFAULT_BG
end

function _update_window!(w::WindowDocument, op::OpenWindowOperation)
    w.title  = op.title
    w.x      = op.x
    w.y      = op.y
    w.width  = op.width
    w.height = op.height
    w.minimum_size = op.minimum_size
    w.maximum_size = op.maximum_size
    op.bg === nothing || (w.bg = op.bg)
    w.style  = op.style
    w.auto_dismiss = op.auto_dismiss
    w.modal  = op.modal
    w.placement = op.placement
    w.content = op.content
end

# Apply Close: remove the matching window from the input; the inner stage's
# window reconcile drops it from the output.

_apply_close!(iomap::WindowManagingIoMap, op::CloseWindowOperation) =
    _close_screen_window!(iomap.input, op)

# Answers the selection that the window gives back, or `nothing`.
function _close_screen_window!(screen, op::CloseWindowOperation)
    screen isa ScreenDocument || return nothing

    in_wins = screen.windows
    for i in 1:length(in_wins)
        existing = in_wins[i]
        existing isa WindowDocument || continue
        existing.id === op.id || continue
        given_back = _give_back_window_selection(screen, i, existing)
        deleteat!(in_wins, i)
        return given_back
    end
    nothing
end

# The selection that window `i` gives back as it closes: the selection that the
# screen had before the window took it, while the window still holds the selection
# and that selection is still a place of the screen. `nothing` otherwise.
function _give_back_window_selection(screen::ScreenDocument, i::Int, window::WindowDocument)
    before = window.selection_before
    (before isa Reference && _holds_screen_selection(screen, i)) || return nothing
    _get_window_step_index(before, length(screen.windows)) == i && return nothing
    _is_screen_place(screen, before) || return nothing
    SelectDocumentOperation(screen, before)
end

# Whether `path` still names a place of `screen`. A caret at its end names a place
# in a text, which the resolver of a path does not read, so the path is read up to
# the node that holds the caret, as the write of a selection reads it.
function _is_screen_place(screen::ScreenDocument, path::Reference)
    steps = get_reference_steps(strip_reference_types(path))
    isempty(steps) && return true
    tail = steps[end]
    caret = hasproperty(tail, :start) && hasproperty(tail, :stop) && tail.start == tail.stop
    caret || return is_valid_reference(screen, strip_reference_types(path))
    is_valid_reference(screen, extend_reference(EmptyReference(), steps[1:(end - 1)]...))
end

# A window operation that reaches the editor applies to the screen that the
# editor's document wraps, as the window manager applies one that passes it. It
# comes from a wrapper outside the screen projection, such as the one that keeps
# the tooltip window, or from a verb, such as the one that opens a file dialog. The
# selection that the window takes or gives back is applied after it.
function evaluate_operation(editor, op::OpenWindowOperation)
    selection = _open_screen_window!(_find_editor_screen(editor), op)
    selection === nothing || evaluate_operation(editor, selection)
    nothing
end

function evaluate_operation(editor, op::CloseWindowOperation)
    selection = _close_screen_window!(_find_editor_screen(editor), op)
    selection === nothing || evaluate_operation(editor, selection)
    nothing
end
function evaluate_operation(editor, op::ChangeScreenPointerShapeOperation)
    screen = _find_editor_screen(editor)
    screen isa ScreenDocument && screen.pointer_shape !== op.shape && (screen.pointer_shape = op.shape)
    nothing
end

_find_editor_screen(editor) =
    hasproperty(editor, :document) ? get_wrapped_document(editor.document) : nothing

# Close every window that dismisses itself (`auto_dismiss`), or only those of
# `style` when it is given. Answers the selections that the closed windows give
# back, or `nothing` when no window closed.
function _close_popup_windows!(iomap::WindowManagingIoMap; style::Union{Symbol,Nothing} = nothing)
    input = iomap.input
    input isa ScreenDocument || return nothing
    ids = Symbol[w.id for w in input.windows
                 if w isa WindowDocument && w.auto_dismiss === true &&
                    (style === nothing || w.style === style)]
    isempty(ids) && return nothing
    Any[_apply_close!(iomap, CloseWindowOperation(id)) for id in ids]
end

_is_bare_escape(event) = false
_is_bare_escape(event::KeyDown) =
    event.key === :escape &&
    !(event.modifiers.ctrl || event.modifiers.shift || event.modifiers.alt || event.modifiers.meta)

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
