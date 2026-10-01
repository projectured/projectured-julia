# Fragment of `DataFramesModule`.
#
# A column of a view as a place in it, and the context menus of the header of a
# column and of the whole view. A column is named by its name, so a path to it
# outlives a hide or a move of another column.

"""
    DataFrameColumnReferenceStep(name)

The step of a reference that names the column `name` of a `DataFrameView`. It
evaluates to a [`DataFrameColumn`](@ref), and to `nothing` when the frame has no
such column.
"""
@cell_struct struct DataFrameColumnReferenceStep <: ReferenceStep
    name::String
end

get_reference_step_kind(::DataFrameColumnReferenceStep) = :structural

Base.:(==)(a::DataFrameColumnReferenceStep, b::DataFrameColumnReferenceStep) = a.name == b.name
Base.hash(s::DataFrameColumnReferenceStep, h::UInt) = hash(s.name, hash(:DataFrameColumnReferenceStep, h))
Base.show(io::IO, s::DataFrameColumnReferenceStep) = print(io, "column(", repr(s.name), ")")

"""
    DataFrameColumn(view, name)

The column `name` of `view`: what a [`DataFrameColumnReferenceStep`](@ref)
names. Its context menu hides it.
"""
struct DataFrameColumn
    view::DataFrameView
    name::String
end

evaluate_reference_step(step::DataFrameColumnReferenceStep, view::DataFrameView) =
    step.name in names(view.frame) ? DataFrameColumn(view, step.name) : nothing

# The path of column `name` in a view.
_make_column_reference(name::String) =
    ConcreteReference(DataFrameColumnReferenceStep(name), EmptyReference())

# ── The menus ────────────────────────────────────────────────────────────────

# An item of a menu that posts the operation that `make` gives when it is
# chosen, so the operation reads the view as it is then.
_make_menu_item(label::String, make; enabled::Bool = true) =
    WidgetMenuItem(label; enabled,
                   action = Action(label; enabled, callback = editor -> post_operation!(editor, make())))

# The menu of the header of a column: filter it by its values, and hide it. The
# last column that the view shows can not be hidden.
function compute_context_menu(column::DataFrameColumn)
    view, name = column.view, column.name
    values = Action("Filter by values…"; callback = editor -> _open_value_list!(editor, view, name))
    WidgetMenu(Any[WidgetMenuItem("Filter by values…"; action = values),
                   _make_menu_item("Hide column", () -> _make_hide_column_operation(view, name);
                                   enabled = length(_get_shown_columns(view)) > 1)])
end

# The menu of the whole view, which the corner of the table reaches: show one
# hidden column, or all of them. `nothing` when no column is hidden.
function compute_context_menu(view::DataFrameView)
    hidden = view.query.hidden_columns
    isempty(hidden) && return nothing
    items = Any[_make_menu_item("Show all columns", () -> _make_hidden_columns_operation(view, String[]))]
    for name in hidden
        push!(items, _make_menu_item("Show " * name, () -> _make_show_column_operation(view, name)))
    end
    WidgetMenu(items)
end
