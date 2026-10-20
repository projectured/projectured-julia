# Fragment of `PivotModule`.
#
# The display of a pivot, which the REPL and the answer of a tool show: a line
# that names the zones of the bar, then the grid of the table as text, with the
# keys of the rows and of the columns, and the value of each measure in each cell
# in a text column of its own. A limited display shows the rows and the columns
# that its display size holds, and says how many it leaves out.

# The fewest rows of the grid that a limited display shows.
const _PIVOT_DISPLAY_MINIMUM_ROWS = 3

# The most names of the Fields zone that a limited display lists.
const _PIVOT_DISPLAY_FIELD_NAMES = 8

function Base.show(io::IO, ::MIME"text/plain", pivot::PivotTable)
    limited = get(io, :limit, false)::Bool
    height, width = displaysize(io)
    println(io, _describe_pivot_zones(pivot, limited))
    cross = pivot.cross_table
    row_count, column_count = get_pivot_row_count(cross), get_pivot_column_count(cross)
    header_lines = _get_pivot_display_header_lines(pivot)
    shown_rows = limited ? min(row_count, max(height - header_lines - 4, _PIVOT_DISPLAY_MINIMUM_ROWS)) : row_count
    left = _make_pivot_display_row_columns(pivot, cross, shown_rows)
    used = sum(textwidth ∘ first, left) + 2 * (length(left) - 1)
    right = Vector{String}[]
    shown_columns = 0
    for c in 1:column_count
        group = _make_pivot_display_value_columns(pivot, cross, c, shown_rows)
        group_width = sum(column -> 2 + textwidth(first(column)), group)
        (limited && shown_columns > 0 && used + group_width > width) && break
        append!(right, group)
        shown_columns += 1
        used += group_width
    end
    for line in 1:(header_lines + shown_rows)
        texts = vcat(String[column[line] for column in left], String[column[line] for column in right])
        println(io, rstrip(join(texts, "  ")))
    end
    row_count == 0 && println(io, "No row of the source is in the pivot.")
    parts = filter(!isempty, [_count_pivot_display_part(row_count - shown_rows, "row"),
                              _count_pivot_display_part(column_count - shown_columns, "column")])
    isempty(parts) ||
        print(io, "⋮ ", join(parts, " and "), " more. `find_pivot_value(pivot, row_key, column_key)` reads one cell.")
    nothing
end

_count_pivot_display_part(count::Int, name::String) =
    count <= 0 ? "" : string(count, " ", name, count == 1 ? "" : "s")

# The line that names the zones of `pivot`, as the bar shows them. A limited line
# lists the first few names of the Fields zone and counts the others.
function _describe_pivot_zones(pivot::PivotTable, limited::Bool)
    describe_items(zone) = String[_describe_pivot_zone_item(item) for item in zone]
    join_items(items) = isempty(items) ? "none" : join(items, ", ")
    fields = describe_items(pivot.unused_dimensions)
    more = limited ? length(fields) - _PIVOT_DISPLAY_FIELD_NAMES : 0
    more > 0 && (fields = push!(fields[1:_PIVOT_DISPLAY_FIELD_NAMES], string("and ", more, " more")))
    parts = String[
        string("PivotTable of ", get_table_row_count(pivot.source), " source rows"),
        "Fields: " * join_items(fields),
        "Columns: " * join_items(describe_items(pivot.column_dimensions)),
        "Rows: " * join_items(describe_items(pivot.row_dimensions)),
        "Cells: " * join(push!(describe_items(pivot.cell_dimensions), _describe_pivot_cells(pivot)), ", "),
        "Values: " * join_items(describe_items(get_pivot_measures(pivot))),
        "Totals: " * (pivot.totals ? "shown" : "hidden")]
    isempty(pivot.collapsed) || push!(parts, string("Closed runs: ", length(pivot.collapsed)))
    join(parts, ". ") * "."
end

# The number of lines of the header of the grid: one for each column dimension,
# and one more that names the measures when there are several, or only that one
# for a pivot with no column dimension.
_get_pivot_display_header_lines(pivot::PivotTable) =
    isempty(pivot.column_dimensions) ? 1 :
        length(pivot.column_dimensions) + (length(get_pivot_measures(pivot)) > 1 ? 1 : 0)

# The columns of the keys of the rows, each padded to its width: one for each row
# dimension, whose last header line names it, or one of `all` for a pivot with
# none.
function _make_pivot_display_row_columns(pivot::PivotTable, cross::PivotCrossTable, shown_rows::Int)
    blank = fill("", _get_pivot_display_header_lines(pivot) - 1)
    leveled = !isempty(pivot.row_dimensions)
    labels = [leveled ? _format_pivot_row_labels(pivot, cross.row_keys[r]) : ["all"] for r in 1:shown_rows]
    corner = leveled ? String[dimension.column for dimension in pivot.row_dimensions] : [""]
    columns = [vcat(blank, [corner[k]], String[label[k] for label in labels]) for k in eachindex(corner)]
    [rpad.(column, maximum(textwidth, column)) for column in columns]
end

# The text columns of the column `c` of the cross table, one for each measure,
# each padded to its width: a header line for each value of the key of the column,
# and a line with the name of the measure when the header has one, then the value
# of the measure in each shown row. A cell that no row reaches is empty.
function _make_pivot_display_value_columns(pivot::PivotTable, cross::PivotCrossTable, c::Int, shown_rows::Int)
    key = cross.column_keys[c]
    measures = get_pivot_measures(pivot)
    named = _get_pivot_display_header_lines(pivot) > length(pivot.column_dimensions)
    parts = [find_pivot_part_rows(cross, cross.row_keys[r], key) for r in 1:shown_rows]
    map(measures) do measure
        header = String[format_pivot_value(value) for value in key]
        named && push!(header, describe_pivot_measure(measure))
        values = String[rows === nothing ? "" : format_pivot_value(compute_pivot_measure(pivot.source, rows, measure))
                        for rows in parts]
        column = vcat(header, values)
        lpad.(column, maximum(textwidth, column))
    end
end
