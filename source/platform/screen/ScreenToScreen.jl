# Fragment of `ScreenModule`.
#
# The screen-domain projection. `ScreenToScreen` owns *all* structural knowledge
# of the screen domain — `ScreenDocument` and `WindowDocument` — so that the
# domain-independent `CopyingProjection` need not. It:
#
# - copies the `ScreenDocument` shell, recursing each window through itself;
# - copies a `WindowDocument`'s metadata verbatim and recurses its `content`
#   through the outer pipeline (`recursion`), seeding the window's
#   `width`/`height` as the available layout extent so layout-aware content
#   sizes itself to the window;
# - on the reader side, routes an `WindowInput` to the matching window by
#   `window_id`, hands the inner event to that window's `content` reader, and
#   prepends the `windows[i].content` steps to the operation that comes back.
#
# `ScreenToScreen` is normally the `inner` of a `WindowManagingProjection`, which
# layers window-management *operations* (open/close/resize) on top. The two are
# separate concerns: structural projection here, operation interception there.
struct ScreenToScreen <: Projection end

# ── IoMaps ──────────────────────────────────────────────────────────────────

@iomap struct ScreenToScreenIoMap
    projection::ScreenToScreen
    input::Any              # ScreenDocument
    output::Any             # ScreenDocument
    window_iomaps::Cell     # Vector of ScreenWindowIoMap, one per window
end

@iomap struct ScreenWindowIoMap
    projection::ScreenToScreen
    input::Any              # WindowDocument
    output::Any             # WindowDocument
    content_iomap::Any      # iomap of the recursively-projected content
end

# ── Printer ─────────────────────────────────────────────────────────────────

function print_document(p::ScreenToScreen, recursion, input::ScreenDocument, ctx)
    iomap_cell = Cell(nothing)
    # Reconcile windows by identity so opening/closing a sibling reuses the
    # surviving windows' iomaps (PAR-STABLE-IOMAP-IDENTITY).
    window_iomaps = reconcile_child_iomaps(
        () -> input.windows,
        (i, x) -> print_document(p, recursion, x,
            make_child_context(ctx, FieldReferenceStep("windows"), ElementReferenceStep(i))))
    out_windows = Cell(@computation CellVector(Cell[Cell(im.output) for im in window_iomaps[]]))
    paths = make_output_path_cells(input, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)
    output = ScreenDocument(out_windows, paths.selection, paths.mouse_target)
    iomap = ScreenToScreenIoMap(p, input, output, window_iomaps)
    iomap_cell[] = iomap
    iomap
end

function print_document(p::ScreenToScreen, recursion, input::WindowDocument, ctx)
    # Seed the window's pixel size as the available layout extent for its
    # content, so split/tabbed/scroll panes size to the window.
    #
    # A window that fits its content is offered its **maximum**, and always that:
    # the backend gives such a window the extent of what it printed, and an offer
    # that followed that size would chase it. So a text wraps at the maximum
    # width, and the window ends as wide as the text needed.
    maximum_size = getfield(input, :maximum_size)
    offer_width = Cell(@computation((m = maximum_size[];
                                     m[1] > 0 ? m[1] : getfield(input, :width)[])))
    offer_height = Cell(@computation((m = maximum_size[];
                                      m[2] > 0 ? m[2] : getfield(input, :height)[])))
    content_ctx = with_exact_size(make_child_context(ctx, FieldReferenceStep("content"));
                                  width=offer_width, height=offer_height)
    # Reconcile the content by identity so replacing a same-id window's content
    # (a hover probe following the cursor, a re-opened tooltip) re-projects it
    # reactively; a same object mutated in place reuses the iomap and re-derives
    # through its own cells. This is what lets the window manager mutate only the
    # input screen and rely on this stage to mirror the output (PAR-STABLE-IOMAP-IDENTITY).
    content_iomap = reconcile_child_iomap(() -> input.content,
                                          c -> print_child(recursion, c, content_ctx))
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(input, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)
    # Metadata cells are shared verbatim (non-document fields), so a metadata edit on
    # the input window is reflected here through the shared cell; only the content
    # and the paths (the selection, the mouse target) are produced fresh.
    # By keyword, and not by position: a field added to `WindowDocument` shifts
    # a positional list, and `x`, `y`, `width` and `height` are all `Int`, so a
    # shifted argument would mis-size or misplace a window with no error.
    output = WindowDocument(; id = getfield(input, :id), title = getfield(input, :title),
                            x = getfield(input, :x), y = getfield(input, :y),
                            width = getfield(input, :width), height = getfield(input, :height),
                            minimum_size = getfield(input, :minimum_size),
                            maximum_size = getfield(input, :maximum_size),
                            bg = getfield(input, :bg), style = getfield(input, :style),
                            auto_dismiss = getfield(input, :auto_dismiss),
                            modal = getfield(input, :modal),
                            content = Cell(@computation content_iomap[].output),
                            paths...)
    iomap = ScreenWindowIoMap(p, input, output, content_iomap)
    iomap_cell[] = iomap
    iomap
end

# ── Reference mapping (order- and structure-preserving) ───────────────────────

_wval(v) = Int(v isa Cell ? v[] : v)

# Screen level: peel `windows` + `[i]`, delegate the tail to window `i`'s iomap,
# and re-root what it answers at `windows[i]`. A point with no window names no
# part: a screen point reaches a window only through the id of its window.
function _map_screen(fn, iomap::ScreenToScreenIoMap, reference)
    reference isa ConcreteReference || return (reference isa Reference ? reference : nothing)
    h = get_reference_head(reference)
    (h isa FieldReferenceStep && h.name == "windows") || return reference
    rest1 = get_reference_tail(reference)
    rest1 isa ConcreteReference || return reference
    elem = get_reference_head(rest1)
    elem isa RangeReferenceStep || return reference
    i = elem.stop                       # ElementReferenceStep(i) == RangeReferenceStep(i-1, i)
    ims = iomap.window_iomaps
    (i < 1 || i > length(ims)) && return nothing
    wim = ims[i]
    mapped = fn(wim.projection, wim, get_reference_tail(rest1))
    mapped === nothing && return nothing
    ConcreteReference(FieldReferenceStep("windows"), ConcreteReference(elem, mapped))
end

# Window level: peel `content`, delegate the tail to the content iomap, and re-root
# what it answers at `content`.
function _map_window(fn, iomap::ScreenWindowIoMap, reference)
    reference isa ConcreteReference || return (reference isa Reference ? reference : nothing)
    h = get_reference_head(reference)
    (h isa FieldReferenceStep && h.name == "content") || return reference  # metadata: identity
    cim = iomap.content_iomap
    mapped = fn(cim.projection, cim, get_reference_tail(reference))
    mapped === nothing && return nothing
    ConcreteReference(FieldReferenceStep("content"), mapped)
end

map_reference_forward(::ScreenToScreen, iomap::ScreenToScreenIoMap, reference) =
    _map_screen(map_reference_forward, iomap, reference)
map_reference_backward(::ScreenToScreen, iomap::ScreenToScreenIoMap, reference) =
    _map_screen(map_reference_backward, iomap, reference)
map_reference_forward(::ScreenToScreen, iomap::ScreenWindowIoMap, reference) =
    _map_window(map_reference_forward, iomap, reference)
map_reference_backward(::ScreenToScreen, iomap::ScreenWindowIoMap, reference) =
    _map_window(map_reference_backward, iomap, _move_content_point(iomap, reference))

# The place of the root canvas of the content of a window, `(x, y)` in the frame
# of the window. A widget reads a point in the frame of its own canvas, so the
# window takes this place off a point before the content reads it, as a container
# takes off the place of its child.
function _get_content_place(iomap::ScreenWindowIoMap)
    output = unwrap_cell(get_iomap_output(iomap.content_iomap))
    output isa GraphicsDocument && hasproperty(output, :x) && hasproperty(output, :y) || return (0, 0)
    (_wval(getfield(output, :x)), _wval(getfield(output, :y)))
end

# Whether the point of `event`, in the frame of the root canvas of the content, is
# on that canvas. A canvas with no size leaves the decision to the content.
function _is_event_on_content(iomap::ScreenWindowIoMap, event)
    output = unwrap_cell(get_iomap_output(iomap.content_iomap))
    (output isa GraphicsDocument && hasproperty(output, :w) && hasproperty(output, :h)) ||
        return true
    width, height = _wval(getfield(output, :w)), _wval(getfield(output, :h))
    (width <= 0 || height <= 0) && return true
    0 <= event.x < width && 0 <= event.y < height
end

# `content` followed by a point of the window, with the point in the frame of the
# root canvas of the content.
function _move_content_point(iomap::ScreenWindowIoMap, reference)
    reference isa ConcreteReference || return reference
    tail = get_reference_tail(reference)
    (tail isa ConcreteReference && get_reference_head(tail) isa PointReferenceStep &&
     get_reference_tail(tail) isa EmptyReference) || return reference
    x, y = _get_content_place(iomap)
    (x == 0 && y == 0) && return reference
    point = get_reference_head(tail)
    ConcreteReference(get_reference_head(reference),
        ConcreteReference(PointReferenceStep(point.x - x, point.y - y), EmptyReference()))
end

# ── Reader ────────────────────────────────────────────────────────────────────
# Route an WindowInput to the matching window's content, then prepend the
# steps that lead from the screen root to that content so the operation's path
# is rooted at the ScreenDocument.

function read_intent(p::ScreenToScreen, recursion, change::Intent, iomap::ScreenToScreenIoMap)
    # An operation with a route goes to the window its route names.
    if change.route !== nothing
        for (i, wim) in enumerate(iomap.window_iomaps)
            steps = (FieldReferenceStep("windows"), ElementReferenceStep(i))
            routed = follow_intent_route(change, steps...)
            routed === nothing && continue
            inner = read_routed_intent(wim.projection, recursion, routed, wim)
            return Intent(change.gesture, _prefix_op(inner.operation, steps))
        end
        return Intent(change.gesture, nothing)
    end
    window_input = change.gesture
    if window_input isa WindowInput
        event = window_input.event
        index = _find_window_index(iomap, window_input.window_id)
        op = nothing
        if index != 0
            wim = iomap.window_iomaps[index]
            op = read_intent(wim.projection, recursion, change, wim).operation
            # A window that names no part under the pointer is that part itself.
            is_move_without_button(event) && (op = add_mouse_target(op))
            op = _prefix_op(op, (FieldReferenceStep("windows"), ElementReferenceStep(index)))
        end
        if is_move_without_button(event) || event isa WindowLeave
            op = _read_window_leave(recursion, iomap, index, event, op)
        end
        return Intent(change.gesture, op)
    end
    # Non-window-input change (operation threaded up, or coordless gesture):
    # fall back to the generic per-reference mapping (selection/edit retarget).
    payload = change.operation === nothing ? change.gesture : change.operation
    return Intent(change.gesture, read_intent(p, iomap, payload))
end

# The 1-based index of the window whose id is `id`, or 0.
function _find_window_index(iomap::ScreenToScreenIoMap, id)
    for (index, wim) in enumerate(iomap.window_iomaps)
        window = wim.input
        window isa WindowDocument && window.id === id && return index
    end
    0
end

# The pointer leaves the window that the screen's mouse target names, when a move
# comes in window `index`, another window, or when that window reports the leave
# of the pointer. That window gets a move to a point off it, `(-1, -1)`: the backend
# does not say where the pointer is, and a point off the window reaches only the
# parts that the pointer leaves. Its answer comes before `answer`, the answer of the
# window that the event came in. After a leave the pointer is over no window, and
# the screen itself is the part under it.
function _read_window_leave(recursion, iomap::ScreenToScreenIoMap, index::Int, event, answer)
    target = get_mouse_target(iomap.input)
    old = _get_window_step_index(target, length(iomap.window_iomaps))
    if event isa WindowLeave
        (old != 0 && old == index) || return answer
    else
        (old == 0 || old == index) && return answer
    end
    wim = iomap.window_iomaps[old]
    modifiers = event isa MouseMove ? event.modifiers : ModifierKeys()
    move = MouseMove(-1, -1, MouseButtons(), modifiers; time = get_event_time(event))
    left = read_intent(wim.projection, recursion, Intent(WindowInput(wim.input.id, move), nothing),
                       wim).operation
    left = _prefix_op(left, (FieldReferenceStep("windows"), ElementReferenceStep(old)))
    event isa WindowLeave || return join_move_answers(left, answer)
    join_move_answers(left, answer, ReplaceMouseTargetOperation(EmptyReference()))
end

# The window `i` of a path that begins `windows[i]`, or 0.
function _get_window_step_index(path, n::Int)
    path isa ConcreteReference || return 0
    head = get_reference_head(path)
    (head isa FieldReferenceStep && head.name == "windows") || return 0
    rest = get_reference_tail(path)
    (rest isa ConcreteReference && get_reference_head(rest) isa RangeReferenceStep) || return 0
    index = get_reference_head(rest).stop
    1 <= index <= n ? index : 0
end

function read_intent(p::ScreenToScreen, recursion, change::Intent, iomap::ScreenWindowIoMap)
    if change.route !== nothing
        steps = (FieldReferenceStep("content"),)
        routed = follow_intent_route(change, steps...)
        routed === nothing && return Intent(change.gesture, nothing)
        cim = iomap.content_iomap
        inner = read_routed_intent(cim.projection, recursion, routed, cim)
        return Intent(change.gesture, _open_popup_windows(_prefix_op(inner.operation, steps), iomap.input))
    end
    window_input = change.gesture
    if window_input isa WindowInput
        cim = iomap.content_iomap
        x, y = _get_content_place(iomap)
        event = window_input.event
        event isa Union{Event, Gesture} && (event = shift_event_position(event, -x, -y))
        inner = read_intent(cim.projection, recursion, Intent(event, nothing), cim)
        operation = inner.operation
        # When the content names no part under the pointer and the point is on it,
        # its own backward map of the point names the part.
        if is_move_without_button(event) && _is_event_on_content(iomap, event) &&
           !has_mouse_target(operation)
            operation = add_mouse_target(operation, compute_part_at_point(cim, event.x, event.y))
        end
        op = _prefix_op(shift_operation_position(operation, x, y), (FieldReferenceStep("content"),))
        return Intent(change.gesture, _open_popup_windows(op, iomap.input))
    end
    payload = change.operation === nothing ? change.gesture : change.operation
    return Intent(change.gesture, read_intent(p, iomap, payload))
end

# A popup that the content of a window answers is in the frame of the window. It
# opens as a `:popup` window of its own, which never takes the focus, at the
# screen origin of this window plus its position, and it takes the extent of
# what it draws, up to the size of the popup. The mark that kept it out of a history is not needed above the
# window, so a popup inside `ReplaceViewStateOperation` opens bare, and the
# window manager finds it. Any other operation that holds a point, such as a
# tooltip, has it moved into the screen here too (`map_operation_position`); an
# answer to a routed gesture holds a point in the frame of the window, because a
# route moves no point.
_open_popup_windows(op, window::WindowDocument) =
    _open_popup_window(op, _wval(getfield(window, :x)), _wval(getfield(window, :y)))
_open_popup_windows(op, window) = op

_open_popup_window(op, x, y) = map_operation_position(op, (px, py) -> (px + x, py + y))
_open_popup_window(op::OpenPopupOperation, x, y) =
    OpenWindowOperation(; id = op.id, x = x + op.x, y = y + op.y,
                          width = op.width, height = op.height,
                          maximum_size = (op.width, op.height), style = :popup,
                          auto_dismiss = op.auto_dismiss, content = op.content)
function _open_popup_window(op::CompoundOperation, x, y)
    members = Any[_open_popup_window(member, x, y) for member in op.operations]
    all(member === original for (member, original) in zip(members, op.operations)) ?
        op : CompoundOperation(members)
end
function _open_popup_window(op::WrappingOperation, x, y)
    inner = get_wrapped_operation(op)
    opened = _open_popup_window(inner, x, y)
    opened === inner && return op
    (op isa ReplaceViewStateOperation && opened isa OpenWindowOperation) && return opened
    rewrap_operation(op, opened)
end

# Prepend `steps` to the reference path inside `op` (if it carries one), rooting a
# child's operation at the ScreenDocument. Every path-carrying operation type must
# be handled here; an unhandled type would fall through unchanged and apply its
# child-relative path against the screen root (e.g. ReplaceDocumentOperation's
# `.slice` from the clipboard projection).
function _prefix_op(op, steps::Tuple)
    op === nothing && return nothing
    if op isa ReplaceStringRangeOperation
        return ReplaceStringRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplaceNumberRangeOperation
        return ReplaceNumberRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplacePathOperation
        return make_path_operation(op, _prepend(steps, get_operation_path(op)))
    elseif op isa ReplaceReferencedValueOperation
        return op.document === nothing ?
            ReplaceReferencedValueOperation(nothing, _prepend(steps, op.reference), op.value) : op
    elseif op isa CompoundOperation
        return CompoundOperation(Any[_prefix_op(o, steps) for o in op.operations])
    elseif op isa WrappingOperation
        return rewrap_operation(op, _prefix_op(get_wrapped_operation(op), steps))
    else
        return reroot_operation(op, steps)
    end
end

function _prepend(steps::Tuple, path::Reference)
    result = path
    for step in reverse(steps)
        result = ConcreteReference(step, result)
    end
    result
end
