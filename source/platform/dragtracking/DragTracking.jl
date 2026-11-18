# Fragment of `DragTrackingModule` — the projection that keeps the part whose drag
# is on, and gives that part the parts of its drag.

"""
    DragTrackingProjection(; inner, find_window = nothing)

Show the content of a [`DragTrackingState`](@ref) through `inner`, and keep the
drag that a part of the content starts.

A part starts its drag with a `StartDragOperation` in its answer. The projection
takes that operation out of the answer, and keeps its path and the dragged thing
in the state. While the drag is on, each input of a window goes on to the content
by position, as always, so the part under the pointer lights. The projection also
sends the part of the drag by the kept path, with the point in the frame of that
part:

- a move with a button held gives `DragMove`;
- the release gives `DragEnd`, and the drag ends;
- Escape, the loss of the focus of a window, and a move with no button held, which
  shows a release that the window did not get, give `DragCancel`, and the drag
  ends. Escape goes no further.

A click that the gesture tracker recognizes while the drag is on goes nowhere.

**A global drag** carries a thing, `dragged`, to a part that takes it. Its moves and
its release also go by position to the window under the pointer, as
`DragOver(x, y, dragged)` and `DragDrop(x, y, dragged)`, with the point in the frame
of that window. When the pointer goes to another window or outside, and when the
drag ends with no drop, the window that got the last `DragOver` gets
`DragOver(-1, -1, dragged)`. `DragMove` and `DragEnd` say with `outside` whether the
pointer is outside every window.

`find_window(content, window_id, x, y)` finds the window under the point `(x, y)`
of the window `window_id`, and answers `(id, x, y)`, the window and the point in its
frame, or `nothing` outside every window. The screen gives it, because only the
screen knows the places of its windows. With no `find_window`, the pointer is
always in the window of the input, at its point.
"""
struct DragTrackingProjection <: Projection
    inner::Projection
    find_window::Any
end

DragTrackingProjection(; inner::Projection, find_window = nothing) =
    DragTrackingProjection(inner, find_window)
DragTrackingProjection(inner::Projection) = DragTrackingProjection(inner, nothing)

# `output` forwards the output of the content reactively, so the IoMap keeps its
# identity while the content re-derives, and a swap of the content rebuilds the
# child.
@iomap struct DragTrackingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

get_child_iomaps(iomap::DragTrackingIoMap) = Any[iomap.child_iomap]

# ── Printer (transparent) ─────────────────────────────────────────────────

function print_document(p::DragTrackingProjection, recursion, input::DragTrackingState, ctx)
    child = make_reconciled_child_iomap_cell(() -> input.content,
                                  content -> print_document(p.inner, recursion, content, ctx))
    DragTrackingIoMap(p, input, Cell(@computation child[].output), child)
end

# ── Reader ────────────────────────────────────────────────────────────────

function read_intent(p::DragTrackingProjection, recursion, change::Intent,
                     iomap::DragTrackingIoMap)
    change.route === nothing || return read_routed_child(recursion, change, iomap)
    input = change.gesture
    state = iomap.input
    path = state.drag_path
    if path isa Reference && input isa WindowInput
        event = input.event
        part = gesture -> _read_drag_part(p, recursion, iomap, path,
                                          WindowInput(input.window_id, gesture))
        content = () -> _drop_drag_start(_read_content(p, recursion, change, iomap))
        if event isa MouseClick
            return Intent(input, nothing)
        elseif is_move_without_button(event) || event isa WindowDefocus
            time = get_event_time(event)
            return Intent(input, _join_operations(part(DragCancel(; time)),
                                                  _leave_drop_window(p, recursion, iomap, time),
                                                  _end_drag(state), content()))
        elseif event isa MouseMove
            found = _find_drop_window(p, state, input.window_id, event.x, event.y)
            # The move goes to the window under the pointer first, so the parts there
            # light and the parts that the pointer left hear it, then the parts of
            # the drag read their gestures.
            return Intent(input, _join_operations(
                _drop_drag_start(_read_content(p, recursion, _move_to_window(change, found), iomap)),
                _read_drag_over(p, recursion, iomap, found, event.time),
                part(DragMove(event.x, event.y, event.modifiers; time = event.time,
                              outside = _is_outside(state, found)))))
        elseif event isa MouseUp
            found = _find_drop_window(p, state, input.window_id, event.x, event.y)
            return Intent(input, _join_operations(
                _read_drag_drop(p, recursion, iomap, found, event),
                part(DragEnd(event.x, event.y, event.modifiers; time = event.time,
                             outside = _is_outside(state, found))),
                _end_drag(state), content()))
        elseif _is_bare_escape(event)
            return Intent(input, _join_operations(part(DragCancel(; time = event.time)),
                                                  _leave_drop_window(p, recursion, iomap, event.time),
                                                  _end_drag(state)))
        end
    end
    answer = _read_content(p, recursion, change, iomap)
    start, _ = _split_drag_start(answer)
    Intent(input, _join_operations(_take_drag_start(state, answer),
                                   _read_start_over(p, recursion, iomap, input, start)))
end

# The answer of the content to `change`, as an operation from the state.
function _read_content(p::DragTrackingProjection, recursion, change::Intent,
                       iomap::DragTrackingIoMap)
    read_child_intent(p, recursion, change, iomap, iomap.child_iomap, (FieldReferenceStep("content"),);
                      read_child = (_, r, c, child) -> read_routed_intent(p.inner, r, c, child)).operation
end

# The answer of the part at `path` of the content to `gesture`, a part of its
# drag, which goes to the part by the path, as an operation from the state. The
# route carries the type of each node of the content as it is now, because a view
# on the way checks them when it maps the route forward.
function _read_drag_part(p::DragTrackingProjection, recursion, iomap::DragTrackingIoMap,
                         path::Reference, gesture)
    route = annotate_reference_types(iomap.input.content, path)
    answer = read_intent(p.inner, recursion, Intent(gesture, nothing, "", "", route),
                         iomap.child_iomap)
    operation = answer isa Intent ? answer.operation : answer
    reroot_operation(operation, (FieldReferenceStep("content"),))
end

# ── The window under the pointer of a global drag ─────────────────────────

# The window under the point `(x, y)` of the window `window_id`, with the point in
# its frame, as `(id, x, y)`, or `nothing` outside every window. A local drag
# carries nothing and goes to no window. With no `find_window`, the pointer is in
# the window of the input.
function _find_drop_window(p::DragTrackingProjection, state::DragTrackingState,
                           window_id, x::Integer, y::Integer)
    state.dragged === nothing && return nothing
    p.find_window === nothing && return (window_id, Int(x), Int(y))
    p.find_window(state.content, window_id, Int(x), Int(y))
end

# `change`, a move of the pointer, in the window under the pointer that `found`
# names, at the point in its frame: a global drag keeps the moves in the window of
# its press, wherever the pointer is. With no window found, the move stays where it
# came, at a point off that window.
function _move_to_window(change::Intent, found)
    input = change.gesture
    (found === nothing || found[1] == input.window_id) && return change
    event = input.event
    moved = MouseMove(found[2], found[3], event.buttons, event.modifiers; time = event.time)
    Intent(WindowInput(found[1], moved), change.operation, change.description, change.domain, change.route)
end

# Whether the pointer of the drag of `state` is outside every window: only a global
# drag looks for a window, so a local drag is never outside.
_is_outside(state::DragTrackingState, found) = state.dragged !== nothing && found === nothing

# The answer of the window `found` to a gesture there, by position, as an
# operation from the state.
function _read_window_gesture(p::DragTrackingProjection, recursion, iomap::DragTrackingIoMap,
                              window_id, gesture)
    answer = _read_content(p, recursion, Intent(WindowInput(window_id, gesture)), iomap)
    _drop_drag_start(answer)
end

# The move that starts a global drag: the window under the pointer gets `DragOver`
# at once, so the part that takes the thing shows where it would land from the
# first move of the drag. `start` is the `StartDragOperation` that the state keeps,
# or `nothing`.
function _read_start_over(p::DragTrackingProjection, recursion, iomap::DragTrackingIoMap,
                          input, start)
    (input isa WindowInput && input.event isa MouseMove) || return nothing
    start === nothing && return nothing
    dragged = start.dragged
    dragged === nothing && return nothing
    event = input.event
    found = p.find_window === nothing ? (input.window_id, event.x, event.y) :
            p.find_window(iomap.input.content, input.window_id, event.x, event.y)
    found === nothing && return nothing
    over = _read_window_gesture(p, recursion, iomap, found[1],
                                DragOver(found[2], found[3], dragged; time = event.time))
    _join_operations(over, _write_state(iomap.input, "drop_window", found[1]))
end

# A move of a global drag: the window under the pointer gets `DragOver` there, and
# the window that got the last one, when it is another, gets the leave first.
function _read_drag_over(p::DragTrackingProjection, recursion, iomap::DragTrackingIoMap,
                         found, time)
    state = iomap.input
    dragged = state.dragged
    dragged === nothing && return nothing
    last_id = state.drop_window
    window_id = found === nothing ? nothing : found[1]
    leave = (last_id === nothing || last_id == window_id) ? nothing :
            _read_window_gesture(p, recursion, iomap, last_id, DragOver(-1, -1, dragged; time))
    over = found === nothing ? nothing :
           _read_window_gesture(p, recursion, iomap, window_id, DragOver(found[2], found[3], dragged; time))
    write = last_id == window_id ? nothing : _write_state(state, "drop_window", window_id)
    _join_operations(leave, over, write)
end

# The release of a global drag: the window under the pointer gets `DragDrop` there,
# and a window that got a `DragOver` and is not under the pointer gets the leave.
function _read_drag_drop(p::DragTrackingProjection, recursion, iomap::DragTrackingIoMap,
                         found, event)
    state = iomap.input
    dragged = state.dragged
    dragged === nothing && return nothing
    last_id = state.drop_window
    window_id = found === nothing ? nothing : found[1]
    leave = (last_id === nothing || last_id == window_id) ? nothing :
            _read_window_gesture(p, recursion, iomap, last_id, DragOver(-1, -1, dragged; time = event.time))
    drop = found === nothing ? nothing :
           _read_window_gesture(p, recursion, iomap, window_id,
                                DragDrop(found[2], found[3], dragged, event.modifiers; time = event.time))
    _join_operations(leave, drop)
end

# The end of a global drag with no drop: the window that got the last `DragOver`
# gets the leave, so it puts away what it showed.
function _leave_drop_window(p::DragTrackingProjection, recursion, iomap::DragTrackingIoMap, time)
    state = iomap.input
    (state.dragged === nothing || state.drop_window === nothing) && return nothing
    _read_window_gesture(p, recursion, iomap, state.drop_window,
                         DragOver(-1, -1, state.dragged; time))
end

_is_bare_escape(event) = false
_is_bare_escape(event::KeyDown) =
    event.key === :escape &&
    !(event.modifiers.ctrl || event.modifiers.shift || event.modifiers.alt || event.modifiers.meta)

# ── The start and the end of a drag ────────────────────────────────────────

# `operation` with a `StartDragOperation` in it taken out and kept in the state:
# its path, which starts at the state with the step into the content, and the
# dragged thing.
function _take_drag_start(state::DragTrackingState, operation)
    start, rest = _split_drag_start(operation)
    start === nothing && return operation
    path = strip_reference_types(get_operation_path(start))
    (path isa ConcreteReference && get_reference_head(path) == FieldReferenceStep("content")) ||
        return rest
    _join_operations(rest, _write_state(state, "drag_path", get_reference_tail(path)),
                     _write_state(state, "dragged", start.dragged))
end

# `operation` with no `StartDragOperation`: while a drag is on, a part starts no
# other drag.
_drop_drag_start(operation) = last(_split_drag_start(operation))

# The `StartDragOperation` in `operation`, and the rest of it.
_split_drag_start(operation::StartDragOperation) = (operation, nothing)
_split_drag_start(operation) = (nothing, operation)
function _split_drag_start(operation::CompoundOperation)
    for (index, member) in enumerate(operation.operations)
        start, rest = _split_drag_start(member)
        start === nothing && continue
        members = Any[other for (place, other) in enumerate(operation.operations) if place != index]
        rest === nothing || insert!(members, index, rest)
        return (start, _join_operations(members...))
    end
    (nothing, operation)
end

_end_drag(state::DragTrackingState) =
    _join_operations(_write_state(state, "drag_path", nothing),
                     _write_state(state, "dragged", nothing),
                     state.drop_window === nothing ? nothing : _write_state(state, "drop_window", nothing))

# A write of one field of the state, which a history does not record.
_write_state(state::DragTrackingState, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(state, field, value))

# The operations in order, without the ones that are `nothing`, as one operation.
function _join_operations(operations...)
    kept = Any[operation for operation in operations if operation !== nothing]
    isempty(kept) ? nothing : length(kept) == 1 ? kept[1] : CompoundOperation(kept)
end

# ── Reference mapping (transparent, through the `content` field) ───────────

function map_reference_forward(p::DragTrackingProjection, iomap::DragTrackingIoMap, reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    head isa FieldReferenceStep && head.name == "content" || return nothing
    map_reference_forward(p.inner, iomap.child_iomap, get_reference_tail(reference))
end

function map_reference_backward(p::DragTrackingProjection, iomap::DragTrackingIoMap, reference)
    inner = map_reference_backward(p.inner, iomap.child_iomap, reference)
    inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
end
