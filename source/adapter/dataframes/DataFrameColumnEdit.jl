# Fragment of `DataFramesModule`.
#
# The insert, the delete and the move of a column of a frame, from the menu of
# its header. Each names its view, so it travels up as it is, and has its
# inverse, so it is one step of undo. The view makes the step of each: the
# selection, and the drop of the open cells of a deleted column.

"""
    InsertDataFrameColumnOperation(view, index, name, vector)
    DeleteDataFrameColumnOperation(view, name)
    MoveDataFrameColumnOperation(view, name, index)

The insert of `vector` as column `name` at number `index` of the frame of
`view`, the delete of column `name`, and the move of column `name` to number
`index`. Each moves the version of the frame. The insert and the delete are
each the inverse of the other: the delete keeps the vector and its number for
its inverse, and the insert takes the vector as it is, so the undo of a delete
puts back the same vector. The inverse of a move moves the column back. A
`SubDataFrame` takes none of them.
"""
struct InsertDataFrameColumnOperation <: Operation
    view::DataFrameView
    index::Int
    name::String
    vector::AbstractVector
end

struct DeleteDataFrameColumnOperation <: Operation
    view::DataFrameView
    name::String
end

struct MoveDataFrameColumnOperation <: Operation
    view::DataFrameView
    name::String
    index::Int
end

const _DataFrameColumnOperation =
    Union{InsertDataFrameColumnOperation,DeleteDataFrameColumnOperation,MoveDataFrameColumnOperation}

operation_travels_unchanged(::_DataFrameColumnOperation) = true

function evaluate_operation(editor, op::InsertDataFrameColumnOperation)
    insertcols!(op.view.frame, op.index, op.name => op.vector; copycols = false)
    _move_frame_version!(op.view)
end

function evaluate_operation(editor, op::DeleteDataFrameColumnOperation)
    select!(op.view.frame, Not(op.name))
    _move_frame_version!(op.view)
end

function evaluate_operation(editor, op::MoveDataFrameColumnOperation)
    order = filter(!=(op.name), names(op.view.frame))
    insert!(order, op.index, op.name)
    select!(op.view.frame, order)
    _move_frame_version!(op.view)
end

make_inverse_operation(document, op::InsertDataFrameColumnOperation) =
    DeleteDataFrameColumnOperation(op.view, op.name)

function make_inverse_operation(document, op::DeleteDataFrameColumnOperation)
    frame = op.view.frame
    InsertDataFrameColumnOperation(op.view, columnindex(frame, op.name), op.name, frame[!, op.name])
end

make_inverse_operation(document, op::MoveDataFrameColumnOperation) =
    MoveDataFrameColumnOperation(op.view, op.name, columnindex(op.view.frame, op.name))

# The first name `column N` that `frame` does not have, from the number after its
# last column.
function _make_new_column_name(frame)
    taken = Set(names(frame))
    n = ncol(frame) + 1
    while ("column " * string(n)) in taken
        n += 1
    end
    "column " * string(n)
end

# ── The step of the view ─────────────────────────────────────────────────────

# The step that a column operation makes in the view. A path names a column by
# its number, so the step selects the whole view first, which every state has,
# then makes the change, then selects the column that the change leaves for the
# person: the new column, the moved column, or the shown column after a deleted
# one, or the one before it. A delete drops the open cells of its column before
# it. So the undo takes back the change before it puts back the old selection,
# in the numbers of the columns that it names.
function _make_column_step(op::_DataFrameColumnOperation)
    view = op.view
    operations = Any[ReplaceSelectionOperation(EmptyReference())]
    if op isa DeleteDataFrameColumnOperation
        for edit in view.edits
            edit.column == op.name &&
                push!(operations, ReplaceViewStateOperation(CloseDataFrameCellOperation(view, edit.row, op.name)))
        end
    end
    push!(operations, op)
    target = _find_column_after(op)
    target === nothing ||
        push!(operations, ReplaceSelectionOperation(_make_element_reference("columns", target, EmptyReference())))
    _make_cell_step(operations, true)
end

# The number, after `op`, of the column that the selection goes to, or `nothing`.
_find_column_after(op::InsertDataFrameColumnOperation) = op.index
_find_column_after(op::MoveDataFrameColumnOperation) = op.index
function _find_column_after(op::DeleteDataFrameColumnOperation)
    shown = _get_shown_columns(op.view)
    j = findfirst(==(op.name), shown)
    j === nothing && return nothing
    neighbour = j < length(shown) ? shown[j + 1] : j > 1 ? shown[j - 1] : nothing
    neighbour === nothing && return nothing
    remaining = filter(!=(op.name), names(op.view.frame))
    findfirst(==(neighbour), remaining)
end

# ── The menu items of a column ───────────────────────────────────────────────

# The items of the menu of column `name` that change the frame: insert a column
# of text before and after it, move it past the shown column on its left or on its
# right, and delete it. A `SubDataFrame` takes none, and the last column can not
# be deleted.
function _make_column_edit_items(view::DataFrameView, name::String)
    frame = view.frame
    editable = frame isa DataFrame
    c = columnindex(frame, name)
    shown = _get_shown_columns(view)
    j = findfirst(==(name), shown)
    left = (j === nothing || j == 1) ? nothing : columnindex(frame, shown[j - 1])
    right = (j === nothing || j == length(shown)) ? nothing : columnindex(frame, shown[j + 1])
    new_column() = Vector{Union{Missing,String}}(missing, nrow(frame))
    Any[_make_menu_item("Insert column before",
                        () -> InsertDataFrameColumnOperation(view, c, _make_new_column_name(frame), new_column());
                        enabled = editable),
        _make_menu_item("Insert column after",
                        () -> InsertDataFrameColumnOperation(view, c + 1, _make_new_column_name(frame), new_column());
                        enabled = editable),
        _make_menu_item("Move column left", () -> MoveDataFrameColumnOperation(view, name, something(left, c));
                        enabled = editable && left !== nothing),
        _make_menu_item("Move column right", () -> MoveDataFrameColumnOperation(view, name, something(right, c));
                        enabled = editable && right !== nothing),
        _make_menu_item("Delete column", () -> DeleteDataFrameColumnOperation(view, name);
                        enabled = editable && ncol(frame) > 1)]
end
