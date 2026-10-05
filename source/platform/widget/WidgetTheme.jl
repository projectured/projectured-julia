# Fragment of `WidgetModule` — the theme of the widgets: the colours, the fonts and
# the named sizes, and the values that the widgets derive from a scaled theme.

"""
    WidgetTheme

The colors, the fonts and the sizes of every widget on screen: a button, a
card, a menu, a checkbox and a slider.

The theme of the widgets: the colors, the fonts and the sizes that every widget
projection draws with. `@theme` declares it, so `ScaledWidgetTheme` holds each
value times its scale, and `WidgetTheme()` is the default theme. Each colour is a
role of the colour theme, so the colour settings of the appearance choose it.

The fields are in groups: the palette, the decorations, the fonts, the spacing,
the radii, the lines, the parts of controls and the icons. Each field has a
docstring that says what it draws, which the appearance tab shows under its name.

The text styles are no fields: a widget derives them from the fonts and the
palette, so they follow a change of either.
A widget projection holds its styles as `UntrackedCell` fields, and no theme: its
builder fills them from a theme, scaled or not.
"""
@theme struct WidgetTheme
    # ── Palette ──
    "The surface behind the widgets of a window."
    background::StyleColor = ColorRole(:background)
    "The text and the marks on the background."
    foreground::StyleColor = ColorRole(:text)
    "The surface of a card, an alert and a panel."
    card::StyleColor = ColorRole(:surface)
    "The text on a card."
    card_foreground::StyleColor = ColorRole(:text)
    "The surface of a menu, a popup and a tooltip."
    popover::StyleColor = ColorRole(:surface)
    "The text on a menu, a popup and a tooltip."
    popover_foreground::StyleColor = ColorRole(:text)
    "A quiet surface: a disabled control, a skeleton, a track."
    muted::StyleColor = ColorRole(:surface_sunken)
    "Quiet text: a caption, a hint, a placeholder."
    muted_foreground::StyleColor = ColorRole(:text_muted)
    "The color of the main action: a default button, a checked box, a selected item."
    primary::StyleColor = ColorRole(:accent)
    "The text on the primary color."
    primary_foreground::StyleColor = ColorRole(:text_on_accent)
    "The surface of a secondary button."
    secondary::StyleColor = ColorRole(:surface_sunken)
    "The text on a secondary button."
    secondary_foreground::StyleColor = ColorRole(:text)
    "The surface of a hovered or a selected item in a list or a menu."
    accent::StyleColor = ColorRole(:accent_tint)
    "The text on the accent color."
    accent_foreground::StyleColor = ColorRole(:accent_text)
    "The color of an action that deletes or an error."
    destructive::StyleColor = ColorRole(:error_fill)
    "The text on the destructive color."
    destructive_foreground::StyleColor = ColorRole(:text_on_accent)
    "The border of a card, a pane and a separator."
    border::StyleColor = ColorRole(:border)
    "The border of a control that takes text or a value."
    input::StyleColor = ColorRole(:border_strong)
    "The focus ring of a control."
    ring::StyleColor = ColorRole(:focus_ring)
    "The track of a switch that is off."
    track_off::StyleColor = ColorRole(:border_strong)
    # ── Decorations ──
    "The shadow under a card and a popup."
    shadow::StyleColor = ColorRole(:shadow)
    "The layer that covers the window behind a dialog."
    scrim::StyleColor = ColorRole(:scrim)
    "The layer over a widget under the pointer."
    hover::StyleColor = ColorRole(:hover)
    "The layer over a pressed widget."
    pressed::StyleColor = ColorRole(:pressed)
    "The knob of a switch and of a slider."
    knob::StyleColor = ColorRole(:text_on_accent)
    # ── Fonts ──
    "The font of the text of a widget."
    font::StyleFont = StyleFont("Ubuntu", 13)
    "The font of a title and of a header."
    font_bold::FontRole = FontRole(weight = 700)
    "The font of a caption and of a badge."
    font_small::FontRole = FontRole(relative_size = 0.9)
    # ── Spacing ──
    "The space inside a button, a text box and the other controls."
    control_padding::Spacing = Spacing(Inset(5, 5, 10, 10))
    "The space inside a card and an alert."
    container_padding::Spacing = Spacing(12)
    "The space inside a badge."
    compact_padding::Spacing = Spacing(Inset(2, 2, 6, 6))
    "The space inside a command of a menu and of a context menu."
    menu_item_padding::Spacing = Spacing(Inset(4, 4, 12, 12))
    "The space inside the name of a menu on a menu bar: an item that opens a menu."
    menu_name_padding::Spacing = Spacing(Inset(4, 4, 6, 6))
    "The space inside a menu bar."
    menu_bar_padding::Spacing = Spacing(Inset(2, 2, 2, 2))
    "The space inside a toolbar."
    toolbar_padding::Spacing = Spacing(Inset(4, 4, 4, 4))
    "The space inside a button of a toolbar."
    toolbar_item_padding::Spacing = Spacing(Inset(4, 4, 4, 4))
    "The space inside a status bar."
    status_bar_padding::Spacing = Spacing(Inset(4, 4, 8, 8))
    "The space between the edge of a tabbed pane and its tab strip and page."
    tabbed_pane_padding::Spacing = Spacing(Inset(8, 8, 8, 8))
    "The largest width and height of the window of a context menu."
    context_menu_maximum_size::ControlSize = ControlSize(Point2D(640, 800))
    "The space between the items of a bar, a list or a popup."
    item_gap::Spacing = Spacing(2)
    "The space under a title."
    title_gap::Spacing = Spacing(4)
    "The space between an icon or a mark and its label."
    label_gap::Spacing = Spacing(6)
    "The space between sections, and between the rows of a radio group."
    section_gap::Spacing = Spacing(8)
    "The space between the items of a menu bar."
    bar_gap::Spacing = Spacing(8)
    "The space between the label column and the control column of a form."
    form_column_gap::Spacing = Spacing(12)
    "The space between the rows of a form."
    form_row_gap::Spacing = Spacing(8)
    "The indent of a level of a tree."
    indent::Spacing = Spacing(12)
    "The offset of the shadow under a button."
    shadow_offset::Spacing = Spacing(2)
    "How far the chevron of a card sits under the middle line of its header."
    chevron_nudge::Spacing = Spacing(1)
    "The space between the edge of a toggle group and its toggles."
    toggle_group_padding::Spacing = Spacing(2)
    "The space between the + and − marks of a spin box and the edge of its stepper."
    stepper_glyph_inset::Spacing = Spacing(3)
    "The space above the open body of an accordion item."
    accordion_body_gap::Spacing = Spacing(2)
    # ── Radii ──
    "The radius of the corners of a control, a card and a popup."
    radius::Radius = Radius(6)
    "The radius of the corners of a checkbox, a row band, a highlight and a skeleton."
    radius_small::Radius = Radius(3)
    # ── Lines ──
    "The width of a border."
    border_width::LineWidth = LineWidth(1)
    "The width of a checkmark, of the ring of a radio button and of the ring of a knob."
    stroke::LineWidth = LineWidth(2)
    "The width of a focus ring."
    ring_width::LineWidth = LineWidth(2)
    # ── Parts of controls ──
    "The size of the box of a checkbox and of the circle of a radio button."
    indicator_size::ControlSize = ControlSize(16)
    "The radius of the dot of a selected radio button."
    indicator_dot::ControlSize = ControlSize(4)
    "The side of the square of a color swatch."
    swatch_size::ControlSize = ControlSize(16)
    "The width and the height of the track of a switch."
    switch_track::ControlSize = ControlSize(Point2D(36, 20))
    "The space between the knob of a switch and its track."
    switch_knob_padding::ControlSize = ControlSize(2)
    "The height of a slider."
    slider_height::ControlSize = ControlSize(20)
    "The height of the track of a slider."
    slider_track::ControlSize = ControlSize(4)
    "The radius of the knob of a slider."
    slider_knob::ControlSize = ControlSize(7)
    "The height of a progress bar."
    progress_height::ControlSize = ControlSize(4)
    "The thickness of a scroll bar."
    scroll_bar_thickness::ControlSize = ControlSize(10)
    "The smallest length of the thumb of a scroll bar."
    scroll_thumb_minimum::ControlSize = ControlSize(8)
    # ── Icons ──
    "Half the side of a chevron."
    chevron::IconSize = IconSize(4)
    "The width of the column of the chevrons of a tree."
    tree_chevron_column::IconSize = IconSize(16)
    "The width of the column of the icons of a tree."
    tree_icon_column::IconSize = IconSize(20)
    "The size of an icon beside a text, as a part of the height of a line of that text."
    icon_size::IconSize = IconSize(1.0)
    "The smallest size of the + and − marks of a spin box."
    stepper_glyph_minimum::IconSize = IconSize(8)
end

# ── The theme with a font ───────────────────────────────────────────────────

"""
    make_widget_theme(; font = StyleFont("Ubuntu", 13)) -> WidgetTheme

The default widget theme with the font `font`. Its colours are roles of the
colour theme, so the colour settings of the appearance choose the palette, the
mode and the contrast.
"""
make_widget_theme(; font::StyleFont = StyleFont("Ubuntu", 13)) = WidgetTheme(; font)

# ── Values that a widget derives from a theme ───────────────────────────────

# The same color at another alpha: what makes a layer or a highlight read over the
# surface that it covers, and not in place of it.
_with_alpha(color::StyleColor, alpha::Real) =
    StyleColor(color.red, color.green, color.blue, Float64(alpha))

# The four text styles, and the layers of a hovered and of a pressed widget. The
# styles are no fields of the theme, so they follow the fonts and the palette. Each
# takes the values of a widget theme, scaled or not (`get_theme_values`).
_get_body_text(theme) = StyleText(theme.font, theme.foreground)
_get_title_text(theme) = StyleText(theme.font_bold, theme.foreground)
_get_caption_text(theme) = StyleText(theme.font_small, theme.muted_foreground)
_get_label_text(theme) = StyleText(theme.font, theme.foreground)
_get_hover_layer(theme) = theme.hover
_get_pressed_layer(theme) = theme.pressed

# The ring around a part selected as a whole, and the band of a selected row: values
# of the graphics theme `graphics_theme`, scaled or not, or of the default graphics
# theme for `nothing`. The layouts under the widgets draw with the same theme. A
# constructor reads them, and a print does not.
_make_graphics_style(graphics_theme) = make_theme_values_field(GraphicsTheme, graphics_theme)
_make_selected_row_color(graphics_theme) =
    graphics_theme === nothing ? get_theme_defaults(GraphicsTheme).selection_band :
                                 make_theme_cell(StyleColor, graphics_theme, values -> values.selection_band)

# The gap between the items that a builder of widgets puts in a row or a column:
# the `item_gap` of the widget theme `theme`, or of the default theme for
# `nothing`. A builder that runs outside a printer takes the theme of its caller.
_get_bar_item_gap(theme) = _get_theme_values(theme).item_gap

# The values of the widget theme `theme`, scaled or not, or of the default theme for
# `nothing`, for a builder that runs outside a printer.
_get_theme_values(theme) = theme === nothing ? get_theme_defaults(WidgetTheme) : get_theme_values(theme)

# The inset of `width` on every side, for a border.
_make_uniform_inset(width::Integer) = Inset(width, width, width, width)

"""
    _themed(T, theme, f) -> UntrackedCell{T}

A style field of a widget projection: [`make_theme_cell`](@ref) of the widget
theme `theme`, scaled or not.
"""
_themed(::Type{T}, theme, f) where {T} = make_theme_cell(T, theme, f)
