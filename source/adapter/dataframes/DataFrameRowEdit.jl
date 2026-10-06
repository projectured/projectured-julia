# Fragment of `DataFramesModule`.
#
# The insert and the delete of a row of a frame, from the menu of the row. Each
# names its view, so it travels up as it is, and each is the inverse of the
# other, so it is one step of undo. The view makes the step of each: the
# selection, the entries that name a later row, and the place of the view.

"""
    InsertDataFrameRowOperation(view, row, values)
    DeleteDataFrameRowOperation(view, row)

The insert of a row of `values`, one for each column, at number `row` of the
frame of `view`, and the delete of row `row`. Each moves by one the row of each
entry that names a later row, and the version of the frame, so the view sorts
and filters again. Each is the inverse of the other: the delete keeps the values
of the row for its inverse. A `SubDataFrame` takes neither, as DataFrames says.
"""
struct InsertDataFrameRowOperation <: Operation
    view::DataFrameView
    row::Int
    values::Vector{Any}
end

struct DeleteDataFrameRowOperation <: Operation
    view::DataFrameView
    row::Int
end

is_self_contained_operation(::Union{InsertDataFrameRowOperation,
                                    DeleteDataFrameRowOperation}) = true

function evaluate_operation(editor, op::InsertDataFrameRowOperation)
    view = op.view
    insert!(view.frame, op.row, op.values)
    _move_cell_edits!(view, op.row, 1)
    _move_frame_version!(view)
end

function evaluate_operation(editor, op::DeleteDataFrameRowOperation)
    view = op.view
    deleteat!(view.frame, op.row)
    _move_cell_edits!(view, op.row + 1, -1)
    _move_frame_version!(view)
end

make_inverse_operation(document, op::InsertDataFrameRowOperation) =
    DeleteDataFrameRowOperation(op.view, op.row)

make_inverse_operation(document, op::DeleteDataFrameRowOperation) =
    InsertDataFrameRowOperation(op.view, op.row, collect(Any, op.view.frame[op.row, :]))

# Move by `by` the row of each entry of `view` in row `from` or after it.
function _move_cell_edits!(view::DataFrameView, from::Int, by::Int)
    for edit in view.edits
        edit.row >= from && (getfield(edit, :row)[] = edit.row + by)
    end
end

# The values of a new row of `frame`: `missing` where a column allows it, and
# else `0` of its type for a number, `""` for a string and `false` for a Bool.
# `nothing` when a column of another type takes no `missing`.
function _make_new_row_values(frame)
    values = Any[]
    for column in eachcol(frame)
        type = eltype(column)
        if Missing <: type
            push!(values, missing)
            continue
        end
        value = type <: Bool ? false :
                type <: AbstractString ? "" :
                type <: Real ? (try zero(type) catch; nothing end) : nothing
        value === nothing && return nothing
        push!(values, value)
    end
    values
end

# ── The step of the view ─────────────────────────────────────────────────────

# The step that the insert of row `op.row` makes in the view: the selection of
# the whole view, which every state has, the insert, the selection of the first
# shown cell of the new row, which the insert makes, and the place of the view
# that keeps the new row where the row of its number stood, or after the last
# one. So the undo takes back the insert before it puts back the old selection.
function _make_row_insert_step(op::InsertDataFrameRowOperation)
    view = op.view
    shown = _get_shown_columns(view)
    isempty(shown) && return op
    operations = Any[ReplaceSelectionOperation(EmptyReference()), op,
                     _make_whole_cell_selection(view, op.row, first(shown))]
    before = view.kept_rows
    after = _compute_kept_rows_of(view, Any[_InsertedValueVector(column, op.row, value)
                                            for (column, value) in zip(eachcol(view.frame), op.values)])
    # The new row stands where the row of its number stood, or after the last one.
    place = op.row <= nrow(view.frame) ? findfirst(==(op.row), before) :
            (isempty(before) ? nothing : length(before) + 1)
    place === nothing || _push_anchor_place!(operations, view, place, op.row, after)
    _make_cell_step(operations, true)
end

# The step that the delete of row `op.row` makes in the view: the selection of the
# row that follows it in the order of the view, or of the row before it, the drop
# of its open cells, the delete, and the place of the view that keeps the row of
# the selection where the deleted row stood.
function _make_row_delete_step(op::DeleteDataFrameRowOperation)
    view = op.view
    r = op.row
    before = view.kept_rows
    place = findfirst(==(r), before)
    target = place === nothing ? nothing :
             place < length(before) ? before[place + 1] : place > 1 ? before[place - 1] : nothing
    renumber(row) = row > r ? row - 1 : row
    selection = target === nothing ? ReplaceSelectionOperation(EmptyReference()) :
                ReplaceSelectionOperation(_make_element_reference("rows", renumber(target), EmptyReference()))
    operations = Any[selection]
    for edit in view.edits
        edit.row == r && push!(operations, ReplaceViewStateOperation(CloseDataFrameCellOperation(view, r, edit.column)))
    end
    push!(operations, op)
    if target !== nothing
        after = _compute_kept_rows_of(view, Any[_DeletedValueVector(column, r) for column in eachcol(view.frame)])
        _push_anchor_place!(operations, view, place, renumber(target), after)
    end
    _make_cell_step(operations, true)
end

"""
    _InsertedValueVector(column, row, value)
    _DeletedValueVector(column, row)

The values of `column` with `value` inserted at `row`, and with the value at
`row` left out. Neither copies a value, so the order of the kept rows after an
insert or a delete costs no copy of the frame.
"""
struct _InsertedValueVector{T,V<:AbstractVector{T}} <: AbstractVector{T}
    column::V
    row::Int
    value::T
end

_InsertedValueVector(column::AbstractVector{T}, row::Int, value) where {T} =
    _InsertedValueVector{T,typeof(column)}(column, row, convert(T, value))

Base.size(vector::_InsertedValueVector) = (length(vector.column) + 1,)
Base.IndexStyle(::Type{<:_InsertedValueVector}) = IndexLinear()
Base.getindex(vector::_InsertedValueVector, i::Int) =
    i < vector.row ? vector.column[i] : i == vector.row ? vector.value : vector.column[i - 1]

struct _DeletedValueVector{T,V<:AbstractVector{T}} <: AbstractVector{T}
    column::V
    row::Int
end

Base.size(vector::_DeletedValueVector) = (length(vector.column) - 1,)
Base.IndexStyle(::Type{<:_DeletedValueVector}) = IndexLinear()
Base.getindex(vector::_DeletedValueVector, i::Int) =
    i < vector.row ? vector.column[i] : vector.column[i + 1]

# ── The menu of a row ────────────────────────────────────────────────────────

get_document_title(row::DataFrameViewRow) = "row " * string(row.row)

# The menu of a row: open it as a page or in a new tab, insert a row above it or
# below it, and delete it. A `SubDataFrame` takes neither an insert nor a delete,
# nor does a frame with a column that takes no write, such as a range, which can
# not grow or shrink; a frame with a column that has no value for a new row takes
# no insert. An open names the row itself, so the navigator around the table
# opens it, or a new tab does when there is none.
function compute_context_menu(row::DataFrameViewRow)
    view, r = row.view, row.row
    frame = view.frame
    editable = frame isa DataFrame && all(_is_writable_column, eachcol(frame))
    values = editable ? _make_new_row_values(frame) : nothing
    WidgetMenu(Any[
        _make_menu_item("Open as a page", () -> OpenPageOperation(nothing, EmptyReference())),
        _make_menu_item("Open in a new tab", () -> OpenPageOperation(nothing, EmptyReference(), :new_tab)),
        WidgetSeparator(),
        _make_menu_item("Insert row above", () -> InsertDataFrameRowOperation(view, r, values);
                        enabled = values !== nothing),
        _make_menu_item("Insert row below", () -> InsertDataFrameRowOperation(view, r + 1, values);
                        enabled = values !== nothing),
        _make_menu_item("Delete row", () -> DeleteDataFrameRowOperation(view, r);
                        enabled = editable)])
end

# A right click on a row, its header or a cell of it, opens its menu.
get_document_gesture_bindings_own(::Type{DataFrameViewRow}) =
    GestureBinding[make_context_menu_binding(compute_context_menu;
                                             description = "Show the menu of the row")]
