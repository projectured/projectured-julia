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
    ReferenceDispatchingProjection(f::Function; reads_context = false)

A compound projection that dispatches to different inner projections based on
the current `reference` path argument.

The pair-based form uses structural equality: `default` is used when no key
matches; `pairs` is a list of `Reference => Projection` pairs.

The function-based form takes a `reference -> Projection` callable, enabling
`@reference_case` patterns (including the `above()` arm and `_` wildcards). With
`reads_context = true` it takes `(reference, context) -> Projection`, so it can
also read a property of the printer context.

The choice is a computation. A function that reads a cell chooses again when the
cell changes, and when it answers another projection, the position prints again
through the same IO map. A function that reads no cell chooses once.

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
    reads_context::Bool
end

ReferenceDispatchingProjection(default, pairs::Pair...) =
    ReferenceDispatchingProjection(default, collect(Pair{Any, Any}, pairs), nothing, false)

ReferenceDispatchingProjection(f::Function; reads_context::Bool = false) =
    ReferenceDispatchingProjection(nothing, Pair{Any, Any}[], f, reads_context)

# ── Projection interface ──────────────────────────────────────────────────

function _dispatch_proj(rdp::ReferenceDispatchingProjection, reference, ctx)
    if rdp.cases !== nothing
        return rdp.reads_context ? rdp.cases(reference, ctx) : rdp.cases(reference)
    end
    for (ref, proj) in rdp.dispatch
        ref == reference && return proj
    end
    return rdp.default
end

# The dispatch key is `ctx.reference`, the path to this position, and what the
# function reads. `inner_iomap` is reconciled by the chosen projection: a new
# choice prints the position again, and the same choice keeps the inner IO map.
# The inner print runs in a computation that is only peeked, so what it reads as
# it prints is no dependency of the choice. `output` forwards the output of the
# inner IO map through a cell, which keeps the identity of this IO map while the
# inner one changes (PAR-STABLE-IOMAP-IDENTITY).
@iomap struct ReferenceDispatchingIoMap
    projection::Any
    input::Any
    output::Any
    reference::Any        # the `reference` arg used at print time
    inner_iomap::Any      # the iomap of the chosen inner projection
end

function print_document(rdp::ReferenceDispatchingProjection, recursion, input, ctx)
    inner = make_reconciled_child_iomap_cell(() -> _dispatch_proj(rdp, ctx.reference, ctx),
        proj -> peek(Cell(@computation print_document(proj, recursion, input, ctx))))
    # The choice and the print happen now, as the rest of the pipeline assumes, and
    # the peek keeps the printer of this position from reading the choice.
    peek(inner)
    ReferenceDispatchingIoMap(rdp, input, Cell(@computation inner[].output), ctx.reference, inner)
end

# The reader and the maps go to the projection of the inner IO map that stands.
function read_intent(rdp::ReferenceDispatchingProjection, recursion, change::Intent, iomap::ReferenceDispatchingIoMap)
    inner = iomap.inner_iomap
    return read_intent(get_iomap_projection(inner), recursion, change, inner)
end

read_intent(rdp::ReferenceDispatchingProjection, iomap::ReferenceDispatchingIoMap, payload) =
    read_intent(rdp, nothing, Intent(payload), iomap).operation

function map_reference_forward(::ReferenceDispatchingProjection, iomap::ReferenceDispatchingIoMap, reference)
    inner = iomap.inner_iomap
    return map_reference_forward(get_iomap_projection(inner), inner, reference)
end

function map_reference_backward(::ReferenceDispatchingProjection, iomap::ReferenceDispatchingIoMap, reference)
    inner = iomap.inner_iomap
    return map_reference_backward(get_iomap_projection(inner), inner, reference)
end
