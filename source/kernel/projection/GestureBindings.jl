# Fragment of `ProjectionModule` — the open generics for the gesture-binding
# tables of a projection. The concrete generic and higher-order projections
# that consume `read_projection_gesture` are domain-independent framework that
# sinks to a higher package; the kernel keeps only the binding machinery.

"""
    get_projection_gesture_bindings(projection, iomap) -> Vector{GestureBinding}

Gestures owned by a *projection* rather than a document (focus, collapse
glyph, clipboard, …). Default empty; a projection overrides this to
contribute its own rows to a listing. `read_projection_gesture` fires them and
answers a `CollectIntents` payload with all of them, so the reader gathers them
across the chain with no second traversal.
"""
get_projection_gesture_bindings(::Projection, iomap) = GestureBinding[]

"""
    read_projection_gesture(projection, iomap, event) -> Operation | Nothing

Fire the first reified `get_projection_gesture_bindings(projection, iomap)`
binding whose pattern `matches` the event and whose `applicable`
precondition holds; a binding whose `operation` returns `nothing` is
skipped so a later one may still fire. The projection-layer analogue of
`read_bound_gesture`: a projection whose reader delegates here (e.g.
Clipboard) *fires* the very table a listing *shows*.

It answers a `CollectIntents` payload too, because `fire_gesture_bindings` does.
A projection that routes its gestures through here needs no separate collector.
"""
function read_projection_gesture(projection, iomap, event)
    bindings = get_projection_gesture_bindings(projection, iomap)
    isempty(bindings) && return nothing
    input = hasproperty(iomap, :input) ? iomap.input : nothing
    selection = (input !== nothing && hasfield(typeof(input), :selection)) ?
                getfield(input, :selection)[] : nothing
    return fire_gesture_bindings(bindings, input, selection, event)
end
