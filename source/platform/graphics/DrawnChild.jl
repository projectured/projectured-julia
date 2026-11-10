# Fragment of `GraphicsModule` — the children that a view draws at a place of its
# own canvas. A child is the print of a part of the input of the view, drawn in a
# rectangle over the canvas: the view finds the child under a point, gives it the
# pointer gestures in its own frame, and takes its answer back into the frame and
# the paths of the view.
#
# A child is a named tuple `(; x, y, w, h, iomap, steps)`: the rectangle where the
# view draws the output of `iomap`, in the frame of the view, and the steps from
# the input of the view to the input of `iomap`. A view lists its children from the
# top one down.

"""
    find_drawn_child_at(children, x, y) -> child or nothing

The first of `children` whose rectangle holds the point `(x, y)` of the view, or
`nothing`.
"""
function find_drawn_child_at(children, x::Integer, y::Integer)
    for child in children
        (child.x <= x < child.x + child.w && child.y <= y < child.y + child.h) && return child
    end
    nothing
end

"""
    read_drawn_child_event(document, child, event) -> operation or nothing

The answer of `child` to `event`, a pointer gesture on it. The child reads the
gesture in its own frame, each position of its answer comes back into the frame of
the view, and each path gets the steps of the child. A dwell and a right click that
the child does not answer go to the part under the point in the child, and then out
over `document`, the input of the view, by the rule of `read_container_gesture`.
"""
function read_drawn_child_event(document, child, event)
    moved = shift_event_position(event, -child.x, -child.y)
    iomap = child.iomap
    answer = read_intent(get_iomap_projection(iomap), iomap, moved)
    answer isa Operation || (answer = nothing)
    is_outward_gesture(event) && answer === nothing && (answer = read_child_part_gesture(iomap, moved))
    answer = reroot_operation(shift_operation_position(answer, child.x, child.y), child.steps)
    is_outward_gesture(event) ? read_container_gesture(answer, event, document; steps = child.steps) : answer
end

"""
    read_drawn_child_move(document, children, event) -> operation or nothing

The answer of the children of a view to `event`, a move of the pointer, in the frame
of the view. The child that the pointer was on, the one whose steps begin the mouse
target of `document`, gets the leave when the pointer is off it now
(`read_child_leave`), so a press released off a button ends. The child under the
point gets the move with the part under the pointer (`read_child_move`). `nothing`
when the pointer is on no child and left none.
"""
function read_drawn_child_move(document, children, event::MouseMove)
    child = find_drawn_child_at(children, event.x, event.y)
    target = get_mouse_target(document)
    old = target === nothing ? nothing :
          findfirst(c -> _is_path_in_drawn_child(strip_reference_types(target), c.steps), children)
    left = nothing
    if old !== nothing && children[old] !== child
        previous = children[old]
        left = reroot_operation(read_child_leave(previous.iomap, event, previous.x, previous.y),
                                previous.steps)
    end
    child === nothing && return left
    move = MouseMove(event.x - child.x, event.y - child.y, event.buttons, event.modifiers; time = event.time)
    answer = reroot_operation(shift_operation_position(read_child_move(child.iomap, move), child.x, child.y),
                              child.steps)
    join_move_answers(left, answer)
end

# Whether `path` goes into the child that `steps` lead to.
function _is_path_in_drawn_child(path, steps::Tuple)
    path isa ConcreteReference || return false
    path_steps = get_reference_steps(path)
    length(path_steps) >= length(steps) && all(i -> path_steps[i] == steps[i], eachindex(steps))
end

"""
    map_drawn_child_point(document, child, x, y) -> Reference

The path in `document`, the input of the view, of the part of `child` under the
point `(x, y)` of the view: the steps of the child, typed from `document`, and the
path that the backward map of the child gives for the point in its frame.
"""
function map_drawn_child_point(document, child, x::Integer, y::Integer)
    iomap = child.iomap
    inner = map_reference_backward(get_iomap_projection(iomap), iomap,
                                   ConcreteReference(PointReferenceStep(x - child.x, y - child.y),
                                                     EmptyReference()))
    head = annotate_reference_types(document, Reference(child.steps...))
    inner isa Reference ? concat_references(head, inner) : head
end
