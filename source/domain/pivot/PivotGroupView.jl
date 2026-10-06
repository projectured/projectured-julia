# Fragment of `PivotModule`.
#
# The group layout of a pivot: the rows of the source in the order of their
# groups, each in line with the others under the columns of the source, and the
# row headers that name the group of each row. The labels of the row dimensions
# merge across the rows of a group, so a group shows its key once, and the last
# level of a header is the number of the row in the source. A closed group, a
# closed run and a total are one row that counts the rows that they hold.

describe_pivot_cell_view(::Type{PivotGroupView}) = "rows under their groups"
get_pivot_cell_view_lines(::PivotGroupView) = 1

# A path that names a cell of the pivot reaches the table of its part, as in the
# rows view.
get_pivot_cell_key(pivot::PivotTable, ::PivotGroupView, row_key::Tuple, column_key::Tuple) =
    get_pivot_cell_key(pivot, PivotRowsView(), row_key, column_key)
make_pivot_cell_document(pivot::PivotTable, ::PivotGroupView, row_key::Tuple, column_key::Tuple) =
    make_pivot_cell_document(pivot, PivotRowsView(), row_key, column_key)

# Whether the table of `pivot` shows its rows in groups.
_is_pivot_group_layout(pivot::PivotTable) = get_pivot_cell_view(pivot) isa PivotGroupView

# The rows of the table for each row of the cross table: `parts[r]`, the rows of
# the source that row `r` shows one by one, or `nothing` for a row that is one row
# of the table, a total or a closed group; `held[r]`, the count of the rows of the
# source under row `r`; and `ends[r]`, the last row of the table of row `r`.
struct _PivotGroupRows
    parts::Vector{Any}
    held::Vector{Int}
    ends::Vector{Int}
end

function _get_pivot_group_rows(pivot::PivotTable)
    cross = pivot.cross_table
    collapsed = collect(pivot.collapsed)
    _get_pivot_memo!(pivot, :groups, (objectid(cross), collapsed)) do
        parts, held, ends = Any[], Int[], Int[]
        last = 0
        for (r, key) in enumerate(cross.row_keys)
            rows = Int[]
            for c in 1:get_pivot_column_count(cross)
                part = find_pivot_part_rows(cross, r, c)
                part === nothing || append!(rows, part)
            end
            sort!(rows)
            single = any(value -> value isa PivotTotal, key) || any(isequal(key), collapsed)
            push!(parts, single ? nothing : rows)
            push!(held, length(rows))
            last += single ? 1 : length(rows)
            push!(ends, last)
        end
        _PivotGroupRows(parts, held, ends)
    end
end

# The row of the cross table of row `k` of the table, and the row of the source
# that it shows, or `nothing` for a row that holds a group; `nothing` past the end.
function _find_pivot_group_row(groups::_PivotGroupRows, k::Int)
    r = searchsortedfirst(groups.ends, k)
    r > length(groups.ends) && return nothing
    part = groups.parts[r]
    part === nothing && return (r, nothing)
    (r, part[k - (r == 1 ? 0 : groups.ends[r - 1])])
end

# The key of the row of the cross table that row `k` of the table shows, in the
# layout of `pivot`; `nothing` past the end.
function _get_pivot_table_row_key(pivot::PivotTable, k::Int)
    cross = pivot.cross_table
    if !_is_pivot_group_layout(pivot)
        return 1 <= k <= get_pivot_row_count(cross) ? cross.row_keys[k] : nothing
    end
    found = _find_pivot_group_row(_get_pivot_group_rows(pivot), k)
    found === nothing ? nothing : cross.row_keys[found[1]]
end

# The columns of the source that the group layout shows: the cell dimensions, or
# every column that is no row dimension.
function _get_pivot_group_columns(pivot::PivotTable)
    columns = String[dimension.column for dimension in pivot.cell_dimensions]
    isempty(columns) || return columns
    grouped = Set(dimension.column for dimension in pivot.row_dimensions)
    String[name for name in get_table_column_names(pivot.source) if !(name in grouped)]
end

_make_pivot_group_column_headers(pivot::PivotTable) =
    Any[WidgetLabel(column) for column in _get_pivot_group_columns(pivot)]

# The rows of the table as a list: a row of the source shows its values, and a
# row that holds a group shows the count of its rows.
function _make_pivot_group_row_list(pivot::PivotTable)
    groups = _get_pivot_group_rows(pivot)
    count = isempty(groups.ends) ? 0 : last(groups.ends)
    count == 0 && return CellVector()
    columns = _get_pivot_group_columns(pivot)
    source = pivot.source
    make_index_list(count, 1, k -> begin
        r, row = _find_pivot_group_row(groups, k)
        texts = row === nothing ?
            String[c == 1 ? string(groups.held[r], " rows") : "" for c in eachindex(columns)] :
            String[format_pivot_value(get_table_value(source, row, column)) for column in columns]
        CellVector(Cell[Cell(WidgetLabel(text)) for text in texts])
    end)
end

# The header of each row of the table: the labels of the key of its group, and
# the number of its row in the source, or nothing for a row that holds a group.
function _make_pivot_group_header_list(pivot::PivotTable)
    groups = _get_pivot_group_rows(pivot)
    count = isempty(groups.ends) ? 0 : last(groups.ends)
    count == 0 && return CellVector()
    keys = pivot.cross_table.row_keys
    make_index_list(count, 1, k -> begin
        r, row = _find_pivot_group_row(groups, k)
        labels = collect(_make_pivot_row_labels(pivot, keys[r]))
        CellVector(Any[labels..., WidgetLabel(row === nothing ? "" : string(row))])
    end)
end

# The corner of the group layout: the names of the row dimensions, and # for the
# number of a row.
_make_pivot_group_corner(pivot::PivotTable) =
    CellVector(Any[(dimension.column for dimension in pivot.row_dimensions)..., "#"])
