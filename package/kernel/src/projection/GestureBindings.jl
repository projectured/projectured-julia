"""
    ProjectionGestureBindingsModule

R3 completion of kernel plan P8 (2026-07-06). The three
projection-typed gesture-seam methods —
`get_projection_gesture_bindings`, `read_projection_gesture`, and the
default `collect_gesture_bindings(p::Projection, …)` — moved up here from
`device/GestureBinding.jl`. Before R3, they lived in the device layer's
`GestureBindingModule` (now `GestureModule`) even though their
`::Projection` dispatch targets a higher layer; GestureModule imported
`Projection` from `..ProjectionApiModule` for that purpose. R3 dissolves
that upward private edge by moving the methods themselves up to the
projection layer beside their type; the reified GestureBinding container
and the document-typed methods stay in `GestureModule`.
"""
module ProjectionGestureBindingsModule

import ..ProjectionApiModule: Projection
import ..DocumentModule: Document
import ..GestureModule: GestureBinding, matches,
                        get_document_gesture_bindings,
                        get_instance_gesture_bindings

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
`read_document_gesture`: a projection whose reader delegates here (e.g.
Clipboard) *fires* the very table `collect_gesture_bindings` *shows*.
"""
function read_projection_gesture(projection, iomap, event)
    bindings = get_projection_gesture_bindings(projection, iomap)
    isempty(bindings) && return nothing
    input = hasproperty(iomap, :input) ? iomap.input : nothing
    sel = (input !== nothing && hasfield(typeof(input), :selection)) ?
          getfield(input, :selection)[] : nothing
    for b in bindings
        if matches(b.pattern, event) && b.applicable(input, sel)
            op = b.operation(input, event)
            op === nothing || return op
        end
    end
    return nothing
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
