# Fragment of `DragTrackingModule` — the projection that keeps the part whose drag
# is on, and gives that part the parts of its drag.

"""
    DragTrackingProjection(; inner)

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
"""
struct DragTrackingProjection <: Projection
    inner::Projection
end

DragTrackingProjection(; inner::Projection) = DragTrackingProjection(inner)

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
    child = reconcile_child_iomap(() -> input.content,
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
            return Intent(input, _join_operations(part(DragCancel(; time = get_event_time(event))),
                                                  _end_drag(state), content()))
        elseif event isa MouseMove
            return Intent(input, _join_operations(
                part(DragMove(event.x, event.y, event.modifiers; time = event.time)), content()))
        elseif event isa MouseUp
            return Intent(input, _join_operations(
                part(DragEnd(event.x, event.y, event.modifiers; time = event.time)),
                _end_drag(state), content()))
        elseif _is_bare_escape(event)
            return Intent(input, _join_operations(part(DragCancel(; time = event.time)),
                                                  _end_drag(state)))
        end
    end
    Intent(input, _take_drag_start(state, _read_content(p, recursion, change, iomap)))
end

read_intent(p::DragTrackingProjection, iomap::DragTrackingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# The answer of the content to `change`, as an operation from the state.
function _read_content(p::DragTrackingProjection, recursion, change::Intent,
                       iomap::DragTrackingIoMap)
    answer = read_intent(p.inner, recursion, change, iomap.child_iomap)
    operation = answer isa Intent ? answer.operation : answer
    reroot_operation(operation, (FieldReferenceStep("content"),))
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
                     _write_state(state, "dragged", nothing))

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
