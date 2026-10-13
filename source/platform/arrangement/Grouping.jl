# Fragment of `ArrangementModule` — the group of a collection and its first
# items: a stage that makes one row for each group, the rows and the aggregates
# that a group computes, and the first items, which a pick gives.

make_arrangement_projection(first::ArrangementFirst) =
    PickingProjection(items -> 1:min(max(first.count, 0), length(items)))
make_arrangement_projection(group::ArrangementGroup) = GroupingProjection(group)

"""
    GroupingProjection(group)

The rows that `group` makes of the items of a collection, one for each group, as
a `CellVector{ArrangementGroupRow}` ([`compute_group_rows`](@ref)). A row stands
for no one item of the input, so a path in a row is a part that the stage made,
and the path of an item has no place in the output.
"""
struct GroupingProjection <: Projection
    group::ArrangementGroup
end

@iomap struct GroupingIoMap
    projection::Any
    input::Any
    output::Any
end

function print_document(p::GroupingProjection, recursion, input::Union{CellVector, AbstractVector}, ctx)
    output = CellVector{ArrangementGroupRow}()
    set_cell_computation!(getfield(output, :elements),
                          () -> Cell[Cell(row) for row in compute_group_rows(p.group, input)])
    GroupingIoMap(p, input, output)
end

# A document that holds no items of its own passes through, as at a pick.
print_document(p::GroupingProjection, recursion, input, ctx) = GroupingIoMap(p, input, input)

function map_reference_forward(p::GroupingProjection, iomap::GroupingIoMap, reference)
    (iomap.output === iomap.input || _is_later_introduced(p, reference)) && return reference
    reference isa EmptyReference && return reference
    @invoke map_reference_forward(p::Projection, iomap, reference)
end

function map_reference_backward(p::GroupingProjection, iomap::GroupingIoMap, reference)
    (iomap.output === iomap.input || _is_later_introduced(p, reference)) && return reference
    reference isa EmptyReference && return reference
    @invoke map_reference_backward(p::Projection, iomap, reference)
end

"""
    compute_group_rows(group, items) -> Vector{ArrangementGroupRow}

One row for each value that the items of `items` have at the keys of `group`, in
the order in which the first item of each group comes: the values of the keys,
and then the value of each aggregate of `group` over the items of the group. The
names of the columns are the keys as a person reads them, and each aggregate as
its chip says it, such as `mean of delay`.
"""
function compute_group_rows(group::ArrangementGroup, items)
    keys = Any[key for key in group.keys]
    aggregates = Any[aggregate for aggregate in group.aggregates]
    columns = vcat(String[_describe_key(key) for key in keys],
                   String[describe_arrangement_part(aggregate) for aggregate in aggregates])
    order = Vector{Any}[]
    members = Dict{Vector{Any}, Vector{Int}}()
    for i in 1:length(items)
        value = Any[find_arrangement_key_value(items[i], key) for key in keys]
        found = get(members, value, nothing)
        if found === nothing
            found = Int[]
            members[value] = found
            push!(order, value)
        end
        push!(found, i)
    end
    rows = ArrangementGroupRow[]
    for value in order
        indices = members[value]
        totals = Any[compute_arrangement_aggregate(Val(aggregate.operator),
                                                   Any[find_arrangement_key_value(items[i], aggregate.key)
                                                       for i in indices])
                     for aggregate in aggregates]
        push!(rows, ArrangementGroupRow(columns, vcat(value, totals), indices))
    end
    rows
end

"""
    compute_arrangement_aggregate(operator::Val, values) -> Any

The aggregate `operator` over `values`, the values of the items of one group at
the key of the aggregate. `:count` counts them. `:sum`, `:mean`, `:minimum` and
`:maximum` take the numbers among them, and the last three answer `nothing` when
there is no number. A slice adds an operator with a method, such as the width of
a mean.
"""
function compute_arrangement_aggregate end

compute_arrangement_aggregate(::Val{:count}, values) = length(values)
compute_arrangement_aggregate(::Val{:sum}, values) = sum(_collect_numbers(values); init = 0)
compute_arrangement_aggregate(::Val{:mean}, values) =
    (numbers = _collect_numbers(values); isempty(numbers) ? nothing : sum(numbers) / length(numbers))
compute_arrangement_aggregate(::Val{:minimum}, values) =
    (numbers = _collect_numbers(values); isempty(numbers) ? nothing : minimum(numbers))
compute_arrangement_aggregate(::Val{:maximum}, values) =
    (numbers = _collect_numbers(values); isempty(numbers) ? nothing : maximum(numbers))

_collect_numbers(values) = Real[value for value in values if value isa Real]

# A key of a row of a group is the name of one of its columns.
function find_arrangement_key_value(row::ArrangementGroupRow, key::Reference)
    key isa EmptyReference && return get_arrangement_value(row)
    steps = get_reference_steps(strip_reference_types(key))
    all(step -> step isa FieldReferenceStep, steps) || return nothing
    index = findfirst(==(join((step.name for step in steps), ".")), row.columns)
    index === nothing ? nothing : get_arrangement_value(row.values[index])
end

# What a row of a group is as one value, which "any value" of a quick text reads:
# its values.
get_arrangement_value(row::ArrangementGroupRow) = row.values
