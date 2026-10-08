# Fragment of `ArrangementModule` — the filter and the sort of a collection: a
# stage that picks items by index, and the indices that a filter and a sort
# compute from their descriptions.

"""
    PickingProjection(compute_rows)

The items of a collection at the indices that `compute_rows(collection)`
answers, in that order: a filter answers the indices of the items that it keeps,
and a sort a permutation. The output holds the same items, not printed, so the
projection after it prints them. `[j]` of the output is `[rows[j]]` of the input,
so a path, and an operation that names one, maps back to the item of the input.
"""
struct PickingProjection <: Projection
    compute_rows::Function
end

@iomap struct PickingIoMap
    projection::Any
    input::Any
    output::Any
    rows::Any           # the index in the input of each item of the output
end

function print_document(p::PickingProjection, recursion, input::CellVector, ctx)
    rows = Cell(@computation collect(Int, p.compute_rows(input)))
    output = CellVector(@computation Any[input[i] for i in rows[]])
    set_output_path_computations!(output, input, path -> _map_picked_forward(rows[], path))
    PickingIoMap(p, input, output, rows)
end

function print_document(p::PickingProjection, recursion, input::AbstractVector, ctx)
    rows = Cell(@computation collect(Int, p.compute_rows(input)))
    PickingIoMap(p, input, Cell(@computation input[rows[]]), rows)
end

# The path of the output for the path `path` of the input, or `nothing` for an
# item that is not picked.
function _map_picked_forward(rows, path)
    @reference_case path begin
        [i].rest... => begin
            j = findfirst(==(i), rows)
            j === nothing ? nothing : ConcreteReference(ElementReferenceStep(j), rest)
        end
        __ => path
    end
end

function map_reference_forward(p::PickingProjection, iomap::PickingIoMap, reference)
    @reference_case reference begin
        [i].rest... => begin
            j = findfirst(==(i), iomap.rows)
            j === nothing && return nothing
            ConcreteReference(get_reference_node_type(iomap.output), ElementReferenceStep(j), rest)
        end
        __ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::PickingProjection, iomap::PickingIoMap, reference)
    @reference_case reference begin
        [j].rest... => begin
            rows = iomap.rows
            (1 <= j <= length(rows)) || return nothing
            ConcreteReference(get_reference_node_type(iomap.input), ElementReferenceStep(rows[j]), rest)
        end
        __ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

make_arrangement_projection(filter::ArrangementFilter) =
    PickingProjection(items -> compute_filter_rows(filter, items))
make_arrangement_projection(sort::ArrangementSort) =
    PickingProjection(items -> compute_sort_rows(sort, items))

"""
    get_arrangement_value(value) -> Any

The value that a condition compares and a sort orders: `value` itself, or the
`value` of a primitive document. A domain adds a method for the documents of its
values, such as the number of a JSON number.
"""
get_arrangement_value(value) = value
get_arrangement_value(document::PrimitiveDocument) = document.value

# The value at the path `key` inside `item`; the empty path is the item itself.
_find_key_value(item, key::EmptyReference) = get_arrangement_value(item)
_find_key_value(item, key::Reference) = get_arrangement_value(try_evaluate_reference(item, key, nothing))

"""
    compute_filter_rows(filter, items) -> Vector{Int}

The indices of the items of `items` for which every condition of `filter` holds,
in their order.
"""
function compute_filter_rows(filter::ArrangementFilter, items)
    conditions = Any[condition for condition in filter.conditions]
    Int[i for i in 1:length(items) if all(c -> is_condition_holding(c, items[i]), conditions)]
end

"""
    is_condition_holding(condition, item) -> Bool

Whether the value at the key of `condition` inside `item` compares with the value
of `condition` by its operator.
"""
function is_condition_holding(condition::ArrangementCondition, item)
    actual = _find_key_value(item, condition.key)
    expected = condition.value
    operator = condition.operator
    operator === :equal && return isequal(actual, expected)
    operator === :not_equal && return !isequal(actual, expected)
    operator === :contains &&
        return actual !== nothing && occursin(lowercase(string(expected)), lowercase(string(actual)))
    order = compare_arrangement_values(actual, expected)
    operator === :less && return order < 0
    operator === :greater && return order > 0
    operator === :at_most && return order <= 0
    operator === :at_least && return order >= 0
    error("ArrangementCondition: no operator ", repr(operator))
end

"""
    compute_sort_rows(sort, items) -> Vector{Int}

The indices of `items` in the order of the keys of `sort`: by the first key, then
by the next for items that are equal, and in their own order for items that are
equal in every key. A missing value comes last in either direction.
"""
function compute_sort_rows(sort::ArrangementSort, items)
    keys = Any[key for key in sort.keys]
    values = [Any[_find_key_value(items[i], key.key) for key in keys] for i in 1:length(items)]
    before(i, j) = begin
        for (n, key) in enumerate(keys)
            a, b = values[i][n], values[j][n]
            _is_missing_value(a) != _is_missing_value(b) && return _is_missing_value(b)
            order = compare_arrangement_values(a, b)
            order == 0 && continue
            return key.direction === :descending ? order > 0 : order < 0
        end
        false
    end
    Base.sort(collect(1:length(items)); lt = before, alg = MergeSort)
end

_is_missing_value(value) = value === nothing || value === missing

"""
    compare_arrangement_values(a, b) -> Int

The order of two values, -1, 0 or 1: numbers before text, text before other
values, and a missing value last; two values of one kind in their own order, and
two other values in the order of their text.
"""
function compare_arrangement_values(a, b)
    rank_a, rank_b = _get_value_rank(a), _get_value_rank(b)
    rank_a == rank_b || return cmp(rank_a, rank_b)
    rank_a == 1 && return cmp(a, b)
    rank_a == 2 && return cmp(String(a), String(b))
    rank_a == 3 && return cmp(string(a), string(b))
    0
end

_get_value_rank(value) = value isa Real ? 1 : value isa AbstractString ? 2 : _is_missing_value(value) ? 4 : 3
