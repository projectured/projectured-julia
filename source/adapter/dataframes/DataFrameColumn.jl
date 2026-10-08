# Fragment of `DataFramesModule`.
#
# A column of a view as a place in it, and the context menus of the header of a
# column and of the whole view. A column is `columns[c]` of the view, by its
# number in the frame, so a path to it outlives a hide or a move of another
# column in the view.

"""
    DataFrameColumn(view, name)

The column `name` of `view`: what the path `columns[c]` of the view names. It is
a document with a gesture table and no selection of its own, so a right click
on the header of the column opens its menu, which hides it.
"""
struct DataFrameColumn <: Document
    view::DataFrameView
    name::String
end

get_document_title(column::DataFrameColumn) = column.name

# The path of column `name` of the frame of `view`, `columns[c]`, or `nothing`
# when the frame has no such column.
function _make_column_reference(view::DataFrameView, name::String)
    c = findfirst(==(name), names(view.frame))
    c === nothing ? nothing : _make_element_reference("columns", c, EmptyReference())
end

# The path `field[i]`, followed by `tail`.
_make_element_reference(field::String, i::Int, tail) =
    ConcreteReference(FieldReferenceStep(field), ConcreteReference(RangeReferenceStep(i - 1, i), tail))

# ── The menus ────────────────────────────────────────────────────────────────

# An item of a menu that makes the operation that `make` gives, on the part of
# the menu, as a step of undo. The operation reads the view as it is when the
# menu opens.
_make_menu_item(label::String, make; enabled::Bool = true) =
    WidgetMenuItem(label; enabled, operation = enabled ? make() : nothing)

# The menu of the header of a column: filter it by its values and hide it, which
# change the view, and the items that change the frame
# (`_make_column_edit_items`). The last column that the view shows can not be
# hidden.
function compute_context_menu(column::DataFrameColumn)
    view, name = column.view, column.name
    values = Action("Filter by values…"; callback = editor -> _open_value_list!(editor, view, name))
    WidgetMenu(Any[WidgetMenuItem("Filter by values…"; action = values),
                   _make_menu_item("Hide column", () -> _make_hide_column_operation(view, name);
                                   enabled = length(_get_shown_columns(view)) > 1),
                   WidgetSeparator(),
                   _make_column_edit_items(view, name)...])
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

# A right click on the header of a column opens its menu.
get_document_gesture_bindings_own(::Type{DataFrameColumn}) =
    GestureBinding[make_context_menu_binding(compute_context_menu;
                                             description = "Show the menu of the column")]
