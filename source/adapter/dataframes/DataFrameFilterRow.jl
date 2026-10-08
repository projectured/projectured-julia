# Fragment of `DataFramesModule`.
#
# The filter row of a view: the header of each column is its name above a text
# field of the filter of the column, and the corner is the count of the kept rows
# above a text field of the pattern of the column names. A field shows a text of
# the query, and the selection of the view in that text is the caret of the
# field. So the selection of each widget of the filter row is computed from the
# selection of the view, as a printer computes the selection of its output, and
# an edit of a field is an edit of the text of the query.

# ── The paths of the texts of the query ──────────────────────────────────────

# The path in a view of the range `range` of the text of the filter at place `i`
# of its query, and of the pattern of the column names.
_make_filter_text_reference(i::Int, range::RangeReferenceStep) =
    Reference(FieldReferenceStep("query"), FieldReferenceStep("column_filters"), RangeReferenceStep(i - 1, i),
              FieldReferenceStep("text"), range)

_make_pattern_reference(range::RangeReferenceStep) =
    Reference(FieldReferenceStep("query"), FieldReferenceStep("column_pattern"), range)

_make_expression_reference(range::RangeReferenceStep) =
    Reference(FieldReferenceStep("query"), FieldReferenceStep("expression"), range)

# The text of the query that the selection of `view` is in, as `(place, range)`:
# the place of a filter in the query, `:pattern` or `:expression`, and the range
# `(start, stop)` of the selection in the text; `nothing` when the selection is
# in no text of the query.
function _find_query_text_selection(view)
    selection = view.selection
    selection === nothing && return nothing
    steps = get_reference_steps(strip_reference_types(selection))
    (length(steps) >= 3 && steps[1] == FieldReferenceStep("query") && steps[end] isa RangeReferenceStep) ||
        return nothing
    range = (steps[end].start, steps[end].stop)
    length(steps) == 3 && steps[2] == FieldReferenceStep("column_pattern") && return (:pattern, range)
    length(steps) == 3 && steps[2] == FieldReferenceStep("expression") && return (:expression, range)
    (length(steps) == 5 && steps[2] == FieldReferenceStep("column_filters") &&
     steps[3] isa RangeReferenceStep && steps[4] == FieldReferenceStep("text")) || return nothing
    (steps[3].stop, range)
end

# The range of the selection of `view` in the filter of column `name`, or
# `nothing`.
function _find_filter_range(view, name::String)
    found = _find_query_text_selection(view)
    (found === nothing || found[1] isa Symbol) && return nothing
    filters = view.query.column_filters
    1 <= found[1] <= length(filters) && filters[found[1]].column == name || return nothing
    found[2]
end

# The range of the selection of `view` in the text `place` of the query,
# `:pattern` or `:expression`, or `nothing`.
function _find_query_text_range(view, place::Symbol)
    found = _find_query_text_selection(view)
    (found === nothing || found[1] !== place) ? nothing : found[2]
end

# The path in the view of a path in the table that goes into a field of the
# filter row, `column_headers[c].children[1].content[a:b]` or
# `corner.children[1].content[a:b]`, with the same range in the text of the
# query; `nothing` for any other path. `column` gives the name of the column of
# header `c`.
function _find_query_text_path(view, path, column)
    steps = get_reference_steps(path)
    length(steps) >= 4 || return nothing
    field = steps[(end - 3):end]
    (field[1] == FieldReferenceStep("children") && field[2] == RangeReferenceStep(1, 2) &&
     field[3] == FieldReferenceStep("content") && field[4] isa RangeReferenceStep) || return nothing
    length(steps) == 5 && steps[1] == FieldReferenceStep("corner") && return _make_pattern_reference(field[4])
    is_header = length(steps) == 6 && steps[1] == FieldReferenceStep("column_headers") &&
                steps[2] isa RangeReferenceStep
    is_header || return nothing
    name = column(steps[2].stop)
    name === nothing && return nothing
    i = _find_filter_place(view.query, name)
    i === nothing ? nothing : _make_filter_text_reference(i, field[4])
end

# ── The widgets ──────────────────────────────────────────────────────────────

_make_content_range_reference(range) =
    ConcreteReference(FieldReferenceStep("content"),
                      ConcreteReference(RangeReferenceStep(range[1], range[2]), EmptyReference()))

# The second child of a layout, the field, followed by `path`.
_make_field_child_reference(path) =
    path === nothing ? nothing :
        ConcreteReference(FieldReferenceStep("children"), ConcreteReference(RangeReferenceStep(1, 2), path))

# A text field of the query: `text()` is its text, `range()` the range of its
# caret or `nothing`, and `reason()` why its text does not parse, or `nothing`.
# A text that does not parse colors the field with `invalid_query`, and its
# tooltip says the reason. `placeholder()` is the example that the empty field
# shows, or `nothing`.
function _make_query_field(text, range, reason, width::Int, invalid_query::StyleColor;
                           language::Union{Nothing,Symbol} = nothing, placeholder = nothing)
    field = WidgetText(""; width, language)
    placeholder === nothing || set_cell_computation!(getfield(field, :placeholder), placeholder)
    set_cell_computation!(getfield(field, :content), text)
    set_cell_computation!(getfield(field, :selection),
                          () -> (r = range(); r === nothing ? nothing : _make_content_range_reference(r)))
    set_cell_computation!(getfield(field, :tooltip), reason)
    set_cell_computation!(getfield(field, :style),
                          () -> reason() === nothing ? nothing : WidgetStyle(; content_color = invalid_query))
    field
end

# `label` above `field`, with the selection of the field.
function _make_labeled_field(label, field)
    layout = VerticalLayout(Any[label, field])
    set_cell_computation!(getfield(layout, :selection), () -> _make_field_child_reference(field.selection))
    layout
end

# The header of column `name`: its name and type and the glyph of its sort,
# above the field of its filter. `p` carries the style of the data frame theme.
function _make_filter_header(p, view, name::String)
    filter = _find_column_filter(view.query, name)
    text() = filter === nothing ? "" : filter.text
    function reason()
        filter === nothing && return nothing
        condition = _parse_column_filter(filter.text, eltype(view.frame[!, name]))
        condition isa String ? condition : nothing
    end
    label = HorizontalLayout(Any[WidgetLabel(_get_header_text(name, eltype(view.frame[!, name]))),
                                 _make_sort_glyph(p, view, name)...]; gap = p.filter_gap)
    _make_labeled_field(label, _make_query_field(text, () -> _find_filter_range(view, name), reason,
                                                 p.query_field_width, p.invalid_query))
end

# The corner: the count of the kept rows, padded with figure spaces, which are
# as wide as a digit, to the digits of the count of all rows, so the header
# column is as wide as the widest row number; and under it the field of the
# pattern of the column names. `p` carries the style of the data frame theme.
function _make_query_corner(p, view)
    label = WidgetLabel("")
    set_cell_computation!(getfield(label, :content),
                          () -> lpad(string(length(view.kept_rows)::Int), ndigits(nrow(view.frame)::Int), '\u2007'))
    function reason()
        keep = _parse_name_pattern(view.query.column_pattern)
        keep isa String ? keep : nothing
    end
    field = _make_query_field(() -> view.query.column_pattern, () -> _find_query_text_range(view, :pattern),
                              reason, p.query_field_width, p.invalid_query)
    _make_labeled_field(label, field)
end

# The bar above the table: the field of the expression of the query, after the
# words that it ends, so it reads "Rows where age > 30", the find field, and at
# the right end the glyph that reads the frame again, as F5 does. The field of
# the expression is Julia code, which the Julia domain colors when it is loaded.
# An empty field shows an example made of the columns of the frame. The bar is a
# grid of one row, whose third column takes the room between the two fields. `p`
# carries the style of the data frame theme.
function _make_expression_bar(p, view)
    field = _make_query_field(() -> view.query.expression, () -> _find_query_text_range(view, :expression),
                              () -> last(view.expression_result), p.expression_field_width, p.invalid_query;
                              language = :julia,
                              placeholder = () -> (view.frame_version; _make_expression_example(view.frame)))
    find = _make_query_field(() -> view.find_text, () -> _find_find_range(view), () -> _get_find_reason(view),
                             p.find_field_width, p.invalid_query; placeholder = () -> "Find (Ctrl+F)")
    bar = GridLayout(Any[WidgetLabel("Rows where"), field, WidgetLabel(""), find, _make_refresh_glyph(view)], 5;
                     horizontal_gap = p.expression_gap, vertical_align = :center,
                     column_policies = Any[Content, Content, Fill, Content, Content])
    set_cell_computation!(getfield(bar, :selection), () -> begin
        inner = _make_field_child_reference(field.selection)
        inner === nothing || return inner
        find.selection === nothing ? nothing :
            ConcreteReference(FieldReferenceStep("children"), ConcreteReference(RangeReferenceStep(3, 4), find.selection))
    end)
    bar
end

# The glyph that reads the frame of `view` again: a flat toolbar item, whose
# tooltip names the key that does the same.
function _make_refresh_glyph(view)
    refresh = (document, event) -> RefreshDataFrameViewOperation(view)
    gestures = GestureBinding[GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), refresh;
                                             description = "Read the frame again", domain = "data frame")]
    WidgetToolbarItem("Read the frame again (F5)"; icon = :refresh, gestures)
end

# The path in the view of a path in the grid of the view that goes into a field
# of the bar above the table, `children[0].children[k].content[a:b]`, with the
# same range in its text: the expression of the query for the second child, and
# the find text for the fourth; `nothing` for any other path.
function _find_expression_path(path)
    steps = get_reference_steps(strip_reference_types(path))
    (length(steps) == 6 && steps[1] == FieldReferenceStep("children") && steps[2] == RangeReferenceStep(0, 1) &&
     steps[3] == FieldReferenceStep("children") && steps[5] == FieldReferenceStep("content") &&
     steps[6] isa RangeReferenceStep) || return nothing
    steps[4] == RangeReferenceStep(1, 2) && return _make_expression_reference(steps[6])
    steps[4] == RangeReferenceStep(3, 4) && return Reference(FieldReferenceStep("find_text"), steps[6])
    nothing
end
