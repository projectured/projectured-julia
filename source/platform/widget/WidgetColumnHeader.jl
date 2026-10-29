# Fragment of `WidgetModule` — the parts of the header of a column of a table:
# the glyph that sorts, the text field of a filter with its reason, and the dialog
# of the values of the column.
#
# The glyph is `arrow-up-down` in a faint color while the column does not sort,
# `arrow-up` for ascending and `arrow-down` for descending, with the place of its
# key after it when more than one column sorts. A click on it sorts the rows by
# that column alone, off, ascending, descending, off; a Shift+click adds the
# column as the next key, or turns its key the same way among the others.
#
# The parts know nothing of the table: they take texts, closures that read cells,
# the sort keys as `(name, descending)` pairs, the values of a column, and the
# operations to post.

# ── The sort ─────────────────────────────────────────────────────────────────

"""
    find_sort_state(keys, name) -> (descending, place) or nothing

The sort of the column `name` in `keys`, as `(descending, place)` of its key, or
`nothing` when the column does not sort. `keys` is a vector of `(name,
descending)` pairs in the order of the sort.

Use it to draw the glyph of a column and to compute the keys after a click on it.

# Example

    find_sort_state([("age", false), ("name", true)], "name")   # (true, 2)

See also `compute_clicked_sort_keys`, `make_sort_glyph`.
"""
function find_sort_state(keys, name::String)
    for (place, key) in enumerate(keys)
        first(key) == name && return (last(key), place)
    end
    nothing
end

"""
    compute_clicked_sort_keys(keys, name, adding) -> Vector{Tuple{String,Bool}}

The sort keys after a click on the glyph of the column `name`, or a Shift+click
when `adding`. A click sorts by the column alone: off, ascending, descending,
off. A Shift+click adds the column as the next key, turns its key to descending,
or removes it, and keeps the other keys.

Use it to write the operation that a click on the glyph of a column posts.

# Example

    compute_clicked_sort_keys([("age", false)], "name", true)   # [("age", false), ("name", false)]

See also `find_sort_state`, `make_sort_glyph`.
"""
function compute_clicked_sort_keys(keys, name::String, adding::Bool)
    state = find_sort_state(keys, name)
    if !adding
        state === nothing && return Tuple{String,Bool}[(name, false)]
        return state[1] ? Tuple{String,Bool}[] : Tuple{String,Bool}[(name, true)]
    end
    clicked = Tuple{String,Bool}[(first(key), last(key)) for key in keys]
    if state === nothing
        push!(clicked, (name, false))
    elseif !state[1]
        clicked[state[2]] = (name, true)
    else
        deleteat!(clicked, state[2])
    end
    clicked
end

"""
    make_sort_glyph(keys, name, unsorted_color, make_operation; domain) -> Vector{Any}

The parts of the header of the column `name` after its name: the glyph, a flat
toolbar item whose own gestures sort, and the place of its key when more than
one column sorts. `keys` is a vector of `(name, descending)` pairs.
`make_operation(adding)` gives the operation that a click posts, and `adding` is
true for a Shift+click. A glyph of a column that does not sort has the color
`unsorted_color`. The tooltip names the column, and its hint the gesture that
adds the column to the order. `domain` is the domain of the gestures in the
gesture help.

Use it to build the header of a column of a table whose rows have an order.

# Example

    make_sort_glyph([("age", false)], "age", unsorted, adding -> operation_of(adding); domain = "table")

See also `compute_clicked_sort_keys`, `find_sort_state`.
"""
function make_sort_glyph(keys, name::String, unsorted_color::StyleColor, make_operation; domain::String)
    state = find_sort_state(keys, name)
    icon = state === nothing ? :arrow_up_down : state[1] ? :arrow_down : :arrow_up
    sort(adding) = (document, event) -> make_operation(adding)
    bind(pattern, adding, description) = GestureBinding(pattern, sort(adding); description, domain)
    adding = MouseClickPattern(:left; modifiers = [:shift])
    gestures = GestureBinding[
        bind(MouseClickPattern(:left; modifiers = Symbol[]), false, "Order the rows by the column"),
        bind(adding, true, "Add the column to the order of the rows")]
    style = state === nothing ? WidgetStyle(; label_text_color = unsorted_color) : nothing
    tooltip = TooltipNote(; title = "Sort by $(name)", text = "Order the rows by this column.",
                          hint = string(describe_gesture_pattern(adding), " adds it to the order of the rows."))
    item = WidgetToolbarItem("Sort by $(name)"; icon, gestures, style, tooltip)
    (state !== nothing && length(keys) > 1) || return Any[item]
    Any[item, WidgetLabel(string(state[2]))]
end

# ── The field of a filter ────────────────────────────────────────────────────

"""
    make_filter_field(text, range, reason, width, invalid_filter; language, placeholder) -> WidgetText

A text field that shows a text which a person edits and which can fail to parse.
`text()` is its text, `range()` the range `(start, stop)` of its caret or
`nothing`, and `reason()` why its text does not parse, or `nothing`. A text that
does not parse colors the field with `invalid_filter`, and the tooltip of the
field says the reason. `placeholder()` is the example that the empty field shows,
or `nothing`. `language` is the language that colors the text.

Use it for the filter under the header of a column, and for any other field that
a table keeps as text.

# Example

    make_filter_field(() -> text, () -> nothing, () -> nothing, 80, color)

See also `make_labeled_field`, `make_field_child_reference`.
"""
function make_filter_field(text, range, reason, width::Int, invalid_filter::StyleColor;
                           language::Union{Nothing,Symbol} = nothing, placeholder = nothing)
    field = WidgetText(""; width, language)
    placeholder === nothing || set_cell_computation!(getfield(field, :placeholder), placeholder)
    set_cell_computation!(getfield(field, :content), text)
    set_cell_computation!(getfield(field, :selection),
                          () -> (r = range(); r === nothing ? nothing : _make_content_range_reference(r...)))
    set_cell_computation!(getfield(field, :tooltip), reason)
    set_cell_computation!(getfield(field, :style),
                          () -> reason() === nothing ? nothing : WidgetStyle(; content_color = invalid_filter))
    field
end

"""
    make_field_child_reference(path) -> Reference or nothing

The path in a layout of `path` in its second child, the field of a labeled
field, or `nothing` for a `path` that is `nothing`.

Use it to map the caret of a field into the layout that holds it.

# Example

    make_field_child_reference(field.selection)

See also `make_labeled_field`.
"""
make_field_child_reference(path) =
    path === nothing ? nothing :
        ConcreteReference(FieldReferenceStep("children"), ConcreteReference(RangeReferenceStep(1, 2), path))

"""
    make_labeled_field(label, field) -> VerticalLayout

`label` above `field`, with the selection of the field. The field is the second
child of the layout.

Use it for the header of a column: its name and its glyph above the field of its
filter.

# Example

    make_labeled_field(WidgetLabel("age"), make_filter_field(text, range, reason, 80, color))

See also `make_filter_field`, `make_field_child_reference`.
"""
function make_labeled_field(label, field)
    layout = VerticalLayout(Any[label, field])
    set_cell_computation!(getfield(layout, :selection), () -> make_field_child_reference(field.selection))
    layout
end

# ── The values of a column ───────────────────────────────────────────────────

# The most distinct values that the dialog of the values lists.
const _VALUE_LIST_LIMIT = 1000

"""
    compute_value_counts(column; limit = 1000) -> Vector or nothing

The distinct values of `column` that are not `missing`, sorted, each as a pair
with the count of its rows; `nothing` when there are more than `limit` of them.
Values of types that have no order between them keep the order of the
dictionary that counts them.

Use it to list the values of a column, and to refuse a list of a column that has
too many.

# Example

    compute_value_counts(["b", "a", "b", missing])   # ["a" => 1, "b" => 2]

See also `make_value_list_dialog`.
"""
function compute_value_counts(column::AbstractVector; limit::Int = _VALUE_LIST_LIMIT)
    counts = Dict{nonmissingtype(eltype(column)),Int}()
    for value in column
        ismissing(value) && continue
        count = get(counts, value, 0)
        count == 0 && length(counts) == limit && return nothing
        counts[value] = count + 1
    end
    counted = collect(counts)
    try
        sort!(counted; by = first)
    catch exception
        exception isa MethodError || rethrow()
    end
    counted
end

"""
    make_value_list_dialog(name, column, filter_text, write; widget = nothing) -> (dialog, take)

The dialog of the values of the column `name`, and `take()`, which gives the
operation that "Apply" posts, or `nothing` when no value is ticked. The dialog
has a box for each distinct value of `column` with the count of its rows, ticked
as the filter text `filter_text` keeps it. `write(text)` gives the operation
that writes the filter text `text`, `= a, b` for the ticked values and the empty
text when all are ticked. A `missing` is not in the list. A column with more than
1,000 distinct values gives a dialog that says so, and a `take` that gives
`nothing`. `widget` is the widget theme of the editor that opens the dialog,
scaled or not, or `nothing` for the default theme.

Use it with a window that shows the dialog, and connect the button "Apply" to
`take`.

# Example

    dialog, take = make_value_list_dialog("kind", column, "", text -> write_filter(text))

See also `compute_value_counts`, `is_value_listed`, `make_value_list_text`.
"""
function make_value_list_dialog(name::String, column::AbstractVector, filter_text::AbstractString, write;
                                widget = nothing)
    counted = compute_value_counts(column)
    if counted === nothing
        text = "The column $(name) has more than $(_VALUE_LIST_LIMIT) distinct values. " *
               "Type a filter in the filter row instead."
        return (WidgetDialog("Filter by values", text, Any[WidgetButton("Close")];
                             popup_id = :value_list), () -> nothing)
    end
    values = Any[first(entry) for entry in counted]
    boxes = WidgetCheckbox[WidgetCheckbox(is_value_listed(filter_text, value, eltype(column));
                                          label = string(value) * "  (" * string(count) * ")")
                           for (value, count) in counted]
    size = unwrap_cell(get_widget_style(widget, :value_list_size))
    list = WidgetScrollPane(VerticalLayout(Any[boxes...]; gap = unwrap_cell(get_widget_style(widget, :item_gap)));
                            size = Point2D(Int(size.x[]), Int(size.y[])))
    function take()
        text = make_value_list_text(values, Bool[box.content for box in boxes])
        text === nothing ? nothing : write(text)
    end
    dialog = WidgetDialog("Filter by values", list, Any[WidgetButton("Cancel"), WidgetButton("Apply")];
                          popup_id = :value_list)
    (dialog, take)
end
