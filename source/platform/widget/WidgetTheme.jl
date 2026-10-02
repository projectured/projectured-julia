# Fragment of `WidgetModule` — the theme of the widgets: the palette, the fonts and
# the named sizes, the four presets, and the values that the widgets derive from a
# scaled theme.

"""
    WidgetTheme

The colors, the fonts and the sizes of every widget on screen: a button, a
card, a menu, a checkbox and a slider.

The theme of the widgets: the colors, the fonts and the sizes that every widget
projection draws with. `@theme` declares it, so `ScaledWidgetTheme` holds each
value times its scale, and `WidgetTheme()` is the default theme, the slate light
preset.

The fields are in groups: the palette, the decorations, the fonts, the spacing,
the radii, the lines, the parts of controls and the icons. Each field has a
docstring that says what it draws, which the appearance tab shows under its name.

The text styles, the hover layer and the pressed layer are no fields: a widget
derives them from the fonts and the palette, so they follow a change of either.
A widget projection reads a scaled theme through its `UntrackedCell` style fields.
"""
@theme struct WidgetTheme
    # ── Palette ──
    "The surface behind the widgets of a window."
    background::StyleColor = color_slate_100
    "The text and the marks on the background."
    foreground::StyleColor = color_slate_950
    "The surface of a card, an alert and a panel."
    card::StyleColor = color_slate_50
    "The text on a card."
    card_foreground::StyleColor = color_slate_950
    "The surface of a menu, a popup and a tooltip."
    popover::StyleColor = color_slate_50
    "The text on a menu, a popup and a tooltip."
    popover_foreground::StyleColor = color_slate_950
    "A quiet surface: a disabled control, a skeleton, a track."
    muted::StyleColor = color_slate_200
    "Quiet text: a caption, a hint, a placeholder."
    muted_foreground::StyleColor = color_slate_500
    "The color of the main action: a default button, a checked box, a selected item."
    primary::StyleColor = color_indigo_600
    "The text on the primary color."
    primary_foreground::StyleColor = color_slate_50
    "The surface of a secondary button."
    secondary::StyleColor = color_slate_200
    "The text on a secondary button."
    secondary_foreground::StyleColor = color_slate_900
    "The surface of a hovered or a selected item in a list or a menu."
    accent::StyleColor = color_indigo_100
    "The text on the accent color."
    accent_foreground::StyleColor = color_indigo_700
    "The color of an action that deletes or an error."
    destructive::StyleColor = color_destructive
    "The text on the destructive color."
    destructive_foreground::StyleColor = color_destructive_fg
    "The border of a card, a pane and a separator."
    border::StyleColor = color_slate_300
    "The border of a control that takes text or a value."
    input::StyleColor = color_slate_300
    "The focus ring of a control."
    ring::StyleColor = color_indigo_500
    "The track of a switch that is off."
    track_off::StyleColor = color_slate_300
    # ── Decorations ──
    "The shadow under a card and a popup."
    shadow::StyleColor = StyleColor(0.0, 0.0, 0.0, 0x14 / 255)
    "The layer that covers the window behind a dialog."
    scrim::StyleColor = StyleColor(0.0, 0.0, 0.0, 0x66 / 255)
    "The ring around a document that is selected as a whole."
    selection_ring::StyleColor = SELECTION_RING_COLOR
    "The knob of a switch and of a slider."
    knob::StyleColor = color_white
    # ── Fonts ──
    "The font of the text of a widget."
    font::StyleFont = StyleFont("Ubuntu", 20)
    "The font of a title and of a header."
    font_bold::FontRole = FontRole(weight = 700)
    "The font of a caption and of a badge."
    font_small::FontRole = FontRole(relative_size = 0.9)
    # ── Spacing ──
    "The space inside a button, a text box and the other controls."
    control_padding::Spacing = Spacing(Inset(9, 9, 14, 14))
    "The space inside a card and an alert."
    container_padding::Spacing = Spacing(16)
    "The space inside a badge."
    compact_padding::Spacing = Spacing(Inset(3, 3, 10, 10))
    "The space between the items of a bar, a list or a popup."
    item_gap::Spacing = Spacing(4)
    "The space under a title."
    title_gap::Spacing = Spacing(6)
    "The space between an icon or a mark and its label."
    label_gap::Spacing = Spacing(6)
    "The space between sections, and between the rows of a radio group."
    section_gap::Spacing = Spacing(10)
    "The space between the items of a menu bar."
    bar_gap::Spacing = Spacing(12)
    "The indent of a level of a tree."
    indent::Spacing = Spacing(22)
    # ── Radii ──
    "The radius of the corners of a control, a card and a popup."
    radius::Radius = Radius(8)
    "The radius of the corners of a checkbox, a row band, a highlight and a skeleton."
    radius_small::Radius = Radius(4)
    # ── Lines ──
    "The width of a border."
    border_width::LineWidth = LineWidth(1)
    "The width of a checkmark, of the ring of a radio button and of the ring of a knob."
    stroke::LineWidth = LineWidth(2)
    "The width of a focus ring and of a selection ring."
    ring_width::LineWidth = LineWidth(2)
    # ── Parts of controls ──
    "The size of the box of a checkbox and of the circle of a radio button."
    indicator_size::ControlSize = ControlSize(18)
    "The radius of the dot of a selected radio button."
    indicator_dot::ControlSize = ControlSize(5)
    "The width and the height of the track of a switch."
    switch_track::ControlSize = ControlSize(Point2D(44, 24))
    "The space between the knob of a switch and its track."
    switch_knob_padding::ControlSize = ControlSize(3)
    "The height of a slider."
    slider_height::ControlSize = ControlSize(24)
    "The height of the track of a slider."
    slider_track::ControlSize = ControlSize(4)
    "The radius of the knob of a slider."
    slider_knob::ControlSize = ControlSize(9)
    "The height of a progress bar."
    progress_height::ControlSize = ControlSize(8)
    "The thickness of a scroll bar."
    scroll_bar_thickness::ControlSize = ControlSize(12)
    "The smallest length of the thumb of a scroll bar."
    scroll_thumb_minimum::ControlSize = ControlSize(8)
    # ── Icons ──
    "Half the side of a chevron."
    chevron::IconSize = IconSize(4)
    "The width of the column of the chevrons of a tree."
    tree_chevron_column::IconSize = IconSize(18)
    "The width of the column of the icons of a tree."
    tree_icon_column::IconSize = IconSize(20)
end

# ── Presets ─────────────────────────────────────────────────────────────────

"""
    make_light_theme(; font = StyleFont("Ubuntu", 20)) -> WidgetTheme

The neutral zinc light theme: a zinc palette on a white background. The slate
theme is the default, see [`make_slate_light_theme`](@ref).
"""
make_light_theme(; font::StyleFont = StyleFont("Ubuntu", 20)) =
    WidgetTheme(; background = color_white,       foreground = color_zinc_950,
                  card = color_white,             card_foreground = color_zinc_950,
                  popover = color_white,          popover_foreground = color_zinc_950,
                  muted = color_zinc_100,         muted_foreground = color_zinc_500,
                  primary = color_zinc_900,       primary_foreground = color_zinc_50,
                  secondary = color_zinc_100,     secondary_foreground = color_zinc_900,
                  accent = color_zinc_100,        accent_foreground = color_zinc_900,
                  border = color_zinc_200,        input = color_zinc_200,
                  ring = color_zinc_400,          track_off = color_zinc_300,
                  font)

"""
    make_dark_theme(; font = StyleFont("Ubuntu", 20)) -> WidgetTheme

The neutral zinc dark theme, on zinc-950 surfaces. For the slate dark theme see
[`make_slate_dark_theme`](@ref).
"""
make_dark_theme(; font::StyleFont = StyleFont("Ubuntu", 20)) =
    WidgetTheme(; background = color_zinc_950,    foreground = color_zinc_50,
                  card = color_zinc_900,          card_foreground = color_zinc_50,
                  popover = color_zinc_900,       popover_foreground = color_zinc_50,
                  muted = color_zinc_800,         muted_foreground = color_zinc_400,
                  primary = color_zinc_50,        primary_foreground = color_zinc_900,
                  secondary = color_zinc_800,     secondary_foreground = color_zinc_50,
                  accent = color_zinc_800,        accent_foreground = color_zinc_50,
                  border = color_zinc_800,        input = color_zinc_800,
                  ring = color_zinc_600,          track_off = color_zinc_700,
                  font)

"""
    make_slate_light_theme(; font = StyleFont("Ubuntu", 20)) -> WidgetTheme

The default light theme: a cool slate palette with an indigo accent, on tinted
surfaces, so the colors read as chosen and not washed out.
"""
make_slate_light_theme(; font::StyleFont = StyleFont("Ubuntu", 20)) = WidgetTheme(; font)

"""
    make_slate_dark_theme(; font = StyleFont("Ubuntu", 20)) -> WidgetTheme

The dark slate theme: deep slate surfaces with a bright indigo accent.
"""
make_slate_dark_theme(; font::StyleFont = StyleFont("Ubuntu", 20)) =
    WidgetTheme(; background = color_slate_950,   foreground = color_slate_50,
                  card = color_slate_900,         card_foreground = color_slate_50,
                  popover = color_slate_900,      popover_foreground = color_slate_50,
                  muted = color_slate_800,        muted_foreground = color_slate_400,
                  primary = color_indigo_500,     primary_foreground = color_slate_50,
                  secondary = color_slate_800,    secondary_foreground = color_slate_50,
                  accent = color_indigo_950,      accent_foreground = color_indigo_200,
                  border = color_slate_800,       input = color_slate_800,
                  ring = color_indigo_400,        track_off = color_slate_700,
                  font)

# The four presets, for the appearance tab.
get_theme_presets(::Type{WidgetTheme}) =
    Pair{String,Any}["Slate light" => make_slate_light_theme, "Slate dark" => make_slate_dark_theme,
                     "Light" => make_light_theme, "Dark" => make_dark_theme]

# ── Values that a widget derives from a scaled theme ────────────────────────

# The same color at another alpha: what makes a layer or a highlight read over the
# surface that it covers, and not in place of it.
_with_alpha(color::StyleColor, alpha::Real) =
    StyleColor(color.red, color.green, color.blue, Float64(alpha))

# The four text styles, and the layers of a hovered and of a pressed widget. They
# are no fields of the theme, so they follow the fonts and the palette.
_get_body_text(theme::ScaledWidgetTheme) = StyleText(theme.font, theme.foreground)
_get_title_text(theme::ScaledWidgetTheme) = StyleText(theme.font_bold, theme.foreground)
_get_caption_text(theme::ScaledWidgetTheme) = StyleText(theme.font_small, theme.muted_foreground)
_get_label_text(theme::ScaledWidgetTheme) = StyleText(theme.font, theme.foreground)
_get_hover_layer(theme::ScaledWidgetTheme) = _with_alpha(theme.primary, 0.12)
_get_pressed_layer(theme::ScaledWidgetTheme) = _with_alpha(theme.primary, 0.20)

# The inset of `width` on every side, for a border.
_make_uniform_inset(width::Integer) = Inset(width, width, width, width)

# A small offset of a widget that is no value of the theme, times the spacing
# scale of the appearance of `theme`.
_scale_space(length, theme::ScaledWidgetTheme) =
    scale_length(length, get_theme_appearance(theme).spacing_scale)

# The icon scale of the appearance of `theme`. The box of a named icon is the box
# that its widget gives, times this scale.
_get_icon_scale(theme::ScaledWidgetTheme) = get_theme_appearance(theme).icon_scale

"""
    _themed(T, theme, f) -> UntrackedCell{T}

A style field of a widget projection: [`make_theme_cell`](@ref) of the scaled
widget theme `theme`.
"""
_themed(::Type{T}, theme::ScaledWidgetTheme, f) where {T} = make_theme_cell(T, theme, f)
