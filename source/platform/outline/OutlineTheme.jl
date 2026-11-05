# Fragment of `OutlineModule` — the theme of an outline: the sizes of a row and of
# its columns, the type of its parts, and the colours of a chip and an inset.

"""
    OutlineTheme

The look of an outline of records, such as a study or a workflow: the width of
the column of the facts of a row and of its menu, the sizes of a mark and of an
avatar, the texts of a title, a section, a row, a field, a link and a time, and
the colours of a chip and of a document inside a row. The row under the pointer
and the row of the caret take the colours of a row of a list, from the widget
theme.

`@theme` declares it, so `ScaledOutlineTheme` holds each value times its scale,
and `OutlineTheme()` is the default theme. A builder of the outline slice takes
its values with `get_outline_style`, from a theme scaled or not.

The gaps and the padding of a row are roles of the widget theme:
`tree_row_padding` around the parts of a row, `item_gap` between the facts of a
line, `button_gap` between two buttons and `section_gap` between two sections. [`make_outline_values_field`](@ref)
gives them with the values of this theme.
"""
@theme struct OutlineTheme
    "The font that the texts of an outline follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu", 14)
    "The title of the document."
    title_text::ThemeText = TextRole(:text; weight = 700, relative_size = 24 / 14)
    "The label of a section: a group of rows of one kind or of one day."
    section_text::ThemeText = TextRole(:text_muted; weight = 700, relative_size = 11 / 14)
    "The text of a row: a statement, a title or a citation."
    text::ThemeText = TextRole(:text; weight = 500, relative_size = 15 / 14)
    "The text of a row that is settled out of the way, such as a done step."
    quiet_text::ThemeText = TextRole(:text_muted; relative_size = 15 / 14)
    "The value of a field of a row."
    field_text::ThemeText = TextRole(:text; relative_size = 13 / 14)
    "The word before the value of a field, and before the chips of a link."
    word_text::ThemeText = TextRole(:text_muted; relative_size = 13 / 14)
    "The words of the links of a row, and the facts of the header."
    relation_text::ThemeText = TextRole(:text_muted; relative_size = 12 / 14)
    "The id of a row."
    id_text::ThemeText = TextRole(:text_muted; family = "Ubuntu Mono", weight = 700, relative_size = 12 / 14)
    "The time and the date of a row."
    time_text::ThemeText = TextRole(:text_muted; family = "Ubuntu Mono", relative_size = 11 / 14)
    "The id in a chip."
    chip_text::ThemeText = TextRole(:text; family = "Ubuntu Mono", weight = 700, relative_size = 12 / 14)
    "A pale text that stands in an empty place, such as the first row of an empty document."
    placeholder_text::ThemeText = TextRole(:text_faint; relative_size = 15 / 14)
    "The ground of a chip."
    chip_fill::ThemeColor = ColorRole(:surface_sunken)
    "The ground of a document inside a row."
    inset_fill::ThemeColor = ColorRole(:surface_sunken)
    "The line around a document inside a row, the line under a section label, and the guide lines of a tree."
    line::ThemeColor = ColorRole(:border)
    "The colour of an open mark and of a control that a row shows under the pointer."
    mark_color::ThemeColor = ColorRole(:text_muted)
    "The colour of what the assistant made: its avatar."
    assistant_color::ThemeColor = ColorRole(:accent_text)
    "The width of the column of the facts of a row: its fold, its mark, its id, its author and its time."
    meta_width::ControlSize = ControlSize(72)
    "The width of the column of the facts of a row of a tree, which shows no id: its fold and its mark."
    tree_meta_width::ControlSize = ControlSize(39)
    "The width of the column of the menu of a row."
    menu_width::ControlSize = ControlSize(24)
    "The size of the mark of a row."
    mark_size::IconSize = IconSize(17)
    "The size of the fold of a row, which shows under the pointer."
    fold_size::IconSize = IconSize(12)
    "The size of the avatar of an author."
    avatar_size::IconSize = IconSize(14)
    "The gap between the columns of a row."
    column_gap::Spacing = Spacing(8)
    "The space inside a chip, around its id."
    chip_padding::Spacing = Spacing(Inset(1, 1, 5, 5))
    "The step of the indent of a row of a tree."
    indent::Spacing = Spacing(30)
    "The width of a guide line of a tree."
    guide_width::Spacing = Spacing(1)
    "The height of a line of the text of a row."
    text_line::Spacing = Spacing(22)
    "The height of a line of a field and of a link."
    field_line::Spacing = Spacing(20)
    "The space inside a document that a row holds, between its line and its content."
    inset_padding::Spacing = Spacing(Inset(6, 6, 10, 10))
    "The roundness of the ground of a row and of an inset."
    radius::Radius = Radius(6)
    "The roundness of a chip."
    chip_radius::Radius = Radius(4)
end

"""
    make_outline_values_field(outline_theme, widget_theme) -> NamedTuple or UntrackedCell{NamedTuple}

The `outline` that a builder of the outline slice takes: every value of the
`OutlineTheme` `outline_theme`, and the roles `tree_row_padding`, `item_gap`,
`button_gap` and `section_gap` of the `WidgetTheme` `widget_theme`. Each theme is scaled or not, or
the default theme for `nothing`. With no theme it is the plain values of the
default themes; with a theme it is a cell that reads the values at each read, as
[`make_theme_values_field`](@ref) does.
"""
function make_outline_values_field(outline_theme, widget_theme)
    names = get_theme_field_names(OutlineTheme)
    get_values(theme, type) = theme === nothing ? get_theme_defaults(type) : get_theme_values(theme)
    make_values(outline, widget) =
        merge(NamedTuple{names}(Tuple(getproperty(outline, name) for name in names)),
              (; tree_row_padding = widget.tree_row_padding, item_gap = widget.item_gap,
                 button_gap = widget.button_gap, section_gap = widget.section_gap))
    outline_theme === nothing && widget_theme === nothing &&
        return make_values(get_theme_defaults(OutlineTheme), get_theme_defaults(WidgetTheme))
    UntrackedCell{NamedTuple}(Computation(() -> make_values(get_values(outline_theme, OutlineTheme),
                                                           get_values(widget_theme, WidgetTheme))))
end
