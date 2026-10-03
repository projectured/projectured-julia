# Fragment of `GraphicsModule` — the answer of a child to a move of the pointer, with
# or without a button held: the child under the pointer names the part under it,
# and each part on the path that the pointer leaves answers that leave.

"""
    compute_part_at_point(iomap, x, y) -> Reference

The path of the part of the input of `iomap` at the point `(x, y)` of its output,
by the backward map of the point, as a move of the pointer names the part
under the pointer, with the types that the map gives it. The empty path, the input
itself, when the map names no part. A point step at the end of the mapped path,
which a part that reads a point further keeps, is dropped.
"""
function compute_part_at_point(iomap, x::Integer, y::Integer)
    answer = map_reference_backward(get_iomap_projection(iomap), iomap,
                                    ConcreteReference(PointReferenceStep(Int(x), Int(y)),
                                                      EmptyReference()))
    answer isa Reference ? _drop_end_points(answer) :
        annotate_reference_types(get_iomap_input(iomap), EmptyReference())
end

# `path` without the point steps at its end. Each node keeps its type, and the node
# that a dropped point stood on becomes the typed end of the path.
function _drop_end_points(path::Reference)
    path isa ConcreteReference || return path
    tail = _drop_end_points(get_reference_tail(path))
    get_reference_head(path) isa PointReferenceStep && tail isa EmptyReference &&
        return EmptyReference(path.type)
    tail === get_reference_tail(path) ? path : ConcreteReference(path.type, get_reference_head(path), tail)
end

"""
    is_outward_gesture(gesture) -> Bool

Whether the documents around the part under the point read `gesture` with their
own tables when the part answers nothing (D64): a dwell, and a click of the right
button. A container that gives such a gesture to the child at its point reads its
own stretch with `read_gesture_outward`.
"""
is_outward_gesture(gesture) =
    gesture isa MouseDwell || (gesture isa MouseClick && gesture.button === :right)

"""
    read_child_part_gesture(child_iomap, gesture) -> operation or nothing

The answer of the documents inside a child to a pointer `gesture` that the child's
reader did not answer. The backward map of the point names the part under it in
the child's input ([`compute_part_at_point`](@ref)), and the documents on that path
read the gesture with their own tables, the part first and then outward up to the
child's input, by the rule of `read_gesture_outward`. So a child that draws a whole
document as one leaf, such as a text, gives a dwell to the part under the point.
`nothing` when no document answers.
"""
function read_child_part_gesture(child_iomap, gesture)
    path = strip_reference_types(compute_part_at_point(child_iomap, gesture.x, gesture.y))
    steps = path isa ConcreteReference ? collect(get_reference_steps(path)) : ReferenceStep[]
    answer = read_gesture_outward(nothing, gesture, get_iomap_input(child_iomap);
                                  steps, with_part = true)
    answer isa Operation ? answer : nothing
end

"""
    read_container_gesture(answer, gesture, document; steps = ()) -> operation or answer

The answer of a container to `gesture`, read outward over its own stretch when
the gesture is a dwell or a right click ([`is_outward_gesture`](@ref)); any other
answer comes back as it is. `document` is the input of the container. `answer` is
the answer of the child at the point in the frame of the container, and `steps`
lead from `document` to that child's input; with no steps, no child took the
gesture, and the container's own input is the part. The documents above the
child's input read the gesture by the rule of `read_gesture_outward`.
"""
read_container_gesture(answer, gesture, document; steps = ()) =
    is_outward_gesture(gesture) ?
        read_gesture_outward(answer, gesture, document; steps, with_part = isempty(steps)) :
        answer

"""
    read_child_move(child_iomap, move::MouseMove) -> operation

The answer of the child under the pointer to `move`, a move of the pointer, with or
without a button held, whose point is in the child's frame, with the part under the pointer: the child's
own answer when it names that part, else the part at the point by the child's
backward map (`compute_part_at_point`), or the child itself. An answer that is no
operation, such as the move that a reader passes through, counts as none.
"""
function read_child_move(child_iomap, move::MouseMove)
    answer = _read_child_operation(child_iomap, move)
    has_mouse_target(answer) ? answer :
        add_mouse_target(answer, compute_part_at_point(child_iomap, move.x, move.y))
end

# @positional: the offset of the frame of the child is a pair, `dx` and `dy`.
"""
    read_child_leave(child_iomap, event::MouseMove, dx, dy) -> operation or nothing

The answer of a child that the pointer leaves to `event`, a move of the pointer,
when the frame of the child lies at `(dx, dy)` of the container's frame. The
child gets the move at `(-1, -1)` of its own frame, a point off it and off each
part in it, whatever the point of `event` is: a part that a pane clips, or a child
that lies under another, can be at the point of `event`. So the child names no part
under the pointer. It gives the move on to the part that it holds, and each part on
the old path answers the leave of the pointer, as a button clears `pressed`. A
position in the answer is moved back into the container's frame.
"""
function read_child_leave(child_iomap, event::MouseMove, dx::Integer, dy::Integer)
    move = MouseMove(-1, -1, event.buttons, event.modifiers; time = event.time)
    shift_operation_position(_read_child_operation(child_iomap, move), dx, dy)
end

# The answer of a child's reader to `move` when it is an operation, else `nothing`:
# a reader that passes its payload through answers the move itself.
function _read_child_operation(child_iomap, move::MouseMove)
    answer = read_intent(child_iomap.projection, child_iomap, move)
    answer isa Operation ? answer : nothing
end

"""
    get_child_frame_offset(entry) -> (dx, dy)

Where the frame of a child lies in the frame of its container. `entry` is the
`(x, y, child_iomap)` triple that a container keeps for each child, whose offsets
are numbers or cells, and the canvas of the child adds its own place.
"""
function get_child_frame_offset(entry)
    (ox, oy, child_iomap) = entry
    canvas = child_iomap.output
    (Int(ox isa AbstractCell ? ox[] : ox) + (canvas isa GraphicsCanvas ? Int(canvas.x) : 0),
     Int(oy isa AbstractCell ? oy[] : oy) + (canvas isa GraphicsCanvas ? Int(canvas.y) : 0))
end

"""
    read_routed_child_in_frame(recursion, change, child; move_in, move_out) -> Intent

The answer of `child` to `change`, whose route leads into it, when the container
draws the child in a frame of its own: the point of a pointer gesture goes into
the frame of the child by `move_in(x, y)`, and each position of the answer comes
back by `move_out(x, y)`, as for a gesture that the container gives to the child
at the point. A change that carries an operation, or a gesture with no point,
goes to the child as it is.
"""
function read_routed_child_in_frame(recursion, change::Intent, child; move_in, move_out)
    projection = get_iomap_projection(child)
    gesture = change.gesture
    (change.operation === nothing && gesture isa Union{Event, Gesture}) ||
        return read_routed_intent(projection, recursion, change, child)
    moved = Intent(map_event_position(gesture, move_in), nothing,
                   change.description, change.domain, change.route)
    inner = read_routed_intent(projection, recursion, moved, child)
    Intent(gesture, map_operation_position(inner.operation, move_out))
end

"""
    read_routed_entry_child(recursion, change, child; entries) -> Intent

The answer of `child` to `change`, whose route leads into it, for a container
that keeps each child as an `(x, y, child_iomap)` entry: the child reads the
change in its own frame ([`get_child_frame_offset`](@ref),
[`read_routed_child_in_frame`](@ref)). A child that no entry places reads the
change as it is.
"""
function read_routed_entry_child(recursion, change::Intent, child; entries)
    for entry in entries
        (entry isa Tuple && length(entry) == 3 && last(entry) === child) || continue
        dx, dy = get_child_frame_offset(entry)
        return read_routed_child_in_frame(recursion, change, child;
                                          move_in = (x, y) -> (x - dx, y - dy),
                                          move_out = (x, y) -> (x + dx, y + dy))
    end
    read_routed_intent(get_iomap_projection(child), recursion, change, child)
end
