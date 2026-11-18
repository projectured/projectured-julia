# Fragment of `GraphicsModule` — the children that a view draws at a place of its
# own canvas. A child is the print of a part of the input of the view, drawn in a
# rectangle over the canvas: the view finds the child under a point, and gives it a
# pointer gesture in its own frame by the passing of the layout slice
# (`read_child_in_frame`), which takes its answer back into the frame and the paths
# of the view.
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
          findfirst(c -> find_drawn_child_path(target, c.steps) !== nothing, children)
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

"""
    find_drawn_child_path(path, steps) -> Reference or nothing

The part of `path`, a path in the input of a view, below `steps`, the steps of a
child, with the node types that `path` has; `nothing` when `path` does not go into
that child. A view gives a child its part of the mouse target of the view with it,
and finds the child that the mouse target names.
"""
function find_drawn_child_path(path, steps::Tuple)
    for step in steps
        (path isa ConcreteReference && get_reference_head(path) == step) || return nothing
        path = get_reference_tail(path)
    end
    path
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
