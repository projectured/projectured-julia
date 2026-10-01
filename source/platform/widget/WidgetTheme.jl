# Fragment of `WidgetModule` — the theme of the widgets: the palette, the fonts and
# the named sizes, the four presets, and the values that the widgets derive from a
# scaled theme.

"""
    WidgetTheme

The theme of the widgets: the colors, the fonts and the sizes that every widget
projection draws with. `@theme` declares it, so `ScaledWidgetTheme` holds each
value times its scale, and `WidgetTheme()` is the default theme, the slate light
preset.

- **Palette** — `background … ring`, and `track_off`, the track of a switch that
  is off.
- **Decorations** — `shadow`, `scrim`, `selection_ring` (the ring around a
  document selected as a whole) and `knob`.
- **Fonts** — `font`, `font_bold` and `font_small`.
- **Spacing** — `control_padding` (the padding of a control), `container_padding`
  (of a card and an alert), `compact_padding` (of a badge), `item_gap` (between the
  items of a bar, a list or a popup), `title_gap` (under a title), `label_gap`
  (between an icon or a mark and its label), `section_gap` (between sections and
  between the rows of a radio group), `bar_gap` (between the items of a menu bar)
  and `indent` (of a tree level).
- **Radii** — `radius`, and `radius_small` for a checkbox, a row band, a highlight
  and a skeleton.
- **Lines** — `border_width`, `stroke` (a checkmark, a radio ring, a knob ring)
  and `ring_width` (a focus ring and a selection ring).
- **Parts of controls** — the indicator of a checkbox and a radio button and its
  dot, the track and the knob padding of a switch, the height, the track and the
  knob of a slider, the height of a progress bar, and the thickness and the
  minimum thumb of a scroll bar.
- **Icons** — `chevron` (half the side of a chevron), and the chevron column and
  the icon column of a tree.

The text styles, the hover layer and the pressed layer are no fields: a widget
derives them from the fonts and the palette, so they follow a change of either.
A widget projection reads a scaled theme through its `UntrackedCell` style fields.
"""
@theme struct WidgetTheme
    # ── Palette ──
    background::StyleColor = color_slate_100
    foreground::StyleColor = color_slate_950
    card::StyleColor = color_slate_50
    card_foreground::StyleColor = color_slate_950
    popover::StyleColor = color_slate_50
    popover_foreground::StyleColor = color_slate_950
    muted::StyleColor = color_slate_200
    muted_foreground::StyleColor = color_slate_500
    primary::StyleColor = color_indigo_600
    primary_foreground::StyleColor = color_slate_50
    secondary::StyleColor = color_slate_200
    secondary_foreground::StyleColor = color_slate_900
    accent::StyleColor = color_indigo_100
    accent_foreground::StyleColor = color_indigo_700
    destructive::StyleColor = color_destructive
    destructive_foreground::StyleColor = color_destructive_fg
    border::StyleColor = color_slate_300
    input::StyleColor = color_slate_300
    ring::StyleColor = color_indigo_500
    track_off::StyleColor = color_slate_300
    # ── Decorations ──
    shadow::StyleColor = StyleColor(0.0, 0.0, 0.0, 0x14 / 255)
    scrim::StyleColor = StyleColor(0.0, 0.0, 0.0, 0x66 / 255)
    selection_ring::StyleColor = SELECTION_RING_COLOR
    knob::StyleColor = color_white
    # ── Fonts ──
    font::StyleFont = font_ubuntu_regular_20
    font_bold::StyleFont = font_ubuntu_bold_20
    font_small::StyleFont = font_ubuntu_regular_18
    # ── Spacing ──
    control_padding::Spacing = Spacing(Inset(9, 9, 14, 14))
    container_padding::Spacing = Spacing(16)
    compact_padding::Spacing = Spacing(Inset(3, 3, 10, 10))
    item_gap::Spacing = Spacing(4)
    title_gap::Spacing = Spacing(6)
    label_gap::Spacing = Spacing(6)
    section_gap::Spacing = Spacing(10)
    bar_gap::Spacing = Spacing(12)
    indent::Spacing = Spacing(22)
    # ── Radii ──
    radius::Radius = Radius(8)
    radius_small::Radius = Radius(4)
    # ── Lines ──
    border_width::LineWidth = LineWidth(1)
    stroke::LineWidth = LineWidth(2)
    ring_width::LineWidth = LineWidth(2)
    # ── Parts of controls ──
    indicator_size::ControlSize = ControlSize(18)
    indicator_dot::ControlSize = ControlSize(5)
    switch_track::ControlSize = ControlSize(Point2D(44, 24))
    switch_knob_padding::ControlSize = ControlSize(3)
    slider_height::ControlSize = ControlSize(24)
    slider_track::ControlSize = ControlSize(4)
    slider_knob::ControlSize = ControlSize(9)
    progress_height::ControlSize = ControlSize(8)
    scroll_bar_thickness::ControlSize = ControlSize(12)
    scroll_thumb_minimum::ControlSize = ControlSize(8)
    # ── Icons ──
    chevron::IconSize = IconSize(4)
    tree_chevron_column::IconSize = IconSize(18)
    tree_icon_column::IconSize = IconSize(20)
end

# ── Presets ─────────────────────────────────────────────────────────────────

"""
    make_light_theme(; font = font_ubuntu_regular_20) -> WidgetTheme

The neutral zinc light theme: a zinc palette on a white background. The slate
theme is the default, see [`make_slate_light_theme`](@ref).
"""
make_light_theme(; font::StyleFont = font_ubuntu_regular_20) =
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
    make_dark_theme(; font = font_ubuntu_regular_20) -> WidgetTheme

The neutral zinc dark theme, on zinc-950 surfaces. For the slate dark theme see
[`make_slate_dark_theme`](@ref).
"""
make_dark_theme(; font::StyleFont = font_ubuntu_regular_20) =
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
    make_slate_light_theme(; font = font_ubuntu_regular_20) -> WidgetTheme

The default light theme: a cool slate palette with an indigo accent, on tinted
surfaces, so the colors read as chosen and not washed out.
"""
make_slate_light_theme(; font::StyleFont = font_ubuntu_regular_20) = WidgetTheme(; font)

"""
    make_slate_dark_theme(; font = font_ubuntu_regular_20) -> WidgetTheme

The dark slate theme: deep slate surfaces with a bright indigo accent.
"""
make_slate_dark_theme(; font::StyleFont = font_ubuntu_regular_20) =
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
