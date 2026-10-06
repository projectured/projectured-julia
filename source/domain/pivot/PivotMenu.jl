# Fragment of `PivotModule`.
#
# The menus of a pivot: a right click on a measure chooses its aggregate, and a
# right click on the pivot chooses the view of its cells. An item carries the
# write of the field, so a choice is a step of undo.

# The aggregates of a measure, in the order of its menu.
const _PIVOT_AGGREGATES = (:count, :sum, :mean, :minimum, :maximum, :distinct_count)

"""
    collect_pivot_cell_views() -> Vector

The kinds of the view of a cell that are loaded: each type that has a method of
[`describe_pivot_cell_view`](@ref), in the order of their names. A package that
adds a kind of view adds that method, and the menu of the pivot lists it.
"""
function collect_pivot_cell_views()
    views = Any[]
    for method in methods(describe_pivot_cell_view)
        signature = Base.unwrap_unionall(method.sig)
        length(signature.parameters) == 2 || continue
        argument = signature.parameters[2]
        (argument isa DataType && argument <: Type) || continue
        view = argument.parameters[1]
        view isa TypeVar && continue
        push!(views, view)
    end
    sort!(views; by = describe_pivot_cell_view)
end

# The menu of a pivot: the items of the dimension under the pointer, the totals,
# and the view of its cells, the automatic one or one kind.
function compute_context_menu(pivot::PivotTable)
    current = pivot.cell_view
    found = _find_pivot_zone_item(get_mouse_target(pivot))
    items = Any[]
    if found !== nothing && found[1] != "measures"
        append!(items, _make_pivot_dimension_items(pivot, _get_pivot_zone(pivot, found[1])[found[2]]))
        push!(items, WidgetSeparator())
    end
    push!(items, WidgetMenuItem(pivot.totals ? "Hide the totals" : "Show the totals";
                                operation = ReplaceReferencedValueOperation(pivot, "totals", !pivot.totals)))
    isempty(pivot.collapsed) ||
        push!(items, WidgetMenuItem("Open every run of rows";
                                    operation = ReplaceReferencedValueOperation(pivot, "collapsed", Any[])))
    push!(items, WidgetSeparator())
    push!(items, WidgetMenuItem("Show the cells automatically";
                                operation = ReplaceReferencedValueOperation(pivot, "cell_view", nothing),
                                enabled = current !== nothing))
    for view in collect_pivot_cell_views()
        push!(items, WidgetMenuItem("Show the cells as " * describe_pivot_cell_view(view);
                                    operation = ReplaceReferencedValueOperation(pivot, "cell_view", view()),
                                    enabled = !(current isa view)))
    end
    WidgetMenu(items)
end

# How many values of a dimension its menu lists, to show or to hide each.
const _PIVOT_MENU_VALUES = 20

# The items of a dimension: its order, its direction, its limit, and a check for
# each of its first values, which hides or shows the value.
function _make_pivot_dimension_items(pivot::PivotTable, dimension::PivotDimension)
    write(field, value) = ReplaceReferencedValueOperation(dimension, field, value)
    items = Any[
        WidgetMenuItem("Order by value"; operation = write("order", :natural), enabled = dimension.order !== :natural),
        WidgetMenuItem("Order by first occurrence"; operation = write("order", :first), enabled = dimension.order !== :first),
        WidgetMenuItem("Order by the measure"; operation = write("order", :measure), enabled = dimension.order !== :measure),
        WidgetMenuItem(dimension.descending ? "Ascending" : "Descending"; operation = write("descending", !dimension.descending)),
        WidgetMenuItem("Show the first 5"; operation = write("limit", 5), enabled = dimension.limit != 5),
        WidgetMenuItem("Show the first 10"; operation = write("limit", 10), enabled = dimension.limit != 10),
        WidgetMenuItem("Show every value"; operation = write("limit", 0), enabled = dimension.limit != 0)]
    append!(items, _make_pivot_bin_items(pivot, dimension))
    hidden = Any[dimension.hidden_values...]
    values = compute_pivot_cross_table(pivot.source, [PivotDimension(dimension.column)], PivotDimension[]).row_keys
    for key in values[1:min(end, _PIVOT_MENU_VALUES)]
        value = only(key)
        shown = !any(isequal(value), hidden)
        toggled = shown ? Any[hidden..., value] : Any[v for v in hidden if !isequal(v, value)]
        push!(items, WidgetMenuItem((shown ? "✓ " : "   ") * format_pivot_value(value);
                                    operation = write("hidden_values", toggled)))
    end
    items
end

# The items of the bins of a dimension: two widths of bins for a column of
# numbers, the year, the month and the day for a column of dates, and no bins.
function _make_pivot_bin_items(pivot::PivotTable, dimension::PivotDimension)
    items = Any[]
    type = nonmissingtype(get_table_column_type(pivot.source, dimension.column))
    write(value) = ReplaceReferencedValueOperation(dimension, "bin", value)
    if type <: Real && !(type <: Bool)
        width = _get_pivot_bin_width(pivot, dimension.column)
        for each in (width, 10 * width)
            push!(items, WidgetMenuItem("Bins of " * format_pivot_value(each); operation = write(each),
                                        enabled = !isequal(dimension.bin, each)))
        end
    elseif type <: Dates.TimeType
        for (part, name) in ((:year, "By year"), (:month, "By month"), (:day, "By day"))
            push!(items, WidgetMenuItem(name; operation = write(part), enabled = dimension.bin !== part))
        end
    end
    dimension.bin === nothing || push!(items, WidgetMenuItem("No bins"; operation = write(nothing)))
    items
end

# A round width of the bins of a column of numbers: about a tenth of the range of
# its values, 1, 2 or 5 times a power of ten.
function _get_pivot_bin_width(pivot::PivotTable, column::String)
    source = pivot.source
    found = find_table_column(source, column)
    column_values = found === nothing ? (get_table_value(source, r, column) for r in 1:get_table_row_count(source)) :
                                        found
    values = Float64[Float64(value) for value in column_values if value isa Real && isfinite(value)]
    span = isempty(values) ? 1.0 : maximum(values) - minimum(values)
    step = span > 0 ? span / 10 : 1.0
    power = 10.0^floor(log10(step))
    factor = step / power
    (factor <= 1 ? 1 : factor <= 2 ? 2 : factor <= 5 ? 5 : 10) * power
end

# The menu of a measure: its aggregate. A measure of no column is a count.
function compute_context_menu(measure::PivotMeasure)
    aggregates = isempty(measure.column) ? (:count,) : _PIVOT_AGGREGATES
    WidgetMenu(Any[WidgetMenuItem(describe_pivot_measure(PivotMeasure(measure.column, aggregate));
                                  operation = ReplaceReferencedValueOperation(measure, "aggregate", aggregate),
                                  enabled = measure.aggregate !== aggregate)
                   for aggregate in aggregates])
end

# A right click on a measure opens its menu.
get_document_gesture_bindings_own(::Type{<:PivotMeasure}) =
    GestureBinding[make_context_menu_binding(compute_context_menu; description = "Show the menu of the measure")]

# A right click on the pivot opens its menu; the gesture table of the pivot
# splices it.
const _PIVOT_MENU =
    GestureBinding[make_context_menu_binding(compute_context_menu; description = "Show the menu of the pivot")]
