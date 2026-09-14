# Fragment of `ProjectionAlgebraModule`.
#
# A higher-order projection that selects an inner projection based on matching
# the current *reference path* argument against a list of known keys, with a
# mandatory default projection used when nothing matches. Each path is compared
# structurally (step values are read from their Cells). Complements
# PredicateDispatchingProjection for cases where the dispatch key is a concrete
# reference path.
"""
    ReferenceDispatchingProjection(default, pairs...)
    ReferenceDispatchingProjection(f::Function)

A compound projection that dispatches to different inner projections based on
the current `reference` path argument.

The pair-based form uses structural equality: `default` is used when no key
matches; `pairs` is a list of `Reference => Projection` pairs.

The function-based form takes a `reference -> Projection` callable, enabling
`@reference_case` patterns (including the `above()` arm and `_` wildcards).

# Examples

    rdp = ReferenceDispatchingProjection(
        CopyingProjection(),
        @reference(elements) => SortingProjection(by = x -> x[]),
    )

    rdp = ReferenceDispatchingProjection(ref -> @reference_case ref begin
        above(entries) => CopyingProjection()
        entries        => SortingProjection(by = x -> x.key)
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

# The dispatch key is `ctx.reference` — structural (the path to this position), so
# fixed per print. `output` forwards the dispatched inner's output through a cell,
# keeping the IoMap's identity while the inner re-derives (PAR-STABLE-IOMAP-IDENTITY).
@iomap struct ReferenceDispatchingIoMap
    projection::Any
    input::Any
    output::Any
    reference::Any        # the `reference` arg used at print time
    inner_iomap::Any      # the iomap returned by the dispatched inner projection
end

function print_document(rdp::ReferenceDispatchingProjection, recursion, input, ctx)
    proj = _dispatch_proj(rdp, ctx.reference)
    inner = print_document(proj, recursion, input, ctx)
    ReferenceDispatchingIoMap(rdp, input, ComputedCell(() -> inner.output), ctx.reference, inner)
end

function read_intent(rdp::ReferenceDispatchingProjection, recursion, change::Intent, iomap::ReferenceDispatchingIoMap)
    proj = _dispatch_proj(rdp, iomap.reference)
    return read_intent(proj, recursion, change, iomap.inner_iomap)
end

read_intent(rdp::ReferenceDispatchingProjection, iomap::ReferenceDispatchingIoMap, payload) =
    read_intent(rdp, nothing, Intent(payload), iomap).operation

function map_reference_forward(::ReferenceDispatchingProjection, iomap::ReferenceDispatchingIoMap, reference)
    proj = _dispatch_proj(iomap.projection, iomap.reference)
    return map_reference_forward(proj, iomap.inner_iomap, reference)
end

function map_reference_backward(::ReferenceDispatchingProjection, iomap::ReferenceDispatchingIoMap, reference)
    proj = _dispatch_proj(iomap.projection, iomap.reference)
    return map_reference_backward(proj, iomap.inner_iomap, reference)
end
