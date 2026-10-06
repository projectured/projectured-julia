# Fragment of `PivotModule`.
#
# The cross table of a pivot: the row keys, the column keys, and the rows of the
# source in each cell where a row key and a column key meet. One pass over the
# source gives each row the code of its value in each dimension; the codes of
# the row dimensions and of the column dimensions give the cell of the row; a
# stable sort of the rows by their cells gives the part of each cell as a range
# of one vector. So a part is an index vector, and no value is copied.

"""
    PivotCrossTable

The parts of a pivot. `row_keys[r]` is the tuple of the values of the row
dimensions of row `r`, and `column_keys[c]` the same for column `c`, each in the
order of their dimensions. Only the keys that occur in the source are there. The
rows of the source in the cell of row `r` and column `c` are
[`find_pivot_part_rows`](@ref)`(cross, r, c)`, in the order of the source.
"""
struct PivotCrossTable
    row_keys::Vector{Tuple}
    column_keys::Vector{Tuple}
    part_rows::Vector{Int}
    part_ranges::Dict{Int,UnitRange{Int}}
end

get_pivot_row_count(cross::PivotCrossTable) = length(cross.row_keys)
get_pivot_column_count(cross::PivotCrossTable) = length(cross.column_keys)

"""
    find_pivot_part_rows(cross, row, column) -> Union{AbstractVector{Int}, Nothing}

The rows of the source in the cell of row `row` and column `column` of `cross`,
in the order of the source; `nothing` when no row of the source has that row
key and that column key.
"""
function find_pivot_part_rows(cross::PivotCrossTable, row::Integer, column::Integer)
    range = get(cross.part_ranges, _get_cell_number(cross, row, column), nothing)
    range === nothing ? nothing : view(cross.part_rows, range)
end

_get_cell_number(cross::PivotCrossTable, row::Integer, column::Integer) =
    (Int(row) - 1) * max(1, length(cross.column_keys)) + Int(column)

"""
    compute_pivot_cross_table(pivot::PivotTable) -> PivotCrossTable
    compute_pivot_cross_table(table, row_dimensions, column_dimensions) -> PivotCrossTable

The cross table of `table` by its row and its column dimensions. A pivot with no
row dimension has one row, whose key is the empty tuple, and the same holds for
the columns. A row of the source whose value in a dimension is one of its
`hidden_values` is in no part. The keys follow the order of each dimension,
the first dimension first.
"""
function compute_pivot_cross_table(pivot::PivotTable)
    pivot.source_version
    compute_pivot_cross_table(pivot.source, collect(pivot.row_dimensions), collect(pivot.column_dimensions))
end

function compute_pivot_cross_table(table, row_dimensions::AbstractVector, column_dimensions::AbstractVector)
    count = get_table_row_count(table)
    row_codes, row_keys = _compute_key_codes(table, row_dimensions, count)
    column_codes, column_keys = _compute_key_codes(table, column_dimensions, count)
    width = max(1, length(column_keys))
    cells = Vector{Int}(undef, count)
    for r in 1:count
        row, column = row_codes[r], column_codes[r]
        cells[r] = (row == 0 || column == 0) ? 0 : (row - 1) * width + column
    end
    order = sortperm(cells)
    part_ranges = Dict{Int,UnitRange{Int}}()
    first = findfirst(k -> cells[k] != 0, order)
    part_rows = first === nothing ? Int[] : order[first:end]
    start = 1
    for k in eachindex(part_rows)
        cell = cells[part_rows[k]]
        if k == length(part_rows) || cells[part_rows[k + 1]] != cell
            part_ranges[cell] = start:k
            start = k + 1
        end
    end
    PivotCrossTable(row_keys, column_keys, part_rows, part_ranges)
end

# The code of the key of each row of the source by `dimensions`, from 1 in the
# order of the keys, or 0 for a row that a hidden value leaves out; and the
# keys. With no dimension, every row has the one empty key.
function _compute_key_codes(table, dimensions::AbstractVector, count::Int)
    isempty(dimensions) && return (fill(1, count), Tuple[()])
    levels = [_compute_value_codes(table, dimension, count) for dimension in dimensions]
    sizes = [length(values) for (_, values) in levels]
    value_codes = Vector{Int}[codes for (codes, _) in levels]
    codes, combinations = _compute_combination_codes(value_codes, sizes, count,
                                                      _is_radix_size(sizes) ? Int : Vector{Int})
    # The keys in the order of the dimensions: each value has its rank in the
    # order of its dimension, and the keys sort by their ranks, the first
    # dimension first.
    ranks = [_compute_value_ranks(values, dimension) for ((_, values), dimension) in zip(levels, dimensions)]
    digits = [_split_combination(combination, sizes) for combination in combinations]
    order = sortperm(digits; by = digit -> Tuple(ranks[d][digit[d]] for d in eachindex(digit)))
    place = invperm(order)
    for r in 1:count
        codes[r] == 0 || (codes[r] = place[codes[r]])
    end
    key_list = Tuple[Tuple(levels[d][2][digit[d]] for d in eachindex(digit)) for digit in digits[order]]
    (codes, key_list)
end

# The value code of each row of the source in `dimension`, from 1 in the order in
# which the values first occur, or 0 for a hidden value; and the values.
function _compute_value_codes(table, dimension, count::Int)
    column = find_table_column(table, dimension.column)
    values = column === nothing ? [get_table_value(table, r, dimension.column) for r in 1:count] : column
    _compute_value_codes(values, Any[dimension.hidden_values...])
end

function _compute_value_codes(values::AbstractVector{T}, hidden::Vector{Any}) where {T}
    index = Dict{T,Int}()
    found = T[]
    codes = Vector{Int}(undef, length(values))
    for (r, value) in enumerate(values)
        codes[r] = get!(index, value) do
            push!(found, value)
            length(found)
        end
    end
    if !isempty(hidden)
        left_out = BitSet(code for (code, value) in enumerate(found) if any(isequal(value), hidden))
        for r in eachindex(codes)
            codes[r] in left_out && (codes[r] = 0)
        end
    end
    (codes, found)
end

# The rank of each value of a dimension in its order. `missing` is last in
# either direction.
function _compute_value_ranks(values::AbstractVector, dimension)
    order = dimension.order === :first ? collect(1:length(values)) :
            sortperm(values; lt = _is_value_before)
    dimension.descending && reverse!(order)
    absent = findfirst(k -> ismissing(values[k]), order)
    absent === nothing || push!(order, popat!(order, absent))
    invperm(order)
end

# The code of the combination of the values of each row, from 1 in the order in
# which the combinations first occur, or 0 for a row that a hidden value leaves
# out; and the combinations.
function _compute_combination_codes(value_codes::Vector{Vector{Int}}, sizes::Vector{Int}, count::Int,
                                    ::Type{K}) where {K}
    combinations = K[]
    index = Dict{K,Int}()
    codes = Vector{Int}(undef, count)
    for r in 1:count
        combination = _get_combination(value_codes, sizes, r, K)
        codes[r] = combination === nothing ? 0 : get!(index, combination) do
            push!(combinations, combination)
            length(combinations)
        end
    end
    (codes, combinations)
end

# Whether a combination of values fits in one `Int`, in mixed radix over the
# counts of the values of the dimensions.
function _is_radix_size(sizes::Vector{Int})
    product = 1
    for size in sizes
        product, overflow = Base.mul_with_overflow(product, max(1, size))
        overflow && return false
    end
    true
end

# The combination of the values of row `r` in the dimensions: one `Int` in mixed
# radix, or the vector of the value codes when that does not fit; `nothing` for a
# row that a hidden value leaves out.
function _get_combination(value_codes::Vector{Vector{Int}}, sizes::Vector{Int}, r::Int, ::Type{Int})
    combination = 0
    for d in eachindex(value_codes)
        code = value_codes[d][r]
        code == 0 && return nothing
        combination = combination * sizes[d] + (code - 1)
    end
    combination
end

function _get_combination(value_codes::Vector{Vector{Int}}, sizes::Vector{Int}, r::Int, ::Type{Vector{Int}})
    combination = Int[codes[r] for codes in value_codes]
    any(==(0), combination) ? nothing : combination
end

# The value codes of a combination, one for each dimension, the first dimension
# first.
_split_combination(combination::Vector{Int}, ::Vector{Int}) = combination

function _split_combination(combination::Int, sizes::Vector{Int})
    digits = Vector{Int}(undef, length(sizes))
    for d in length(sizes):-1:1
        digits[d] = combination % sizes[d] + 1
        combination ÷= sizes[d]
    end
    digits
end

# The natural order of two values: `isless`, with `missing` last; two values that
# `isless` does not compare, such as a number and a text, compare by their texts.
function _is_value_before(a, b)
    try
        isless(a, b)
    catch
        isless(string(a), string(b))
    end
end

"""
    compute_pivot_measure(table, rows, measure::PivotMeasure)

The value of `measure` over the rows `rows` of `table`. A `missing` value counts
for `:count` and for nothing else. `:sum` of no value is `0`; `:mean`,
`:minimum` and `:maximum` of no value are `missing`.
"""
function compute_pivot_measure(table, rows::AbstractVector{<:Integer}, measure)
    aggregate = measure.aggregate
    aggregate === :count && return length(rows)
    column = find_table_column(table, measure.column)
    values = column === nothing ? [get_table_value(table, r, measure.column) for r in rows] : view(column, rows)
    present = skipmissing(values)
    aggregate === :sum && return isempty(present) ? 0 : sum(present)
    aggregate === :distinct_count && return length(unique(present))
    isempty(present) && return missing
    aggregate === :mean && return sum(present) / count(_ -> true, present)
    aggregate === :minimum && return minimum(present)
    aggregate === :maximum && return maximum(present)
    throw(ArgumentError("a pivot measure has no aggregate :$aggregate"))
end
