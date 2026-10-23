# Fragment of `OutlineModule` — the parts of a row of an outline, built of widgets.
#
# Each builder takes `outline`, the values of an `OutlineTheme` by the names of its
# fields, as `make_theme_values_field` gives them and `unwrap_cell` reads them at a
# print. A part reads no cell of the domain to choose its shape; a text that
# follows a value of the domain reads it in a cell of its own, so a key draws the
# text again and builds no row.

"""
    make_outline_label(outline, text, role; line = nothing, max_lines = 0, tooltip = nothing)
        -> WidgetLabel

A text of an outline in the text role `role`, a field of the theme such as
`:id_text` or `:time_text`, with no box. `text` is a string or a function of no
arguments, as for a `WidgetLabel`. `line`, a field of the theme such as
`:field_line`, gives each line of the text that height, so the label stands on
the lines of the text beside it.
"""
make_outline_label(outline, text, role::Symbol; line::Union{Nothing, Symbol} = nothing,
                   max_lines::Integer = 0, tooltip = nothing) =
    WidgetLabel(text; text_style = getproperty(outline, role), max_lines, tooltip,
                line_spacing = line === nothing ? nothing : ExactSpacing(getproperty(outline, line)),
                margin = inset_default, border = inset_default, padding = inset_default)

"""
    make_outline_text(outline, read; role = :text, line = :text_line, placeholder = nothing)
        -> WidgetText

A field of prose of an outline: a quiet `WidgetText` that wraps at the width of
its column, draws its box only while it holds the caret, and shows the value that
`read()` answers. Each of its lines is as tall as the field `line` of the theme,
or as the font asks for with `line = nothing`, as a title does. The caller maps a
path into its `content` to the value of the domain.
"""
function make_outline_text(outline, read::Function; role::Symbol = :text,
                           line::Union{Nothing, Symbol} = :text_line, placeholder = nothing)
    field = WidgetText(""; placeholder, text_style = getproperty(outline, role), wrap = true, quiet = true,
                       line_spacing = line === nothing ? nothing : ExactSpacing(getproperty(outline, line)),
                       margin = inset_default, border = inset_default, padding = inset_default)
    # The field reads the value in its own cell, so a key that changes the text
    # draws the field again and builds no row.
    set_cell_computation!(getfield(field, :content), read)
    field
end

# The binding of a press on a part of an outline: `make()` makes the operation at
# the time of the press, and `name` says what the press does.
_make_press_binding(name::AbstractString, make::Function) =
    GestureBinding(MouseClickPattern(:left), (_, _) -> make(); description = name, domain = "outline")

"""
    make_outline_chip(outline, text, name, make; tooltip = nothing) -> WidgetLabel

The id of a linked record as a chip: a monospaced label on a small rounded ground.
A press on it answers the operation that `make()` makes then, such as the
selection of the record; `name` says what the press does, and `tooltip` what the
pointer on the chip shows, such as the text of the record.
"""
make_outline_chip(outline, text, name::AbstractString, make::Function; tooltip = nothing) =
    WidgetLabel(text; text_style = outline.chip_text, corner_radius = outline.chip_radius,
                margin = inset_default, border = inset_default, padding = outline.chip_padding,
                style = WidgetStyle(; padding_color = outline.chip_fill, content_color = outline.chip_fill),
                tooltip = something(tooltip, TooltipNote(; title = name)),
                gestures = GestureBinding[_make_press_binding(name, make)])

"""
    make_outline_mark(outline, icon, name, make) -> WidgetToolbarItem

The mark of a record: `icon`, a `WidgetIcon` of its kind in the colour of its
status, with the marks of its corners, at the size of a mark. A press on it
answers the operation that `make()` makes then, such as the menu of the row.
"""
make_outline_mark(outline, icon::WidgetIcon, name::AbstractString, make::Function) =
    WidgetToolbarItem(name; icon = WidgetIcon(icon.name; role = icon.role, top_left = icon.top_left,
                                              top_right = icon.top_right, bottom_left = icon.bottom_left,
                                              bottom_right = icon.bottom_right, size = outline.mark_size),
                      gestures = GestureBinding[_make_press_binding(name, make)], focusable = false,
                      margin = inset_default, border = inset_default, padding = inset_default,
                      tooltip = TooltipNote(; title = name))

"""
    make_outline_control(outline, icon, name, make; size = :fold_size) -> WidgetToolbarItem

A control of a row that shows only while the pointer is on the row or the caret is
in it, such as its fold or its menu: the glyph `icon` at the size that the field
`size` of the theme gives. `make_outline_row` takes it among its `revealed`
controls. At rest it keeps its size and takes no colour, so the row does not
move when it shows.
"""
make_outline_control(outline, icon::Symbol, name::AbstractString, make::Function;
                     size::Symbol = :fold_size) =
    WidgetToolbarItem(name; icon = WidgetIcon(icon; size = getproperty(outline, size)),
                      gestures = GestureBinding[_make_press_binding(name, make)], focusable = false,
                      margin = inset_default, border = inset_default, padding = inset_default,
                      style = WidgetStyle(; label_text_color = outline.mark_color),
                      tooltip = TooltipNote(; title = name))

"""
    make_outline_spacer(outline, size = :fold_size) -> WidgetLabel

An empty part as wide as the field `size` of the theme, such as the place of the
fold of a row that does not fold, so its mark stands under the marks of the rows
that do.
"""
make_outline_spacer(outline, size::Symbol = :fold_size) =
    WidgetLabel(""; margin = inset_default, border = inset_default,
                padding = Inset(0, 0, getproperty(outline, size), 0))

"""
    make_outline_avatar(outline, icon; color = nothing, tooltip = nothing) -> WidgetAvatar

The author of a record as a small round mark: the glyph `icon`, such as `:user`
for a person and `:sparkle` for the assistant, in `color` or the colour of a mark,
such as the `assistant_color` of the theme.
"""
make_outline_avatar(outline, icon::Symbol; color = nothing, tooltip = nothing) =
    WidgetAvatar(icon; size = outline.avatar_size, tooltip,
                 margin = inset_default, border = inset_default, padding = inset_default,
                 style = WidgetStyle(; content_color = outline.chip_fill,
                                     label_text_color = something(color, outline.mark_color)))

"""
    make_outline_facts(outline, lines) -> VerticalLayout

The column of the facts of a row. Each of `lines` is a vector of parts, such as the
fold, the mark and the id, and stands on one line of the text of the row, as tall
as it, with its parts in the middle of it.
"""
make_outline_facts(outline, lines) =
    VerticalLayout(Any[_make_outline_line(outline, line) for line in lines])

_make_outline_line(outline, parts) =
    LayoutConstraint(HorizontalLayout(collect(Any, parts); gap = outline.meta_gap, vertical_align = :center);
                     height = Fixed(outline.text_line))

"""
    make_outline_field(outline, word, value) -> HorizontalLayout

A field of a row on its line: the word of its meaning, such as "answered by" or
"because", and its value beside it. Both take the line of a field, so their first
lines stand on one baseline.
"""
make_outline_field(outline, word::AbstractString, value) =
    HorizontalLayout(Any[make_outline_label(outline, word, :word_text; line = :field_line),
                         LayoutConstraint(value; width = Fill)];
                     gap = outline.meta_gap, vertical_align = :top)

"""
    make_outline_relations(outline, groups) -> FlowLayout

The links of a row on one line that wraps: each of `groups` is a pair of the word
of a link and its chips, as `"rests on" => [chip]`, and a dot stands between two
groups, as in "addresses Q1 · rests on S1 · tested by X1 N1".
"""
function make_outline_relations(outline, groups)
    parts = Any[]
    for (index, (word, chips)) in enumerate(groups)
        index > 1 && push!(parts, make_outline_label(outline, "·", :relation_text))
        push!(parts, make_outline_label(outline, word, :relation_text))
        append!(parts, chips)
    end
    FlowLayout(parts; horizontal_gap = outline.meta_gap, vertical_align = :center)
end

"""
    make_outline_section(outline, title) -> WidgetLabel

The label of a section of an outline, such as a kind of record or a day: small
bold capitals, with the gap of a section above it, in line with the facts of the
rows under it.
"""
make_outline_section(outline, title::AbstractString) =
    WidgetLabel(uppercase(title); text_style = outline.section_text, margin = inset_default,
                border = inset_default,
                padding = Inset(outline.section_gap, outline.meta_gap, outline.row_padding.left[], 0))

"""
    make_outline_menu_operation(title, compute_menu) -> Operation | Nothing

The answer of a press that opens the menu of a row under the part pressed, such as
its mark or its "⋯": the menu that `compute_menu()` makes at the time of the press,
in the context menu window, named `title` when F2 shows more than one menu.
"""
make_outline_menu_operation(title, compute_menu::Function) =
    make_context_menu_operation(nothing, compute_menu(), nothing; title)

# The bindings of a row that has a menu: a right click on the row opens it at the
# pointer, and Shift+F10 opens it under the row while the caret is in it.
function _make_row_menu_bindings(title, compute_menu::Function)
    description = "Show the menu of " * title
    GestureBinding[
        GestureBinding(MouseClickPattern(:right),
                       (document, gesture) -> make_context_menu_operation(document, compute_menu(), gesture; title);
                       description, domain = "outline"),
        GestureBinding(KeyDownPattern(:f10; modifiers = [:shift]),
                       (document, gesture) -> make_context_menu_operation(document, compute_menu(), nothing; title);
                       description, domain = "outline", name = description)]
end

"""
    make_outline_row(outline; facts, body, menu = nothing, indent = 0, revealed = (),
                     title = nothing, compute_menu = nothing, facts_width = nothing) -> WidgetCard

A row of a record: the column of its `facts`, its `body` in the rest of the width,
and its `menu` in a column of its own, on the line of the first line of its text.
The row is a `:row` card, so it lights under the pointer and tints while the caret
is in it. Each control of `revealed`, made with `make_outline_control`, shows
only then. `indent` moves the row to the right, as a row of a tree is.
`facts_width` is the width of the column of the facts, the `meta_width` of the
theme by default; a tree whose rows show no id takes the `tree_meta_width`.

`compute_menu()` makes the menu of the row, a `WidgetMenu`, at the time it opens:
a right click on the row opens it at the pointer, and Shift+F10 under the row. Its
mark and its "⋯" open the same menu with `make_outline_menu_operation`. `title`
names the row in the menu window.
"""
function make_outline_row(outline; facts, body, menu = nothing, indent::Integer = 0, revealed = (),
                          title = nothing, compute_menu = nothing, facts_width = nothing)
    columns = Any[LayoutConstraint(facts; width = Fixed(something(facts_width, outline.meta_width))),
                  LayoutConstraint(body; width = Fill)]
    menu === nothing ||
        push!(columns, LayoutConstraint(_make_outline_line(outline, Any[menu]); width = Fixed(outline.menu_width)))
    gestures = compute_menu === nothing ? GestureBinding[] :
               _make_row_menu_bindings(something(title, "the row"), compute_menu)
    row = WidgetCard(; variant = :row,
                     content = HorizontalLayout(columns; gap = outline.column_gap, vertical_align = :top),
                     margin = Inset(0, 0, indent, 0), border = inset_default, padding = outline.row_padding,
                     gestures)
    for control in revealed
        _reveal_in_row!(control, row)
    end
    row
end

# A control that shows only while the pointer is on `row` or the caret is in it:
# its colour is none at rest. The colour follows the two cells of the row, so the
# control draws again and the row builds nothing.
function _reveal_in_row!(control, row::WidgetCard)
    shown = control.style.label_text_color
    set_cell_computation!(getfield(control.style, :label_text_color), () ->
        get_selection(row) !== nothing || get_mouse_target(row) !== nothing ? shown : color_transparent)
    control
end
