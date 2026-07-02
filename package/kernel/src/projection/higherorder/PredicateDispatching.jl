"""
    PredicateDispatchingModule

A higher-order projection that selects an inner projection based on
user-supplied predicate functions applied to the input document. Each
predicate is tested in order; the first one that returns true wins. This
complements TypeDispatchingProjection for cases where type alone is not a
sufficient discriminator.
"""
module PredicateDispatchingModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..ChangeModule: Change
export PredicateDispatchingProjection

"""
    PredicateDispatchingProjection(pairs...)

A compound projection that dispatches to different projections based on
predicate functions applied to the input.  Given a list of
`(predicate, projection)` pairs, calling `projection_print` applies the
projection associated with the first predicate that returns `true`.

# Example

    pdp = PredicateDispatchingProjection(
        (x -> x.kind == :inline) => InlineProjection(),
        (x -> x.kind == :block)  => BlockProjection(),
    )
    result = projection_print(pdp, node)  # dispatches on node.kind
"""
struct PredicateDispatchingProjection <: Projection
    dispatch::Vector{Pair{Any, Any}}
end

PredicateDispatchingProjection(pairs::Pair...) =
    PredicateDispatchingProjection(collect(Pair{Any, Any}, pairs))

"""
    projection_print(pdp::PredicateDispatchingProjection, recursion, input, ctx) -> output

Apply the projection whose predicate matches `input` first.
Throws an error if no predicate matches.
"""
function projection_print(pdp::PredicateDispatchingProjection, recursion, input, ctx)
    for (pred, proj) in pdp.dispatch
        if pred(input)
            return projection_print(proj, recursion, input, ctx)
        end
    end
    error("PredicateDispatchingProjection: no predicate matched for input $(typeof(input))")
end

# PredicateDispatchingProjection is a transparent wrapper — it returns the
# inner projection's IoMap directly, so input/output fields are already correct.

function projection_read(pdp::PredicateDispatchingProjection, recursion, change::Change, iomap)
    for (pred, proj) in pdp.dispatch
        if pred(iomap.input)
            return projection_read(proj, recursion, change, iomap)
        end
    end
    return Change(change.gesture, nothing)
end

projection_read(pdp::PredicateDispatchingProjection, iomap, payload) =
    projection_read(pdp, nothing, Change(payload), iomap).operation

function map_reference_forward(::PredicateDispatchingProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::PredicateDispatchingProjection, iomap, reference)
    return nothing
end

end # module
