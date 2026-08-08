"""
    ProjectionGestureBindingsModule

The three projection-typed gesture-seam methods —
`get_projection_gesture_bindings`, `read_projection_gesture`, and the
default `collect_gesture_bindings(p::Projection, …)`. They dispatch on
`::Projection`, so they live here beside that type: the binding layer owns the
reified `GestureBinding` container and the document-typed methods, and cannot
name `Projection` without an upward edge. A projection contributes its own
gestures by adding methods here — the seam pattern, with the framework below and
the per-projection methods above.
"""
module ProjectionGestureBindingsModule

using ..ProjectionApiModule
using ..DocumentModule
using ..EventPatternModule
using ..GestureBindingModule

export get_projection_gesture_bindings, read_projection_gesture,
       collect_gesture_bindings

"""
    get_projection_gesture_bindings(projection, iomap) -> Vector{GestureBinding}

Gestures owned by a *projection* rather than a document (focus, collapse
glyph, clipboard, …). Default empty; a projection overrides this to
contribute its own rows to the contextual collector. The combinator
`collect_gesture_bindings` methods (beside the `read_intent` combinators)
gather these across the chain.
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

"""
    collect_gesture_bindings(projection, recursion, iomap) -> Vector{GestureBinding}

Gather every gesture available at `iomap` — the data-driven generalization
of `read_intent`'s 4-arg routing: where the reader *matches* one gesture,
this *collects* them all. The leaf default is the projection's own
`get_projection_gesture_bindings` plus
`get_document_gesture_bindings(iomap.input)`; compound projections override
to recurse in lockstep with their reader.
"""
function collect_gesture_bindings(p::Projection, recursion, iomap)
    result = GestureBinding[]
    append!(result, get_projection_gesture_bindings(p, iomap))
    input = hasproperty(iomap, :input) ? iomap.input : nothing
    if input isa Document
        # Per-instance bindings first (they shadow same-pattern type
        # defaults in the reader), then the per-type table.
        append!(result, get_instance_gesture_bindings(input))
        append!(result, get_document_gesture_bindings(typeof(input)))
    end
    return result
end

end # module
