# Fragment of `DataFramesModule`.
#
# The view of one data frame: a document that holds the native frame and the
# state of the view. The frame is not copied. The rows of the view are a list
# anchored at any row of the frame, and a node of the list is built from its
# index alone, so a jump to any row costs the rows that the table shows.

"""
    DataFrameView(frame; anchor = 1, column_anchor = 1)

The view of `frame`, an `AbstractDataFrame`. `query`, a [`DataFrameQuery`](@ref),
says what the view keeps of the frame: the columns that it shows, and the rows
that pass its filters. `expression_result` holds the rows that the expression of
the query passes, or the reason why it does not run, and `kept_rows` the rows
that pass every filter, by their number in the frame and in its order; both
follow the frame and the query. A path in the view names a row and a
column of the frame by their numbers: `rows[r]` is a row, `columns[c]` a
column and `rows[r][c]` a cell, through the fields `rows`
and `columns`, which hold a [`DataFrameViewRows`](@ref) and a
[`DataFrameViewColumns`](@ref) of the view. So a sort, a filter, a hidden column
and a scroll do not change what a path names. `edits` holds a
[`DataFrameCellEdit`](@ref) for each cell that a person opened and did not
commit: `rows[r][c]` gives its document, and the table shows it in its cell.
`find_text` is the text of the find field, and `find_reason` is `(text,
"no match")` after a find of `text` that found no cell, or `nothing`.

`anchor` is the place, among the kept rows, of the row at the head of the list
of rows, and `scroll_position` is the offset of the table from that row, in
pixels. A frame with many columns draws its columns as a list too, and
`column_anchor` is the place, among the shown columns, of the column at the head
of that list. `top_row` is the row at the top of the table, counted from the
anchor, which the table writes as it scrolls; the scroll bar shows it.
`column_widths` is the width that a person gave a column by the drag of the edge
of its header, by the name of the column. They are the state of the view: a jump
writes them together, and a history does not record them.

A frame that a program changes in place stays the same object, so the view
does not see the change until [`refresh_document!`](@ref) of it, or the key F5,
reads the frame again: `frame_snapshot` is what the last read saw, or
`nothing` before the first, and `frame_version` moves when a read finds a
change; the first read moves it in any case, so a new view reads no cell for a
refresh. Every computation that reads
the data of the frame reads `frame_version` too.
"""
@document struct DataFrameView <: Document
    frame::Any
    query::DataFrameQuery
    expression_result::Any
    kept_rows::Vector{Int}
    anchor::Int
    column_anchor::Int
    scroll_position::Point2D
    top_row::Int
    column_widths::Dict{String,Int}
    frame_version::Int
    frame_snapshot::Any
    rows::Any
    columns::Any
    edits::Vector{Any}
    find_text::String
    find_reason::Any
end

"""
    DataFrameCellEdit(row, column, document, reason)

A cell of a view that a person opened and did not commit: the row of the frame,
the name of the column, the primitive document that shows its value and takes
the keys, and `reason`, why its last commit failed, or `nothing`. A click in a
cell opens one; the table marks a cell with a reason and shows the reason.
"""
@document struct DataFrameCellEdit
    row::Int
    column::String
    document::Any
    reason::Any
end


# The entry of the cell in row `row` of the frame and column `name`, or `nothing`.
function _find_cell_edit(view::DataFrameView, row::Int, name::String)
    for edit in view.edits
        edit.row == row && edit.column == name && return edit
    end
    nothing
end

function DataFrameView(frame::AbstractDataFrame; anchor::Integer = 1, column_anchor::Integer = 1)
    view = DataFrameView(Cell(frame), Cell(_make_frame_query(frame)), Cell((nothing, nothing)), Cell(Int[]),
                         Cell(Int(anchor)), Cell(Int(column_anchor)), Cell(Point2D(0, 0)), Cell(1),
                         Cell(Dict{String,Int}()), Cell(0), Cell(nothing), Cell(nothing), Cell(nothing),
                         Cell(Any[]), Cell(""), Cell(nothing), Cell(nothing))
    _set_path_fields!(_set_kept_row_computations!(view))
end

"""
    DataFrameViewRows(view)

The value of the field `rows` of a [`DataFrameView`](@ref): what the path
`rows[r]` of a row of the frame steps through. `[r]` gives row `r` of the frame,
a [`DataFrameViewRow`](@ref), and a number past the frame is out of bounds. It
holds the view, and reads the frame only when it is indexed. It is a document
with a selection, as the row is, because the walk of a selection writes each
document on its path and goes on only through one that holds a selection: so it
reaches the document of an open cell. `rows` keeps the row of each number that a
path reached, so a path into a row meets the same row each time and the walk
keeps the selection in place.
"""
@document struct DataFrameViewRows <: Document
    view::Any
    rows::Any
end

DataFrameViewRows(view::DataFrameView) = DataFrameViewRows(view, Dict{Int,Any}())

"""
    DataFrameViewRow(view, row)

Row `row` of the frame of `view`, what the path `rows[r]` names. `[c]` gives the
document of the entry of the cell in column `c` when the cell is open, and else
the value in column `c` of the frame.
"""
@document struct DataFrameViewRow <: Document
    view::Any
    row::Int
end

"""
    DataFrameViewColumns(view)

The value of the field `columns` of a [`DataFrameView`](@ref): what the path
`columns[c]` of a column of the frame steps through. `[c]` gives column `c` of
the frame, a [`DataFrameColumn`](@ref).
"""
struct DataFrameViewColumns <: Document
    view::DataFrameView
end

get_selection(::DataFrameViewColumns) = nothing

function Base.getindex(rows::DataFrameViewRows, r::Integer)
    view = rows.view
    1 <= r <= nrow(view.frame) || throw(BoundsError(rows, r))
    get!(() -> DataFrameViewRow(view, Int(r)), rows.rows, Int(r))
end

# One cell for each column of the frame. The inverse of a write of a whole cell
# checks its column against this number.
Base.length(row::DataFrameViewRow) = ncol(row.view.frame)

function Base.getindex(row::DataFrameViewRow, c::Integer)
    frame = row.view.frame
    1 <= c <= ncol(frame) || throw(BoundsError(row, c))
    edit = _find_cell_edit(row.view, row.row, names(frame)[c])
    edit === nothing ? frame[row.row, c] : edit.document
end

# A write of the whole cell in column `c` replaces the document of its entry, as
# a key that turns a number into a type-in does. Only an open cell holds a
# document, so only an open cell takes one.
function Base.setindex!(row::DataFrameViewRow, document, c::Integer)
    frame = row.view.frame
    1 <= c <= ncol(frame) || throw(BoundsError(row, c))
    edit = _find_cell_edit(row.view, row.row, names(frame)[c])
    edit === nothing && error("the cell in row ", row.row, " and column ", names(frame)[c],
                              " is not open, so it holds no document to replace")
    getfield(edit, :document)[] = document
    row
end

function Base.getindex(columns::DataFrameViewColumns, c::Integer)
    frame_names = names(columns.view.frame)
    1 <= c <= length(frame_names) || throw(BoundsError(columns, c))
    DataFrameColumn(columns.view, frame_names[c])
end

# Each holds the view, which holds it, so each prints by its kind alone.
Base.show(io::IO, ::DataFrameViewRows) = print(io, "DataFrameViewRows(…)")

# The rows of a view hold the rows of the frame: a navigator goes from a row up to
# the view, and names no item of the address for them.
is_navigator_stop(::DataFrameViewRows) = false
Base.show(io::IO, row::DataFrameViewRow) = print(io, "DataFrameViewRow(…, ", row.row, ")")
Base.show(io::IO, ::DataFrameViewColumns) = print(io, "DataFrameViewColumns(…)")

# The fields that the paths of `view` step through.
function _set_path_fields!(view::DataFrameView)
    getfield(view, :rows)[] = DataFrameViewRows(view)
    getfield(view, :columns)[] = DataFrameViewColumns(view)
    view
end

# The result of the expression of `view`, computed again when the frame or the
# text of the expression changes, and the rows that pass, computed again when
# the frame, the query or that result changes. A value of a type that a package
# loaded later prints in the newest world.
function _set_kept_row_computations!(view::DataFrameView)
    set_cell_computation!(getfield(view, :expression_result),
                          () -> (view.frame_version; _evaluate_expression(view.frame, view.query.expression)))
    set_cell_computation!(getfield(view, :kept_rows),
                          () -> (view.frame_version;
                                 Base.invokelatest(_compute_kept_rows, view.frame, view.query,
                                                   first(view.expression_result))))
    view
end

# ── The duplicate ────────────────────────────────────────────────────────────
#
# The duplicate of a view is a second view of the same frame: it shares the
# frame, which it reads, and owns a copy of the query and of the place in the
# rows and the columns, so a filter, a sort or a scroll in one does not move the
# other. Its rows are computed again from its own query, and its first refresh
# reads the frame again.
has_document_duplicate(::Union{DataFrameView,DataFrameQuery,DataFrameColumnFilter,DataFrameSortKey}) = true

copy_document(policy::DuplicatePolicy, view::DataFrameView) =
    _set_path_fields!(_set_kept_row_computations!(
        copy_document_fields(policy, view; frame = view.frame, expression_result = (nothing, nothing),
                             kept_rows = Int[], frame_version = 0, frame_snapshot = nothing,
                             rows = nothing, columns = nothing, edits = Any[])))

"""
    jump_to_row(view::DataFrameView, row::Integer) -> Operation or nothing

The operation that shows the kept row at place `row` at the top of the table: a
new anchor, and the table at the anchor. The table stops at the last kept row,
so a jump near the end shows the last row at the bottom. A place out of range is
the first or the last row. `nothing` for a view that keeps no row.
"""
function jump_to_row(view::DataFrameView, row::Integer)
    count = length(view.kept_rows)
    count == 0 && return nothing
    x = Int(view.scroll_position.x[])
    CompoundOperation(Any[
        ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "anchor", clamp(Int(row), 1, count))),
        ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "scroll_position", Point2D(x, 0))),
        ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "top_row", 1))])
end

# A right click on the corner of the table opens the menu of the view
# (`compute_context_menu`), which shows the hidden columns again.
const _DATA_FRAME_VIEW_MENU =
    GestureBinding[make_context_menu_binding(compute_context_menu;
                                             description = "Show the menu of the view")]

@gestures DataFrameView begin
    KeyDown(:home; ctrl) => "Jump to the first row" => jump_to_row(doc, 1)
    KeyDown(:end; ctrl) => "Jump to the last row" => jump_to_row(doc, length(doc.kept_rows))
    KeyDown(:f5) => "Read the frame again" => RefreshDataFrameViewOperation(doc)
    KeyDown(:f; ctrl) => "Find a value" => _make_find_field_selection(doc)
    # A key with Shift comes before the same key without it, which also
    # matches it.
    KeyDown(:f3; shift) => "Find the previous match" => _make_find_operation(doc, true)
    KeyDown(:f3) => "Find the next match" => _make_find_operation(doc, false)
    KeyDown(:return; shift) => "Find the previous match from the find field" =>
        _find_find_range(doc) === nothing ? nothing : _make_find_operation(doc, true)
    KeyDown(:return) => "Find the next match from the find field" =>
        _find_find_range(doc) === nothing ? nothing : _make_find_operation(doc, false)
    splice(_DATA_FRAME_VIEW_MENU)
end

# ── The cells ────────────────────────────────────────────────────────────────

# The longest text that a cell shows. A value that prints longer is cut, and
# the cell of the table clips what is left to its column.
const _CELL_TEXT_LIMIT = 200

"""
    make_data_frame_cell(value, type = typeof(value)) -> Document

The document that shows one value of a column of element type `type`, and takes
its keys. A number, a Bool and a string are the primitive document of their
value, which the natural renderer draws as plain text. A `missing` value is an
empty type-in limited to the type of its column, which shows `missing`. A value
of any other type, such as a `Date`, takes no key: it is a label of its compact
print, cut at 200 characters, whose tooltip says why.
"""
make_data_frame_cell(value::Bool, type::Type = Bool) = PrimitiveBool(value)
make_data_frame_cell(value::Real, type::Type = typeof(value)) = PrimitiveNumber(value)
make_data_frame_cell(value::AbstractString, type::Type = String) = PrimitiveString(String(value))
function make_data_frame_cell(::Missing, type::Type = Missing)
    primitive = _find_primitive_type(nonmissingtype(type))
    primitive === nothing && return WidgetLabel("missing")
    PrimitiveInsertion(; allowed_types = (primitive,), placeholder = "missing")
end
make_data_frame_cell(value, type::Type = typeof(value)) =
    WidgetLabel(_get_cell_text(value); tooltip = "A value of type $(typeof(value)) takes no key here")

# The primitive document of the values of a column of element type `type`, or
# `nothing` for a type that no primitive document holds.
function _find_primitive_type(type::Type)
    type === Union{} && return nothing
    type <: Bool && return PrimitiveBool
    type <: Real && return PrimitiveNumber
    type <: AbstractString && return PrimitiveString
    nothing
end

# The loop of an editor keeps the world of its start, and a value can have a type
# of a package that was loaded later, so the print runs in the newest world.
function _get_cell_text(value)
    text = Base.invokelatest(sprint, print, value; context = (:compact => true, :limit => true))
    length(text) <= _CELL_TEXT_LIMIT ? text : first(text, _CELL_TEXT_LIMIT - 1) * "…"
end

# ── The list of rows ─────────────────────────────────────────────────────────

# The list of the `kept` rows of the frame of `view` with its head at the place
# `anchor`, or an empty vector when it keeps no row: a table draws an empty
# vector as no rows. A row is a vector of its cells in the `columns` that the view
# shows, or, when `column_anchor` is given, a list of them with its head at that
# column. A cell shows the document of its value, or the document of its entry
# while it is open.
function _make_row_list(view::DataFrameView, columns::Vector{String}, kept::Vector{Int},
                        anchor::Int, column_anchor = nothing)
    isempty(kept) && return CellVector()
    frame = view.frame
    types = Dict(name => eltype(frame[!, name]) for name in columns)
    shown(i, name) = (base = make_data_frame_cell(frame[i, name], types[name]);
                      () -> _get_shown_cell_document(view, i, name, base))
    function row_of(i)
        column_anchor === nothing || return make_index_list(length(columns), column_anchor,
                                                             c -> shown(i, columns[c]); computed = true)
        cells = Cell[Cell(nothing) for _ in columns]
        foreach(((cell, name),) -> set_cell_computation!(cell, shown(i, name)), zip(cells, columns))
        CellVector(cells)
    end
    make_index_list(length(kept), anchor, k -> row_of(kept[k]))
end

# The document that the cell in row `i` of the frame and column `name` shows: the
# document of its entry while the cell is open, and else `base`, the document of
# its value, which the cell keeps, so a cell that no entry changes is the same.
function _get_shown_cell_document(view::DataFrameView, i::Int, name::String, base)
    edit = _find_cell_edit(view, i, name)
    edit === nothing ? base : edit.document
end
