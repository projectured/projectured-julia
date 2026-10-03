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
    op.view.frame[op.row, op.column] = op.value
    _move_frame_version!(op.view)
end

# Move the version of the frame of `view`, so every computation that reads the
# frame reads it again.
_move_frame_version!(view::DataFrameView) = (getfield(view, :frame_version)[] = view.frame_version + 1; nothing)

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

# One step of `operations`, whose opens and closes of cells and writes of the
# place of the view are marked as view state. A step that a history records,
# because it writes the frame or drops a change, takes them back with it, so its
# undo opens its cells again and puts the view where it was; any other step only
# shows cells, and a history does not record it.
_make_cell_step(operations::Vector{Any}, recorded::Bool) =
    CompoundOperation(recorded ?
        Any[operation isa ReplaceViewStateOperation ? get_wrapped_operation(operation) : operation
            for operation in operations] : operations)

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
# view state. `closes` tells whether the entry goes, `edits` whether the step
# writes the frame, and `value` is the value of the entry. `nothing` when the
# cell is not open.
function _make_cell_commit(view::DataFrameView, r::Int, name::String)
    edit = _find_cell_edit(view, r, name)
    edit === nothing && return nothing
    frame = view.frame
    found = _convert_cell_value(edit.document, eltype(frame[!, name]))
    found.reason === nothing ||
        return (members = Any[ReplaceViewStateOperation(ReplaceReferencedValueOperation(edit, "reason", found.reason))],
                closes = false, edits = false, value = nothing)
    close = ReplaceViewStateOperation(CloseDataFrameCellOperation(view, r, name))
    isequal(found.value, frame[r, name]) &&
        return (members = Any[close], closes = true, edits = false, value = found.value)
    (members = Any[SetDataFrameValueOperation(view, r, name, found.value), close],
     closes = true, edits = true, value = found.value)
end

# The commit of the open cell in row `r` of the frame and column `name` by `key`,
# `:return`, `:tab` or `:backtab`: the commit, the selection of the whole cell
# that the key goes to when the entry goes, and the place of the view that keeps
# the row of that cell at its place on the screen, as the frame sorts and filters
# again. The selection comes first, so its inverse comes last, after the undo
# opened the cell again. `nothing` when the cell is not open.
function _make_cell_commit_operation(view::DataFrameView, r::Int, name::String, key::Symbol)
    commit = _make_cell_commit(view, r, name)
    commit === nothing && return nothing
    commit.closes || return _make_cell_step(commit.members, false)
    after = commit.edits ? _compute_kept_rows_after_write(view, r, name, commit.value) : view.kept_rows
    target = _find_commit_target(view, r, name, key, after)
    operations = Any[_make_whole_cell_selection(view, target.row, target.column), commit.members...]
    _push_anchor_write!(operations, view, target.row, after)
    _make_cell_step(operations, commit.edits)
end

# Where the commit by `key` of the cell in row `r` of the frame and column `name`
# puts the selection, `(row, column)`, given the kept rows `after` the write.
# Enter goes to the cell below, in the kept row that follows `r` in the order
# before the write. Tab and Shift+Tab go to the next and the previous shown cell
# of row `r`, and act as Enter when the filter hides `r` after the write. With no
# row that follows, the selection stays in row `r`, or goes to the row before it.
function _find_commit_target(view::DataFrameView, r::Int, name::String, key::Symbol, after::Vector{Int})
    before = view.kept_rows
    kept = after === before ? nothing : Set(after)
    is_kept(row) = kept === nothing || row in kept
    if key in (:tab, :backtab) && is_kept(r)
        shown = _get_shown_columns(view)
        j = findfirst(==(name), shown)
        j === nothing && return (row = r, column = name)
        return (row = r, column = shown[clamp(j + (key === :tab ? 1 : -1), 1, length(shown))])
    end
    place = findfirst(==(r), before)
    place === nothing && return (row = r, column = name)
    for q in place+1:length(before)
        is_kept(before[q]) && return (row = before[q], column = name)
    end
    is_kept(r) && return (row = r, column = name)
    for q in place-1:-1:1
        is_kept(before[q]) && return (row = before[q], column = name)
    end
    (row = r, column = name)
end

# Add to `operations` the write of the anchor that keeps row `row` of the frame
# at its place on the screen when the kept rows change from those of `view` to
# `after`: the row keeps its distance from the head of the list. Nothing when the
# anchor stays.
function _push_anchor_write!(operations::Vector{Any}, view::DataFrameView, row::Int, after::Vector{Int})
    after === view.kept_rows && return operations
    place_before = findfirst(==(row), view.kept_rows)
    place_before === nothing && return operations
    _push_anchor_place!(operations, view, place_before, row, after)
end

# Add to `operations` the write of the anchor that puts row `row_after` of the
# frame, among the kept rows `after`, at the place on the screen of place
# `place_before` among the kept rows of `view`: the same distance from the head of
# the list. Nothing when the anchor stays, or `after` does not keep the row.
function _push_anchor_place!(operations::Vector{Any}, view::DataFrameView, place_before::Int, row_after::Int,
                             after::Vector{Int})
    place_after = findfirst(==(row_after), after)
    place_after === nothing && return operations
    anchor = clamp(place_after - (place_before - _get_head_place(view)), 1, max(1, length(after)))
    anchor == view.anchor ||
        push!(operations, ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "anchor", anchor)))
    operations
end

"""
    _ReplacedValueVector(column, row, value)

The values of `column` with `value` in place of the value at `row`. It copies no
value, so the order of the kept rows after a write costs no copy of the frame.
"""
struct _ReplacedValueVector{T,V<:AbstractVector{T}} <: AbstractVector{T}
    column::V
    row::Int
    value::T
end

_ReplacedValueVector(column::AbstractVector{T}, row::Int, value) where {T} =
    _ReplacedValueVector{T,typeof(column)}(column, row, convert(T, value))

Base.size(vector::_ReplacedValueVector) = size(vector.column)
Base.IndexStyle(::Type{<:_ReplacedValueVector}) = IndexLinear()
Base.getindex(vector::_ReplacedValueVector, i::Int) = i == vector.row ? vector.value : vector.column[i]

# The kept rows of `view` after the write of `value` into row `r` of the frame and
# column `name`. When no sort key, no filter and no expression reads the column,
# they are the kept rows as they are; else the query keeps them again from the
# frame with the value in place.
function _compute_kept_rows_after_write(view::DataFrameView, r::Int, name::String, value)
    query = view.query
    is_read = any(key -> key.column == name, query.sort_keys) ||
              any(filter -> filter.column == name && !isempty(strip(filter.text)), query.column_filters) ||
              !isempty(strip(query.expression))
    is_read || return view.kept_rows
    frame = view.frame
    _compute_kept_rows_of(view, Any[column == name ? _ReplacedValueVector(frame[!, column], r, value) :
                                    frame[!, column] for column in names(frame)])
end

# The rows that the query of `view` keeps of a frame of `columns`, the columns of
# its frame in their order, with a change that copies no column.
function _compute_kept_rows_of(view::DataFrameView, columns::Vector{Any})
    changed = DataFrame(AbstractVector[columns...], names(view.frame); copycols = false)
    expression = first(_evaluate_expression(changed, view.query.expression))
    Base.invokelatest(_compute_kept_rows, changed, view.query, expression)
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
                        ReplaceViewStateOperation(CloseDataFrameCellOperation(view, r, name))], changed)
end

# The opening of the cell in row `r` of the frame and column `name` by a key on
# the whole cell, with the caret at the end of the text of its entry. With
# `text === nothing`, for F2, the entry holds the value, and the opening is view
# state, as a click is. With a typed `text`, the entry holds what the text gives
# in an empty value of the column, and the opening is a step of undo, because it
# changes the value. `nothing` when the cell is open, takes no key, or the text
# gives no value of the column.
function _make_cell_edit_operation(view::DataFrameView, r::Int, name::String, text)
    _find_cell_edit(view, r, name) === nothing || return nothing
    frame = view.frame
    type = eltype(frame[!, name])
    document = text === nothing ? make_data_frame_cell(frame[r, name], type) : _make_typed_cell_document(text, type)
    document isa PrimitiveDocument || return nothing
    c = findfirst(==(name), names(frame))
    k = length(get_primitive_text(document))
    caret = _make_element_reference("rows", r, ConcreteReference(RangeReferenceStep(c - 1, c),
        ConcreteReference(FieldReferenceStep("value"), ConcreteReference(RangeReferenceStep(k, k), EmptyReference()))))
    _make_cell_step(Any[ReplaceViewStateOperation(OpenDataFrameCellOperation(view, DataFrameCellEdit(r, name, document, nothing))),
                        ReplaceSelectionOperation(caret)], text !== nothing)
end

# The document that `text`, typed into an empty value of a column of element type
# `type`, gives: the string for a column of strings; for a column of numbers, the
# number, or a type-in of the text that a number can not show yet, such as `-`;
# `nothing` for a text with a character that no number has, and for any other
# column, whose keys are its own, as the keys of a Bool.
function _make_typed_cell_document(text::String, type::Type)
    primitive = _find_primitive_type(nonmissingtype(type))
    primitive === PrimitiveString && return PrimitiveString(text)
    (primitive === PrimitiveNumber && has_only_number_characters(text)) || return nothing
    something(find_exact_primitive_document((PrimitiveNumber,), text),
              PrimitiveInsertion(; value = text, allowed_types = (PrimitiveNumber,)))
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
