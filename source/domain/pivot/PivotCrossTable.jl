# Fragment of `PivotModule`.
#
# The cross table of a pivot: the row keys, the column keys, and the rows of the
# source in each cell where a row key and a column key meet. One pass over the
# source gives each row the code of its value in each dimension; the codes of
# the row dimensions and of the column dimensions give the cell of the row; a
# stable sort of the rows by their cells gives the part of each cell as a range
# of one vector. So a part is an index vector, and no value is copied.

"""
    PivotTotal()

The value of a dimension in the key of a total: the part of every value of the
dimension. A key `("EU", PivotTotal())` is the subtotal of the region EU, and a
key of only `PivotTotal()` values is the total. A header shows it as `total`.
"""
struct PivotTotal end

const _PIVOT_TOTAL = PivotTotal()

"""
    PivotBin(low, high)

The value of a number in a dimension with bins: the bin from `low`, which it
holds, to `high`, which it does not. Bins follow each other by `low`.
"""
struct PivotBin
    low::Float64
    high::Float64
end

Base.isless(a::PivotBin, b::PivotBin) = isless(a.low, b.low)

"""
    PivotMonth(year, month)

The value of a date in a dimension by month. Months follow each other by year,
then by month.
"""
struct PivotMonth
    year::Int
    month::Int
end

Base.isless(a::PivotMonth, b::PivotMonth) = isless((a.year, a.month), (b.year, b.month))

# The value of `value` in a dimension whose bin is `bin`: the value itself, the
# bin of a number, or a part of a date. A value that the bin does not fit, such
# as `missing`, stays as it is.
_bin_pivot_value(value, ::Nothing) = value
_bin_pivot_value(value::Real, width::Real) =
    (low = floor(value / width) * width; PivotBin(low, low + width))
_bin_pivot_value(value::Dates.TimeType, part::Symbol) =
    part === :year ? Dates.year(value) :
    part === :month ? PivotMonth(Dates.year(value), Dates.month(value)) :
    part === :day ? Dates.Date(value) : value
_bin_pivot_value(value, ::Any) = value

# How many values a column dimension shows with no limit of its own. A dimension
# with more values is cut there, and its badge says how many it has, because a
# column of each value of a column of numbers would make a table too wide to draw.
const _PIVOT_MANY_VALUES = 200

"""
    PivotCrossTable

The parts of a pivot. `row_keys[r]` is the tuple of the values of the row
dimensions of row `r`, and `column_keys[c]` the same for column `c`, each in the
order of their dimensions. Only the keys that occur in the source are there,
and the keys of the totals; `row_index` and `column_index` give the number of
each key. The rows of the source in the cell of row `r` and column `c` are
[`find_pivot_part_rows`](@ref)`(cross, r, c)`, in the order of the source.

The keys with no total are the details. `row_details` and `column_details` give,
for each row and column, the range of the details that it covers: a detail
covers itself, and a total the run of the details under its prefix, because the
details sort by their prefixes. `detail_row_keys` are the details of the rows.
The parts of the details are ranges of `part_rows` by the number of their cell
among the details; a total gathers the parts of its details when it is read.
"""
struct PivotCrossTable
    row_keys::Vector{Tuple}
    column_keys::Vector{Tuple}
    row_index::Dict{Tuple,Int}
    column_index::Dict{Tuple,Int}
    part_rows::Vector{Int}
    part_ranges::Dict{Int,UnitRange{Int}}
    row_details::Vector{UnitRange{Int}}
    column_details::Vector{UnitRange{Int}}
    detail_row_keys::Vector{Tuple}
    detail_width::Int
end

# The number of each key. `isequal` compares the keys, so a key with `missing`
# finds its number too.
_make_key_index(keys::Vector{Tuple}) = Dict{Tuple,Int}(key => k for (k, key) in enumerate(keys))

get_pivot_row_count(cross::PivotCrossTable) = length(cross.row_keys)
get_pivot_column_count(cross::PivotCrossTable) = length(cross.column_keys)

"""
    find_pivot_part_rows(cross, row, column) -> Union{AbstractVector{Int}, Nothing}

The rows of the source in the cell of row `row` and column `column` of `cross`,
in the order of the source; `nothing` when no row of the source has that row
key and that column key. The part of a total is gathered from the parts of the
details that it covers.
"""
function find_pivot_part_rows(cross::PivotCrossTable, row::Integer, column::Integer)
    rows, columns = cross.row_details[row], cross.column_details[column]
    if length(rows) == 1 && length(columns) == 1
        range = get(cross.part_ranges, _get_cell_number(cross, first(rows), first(columns)), nothing)
        return range === nothing ? nothing : view(cross.part_rows, range)
    end
    gathered = Int[]
    for r in rows, c in columns
        range = get(cross.part_ranges, _get_cell_number(cross, r, c), nothing)
        range === nothing || append!(gathered, view(cross.part_rows, range))
    end
    isempty(gathered) ? nothing : sort!(gathered)
end

"""
    find_pivot_part_rows(cross, row_key::Tuple, column_key::Tuple) -> Union{AbstractVector{Int}, Nothing}

The rows of the source in the cell of the row with the key `row_key` and the
column with the key `column_key`; `nothing` when either key does not occur, or
no row has both.
"""
function find_pivot_part_rows(cross::PivotCrossTable, row_key::Tuple, column_key::Tuple)
    row = get(cross.row_index, row_key, nothing)
    column = get(cross.column_index, column_key, nothing)
    (row === nothing || column === nothing) ? nothing : find_pivot_part_rows(cross, row, column)
end

# The number of the cell of detail row `row` and detail column `column`.
_get_cell_number(cross::PivotCrossTable, row::Integer, column::Integer) =
    (Int(row) - 1) * cross.detail_width + Int(column)

"""
    compute_pivot_cross_table(pivot::PivotTable) -> PivotCrossTable
    compute_pivot_cross_table(table, row_dimensions, column_dimensions;
                              measure = nothing, totals = false, collapsed = ()) -> PivotCrossTable

The cross table of `table` by its row and its column dimensions. A pivot with no
row dimension has one row, whose key is the empty tuple, and the same holds for
the columns. A row of the source whose value in a dimension is one of its
`hidden_values`, or past its `limit`, is in no part. The keys follow the order
of each dimension, the first dimension first; `measure` is what an order by the
measure reads. `column_limit`, when it is not 0, is the limit of a column
dimension that has none of its own; a pivot sets it, so a column of thousands of
values does not make a table of thousands of columns.

With `totals`, a subtotal row follows each run of an outer row dimension, a
total row follows every row, and a total column every column. A run whose key
prefix is in `collapsed` shows only its subtotal row, with or without `totals`.
"""
function compute_pivot_cross_table(pivot::PivotTable)
    pivot.source_version
    compute_pivot_cross_table(pivot.source, collect(pivot.row_dimensions), collect(pivot.column_dimensions);
                              measure = first(get_pivot_measures(pivot)), totals = pivot.totals,
                              collapsed = collect(pivot.collapsed), column_limit = _PIVOT_MANY_VALUES)
end

function compute_pivot_cross_table(table, row_dimensions::AbstractVector, column_dimensions::AbstractVector;
                                   measure = nothing, totals::Bool = false, collapsed = (), column_limit::Int = 0)
    count = get_table_row_count(table)
    row_codes, detail_rows = _compute_key_codes(table, row_dimensions, count, measure)
    column_codes, detail_columns = _compute_key_codes(table, column_dimensions, count, measure, column_limit)
    width = max(1, length(detail_columns))
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
    row_keys, row_details = _make_axis_keys(detail_rows, length(row_dimensions), totals, Any[collapsed...])
    column_keys, column_details = _make_axis_keys(detail_columns, length(column_dimensions), totals, Any[])
    PivotCrossTable(row_keys, column_keys, _make_key_index(row_keys), _make_key_index(column_keys),
                    part_rows, part_ranges, row_details, column_details, detail_rows, width)
end

# The keys of an axis, and the range of the details that each covers: the
# details, a subtotal after each run of an outer level with `totals` or when its
# prefix is in `collapsed`, and the total last with `totals`.
function _make_axis_keys(details::Vector{Tuple}, levels::Int, totals::Bool, collapsed::Vector{Any})
    (levels == 0 || (!totals && isempty(collapsed))) && return (details, UnitRange{Int}[d:d for d in eachindex(details)])
    keys = Tuple[]
    ranges = UnitRange{Int}[]
    _add_axis_group!(keys, ranges, details, 1, length(details), 0, levels, totals, collapsed)
    if totals && !isempty(details)
        push!(keys, ntuple(_ -> _PIVOT_TOTAL, levels))
        push!(ranges, 1:length(details))
    end
    (keys, ranges)
end

# The keys of `details[low:high]`, which share their first `depth` values: each
# run of the next level, open or closed, and its subtotal.
function _add_axis_group!(keys, ranges, details, low::Int, high::Int, depth::Int, levels::Int, totals::Bool,
                          collapsed::Vector{Any})
    if depth == levels
        for d in low:high
            push!(keys, details[d])
            push!(ranges, d:d)
        end
        return
    end
    d = low
    while d <= high
        value = details[d][depth + 1]
        e = d
        while e < high && isequal(details[e + 1][depth + 1], value)
            e += 1
        end
        prefix = details[d][1:(depth + 1)]
        closed = depth + 1 < levels && any(isequal(prefix), collapsed)
        closed || _add_axis_group!(keys, ranges, details, d, e, depth + 1, levels, totals, collapsed)
        if depth + 1 < levels && (totals || closed)
            push!(keys, (prefix..., ntuple(_ -> _PIVOT_TOTAL, levels - depth - 1)...))
            push!(ranges, d:e)
        end
        d = e + 1
    end
end

# The code of the key of each row of the source by `dimensions`, from 1 in the
# order of the keys, or 0 for a row that a hidden value, or a value past the
# limit of its dimension, leaves out; and the keys. With no dimension, every row
# has the one empty key.
function _compute_key_codes(table, dimensions::AbstractVector, count::Int, measure = nothing,
                            default_limit::Int = 0)
    isempty(dimensions) && return (fill(1, count), Tuple[()])
    levels = [_compute_value_codes(table, dimension, count) for dimension in dimensions]
    # Each value has its rank in the order of its dimension, and a limit leaves
    # out the values past it.
    ranks = [_compute_value_ranks(values, dimension, table, codes, measure)
             for ((codes, values), dimension) in zip(levels, dimensions)]
    for (d, dimension) in enumerate(dimensions)
        limit = dimension.limit > 0 ? dimension.limit : default_limit
        limit > 0 && _limit_value_codes!(levels[d][1], ranks[d], limit)
    end
    sizes = [length(values) for (_, values) in levels]
    value_codes = Vector{Int}[codes for (codes, _) in levels]
    codes, combinations = _compute_combination_codes(value_codes, sizes, count,
                                                      _is_radix_size(sizes) ? Int : Vector{Int})
    # The keys sort by the ranks of their values, the first dimension first.
    digits = [_split_combination(combination, sizes) for combination in combinations]
    order = sortperm(digits; by = digit -> Tuple(ranks[d][digit[d]] for d in eachindex(digit)))
    place = invperm(order)
    for r in 1:count
        codes[r] == 0 || (codes[r] = place[codes[r]])
    end
    key_list = Tuple[Tuple(levels[d][2][digit[d]] for d in eachindex(digit)) for digit in digits[order]]
    (codes, key_list)
end

# Leave out the values of a dimension past the first `limit` in the order of
# their ranks, among the values that some row has.
function _limit_value_codes!(codes::Vector{Int}, ranks::Vector{Int}, limit::Int)
    present = falses(length(ranks))
    for code in codes
        code > 0 && (present[code] = true)
    end
    shown = sort!(findall(present); by = code -> ranks[code])
    length(shown) <= limit && return codes
    dropped = BitSet(shown[(limit + 1):end])
    for r in eachindex(codes)
        codes[r] in dropped && (codes[r] = 0)
    end
    codes
end

# The value code of each row of the source in `dimension`, from 1 in the order in
# which the values first occur, or 0 for a hidden value; and the values.
function _compute_value_codes(table, dimension, count::Int)
    column = find_table_column(table, dimension.column)
    values = column === nothing ? [get_table_value(table, r, dimension.column) for r in 1:count] : column
    bin = dimension.bin
    bin === nothing || (values = [_bin_pivot_value(value, bin) for value in values])
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

# The rank of each value of a dimension in its order: by the values, by their
# first occurrence, or by the value of `measure` over the rows of each value.
# `missing` is last in either direction.
function _compute_value_ranks(values::AbstractVector, dimension, table, codes::Vector{Int}, measure)
    order = if dimension.order === :first
        collect(1:length(values))
    elseif dimension.order === :measure && measure !== nothing
        scores = _compute_value_scores(values, table, codes, measure)
        sortperm(collect(eachindex(values)); lt = (a, b) -> _is_value_before(scores[a], scores[b]))
    else
        sortperm(values; lt = _is_value_before)
    end
    dimension.descending && reverse!(order)
    absent = findfirst(k -> ismissing(values[k]), order)
    absent === nothing || push!(order, popat!(order, absent))
    invperm(order)
end

# The value of `measure` over the rows of each value of a dimension, by its code;
# `missing` for a value that no row keeps.
function _compute_value_scores(values::AbstractVector, table, codes::Vector{Int}, measure)
    rows = [Int[] for _ in values]
    for (r, code) in enumerate(codes)
        code > 0 && push!(rows[code], r)
    end
    Any[isempty(rows[k]) ? missing : compute_pivot_measure(table, rows[k], measure) for k in eachindex(values)]
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
