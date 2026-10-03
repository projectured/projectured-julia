# Fragment of `DataFramesModule`.
#
# The edit of a value of a frame: the commit of an open cell converts the value
# of its document to the type of its column and writes it into the frame, as one
# step of undo. A value that does not convert stays in the open cell, with the
# reason, which the table shows as a mark.

"""
    SetDataFrameValueOperation(view, row, column, value)

Write `value` into row `row` and column `column`, a name, of the frame of
`view`, and move the version of the frame, so every computation that reads the
frame reads it again. Its inverse writes the value that was there, so the commit
of a cell is one step of undo. A view of a `SubDataFrame` writes through to its
parent, as an assignment to a `SubDataFrame` does.
"""
struct SetDataFrameValueOperation <: Operation
    view::DataFrameView
    row::Int
    column::String
    value::Any
end

# The operation names its view, so it travels up a chain as it is.
operation_travels_unchanged(::SetDataFrameValueOperation) = true

function evaluate_operation(editor, op::SetDataFrameValueOperation)
    view = op.view
    view.frame[op.row, op.column] = op.value
    getfield(view, :frame_version)[] = view.frame_version + 1
    nothing
end

make_inverse_operation(document, op::SetDataFrameValueOperation) =
    SetDataFrameValueOperation(op.view, op.row, op.column, op.view.frame[op.row, op.column])

"""
    OpenDataFrameCellOperation(view, edit)
    CloseDataFrameCellOperation(view, row, column)

The opening of a cell of `view`, which adds `edit`, a [`DataFrameCellEdit`](@ref),
to its entries, and the closing of the cell in row `row` of the frame and column
`column`, which removes its entry. Each changes the list of entries as it runs, so
a step that commits one cell and opens another keeps both changes.

Each is the inverse of the other, and the close puts back the same entry. So the
undo of a step that edits the frame opens its cells again with the text of their
edits, and the keys typed in them, each a step of undo, act on a cell that shows.
A step that edits no value marks them as view state, and a history does not
record it.
"""
struct OpenDataFrameCellOperation <: Operation
    view::DataFrameView
    edit::Any
end

struct CloseDataFrameCellOperation <: Operation
    view::DataFrameView
    row::Int
    column::String
end

operation_travels_unchanged(::Union{OpenDataFrameCellOperation,CloseDataFrameCellOperation}) = true

function evaluate_operation(editor, op::OpenDataFrameCellOperation)
    view = op.view
    _find_cell_edit(view, op.edit.row, op.edit.column) === nothing || return nothing
    getfield(view, :edits)[] = Any[view.edits..., op.edit]
    nothing
end

function evaluate_operation(editor, op::CloseDataFrameCellOperation)
    view = op.view
    getfield(view, :edits)[] = Any[edit for edit in view.edits if !(edit.row == op.row && edit.column == op.column)]
    nothing
end

function make_inverse_operation(document, op::OpenDataFrameCellOperation)
    edit = op.edit
    _find_cell_edit(op.view, edit.row, edit.column) === nothing || return DoNothingOperation()
    CloseDataFrameCellOperation(op.view, edit.row, edit.column)
end

function make_inverse_operation(document, op::CloseDataFrameCellOperation)
    edit = _find_cell_edit(op.view, op.row, op.column)
    edit === nothing ? DoNothingOperation() : OpenDataFrameCellOperation(op.view, edit)
end

# One step of the opens and the closes of cells in `operations`. A step that edits
# the frame takes its opens and closes back with the edit; any other step only
# shows cells, so its opens and closes are view state.
_make_cell_step(operations::Vector{Any}, edits::Bool) =
    CompoundOperation(edits ? operations :
        Any[operation isa Union{OpenDataFrameCellOperation,CloseDataFrameCellOperation} ?
            ReplaceViewStateOperation(operation) : operation for operation in operations])

# The value of `document`, the document of an open cell, as a value of a column
# of element type `type`, `(value, reason)` with `reason === nothing` when it
# converts. A type-in gives the value that its text parses as; an empty text and
# a number with no value give `missing` where the column allows it.
function _convert_cell_value(document, type::Type)
    shown = nonmissingtype(type)
    value = document.value
    if document isa PrimitiveInsertion
        text = something(value, "")
        parsed = isempty(text) ? nothing : find_primitive_document(document.allowed_types, text)
        isempty(text) || parsed !== nothing ||
            return (value = nothing, reason = string(repr(text), " is not a value of type ", shown))
        value = parsed === nothing ? nothing : parsed.value
    end
    if value === nothing
        Missing <: type && return (value = missing, reason = nothing)
        return (value = nothing, reason = string("A column of type ", shown, " takes no missing value"))
    end
    value isa shown && return (value = value, reason = nothing)
    converted = try
        Some(convert(shown, value))
    catch
        nothing
    end
    converted === nothing && return (value = nothing, reason = string(repr(value), " is not a value of type ", shown))
    (value = something(converted), reason = nothing)
end

# The commit of the open cell in row `r` of the frame and column `name`, as the
# members of a step: the write of its value, when it changes, and the drop of its
# entry. A value that does not convert keeps the cell open, with the reason as
# view state. `closes` tells whether the entry goes, and `edits` whether the
# step writes the frame. `nothing` when the cell is not open.
function _make_cell_commit(view::DataFrameView, r::Int, name::String)
    edit = _find_cell_edit(view, r, name)
    edit === nothing && return nothing
    frame = view.frame
    found = _convert_cell_value(edit.document, eltype(frame[!, name]))
    found.reason === nothing ||
        return (members = Any[ReplaceViewStateOperation(ReplaceReferencedValueOperation(edit, "reason", found.reason))],
                closes = false, edits = false)
    close = CloseDataFrameCellOperation(view, r, name)
    isequal(found.value, frame[r, name]) && return (members = Any[close], closes = true, edits = false)
    (members = Any[SetDataFrameValueOperation(view, r, name, found.value), close], closes = true, edits = true)
end

# The commit of the open cell in row `r` of the frame and column `name` by a key:
# the commit, and the selection of the whole cell when the entry goes. The
# selection comes first, so its inverse comes last, after the undo opened the
# cell again. `nothing` when the cell is not open.
function _make_cell_commit_operation(view::DataFrameView, r::Int, name::String)
    commit = _make_cell_commit(view, r, name)
    commit === nothing && return nothing
    commit.closes || return _make_cell_step(commit.members, false)
    _make_cell_step(Any[_make_whole_cell_selection(view, r, name), commit.members...], commit.edits)
end

# The drop of the open cell in row `r` of the frame and column `name`, and the
# selection of the whole cell. A drop of an entry whose value differs from the
# frame is a step of undo, so Ctrl+Z gives the text of the edit back.
function _make_cell_drop_operation(view::DataFrameView, r::Int, name::String)
    edit = _find_cell_edit(view, r, name)
    edit === nothing && return nothing
    found = _convert_cell_value(edit.document, eltype(view.frame[!, name]))
    changed = found.reason !== nothing || !isequal(found.value, view.frame[r, name])
    _make_cell_step(Any[_make_whole_cell_selection(view, r, name),
                        CloseDataFrameCellOperation(view, r, name)], changed)
end

function _make_whole_cell_selection(view::DataFrameView, r::Int, name::String)
    c = findfirst(==(name), names(view.frame))
    ReplaceSelectionOperation(_make_element_reference("rows", r,
        ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference())))
end

# The row of the frame and the name of the column of the open cell that the
# selection of `view` is in, or `nothing`.
function _find_selected_open_cell(view::DataFrameView)
    selection = view.selection
    selection isa Reference || return nothing
    selection = strip_reference_types(selection)
    (selection isa ConcreteReference && selection.head == FieldReferenceStep("rows")) || return nothing
    tail = selection.tail
    (tail isa ConcreteReference && tail.head isa RangeReferenceStep) || return nothing
    rest = tail.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) || return nothing
    r, c = tail.head.stop, rest.head.stop
    frame_names = names(view.frame)
    1 <= c <= length(frame_names) || return nothing
    _find_cell_edit(view, r, frame_names[c]) === nothing ? nothing : (r, frame_names[c])
end
