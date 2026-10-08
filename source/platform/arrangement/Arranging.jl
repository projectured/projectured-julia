# Fragment of `ArrangementModule` — the projection of an `ArrangementDocument`,
# and the dispatch that puts the projections of its entries at their places.

"""
    make_arrangement_projection(description) -> Projection

The projection that `description`, an element of the `projections` of an
`ArrangementEntry`, stands for. Each kind of description adds a method; the
projection reads the parameters of the description through their cells, so an
edit of a parameter changes no composition.
"""
function make_arrangement_projection end

"""
    ArrangingProjection()

Prints an `ArrangementDocument`: its `document` prints through the recursion,
with the arrangement in the printer context, so that a dispatch from
[`make_arranged_dispatch`](@ref) in that recursion finds the entry of each
place. The output is the output of `document`, and the paths of `document` are
the paths below the field `document`.
"""
struct ArrangingProjection <: Projection end

@iomap struct ArrangingIoMap
    projection::Any
    input::Any          # ArrangementDocument
    output::Any         # the output of the document
    inner_iomap::Any
end

# What the dispatch reads of an arrangement in the printer context: the
# arrangement, the path of its document, and the chain built for each entry.
struct _Arrangement
    arrangement::ArrangementDocument
    base::Reference
    chains::IdDict{Any,Any}
end

function print_document(p::ArrangingProjection, recursion, input::ArrangementDocument, ctx)
    context = make_child_context(ctx, input, FieldReferenceStep("document"))
    context = with_property(context, :arrangement, _Arrangement(input, context.reference, IdDict{Any,Any}()))
    inner = make_reconciled_child_iomap_cell(() -> input.document, d -> print_child(recursion, d, context))
    ArrangingIoMap(p, input, Cell(@computation inner[].output), inner)
end

# Everything goes on to the document, and the answer is rooted under the field
# `document`, so its reference is valid against the arrangement.
function read_intent(p::ArrangingProjection, recursion, change::Intent, iomap::ArrangingIoMap)
    inner = iomap.inner_iomap
    answer = read_intent(get_iomap_projection(inner), recursion, change, inner)
    operation = answer isa Intent ? answer.operation : answer
    Intent(change.gesture, reroot_operation(operation, (FieldReferenceStep("document"),)))
end

read_intent(p::ArrangingProjection, iomap::ArrangingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

function map_reference_forward(::ArrangingProjection, iomap::ArrangingIoMap, reference)
    reference isa ConcreteReference || return reference
    head = get_reference_head(reference)
    (head isa FieldReferenceStep && head.name == "document") || return nothing
    inner = iomap.inner_iomap
    map_reference_forward(get_iomap_projection(inner), inner, get_reference_tail(reference))
end

function map_reference_backward(::ArrangingProjection, iomap::ArrangingIoMap, reference)
    inner = iomap.inner_iomap
    path = map_reference_backward(get_iomap_projection(inner), inner, reference)
    path === nothing ? nothing : ConcreteReference(FieldReferenceStep("document"), path)
end

"""
    make_arranged_dispatch(default) -> ReferenceDispatchingProjection

The dispatch of a recursion that can show an arranged document. At a place
where the `ArrangementDocument` above it has an entry with projections, it gives
the chain of those projections and then `default`; at every other place it gives
`default`, the projection that draws the place when nothing is arranged there.
It chooses again when an entry changes, so a projection that a person adds or
removes prints only its own place again.

# Example

    RecursiveProjection(make_arranged_dispatch(TypeDispatchingProjection(rows)))
"""
make_arranged_dispatch(default) =
    ReferenceDispatchingProjection((reference, context) -> find_arranged_projection(reference, context, default);
                                   reads_context = true)

"""
    find_arranged_projection(reference, context, default) -> Projection

The projection at the place `reference` under the arrangement in `context`: the
chain of the projections of the entry of that place, and then `default`, or
`default` when there is no arrangement, no entry, or an entry with no
projection. A chain is built once for each entry and each list of projections,
so the same entry gives the same object and its place does not print again.
"""
function find_arranged_projection(reference, context, default)
    arrangement = get_property(context, :arrangement, nothing)
    arrangement === nothing && return default
    relative = _find_relative_reference(arrangement.base, reference)
    relative === nothing && return default
    for entry in arrangement.arrangement.entries
        strip_reference_types(entry.at) == relative || continue
        descriptions = Any[description for description in entry.projections]
        isempty(descriptions) && return default
        return _get_entry_chain(arrangement, entry, descriptions, default)
    end
    default
end

# The path of `reference` below `base`, without types, or `nothing` when it is
# not below it.
function _find_relative_reference(base::Reference, reference)
    reference isa Reference || return nothing
    base_steps = get_reference_steps(strip_reference_types(base))
    steps = get_reference_steps(strip_reference_types(reference))
    length(steps) >= length(base_steps) || return nothing
    for (i, step) in enumerate(base_steps)
        steps[i] == step || return nothing
    end
    extend_reference(EmptyReference(), steps[length(base_steps) + 1:end]...)
end

# The chain of `descriptions` and then `default`, built again only when the list
# of descriptions of `entry` is another list.
function _get_entry_chain(arrangement::_Arrangement, entry, descriptions, default)
    cached = get(arrangement.chains, entry, nothing)
    if cached !== nothing && cached.default === default && length(cached.descriptions) == length(descriptions) &&
       all(cached.descriptions[i] === descriptions[i] for i in eachindex(descriptions))
        return cached.chain
    end
    chain = ChainingProjection(Any[(make_arrangement_projection(d) for d in descriptions)..., default])
    arrangement.chains[entry] = (descriptions = descriptions, default = default, chain = chain)
    chain
end
