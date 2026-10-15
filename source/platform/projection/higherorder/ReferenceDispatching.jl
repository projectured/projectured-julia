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
    ReferenceDispatchingProjection(f::Function; reads_context = false, applies = nothing, default = nothing)

A compound projection that dispatches to different inner projections based on
the current `reference` path argument.

The pair-based form uses structural equality: `default` is used when no key
matches; `pairs` is a list of `Reference => Projection` pairs.

The function-based form takes a `reference -> Projection` callable, enabling
`@reference_case` patterns (including the `above()` arm and `_` wildcards). With
`reads_context = true` it takes `(reference, context) -> Projection`, so it can
also read a property of the printer context.

The choice is a computation. It reads the path of the position from the printer
context, so it chooses again when that path moves, as a row of a list does. A
function that reads a cell chooses again when the cell changes, and when it
answers another projection, the position prints again through the same IO map.
A function that reads no cell, at a path that can not move, chooses once.

`applies(context)`, when given, says whether the choice can change at a position.
Where it answers `false`, the dispatch prints `default`, or the projection that
the function answers when there is no `default`, as it is, with no IO map of its
own, so a position where nothing can change costs nothing.

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
    applies::Any          # `nothing`, or `context -> Bool`: whether the choice can change
end

ReferenceDispatchingProjection(default, pairs::Pair...) =
    ReferenceDispatchingProjection(default, collect(Pair{Any, Any}, pairs), nothing, false, nothing)

ReferenceDispatchingProjection(f::Function; reads_context::Bool = false, applies = nothing, default = nothing) =
    ReferenceDispatchingProjection(default, Pair{Any, Any}[], f, reads_context, applies)

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

# The dispatch key is the path to this position, which the cell `ctx.reference`
# gives, and what the function reads. `inner_iomap` is reconciled by the chosen projection: a new
# choice prints the position again, and the same choice keeps the inner IO map.
# The inner print runs in a computation that is only peeked, so what it reads as
# it prints is no dependency of the choice. `output` forwards the output of the
# inner IO map through a cell, which keeps the identity of this IO map while the
# inner one changes (PAR-STABLE-IOMAP-IDENTITY).
#
# The dispatch adds nothing to what the chosen projection prints, so a property
# that it does not have is the property of the inner IO map: a parent that reads
# the grid of a pane, or the cells of a grid, reads them through the dispatch as
# if it were not there, as it reads them through a fault barrier.
struct ReferenceDispatchingIoMap <: IoMap
    projection::Any
    input::Any
    output::Any           # the cell of the output of the inner IO map
    inner_iomap::Any      # the cell of the iomap of the chosen inner projection
end

function Base.getproperty(iomap::ReferenceDispatchingIoMap, name::Symbol)
    (name === :output || name === :inner_iomap) && return getfield(iomap, name)[]
    hasfield(ReferenceDispatchingIoMap, name) && return getfield(iomap, name)
    getproperty(getfield(iomap, :inner_iomap)[], name)
end

Base.propertynames(iomap::ReferenceDispatchingIoMap, private::Bool = false) =
    unique((fieldnames(ReferenceDispatchingIoMap)...,
            propertynames(getfield(iomap, :inner_iomap)[], private)...))

function print_document(rdp::ReferenceDispatchingProjection, recursion, input, ctx)
    if rdp.applies !== nothing && !rdp.applies(ctx)
        fixed = rdp.default === nothing ? _dispatch_proj(rdp, peek(ctx.reference), ctx) : rdp.default
        return print_document(fixed, recursion, input, ctx)
    end
    inner = make_reconciled_child_iomap_cell(() -> _dispatch_proj(rdp, ctx.reference[], ctx),
        proj -> peek(Cell(@computation print_document(proj, recursion, input, ctx))))
    # The choice and the print happen now, as the rest of the pipeline assumes, and
    # the peek keeps the printer of this position from reading the choice.
    peek(inner)
    ReferenceDispatchingIoMap(rdp, input, Cell(@computation inner[].output), inner)
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

# The dispatch adds nothing to the output of the projection that it chose, so a
# printer that looks at the IoMap of a child sees the IoMap of that projection, as
# it sees through a fault barrier.
get_content_iomap(iomap::ReferenceDispatchingIoMap) = get_content_iomap(iomap.inner_iomap)

# Where `applies` answered `false`, the dispatch gave the IO map of the projection
# that it printed, and the projection that holds the dispatch calls it with that
# IO map: the reader and the maps go to the projection of the IO map.
read_intent(::ReferenceDispatchingProjection, recursion, change::Intent, iomap::IoMap) =
    read_intent(get_iomap_projection(iomap), recursion, change, iomap)
read_intent(::ReferenceDispatchingProjection, iomap::IoMap, payload) =
    read_intent(get_iomap_projection(iomap), iomap, payload)
map_reference_forward(::ReferenceDispatchingProjection, iomap::IoMap, reference) =
    map_reference_forward(get_iomap_projection(iomap), iomap, reference)
map_reference_backward(::ReferenceDispatchingProjection, iomap::IoMap, reference) =
    map_reference_backward(get_iomap_projection(iomap), iomap, reference)
