# Fragment of `GraphicsModule` — the answer of a child to a move of the pointer with
# no button held: the child under the pointer names the part under it, and each
# part on the path that the pointer leaves answers that leave.

"""
    compute_part_at_point(iomap, x, y) -> Reference

The path of the part of the input of `iomap` at the point `(x, y)` of its output,
by the backward map of the point, as a move with no button held names the part
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
    read_child_move(child_iomap, move::MouseMove) -> operation

The answer of the child under the pointer to `move`, a move with no button held
whose point is in the child's frame, with the part under the pointer: the child's
own answer when it names that part, else the part at the point by the child's
backward map (`compute_part_at_point`), or the child itself.
"""
function read_child_move(child_iomap, move::MouseMove)
    answer = read_intent(child_iomap.projection, child_iomap, move)
    has_mouse_target(answer) ? answer :
        add_mouse_target(answer, compute_part_at_point(child_iomap, move.x, move.y))
end

# @positional: the offset of the frame of the child is a pair, `dx` and `dy`.
"""
    read_child_leave(child_iomap, event::MouseMove, dx, dy) -> operation or nothing

The answer of a child that the pointer leaves to `event`, a move with no button
held, when the frame of the child lies at `(dx, dy)` of the container's frame. The
child gets the move at `(-1, -1)` of its own frame, a point off it and off each
part in it, whatever the point of `event` is: a part that a pane clips, or a child
that lies under another, can be at the point of `event`. So the child names no part
under the pointer. It gives the move on to the part that it holds, and each part on
the old path answers the leave of the pointer, as a button clears `pressed`. A
position in the answer is moved back into the container's frame.
"""
function read_child_leave(child_iomap, event::MouseMove, dx::Integer, dy::Integer)
    move = MouseMove(-1, -1, event.buttons, event.modifiers; time = event.time)
    answer = read_intent(child_iomap.projection, child_iomap, move)
    shift_operation_position(answer, dx, dy)
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
