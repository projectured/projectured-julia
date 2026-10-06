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

# The menu of a pivot: the view of its cells, the automatic one or one kind.
function compute_context_menu(pivot::PivotTable)
    current = pivot.cell_view
    items = Any[WidgetMenuItem("Show the cells automatically";
                               operation = ReplaceReferencedValueOperation(pivot, "cell_view", nothing),
                               enabled = current !== nothing)]
    for view in collect_pivot_cell_views()
        push!(items, WidgetMenuItem("Show the cells as " * describe_pivot_cell_view(view);
                                    operation = ReplaceReferencedValueOperation(pivot, "cell_view", view()),
                                    enabled = !(current isa view)))
    end
    WidgetMenu(items)
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
