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

While a value that the rows read is provisional, such as a key that a task still
reads, the stage keeps its last final rows (`make_final_holding_cell`) that still
name items of the input, so a table keeps its order until the sort is final.

A filter over a `CellVector` keeps one cell for each item, which says whether the
conditions hold for it, by the identity of the cell of the item. So a change of
one item computes the cell of that item, and the rows compute again only when the
answer of that cell changes.
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

# The rows that a filter keeps, as a function of the items.
struct _FilterRows <: Function
    filter::Any
end

(rows::_FilterRows)(items) = compute_filter_rows(rows.filter, items)

# The cell of each item of a `CellVector` that one description computed, such as
# the conditions of a filter, in the order of `elements`, the cells of the items.
mutable struct _ItemCells
    description::Any
    elements::Any
    cells::Vector{Cell}
end

function print_document(p::PickingProjection, recursion, input::CellVector, ctx)
    rows = _make_picked_rows(p, input)
    # The output has the element type of the input, so a printer that draws a
    # collection of one kind of element draws the picked items as it draws them all.
    output = CellVector{find_declared_element_type(input)}()
    set_cell_computation!(getfield(output, :elements), () -> Cell[Cell(input[i]) for i in rows[]])
    set_output_path_computations!(output, input, path -> _map_picked_forward(rows[], path))
    PickingIoMap(p, input, output, rows)
end

function print_document(p::PickingProjection, recursion, input::AbstractVector, ctx)
    rows = _make_picked_rows(p, input)
    PickingIoMap(p, input, Cell(@computation input[rows[]]), rows)
end

# The rows of `input` that `p` picks, which keep their last final value while a
# value that they read is provisional, as long as each of them names an item.
_make_picked_rows(p::PickingProjection, input) =
    make_final_holding_cell(_make_rows_computation(p.compute_rows, input);
                            is_usable = rows -> all(row -> 1 <= row <= length(input), rows))

# The computation of the rows that `compute_rows` picks of `input`. A filter over a
# `CellVector` keeps the cells of its items from one computation to the next.
_make_rows_computation(compute_rows, input) = () -> collect(Int, compute_rows(input))

function _make_rows_computation(rows::_FilterRows, input::CellVector)
    cells = _ItemCells(nothing, nothing, Cell[])
    () -> _compute_kept_rows(rows.filter, input, cells)
end

# A document that holds no items of its own passes through, with no rows, so a
# recursion inside it can arrange the items where it prints them.
print_document(p::PickingProjection, recursion, input, ctx) = PickingIoMap(p, input, input, Cell(nothing))

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
    (iomap.rows === nothing || _is_later_introduced(p, reference)) && return reference
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
    (iomap.rows === nothing || _is_later_introduced(p, reference)) && return reference
    @reference_case reference begin
        [j].rest... => begin
            rows = iomap.rows
            (1 <= j <= length(rows)) || return nothing
            ConcreteReference(get_reference_node_type(iomap.input), ElementReferenceStep(rows[j]), rest)
        end
        __ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

# Whether `reference` names a part that a later stage of the chain drew, such as
# the chips of the bar: the step stands at the place, which is the input and the
# output of this stage alike, so the path passes through.
_is_later_introduced(p::Projection, reference) =
    is_introduced_reference(reference) && !is_introduced_reference(reference, p)

make_arrangement_projection(filter::ArrangementFilter) = PickingProjection(_FilterRows(filter))
make_arrangement_projection(sort::ArrangementSort) =
    PickingProjection(items -> compute_sort_rows(sort, items))
# A find picks nothing: its stage passes the items as they are, and the bar shows
# its field.
make_arrangement_projection(::ArrangementFind) = IdentityProjection()

"""
    get_arrangement_value(value) -> Any

The value that a condition compares and a sort orders: `value` itself, or the
`value` of a primitive document. A domain adds a method for the documents of its
values, such as the number of a JSON number.
"""
get_arrangement_value(value) = value
get_arrangement_value(document::PrimitiveDocument) = document.value

"""
    find_arrangement_key_value(item, key::Reference) -> Any

The value at the path `key` inside `item`, which a condition compares and a sort
orders: the value of `item` itself for the empty path, and else the value that
the path reaches, each read with `get_arrangement_value`; `nothing` when the path
reaches nothing. A kind of item whose keys are not only the paths of its fields
adds a method, as a row of a roster does for its columns.
"""
function find_arrangement_key_value(item, key::Reference)
    key isa EmptyReference && return get_arrangement_value(item)
    get_arrangement_value(try_evaluate_reference(item, key, nothing))
end

"""
    compute_filter_rows(filter, items) -> Vector{Int}

The indices of the items of `items` for which every condition of `filter` holds,
in their order.
"""
function compute_filter_rows(filter::ArrangementFilter, items)
    conditions = _read_conditions(filter)
    Int[i for i in 1:length(items) if _is_kept(conditions, items[i])]
end

# The conditions of `filter` as plain values, each its key, its operator and its
# value, read through their cells.
_read_conditions(filter::ArrangementFilter) =
    Tuple((condition.key, condition.operator, condition.value) for condition in filter.conditions)

_is_kept(conditions, item) = all(c -> _is_condition_holding(c[1], c[2], c[3], item), conditions)

# The rows that `filter` keeps of `input`, from the cell of each item, which keeps
# its answer while the item and the conditions stay the same.
function _compute_kept_rows(filter::ArrangementFilter, input::CellVector, memo::_ItemCells)
    conditions = _read_conditions(filter)
    cells = _follow_item_cells!(memo, conditions, getfield(input, :elements)[],
                                element -> Cell(Computation(() -> _is_kept(conditions, unwrap_cell(element)))))
    Int[i for (i, cell) in enumerate(cells) if cell[]::Bool]
end

# The cells of `memo` for the cells of the items `elements` and the description
# `description`: the same cell for an item that stays, a new cell from
# `make_cell(element)` for a new item, and new cells for every item after the
# description changed.
function _follow_item_cells!(memo::_ItemCells, description, elements, make_cell)
    isequal(memo.description, description) || (memo.description = description; memo.elements = nothing)
    memo.elements === elements && return memo.cells
    known = IdDict{Any,Cell}()
    memo.elements === nothing || foreach((element, cell) -> known[element] = cell, memo.elements, memo.cells)
    memo.cells = Cell[get(() -> make_cell(element), known, element) for element in elements]
    memo.elements = elements
    memo.cells
end

"""
    is_condition_holding(condition, item) -> Bool

Whether the value at the key of `condition` inside `item` compares with the value
of `condition` by its operator. A key that is `nothing` stands for any value
inside `item`, at any depth: the condition holds when one of them holds it, as
the quick text field of a bar keeps the items where any value contains its text.
An empty text is contained in every item.
"""
is_condition_holding(condition::ArrangementCondition, item) =
    _is_condition_holding(condition.key, condition.operator, condition.value, item)

function _is_condition_holding(key, operator::Symbol, expected, item)
    if key === nothing
        operator === :contains && isempty(string(expected)) && return true
        return _is_any_value_holding(operator, expected, item, IdSet{Any}(), 0)
    end
    _is_value_holding(operator, find_arrangement_key_value(item, key), expected)
end

# Whether `actual` compares with `expected` by `operator`.
function _is_value_holding(operator::Symbol, actual, expected)
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

# Whether any value inside `node` compares with `expected` by `operator`: the value
# of `node` itself when it is a leaf, and else the values of its elements and of
# the fields of a document that are no view state. `seen` keeps a value that two
# places share from a second walk, and the depth ends a walk of a deep structure.
function _is_any_value_holding(operator, expected, node, seen, depth::Int)
    depth > 32 && return false
    value = unwrap_cell(get_arrangement_value(node))
    _is_leaf_value(value) && return _is_value_holding(operator, value, expected)
    (value === nothing || value in seen) && return false
    push!(seen, value)
    if value isa AbstractVector || value isa Tuple || value isa NamedTuple
        return any(element -> _is_any_value_holding(operator, expected, element, seen, depth + 1), value)
    end
    value isa Document || return false
    for name in fieldnames(typeof(value))
        is_view_state_field(name) && continue
        _is_any_value_holding(operator, expected, getfield(value, name), seen, depth + 1) && return true
    end
    false
end

_is_leaf_value(value) = value isa Union{AbstractString, Number, Symbol, AbstractChar}

"""
    compute_sort_rows(sort, items) -> Vector{Int}

The indices of `items` in the order of the keys of `sort`: by the first key, then
by the next for items that are equal, and in their own order for items that are
equal in every key. A missing value comes last in either direction.
"""
function compute_sort_rows(sort::ArrangementSort, items)
    keys = Any[key for key in sort.keys]
    values = [Any[find_arrangement_key_value(items[i], key.key) for key in keys] for i in 1:length(items)]
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
