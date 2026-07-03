"""
    ReferenceDispatchingProjectionModule

A higher-order projection that selects an inner projection based on matching
the current *reference path* argument against a list of known keys, with a
mandatory default projection used when nothing matches. Each path is compared
structurally (step values are read from their Cells). Complements
PredicateDispatchingProjection for cases where the dispatch key is a concrete
reference path.
"""
module ReferenceDispatchingProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..ChangeModule: Change
import ..ReferenceModule: ReferencePath, EmptyReferencePath, ConcreteReferencePath,
                          FieldReference, RangeReference, PointReference, ProjectionReference,
                          head, tail, reference_equal, is_prefix_of
import ..IoMapApiModule: IoMap
export ReferenceDispatchingProjection, ReferenceDispatchingProjectionIoMap

"""
    ReferenceDispatchingProjection(default, pairs...)
    ReferenceDispatchingProjection(f::Function)

A compound projection that dispatches to different inner projections based on
the current `reference` path argument.

The pair-based form uses structural equality: `default` is used when no key
matches; `pairs` is a list of `ReferencePath => Projection` pairs.

The function-based form takes a `reference -> Projection` callable, enabling
`@reference_case` patterns (including `prefix()` and `_` wildcards).

# Examples

    rdp = ReferenceDispatchingProjection(
        CopyingProjection(),
        @reference(elements) => SortingProjection(by = x -> x[]),
    )

    rdp = ReferenceDispatchingProjection(ref -> @reference_case ref begin
        prefix(entries) => CopyingProjection()
        entries         => SortingProjection(by = x -> x.key)
        _               => IdentityProjection()
    end)
"""
struct ReferenceDispatchingProjection <: Projection
    default::Any
    dispatch::Vector{Pair{Any, Any}}
    cases::Any
end

ReferenceDispatchingProjection(default, pairs::Pair...) =
    ReferenceDispatchingProjection(default, collect(Pair{Any, Any}, pairs), nothing)

ReferenceDispatchingProjection(f::Function) =
    ReferenceDispatchingProjection(nothing, Pair{Any, Any}[], f)

# ── Projection interface ──────────────────────────────────────────────────

function _dispatch_proj(rdp::ReferenceDispatchingProjection, reference)
    if rdp.cases !== nothing
        return rdp.cases(reference)
    end
    for (ref, proj) in rdp.dispatch
        ref == reference && return proj
    end
    return rdp.default
end

struct ReferenceDispatchingProjectionIoMap <: IoMap
    projection::ReferenceDispatchingProjection
    input::Any
    output::Any
    reference::Any        # the `reference` arg used at print time
    inner_iomap::Any      # the iomap returned by the dispatched inner projection
end

function projection_print(rdp::ReferenceDispatchingProjection, recursion, input, ctx)
    proj = _dispatch_proj(rdp, ctx.reference)
    inner = projection_print(proj, recursion, input, ctx)
    ReferenceDispatchingProjectionIoMap(rdp, input, inner.output, ctx.reference, inner)
end

function projection_read(rdp::ReferenceDispatchingProjection, recursion, change::Change, iomap::ReferenceDispatchingProjectionIoMap)
    proj = _dispatch_proj(rdp, iomap.reference)
    return projection_read(proj, recursion, change, iomap.inner_iomap)
end

projection_read(rdp::ReferenceDispatchingProjection, iomap::ReferenceDispatchingProjectionIoMap, payload) =
    projection_read(rdp, nothing, Change(payload), iomap).operation

function map_reference_forward(::ReferenceDispatchingProjection, iomap::ReferenceDispatchingProjectionIoMap, reference)
    proj = _dispatch_proj(iomap.projection, iomap.reference)
    return map_reference_forward(proj, iomap.inner_iomap, reference)
end

function map_reference_backward(::ReferenceDispatchingProjection, iomap::ReferenceDispatchingProjectionIoMap, reference)
    proj = _dispatch_proj(iomap.projection, iomap.reference)
    return map_reference_backward(proj, iomap.inner_iomap, reference)
end

end # module
