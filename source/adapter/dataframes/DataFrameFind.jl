# Fragment of `DataFramesModule`.
#
# The find of a view: the next and the previous cell whose text contains the
# text of the find field, in the order of the view. A find moves the selection
# and the place of the view, so it is no step of undo.

# The range `(start, stop)` of the selection of `view` in its find text, or
# `nothing` when the selection is not there.
function _find_find_range(view)
    selection = view.selection
    selection === nothing && return nothing
    steps = get_reference_steps(strip_reference_types(selection))
    (length(steps) == 2 && steps[1] == FieldReferenceStep("find_text") && steps[2] isa RangeReferenceStep) ||
        return nothing
    (steps[2].start, steps[2].stop)
end

# Why the find field shows a mark: "no match" while its text is the text of the
# last find, which found no cell; `nothing` otherwise.
function _get_find_reason(view)
    reason = view.find_reason
    (reason === nothing || reason[1] != view.find_text) ? nothing : reason[2]
end

# The caret at the end of the find text, which Ctrl+F gives.
_make_find_field_selection(view::DataFrameView) =
    ReplaceSelectionOperation(Reference(FieldReferenceStep("find_text"),
                                        RangeReferenceStep(length(view.find_text), length(view.find_text))))

# The find of the next cell, or of the previous one with `backward`, whose text
# contains the find text of `view`, with no regard to case, in the order of the
# view: the kept rows, and in each the shown columns, from the cell of the
# selection, or from the row at the head of the list when the selection is in no
# row, round the end to the start. It selects the whole cell, and the view jumps
# to the row of the cell when it is not the row at the head. When no cell
# matches, the find field shows "no match". `nothing` for an empty find text.
function _make_find_operation(view::DataFrameView, backward::Bool)
    text = lowercase(view.find_text)
    isempty(text) && return nothing
    kept = view.kept_rows
    shown = _get_shown_columns(view)
    match = (isempty(kept) || isempty(shown)) ? nothing :
            _find_cell_match(view.frame, kept, shown, text, _find_find_start(view, kept, shown), backward)
    match === nothing && return _make_find_reason_write(view, "no match")
    place, j = match
    operations = Any[_make_whole_cell_selection(view, kept[place], shown[j])]
    view.find_reason === nothing || push!(operations, _make_find_reason_write(view, nothing))
    place == _get_head_place(view) || push!(operations, jump_to_row(view, place))
    CompoundOperation(operations)
end

_make_find_reason_write(view::DataFrameView, reason) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(view, "find_reason",
                                                              reason === nothing ? nothing : (view.find_text, reason)))

# Where a find starts, `(place, j)`: the place among the kept rows and the number
# among the shown columns of the cell of the selection; `j = 0`, before the first
# column, for a selection of a row, and the row at the head of the list for any
# other selection.
function _find_find_start(view::DataFrameView, kept::Vector{Int}, shown::Vector{String})
    selection = view.selection
    steps = selection === nothing ? Any[] : get_reference_steps(strip_reference_types(selection))
    (length(steps) >= 2 && steps[1] == FieldReferenceStep("rows") && steps[2] isa RangeReferenceStep) ||
        return (_get_head_place(view), 0)
    place = findfirst(==(steps[2].stop), kept)
    place === nothing && return (_get_head_place(view), 0)
    (length(steps) >= 3 && steps[3] isa RangeReferenceStep) || return (place, 0)
    frame_names = names(view.frame)
    c = steps[3].stop
    (place, 1 <= c <= length(frame_names) ? something(findfirst(==(frame_names[c]), shown), 0) : 0)
end

# The place among `kept` and the number among `shown` of the first cell after
# `start`, or before it with `backward`, round the end, whose text contains
# `text`, in lower case; `nothing` when no cell does. The cells of the view are
# numbered from 0 in its order, and the cell of `start` is the last one tried.
function _find_cell_match(frame, kept::Vector{Int}, shown::Vector{String}, text::String, start, backward::Bool)
    columns = [frame[!, name] for name in shown]
    m = length(shown)
    total = length(kept) * m
    place, j = start
    # A start before the first column of its row: the cell before it going
    # forward, and its first cell going back.
    origin = (place - 1) * m + (j == 0 ? (backward ? 0 : -1) : j - 1)
    step = backward ? -1 : 1
    for k in 1:total
        p, q = divrem(mod(origin + step * k, total), m)
        value = columns[q + 1][kept[p + 1]]
        occursin(text, lowercase(_get_shown_cell_text(value))) && return (p + 1, q + 1)
    end
    nothing
end

# The text that a cell of `value` shows, as the find reads it.
_get_shown_cell_text(value::AbstractString) = value
_get_shown_cell_text(::Missing) = "missing"
_get_shown_cell_text(value::Real) = string(value)
_get_shown_cell_text(value) = _get_cell_text(value)
