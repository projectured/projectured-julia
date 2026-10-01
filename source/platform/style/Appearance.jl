# Fragment of `StyleModule` — the appearance of an editor: the zoom, the six
# scales, and the theme and the scaled theme of each domain.

"""
    Appearance(; zoom = 1.0, font_scale = 1.0, icon_scale = 1.0, spacing_scale = 1.0,
                 control_scale = 1.0, radius_scale = 1.0, line_scale = 1.0)

What a person sets about the look of one editor: the zoom of the interface, the
six scales, and for each domain its theme and its scaled theme, found by the type
of the theme.

The main builder of an editor makes one, builds its projection with it, and gives
it to the `appearance` wrapper of `build_editor`. A projection takes the scaled
theme of its domain with [`get_scaled_theme!`](@ref) while it is built. The zoom
and the scales are cells, so a scaled theme follows a change of a scale; the
wrapper then makes the view print again.
"""
@document struct Appearance
    zoom::Float64 = 1.0
    font_scale::Float64 = 1.0
    icon_scale::Float64 = 1.0
    spacing_scale::Float64 = 1.0
    control_scale::Float64 = 1.0
    radius_scale::Float64 = 1.0
    line_scale::Float64 = 1.0
    themes::Dict{Type,Any} = Dict{Type,Any}()
end

"""
    get_scaled_theme!(appearance, T) -> ScaledTheme

The scaled theme of the theme type `T` in `appearance`. When `appearance` holds no
theme of `T`, this makes the default theme `T()`, puts it and its scaled theme
into `appearance`, and answers the scaled theme.

Call it while a projection is built, never while it prints: it writes into
`appearance`.
"""
function get_scaled_theme!(appearance::Appearance, T::Type{<:Theme})
    themes = appearance.themes
    entry = get(themes, T, nothing)
    entry === nothing || return entry.scaled
    set_theme!(appearance, T())
end

"""
    set_theme!(appearance, theme) -> ScaledTheme

Put `theme` into `appearance` in place of the theme of its type, with a new scaled
theme that follows the scales of `appearance`, and answer the scaled theme. A main
builder calls it to give a domain a theme other than its default, such as a
preset of the widgets.
"""
function set_theme!(appearance::Appearance, theme::Theme)
    scaled = make_scaled_theme(theme, appearance)
    appearance.themes[get_theme_type(theme)] = (theme = theme, scaled = scaled)
    scaled
end

"""
    get_theme(appearance, T) -> Theme or nothing

The theme of the type `T` that `appearance` holds, which a person edits, or
`nothing`.
"""
function get_theme(appearance::Appearance, T::Type{<:Theme})
    entry = get(appearance.themes, T, nothing)
    entry === nothing ? nothing : entry.theme
end

"""
    scale_theme_value(value, appearance)

`value` of a theme times the scale of its kind in `appearance`. A font takes the
font scale, a text style scales its font and keeps its color, a stroke scales its
width with the line scale, and each `ThemeLength` takes the scale that its type
names. Every other value, such as a color, stays as it is.
"""
scale_theme_value(value, ::Appearance) = value
scale_theme_value(font::StyleFont, appearance::Appearance) =
    StyleFont(font.filename, scale_length(font.size, appearance.font_scale))
scale_theme_value(text::StyleText, appearance::Appearance) =
    StyleText(scale_theme_value(text.font, appearance), text.color)
scale_theme_value(stroke::StyleStroke, appearance::Appearance) =
    StyleStroke(stroke.color, scale_length(stroke.width, appearance.line_scale), stroke.dash)
scale_theme_value(length::Spacing, appearance::Appearance) =
    scale_length(length.value, appearance.spacing_scale)
scale_theme_value(length::Radius, appearance::Appearance) =
    scale_length(length.value, appearance.radius_scale)
scale_theme_value(length::LineWidth, appearance::Appearance) =
    scale_length(length.value, appearance.line_scale)
scale_theme_value(length::ControlSize, appearance::Appearance) =
    scale_length(length.value, appearance.control_scale)
scale_theme_value(length::IconSize, appearance::Appearance) =
    scale_length(length.value, appearance.icon_scale)

make_scaled_theme(theme::Theme) = make_scaled_theme(theme, Appearance())
