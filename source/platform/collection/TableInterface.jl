# Fragment of `CollectionModule`.
#
# The table interface: what a stage reads of a table, whatever kind of value
# holds its rows. A table has rows, numbered from 1, and columns, each with a
# name. A kind of table adds a method to each function below; a kind that holds a
# column as a vector, or that has a view of its own rows, says so.

"""
    is_table(value) -> Bool

Whether `value` is a table that the functions of the table interface read:
[`get_table_row_count`](@ref), [`get_table_column_names`](@ref),
[`get_table_column_type`](@ref), [`get_table_value`](@ref),
[`find_table_column`](@ref) and [`make_table_part`](@ref).

A vector of named tuples, a named tuple of vectors of one length, and a
[`TablePart`](@ref) are tables. A package that owns a kind of table adds the
methods for it: `ProjecturedDataFrames` adds them for an `AbstractDataFrame`.
"""
is_table(::Any) = false

"""
    get_table_row_count(table) -> Int

The count of the rows of `table`.
"""
function get_table_row_count end

"""
    get_table_column_names(table) -> Vector{String}

The names of the columns of `table`, in their order.
"""
function get_table_column_names end

"""
    get_table_column_type(table, column::AbstractString) -> Type

The type of the values in column `column` of `table`: `Any` when the kind of
table does not know it.
"""
get_table_column_type(::Any, ::AbstractString) = Any

"""
    get_table_value(table, row::Integer, column::AbstractString)

The value in row `row` and column `column` of `table`.
"""
function get_table_value end

"""
    find_table_column(table, column::AbstractString) -> Union{AbstractVector, Nothing}

The values of column `column` of `table` as a vector, in the order of the rows
and with no copy, when the kind of table holds one; `nothing` when it does not.
A stage that reads a whole column reads it here first, because a read of each
value with [`get_table_value`](@ref) costs a call for each row.
"""
find_table_column(::Any, ::AbstractString) = nothing

"""
    make_table_part(table, rows::AbstractVector{<:Integer})

The part of `table` that holds its rows `rows`, in that order, with no copy. A
kind of table that has a view of its own rows gives it, so an edit of the part
writes the table: a `SubDataFrame` for a data frame. Any other kind gives a
[`TablePart`](@ref).
"""
make_table_part(table, rows::AbstractVector{<:Integer}) = TablePart(table, collect(Int, rows))

"""
    TablePart(table, rows)

The rows `rows` of `table`, in that order, read through the table interface
with no copy. It is a table itself: row `r` of the part is row `rows[r]` of
`table`, and a part of a part is a part of `table`.
"""
struct TablePart
    table::Any
    rows::Vector{Int}
end

is_table(::TablePart) = true
get_table_row_count(part::TablePart) = length(part.rows)
get_table_column_names(part::TablePart) = get_table_column_names(part.table)
get_table_column_type(part::TablePart, column::AbstractString) = get_table_column_type(part.table, column)
get_table_value(part::TablePart, row::Integer, column::AbstractString) =
    get_table_value(part.table, part.rows[row], column)

function find_table_column(part::TablePart, column::AbstractString)
    values = find_table_column(part.table, column)
    values === nothing ? nothing : view(values, part.rows)
end

make_table_part(part::TablePart, rows::AbstractVector{<:Integer}) = TablePart(part.table, part.rows[rows])

# ── A vector of named tuples ─────────────────────────────────────────────────
# Each element is a row, and the names of its fields are the columns. The
# names come from the type of the elements, or from the first row when the
# elements have no one type.

is_table(rows::AbstractVector{<:NamedTuple}) = true
get_table_row_count(rows::AbstractVector{<:NamedTuple}) = length(rows)

function get_table_column_names(rows::AbstractVector{<:NamedTuple})
    type = eltype(rows)
    isconcretetype(type) && return String[string(name) for name in fieldnames(type)]
    isempty(rows) ? String[] : String[string(name) for name in keys(first(rows))]
end

function get_table_column_type(rows::AbstractVector{<:NamedTuple}, column::AbstractString)
    type = eltype(rows)
    name = Symbol(column)
    (isconcretetype(type) && name in fieldnames(type)) ? fieldtype(type, name) : Any
end

get_table_value(rows::AbstractVector{<:NamedTuple}, row::Integer, column::AbstractString) =
    getproperty(rows[row], Symbol(column))

# ── A named tuple of vectors ─────────────────────────────────────────────────
# Each field is a column, and every column has the same length.

is_table(columns::NamedTuple) =
    all(value -> value isa AbstractVector, values(columns)) &&
    allequal(length(value) for value in values(columns))

get_table_row_count(columns::NamedTuple) = isempty(columns) ? 0 : length(first(columns))
get_table_column_names(columns::NamedTuple) = String[string(name) for name in keys(columns)]
get_table_column_type(columns::NamedTuple, column::AbstractString) = eltype(getproperty(columns, Symbol(column)))
get_table_value(columns::NamedTuple, row::Integer, column::AbstractString) =
    getproperty(columns, Symbol(column))[row]
find_table_column(columns::NamedTuple, column::AbstractString) = getproperty(columns, Symbol(column))
