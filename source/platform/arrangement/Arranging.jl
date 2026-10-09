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

get_child_iomaps(iomap::ArrangingIoMap) = Any[iomap.inner_iomap]

# Everything goes on to the document, and the answer is rooted under the field
# `document`, so its reference is valid against the arrangement. A gesture with a
# route goes the way of every container, so the gesture table of the
# arrangement reads it too, as the context menu of a value needs; so does a key
# that the document does not answer. An
# `ArrangeCollectionOperation` from inside the document becomes the edit of the
# arrangement, and an edit that leaves the arrangement with no entry takes the
# arrangement away.
function read_intent(p::ArrangingProjection, recursion, change::Intent, iomap::ArrangingIoMap)
    if change.route !== nothing
        answer = read_routed_child(recursion, change, iomap)
        operation = answer isa Intent ? answer.operation : answer
    else
        inner = iomap.inner_iomap
        answer = read_intent(get_iomap_projection(inner), recursion, change, inner)
        operation = reroot_operation(answer isa Intent ? answer.operation : answer, (FieldReferenceStep("document"),))
        # A key that the document does not answer goes to the gesture table of
        # the arrangement, as the keys of find do.
        operation === nothing && change.operation === nothing && change.gesture isa Union{KeyDown, KeyPress} &&
            (operation = read_gesture(iomap.input, change.gesture))
    end
    operation = _make_arranged_change(iomap.input, operation)
    Intent(change.gesture, _take_away_when_empty(iomap.input, operation))
end

# `operation`, or the edit of `arrangement` that it makes when it arranges a
# collection inside the document of `arrangement`.
function _make_arranged_change(arrangement::ArrangementDocument, operation)
    operation isa ArrangeCollectionOperation || return operation
    at = @reference_case strip_reference_types(operation.at) begin
        document.rest... => rest
        __ => nothing
    end
    at === nothing && return operation
    make_arrangement_change_edit(arrangement, ArrangeCollectionOperation(at, operation.description))
end

# `operation`, or the edit that puts the document of `arrangement` in its place
# when `operation` takes away the last entry of `arrangement`. The edit is rooted
# at the arrangement, so the readers around it carry it to its place.
function _take_away_when_empty(arrangement::ArrangementDocument, operation)
    operation isa ReplaceReferencedValueOperation && operation.document === arrangement || return operation
    (length(arrangement.entries) == 1 && operation.value isa AbstractVector && isempty(operation.value)) ||
        return operation
    steps = get_reference_steps(strip_reference_types(operation.reference))
    (length(steps) == 2 && steps[1] == FieldReferenceStep("entries")) || return operation
    ReplaceReferencedValueOperation(nothing, EmptyReference(), arrangement.document)
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
    make_arranged_dispatch(default; bar = nothing) -> ReferenceDispatchingProjection

The dispatch of a recursion that can show an arranged document. At a place
where the `ArrangementDocument` above it has an entry with projections, it gives
the chain of those projections and then `default`; at every other place it gives
`default`, the projection that draws the place when nothing is arranged there.
It chooses again when an entry changes, so a projection that a person adds or
removes prints only its own place again. Outside an arrangement it prints
`default` as it is, so a document that nobody arranged costs nothing more.

`bar(entry)`, when given, makes the stage that shows the chips of `entry` with
the items of the place; it comes after the projections of the entry and before
`default`, which prints what it makes.

# Example

    RecursiveProjection(make_arranged_dispatch(TypeDispatchingProjection(rows)))
"""
make_arranged_dispatch(default; bar = nothing) =
    ReferenceDispatchingProjection((reference, context) -> find_arranged_projection(reference, context, default; bar);
                                   reads_context = true, applies = _is_arranged_context, default)

# Whether a place can have an entry: it prints inside an arrangement. Outside one
# the dispatch prints `default` as it is.
_is_arranged_context(context) = get_property(context, :arrangement, nothing) !== nothing

"""
    find_arranged_projection(reference, context, default; bar = nothing) -> Projection

The projection at the place `reference` under the arrangement in `context`: the
chain of the projections of the entry of that place, and then `default`, or
`default` when there is no arrangement, no entry, or an entry with no
projection. A chain is built once for each entry and each list of projections,
so the same entry gives the same object and its place does not print again.

The place is found by its path in the document of the arrangement: an index
after a filtered or sorted place is the index of the item in the source, which
the picks of the places above give (`ArrangedChainingProjection`). An entry at a
path wins over an entry at a pattern, and among entries of one kind the first
wins. A place is arranged once: where a stage above picked the items of this
place already, the answer is `default`.
"""
function find_arranged_projection(reference, context, default; bar = nothing)
    arrangement = get_property(context, :arrangement, nothing)
    arrangement === nothing && return default
    relative = _find_relative_reference(arrangement.base, reference)
    relative === nothing && return default
    picks = get_property(context, :arranged_picks, Any[])
    # A place that a stage above picked already is arranged, as a document that
    # two recursions print at one path, one inside the other, shows.
    any(pick -> pick.source == relative && pick.rows[] !== nothing, picks) && return default
    relative = _find_source_reference(relative, picks)
    entries = arrangement.arrangement.entries
    entry = something(_find_entry_at(entries, relative, Reference), _find_entry_at(entries, relative, AbstractVector),
                      Some(nothing))
    entry === nothing && return default
    descriptions = Any[description for description in entry.projections]
    isempty(descriptions) && return default
    _get_entry_chain(arrangement, entry, descriptions, default, bar)
end

# The first entry of `entries` whose place, of the kind `kind` (a path or a
# pattern), is `relative`.
function _find_entry_at(entries, relative, kind::Type)
    for entry in entries
        at = entry.at
        at isa kind && _is_entry_at(at, relative) && return entry
    end
    nothing
end

_is_entry_at(at::Reference, relative) = strip_reference_types(at) == relative
_is_entry_at(at::AbstractVector, relative) = match_reference_pattern(:at, at, relative) !== nothing

# `relative`, a path as it prints, with the path of each picked place as it
# prints and the index after it turned into the path of the place in the source
# and the index of the item there, the innermost place first: the path of a pick
# is a path as it prints, so an inner one matches before the outer ones change.
function _find_source_reference(relative, picks)
    for pick in Iterators.reverse(picks)
        rows = pick.rows[]
        rows === nothing || (relative = _replace_picked_index(relative, pick.place, pick.source, rows))
    end
    relative
end

function _replace_picked_index(relative, place, source, rows)
    steps = get_reference_steps(relative)
    prefix = get_reference_steps(place)
    length(steps) > length(prefix) || return relative
    all(steps[i] == prefix[i] for i in eachindex(prefix)) || return relative
    step = steps[length(prefix) + 1]
    (step isa RangeReferenceStep && is_element_reference_step(step)) || return relative
    j = step.start + 1
    (1 <= j <= length(rows)) || return relative
    extend_reference(EmptyReference(), get_reference_steps(source)..., ElementReferenceStep(rows[j]),
                     steps[length(prefix) + 2:end]...)
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
function _get_entry_chain(arrangement::_Arrangement, entry, descriptions, default, bar)
    cached = get(arrangement.chains, entry, nothing)
    if cached !== nothing && cached.default === default && length(cached.descriptions) == length(descriptions) &&
       all(cached.descriptions[i] === descriptions[i] for i in eachindex(descriptions))
        return cached.chain
    end
    stages = Any[(make_arrangement_projection(d) for d in descriptions)...]
    bar === nothing || push!(stages, bar(entry))
    chain = ArrangedChainingProjection(ChainingProjection(Any[stages..., default]))
    arrangement.chains[entry] = (descriptions = descriptions, default = default, chain = chain)
    chain
end

"""
    ArrangedChainingProjection(chain)

The projections of one entry and then the printer of its place, `chain`, printed
as a `ChainingProjection` prints them, but the printer of the place prints with
the indices that the stages before it picked in the printer context, so that
the dispatch at a place inside a picked item finds the entry of the item by its
index in the source. The IO map is the `ChainingIoMap` of `chain`, so the reader
and the maps are those of a chain.
"""
struct ArrangedChainingProjection <: Projection
    chain::ChainingProjection
end

function print_document(p::ArrangedChainingProjection, recursion, input, ctx)
    stages = p.chain.projections
    step_iomaps = Cell[]
    previous = Cell(input)
    # The stages read the count of the items of the place, as the bar shows it.
    ctx = with_property(ctx, :arranged_count, Cell(@computation length(input)))
    for (n, stage) in enumerate(stages)
        stage_ctx = n == length(stages) ? _with_picked_rows(ctx, copy(step_iomaps), stages) : ctx
        iomap_cell, previous = _make_chain_stage(stage, recursion, previous, stage_ctx)
        push!(step_iomaps, iomap_cell)
    end
    foreach(peek, step_iomaps)
    ChainingIoMap(p.chain, input, step_iomaps, Cell(@computation step_iomaps[end][].output))
end

# One stage, as a chain prints it: its IO map is printed again only when the
# output of the stage before it is another object.
function _make_chain_stage(stage, recursion, previous::Cell, ctx)
    iomap_cell = make_reconciled_child_iomap_cell(() -> previous[], v -> print_document(stage, recursion, v, ctx))
    (iomap_cell, Cell(@computation unwrap_cell(iomap_cell[].output)))
end

# `ctx` with the picks of the stages added to the picks of the places above it:
# the path of this place below the arrangement, the path where its items print,
# below the steps that a stage such as the bar puts above them
# (`get_arranged_wrap_steps`), and the index in the input of the stages for each
# index of their output.
function _with_picked_rows(ctx, stage_cells, stages)
    arrangement = get_property(ctx, :arrangement, nothing)
    arrangement === nothing && return ctx
    source = _find_relative_reference(arrangement.base, ctx.reference)
    source === nothing && return ctx
    place = extend_reference(source, (step for stage in stages for step in get_arranged_wrap_steps(stage))...)
    rows = Cell(@computation _compose_picked_rows(stage_cells))
    picks = Any[get_property(ctx, :arranged_picks, Any[])..., (place = place, source = source, rows = rows)]
    with_property(ctx, :arranged_picks, picks)
end

"""
    get_arranged_wrap_steps(stage) -> Tuple

The steps that `stage`, a projection in the chain of an entry, puts above the
items of its place in what it makes: none for a stage that passes the items, and
`(children, [2])` for a bar that puts them second in a layout. The dispatch reads
a path inside a place below these steps.
"""
get_arranged_wrap_steps(stage) = ()

# The index in the input of the first stage for each index of the output of the
# last stage that picks; `nothing` when no stage picks.
function _compose_picked_rows(stage_cells)
    rows = nothing
    for cell in stage_cells
        iomap = cell[]
        iomap isa PickingIoMap || continue
        picked = iomap.rows
        picked === nothing && continue
        rows = rows === nothing ? picked : rows[picked]
    end
    rows
end
