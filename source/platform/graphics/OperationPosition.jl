# Fragment of `GraphicsModule` — the position an operation carries, moved from
# the frame of a child into the frame of its container.
#
# A reader that moves a pointer event into the frame of a child moves the child's
# answer back with these, on the way up. So an operation that carries a position,
# such as a popup that a widget opens, reaches the screen in screen coordinates:
# each reader adds only what it knows, the place where it put its child.

"""
    map_operation_position(operation, move) -> operation

`operation` with every position it carries replaced by `move(x, y) -> (x, y)`.
A `CompoundOperation` moves each member, and a `WrappingOperation` moves the
operation it holds. An operation that carries no position, and `nothing`, come
back unchanged, so a reader applies this to any answer.

A package that defines an operation with a position adds the method for it.
"""
map_operation_position(operation, move) = operation

function map_operation_position(operation::CompoundOperation, move)
    members = Any[map_operation_position(member, move) for member in operation.operations]
    all(member === original for (member, original) in zip(members, operation.operations)) ?
        operation : CompoundOperation(members)
end

function map_operation_position(operation::WrappingOperation, move)
    inner = get_wrapped_operation(operation)
    moved = map_operation_position(inner, move)
    moved === inner ? operation : rewrap_operation(operation, moved)
end

"""
    shift_operation_position(operation, dx, dy) -> operation

`operation` with every position it carries moved by `(dx, dy)`: the answer of a
child, moved into the frame of the container that placed the child at
`(dx, dy)`. A reader that read the child with a pointer event at `(lx, ly)` for
its own `(x, y)` shifts the answer by `(x - lx, y - ly)`.
"""
shift_operation_position(operation, dx::Integer, dy::Integer) =
    (dx == 0 && dy == 0) ? operation :
        map_operation_position(operation, (x, y) -> (x + dx, y + dy))
