# Fragment of `GraphicsModule` — the position a pointer event carries, moved from
# the frame of a container into the frame of a child that it placed.

"""
    shift_event_position(event, dx, dy) -> event

`event` with its position `(x, y)` moved by `(dx, dy)`: a pointer event or a
pointer gesture of a container, moved into the frame of a child that the
container placed at `(-dx, -dy)`. An event with no position, such as a key,
comes back unchanged.

A widget reads a point in the frame of its own canvas, so a reader that hands an
event to a child it placed moves the event with this, and moves the child's
answer back with [`shift_operation_position`](@ref).
"""
function shift_event_position(event::Union{Event, Gesture}, dx::Integer, dy::Integer)
    (dx == 0 && dy == 0) && return event
    T = typeof(event)
    (hasfield(T, :x) && hasfield(T, :y)) || return event
    T((name === :x ? getfield(event, :x) + dx :
       name === :y ? getfield(event, :y) + dy : getfield(event, name)
       for name in fieldnames(T))...)
end

"""
    map_event_position(event, move) -> event

`event` with its position `(x, y)` replaced by `move(x, y) -> (x, y)`: a pointer
event or a pointer gesture of a container, moved into the frame of a child that
the container draws with a transform of its own, such as a scale. An event with
no position, and a value that is no event, come back unchanged.
"""
function map_event_position(event::Union{Event, Gesture}, move)
    T = typeof(event)
    (hasfield(T, :x) && hasfield(T, :y)) || return event
    x, y = move(getfield(event, :x), getfield(event, :y))
    T((name === :x ? convert(fieldtype(T, :x), x) :
       name === :y ? convert(fieldtype(T, :y), y) : getfield(event, name)
       for name in fieldnames(T))...)
end

map_event_position(event, move) = event
