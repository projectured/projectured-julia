# Fragment of `DataFramesModule`.
#
# The order of the rows of a view, and the glyph of the header of a column that
# sets it. The glyph is `arrow-up-down` in a faint color while the column does
# not sort, `arrow-up` for ascending and `arrow-down` for descending, with the
# place of its key after it when more than one column sorts. A click on it sorts
# the rows by that column alone, off, ascending, descending, off; a Shift+click
# adds the column as the next key, or turns its key the same way among the
# others.

# The sort of column `name` in `query`, as `(descending, place)` of its key, or
# `nothing` when the column does not sort.
function _find_sort_state(query, name::String)
    for (place, key) in enumerate(query.sort_keys)
        key.column == name && return (key.descending, place)
    end
    nothing
end

# The keys of `query`, as `(column, descending)`, after a click on the glyph of
# column `name`, or a Shift+click when `adding`.
function _make_clicked_sort_keys(query, name::String, adding::Bool)
    state = _find_sort_state(query, name)
    if !adding
        state === nothing && return Tuple{String,Bool}[(name, false)]
        return state[1] ? Tuple{String,Bool}[] : Tuple{String,Bool}[(name, true)]
    end
    keys = Tuple{String,Bool}[(key.column, key.descending) for key in query.sort_keys]
    if state === nothing
        push!(keys, (name, false))
    elseif !state[1]
        keys[state[2]] = (name, true)
    else
        deleteat!(keys, state[2])
    end
    keys
end

# The operation of a click on the glyph of column `name` in `view`: the new keys
# of its query, and the result from its start.
function _make_sort_operation(view, name::String, adding::Bool)
    keys = _make_clicked_sort_keys(view.query, name, adding)
    value = CellVector(Cell[Cell(DataFrameSortKey(; column, descending)) for (column, descending) in keys])
    _make_query_edit_operation(view, ReplaceReferencedValueOperation(view.query, "sort_keys", value))
end

# The `kept` rows of `frame` in the order of `keys`; a key that names no column
# of the frame is left out. Values of types that have no order between them
# keep the order of the frame.
function _sort_kept_rows(frame, kept::Vector{Int}, keys)
    columns = Tuple{String,Bool}[(key.column, key.descending) for key in keys if key.column in names(frame)]
    isempty(columns) && return kept
    # Through `invokelatest`: the sort runs code of DataFrames that a package
    # loaded later can invalidate, and a view that sorts nothing does not depend
    # on it.
    Base.invokelatest(_sort_rows_by_columns, frame, kept, columns)
end

# The `kept` rows of `frame` in the order of `columns`, each a name and whether it
# descends.
function _sort_rows_by_columns(frame, kept::Vector{Int}, columns::Vector{Tuple{String,Bool}})
    rows = Base.view(frame, kept, first.(columns))
    try
        kept[sortperm(rows, first.(columns); rev = last.(columns))]
    catch exception
        exception isa MethodError || rethrow()
        kept
    end
end

# The parts of the header of column `name` after its name: the glyph, a flat
# toolbar item whose own gestures sort, and the place of its key when more than
# one column sorts. The label of the item is its tooltip. `p` carries the style
# of the data frame theme.
function _make_sort_glyph(p, view, name::String)
    query = view.query
    state = _find_sort_state(query, name)
    icon = state === nothing ? :arrow_up_down : state[1] ? :arrow_down : :arrow_up
    sort(adding) = (document, event) -> _make_sort_operation(view, name, adding)
    bind(pattern, adding, description) = GestureBinding(pattern, sort(adding); description,
                                                        domain = "data frame")
    gestures = GestureBinding[
        bind(MouseClickPattern(:left; modifiers = Symbol[]), false, "Order the rows by the column"),
        bind(MouseClickPattern(:left; modifiers = [:shift]), true, "Add the column to the order of the rows")]
    style = state === nothing ? WidgetStyle(; label_text_color = p.unsorted_glyph) : nothing
    item = WidgetToolbarItem("Sort by $(name); Shift adds it to the sort"; icon, gestures, style)
    (state !== nothing && length(query.sort_keys) > 1) || return Any[item]
    Any[item, WidgetLabel(string(state[2]))]
end
