# Fragment of `StyleModule` — the appearance of an editor: the zoom, the six
# scales, the colour settings and the colour themes, and the theme and the scaled
# theme of each domain.

"""
    COLOR_MODES

The modes of the colours of an appearance: `:system`, which follows the mode of
the operating system, `:light` and `:dark`.
"""
const COLOR_MODES = (:system, :light, :dark)

"""
    COLOR_CONTRASTS

The contrasts of the colours of an appearance: `:system`, which follows the
contrast of the operating system, `:normal` and `:high`.
"""
const COLOR_CONTRASTS = (:system, :normal, :high)

"""
    AppearanceScale(; zoom = 1.0, font_scale = 1.0, icon_scale = 1.0, spacing_scale = 1.0,
                      control_scale = 1.0, radius_scale = 1.0, line_scale = 1.0)

The zoom of the interface and the six scales of an [`Appearance`](@ref), its part
`scale`: the size of the text, of the icons, of the gaps, of the controls, of the
corners and of the lines, each a factor of the size that a theme gives. The fields
are cells, so a scaled theme follows a change of each.
"""
@document struct AppearanceScale
    zoom::Float64 = 1.0
    font_scale::Float64 = 1.0
    icon_scale::Float64 = 1.0
    spacing_scale::Float64 = 1.0
    control_scale::Float64 = 1.0
    radius_scale::Float64 = 1.0
    line_scale::Float64 = 1.0
end

"""
    AppearanceColors(; color_mode = :system, color_contrast = :system, color_palette = "radix",
                       color_accent = :blue, color_neutral = :slate,
                       system_colors = SystemColors())

The colour settings of an [`Appearance`](@ref), its part `colors`. They say how a
[`PaletteColor`](@ref) and a [`ColorRole`](@ref) become a colour: `color_mode` is
one of [`COLOR_MODES`](@ref), `color_contrast` one of [`COLOR_CONTRASTS`](@ref),
`color_palette` the name of a palette of the registry, `color_accent` the hue of
the accent, or `:system` for the hue nearest to the accent of the operating
system, and `color_neutral` the neutral ramp.

`system_colors` holds the colour settings of the operating system, a
`SystemColors` that the `appearance` wrapper takes from the backend; a setting
`:system` reads it (see [`get_color_mode`](@ref)). It is a fact of the system and
not a setting, so a file does not keep it, and with no answer of a backend it is
light, normal and with no accent.
"""
@document struct AppearanceColors
    color_mode::Symbol = :system
    color_contrast::Symbol = :system
    color_palette::String = DEFAULT_PALETTE_NAME
    color_accent::Symbol = :blue
    color_neutral::Symbol = :slate
    system_colors::SystemColors = SystemColors()
end

"""
    ThemeGroup(; title, color_theme = nothing, themes = CellVector(Any[]), open_names = String[])

A heading of the themes of an [`Appearance`](@ref): its `title` and its themes, in
the order that [`get_theme_place`](@ref) gives. The appearance tab shows each
heading over the cards of its themes, and a tree has a node for each heading.

`color_theme` is the colour theme of the present mode and contrast, which the
heading "Editor" shows first: a computed cell that follows the colour settings.
It is `nothing` for the other headings. `themes` holds the themes of the heading;
the font theme stands first in "Editor". `open_names` holds the names of the theme
types whose cards show open, in the appearance tab and on the page of the
heading: view state, which a file does not keep.
"""
@document struct ThemeGroup
    title::String
    color_theme::Any = nothing
    themes::CellVector = CellVector(Any[])
    open_names::Vector{String} = String[]
end

"""
    get_theme_place(T) -> (heading, rank)

Where the themes of the theme type `T` stand: the `heading` of the appearance,
`:editor`, `:tools` or `:documents`, and the `rank` of `T` in it. The themes of a
heading stand in the order of their ranks, and of the names of their types for
one rank. The default puts a theme type of `ProjecturedPlatform` under `:tools`
and any other under `:documents`, at rank 0. A slice adds a method for a theme
that every view draws with, under `:editor`.
"""
function get_theme_place end

get_theme_place(T::Type) =
    (Base.moduleroot(parentmodule(T)) === Base.moduleroot(@__MODULE__) ? :tools : :documents, 0)

"""
    Appearance(; scale = AppearanceScale(), colors = AppearanceColors())

What a person sets about the look of one editor: its `scale`, the zoom of the
interface and the six scales ([`AppearanceScale`](@ref)), its `colors`, the five
colour settings ([`AppearanceColors`](@ref)), and for each domain its theme and its
scaled theme, found by the type of the theme.

`color_themes` holds a [`ColorTheme`](@ref) for each pair of a mode and a
contrast, by the name that [`get_color_variant`](@ref) gives the pair, so a
fine-tune of a role stays with its mode and its contrast. `font_theme` holds the
[`FontTheme`](@ref): the one table of font roles, the same in every mode, which a
[`FontRole`](@ref) that names a role resolves in (see [`resolve_font_role`](@ref)).
`saved_themes` holds the values of each theme that a loaded file names and that
the appearance does not hold yet, by the name of its type; the theme takes them
when it is made (see [`load_appearance!`](@ref)).

`editor_themes`, `tool_themes` and `document_themes` are the three headings of the
themes ([`ThemeGroup`](@ref)): "Editor", with the colour theme of the present mode
and contrast, the font theme and the themes that every view draws with; "Tools",
the other themes of `ProjecturedPlatform`; and "Documents", the themes of the
other packages. [`set_theme!`](@ref) puts each theme into its heading.

`scroll_position` is the place of the appearance tab: view state, which a file
does not keep. The tab keeps it here, and not in the pane that it prints, because
the tab is printed again at each change of the appearance: the `appearance`
wrapper prints the whole view again, and a new pane would start at its top. The
tab gives its pane this cell, so a step of a size or a typed digit of a colour far
down the tab leaves the tab where it is. Every view of the tab shows this place.

The main builder of an editor makes one, builds its projection with it, and gives
it to the `appearance` wrapper of `build_editor`. A projection takes the scaled
theme of its domain with [`get_scaled_theme!`](@ref) while it is built. The zoom,
the scales and the colour settings are cells, so a scaled theme follows a change
of each; the wrapper then makes the view print again.
"""
@document struct Appearance
    scale::AppearanceScale = AppearanceScale()
    colors::AppearanceColors = AppearanceColors()
    color_themes::Dict{Symbol,Any} = make_color_themes()
    font_theme::Theme = FontTheme()
    editor_themes::ThemeGroup = _make_editor_theme_group(colors, color_themes, font_theme)
    tool_themes::ThemeGroup = ThemeGroup(; title = "Tools")
    document_themes::ThemeGroup = ThemeGroup(; title = "Documents")
    themes::Dict{Type,Any} = Dict{Type,Any}()
    saved_themes::Dict{String,Any} = Dict{String,Any}()
    scroll_position::Point2D = Point2D(0, 0)
end

# A tab that shows an appearance, a part or a heading of one, its node in a tree
# and its name in the address of a page, name it so.
get_document_title(::Appearance) = "Appearance"
get_document_title(::AppearanceScale) = "Scale"
get_document_title(::AppearanceColors) = "Colors"
get_document_title(group::ThemeGroup) = group.title

# The heading "Editor" of an appearance whose parts are `colors`, `color_themes`
# and `font_theme`: the font theme first, and the colour theme of the present mode
# and contrast as a cell that follows the colour settings.
function _make_editor_theme_group(colors::AppearanceColors, color_themes::AbstractDict, font_theme::Theme)
    group = ThemeGroup(; title = "Editor", themes = CellVector(Any[font_theme]))
    set_cell_computation!(getfield(group, :color_theme),
                          () -> color_themes[get_color_variant(get_color_mode(colors), get_color_contrast(colors))])
    group
end

# The heading of `appearance` that `heading`, one of the headings of
# `get_theme_place`, names.
_get_theme_group(appearance::Appearance, heading::Symbol) =
    heading === :editor ? appearance.editor_themes :
    heading === :tools ? appearance.tool_themes : appearance.document_themes

# Put `theme` into its heading of `appearance`, in place of the theme of its type,
# or at the place of its rank and its name.
function _put_theme_into_group!(appearance::Appearance, theme::Theme)
    T = get_theme_type(theme)
    (heading, rank) = get_theme_place(T)
    themes = _get_theme_group(appearance, heading).themes
    key = (rank, string(nameof(T)))
    for i in eachindex(themes)
        other = get_theme_type(themes[i])
        other === T && return (themes[i] = theme; nothing)
        (last(get_theme_place(other)), string(nameof(other))) > key &&
            return (insert!(themes, i, theme); nothing)
    end
    push!(themes, theme)
    nothing
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
theme that follows the scales of `appearance`, and into its heading of
`appearance` ([`get_theme_place`](@ref)), and answer the scaled theme. When a
loaded file named values for the type of `theme`, `theme` takes them first. A main
builder calls it to give a domain a theme other than its default, such as a
preset of the widgets.
"""
function set_theme!(appearance::Appearance, theme::Theme)
    saved = pop!(appearance.saved_themes, string(nameof(get_theme_type(theme))), nothing)
    saved === nothing || _write_saved_theme!(theme, saved)
    scaled = make_scaled_theme(theme, appearance)
    appearance.themes[get_theme_type(theme)] = (theme = theme, scaled = scaled)
    _put_theme_into_group!(appearance, theme)
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
    with_font_size(font, scale_length(font.size, appearance.scale.font_scale))
scale_theme_value(text::StyleText, appearance::Appearance) =
    StyleText(scale_theme_value(text.font, appearance), text.color)
scale_theme_value(stroke::StyleStroke, appearance::Appearance) =
    StyleStroke(stroke.color, scale_length(stroke.width, appearance.scale.line_scale), stroke.dash)
scale_theme_value(length::Spacing, appearance::Appearance) =
    scale_length(length.value, appearance.scale.spacing_scale)
scale_theme_value(length::Radius, appearance::Appearance) =
    scale_length(length.value, appearance.scale.radius_scale)
scale_theme_value(length::LineWidth, appearance::Appearance) =
    scale_length(length.value, appearance.scale.line_scale)
scale_theme_value(length::ControlSize, appearance::Appearance) =
    scale_length(length.value, appearance.scale.control_scale)
scale_theme_value(length::IconSize, appearance::Appearance) =
    scale_length(length.value, appearance.scale.icon_scale)

"""
    scale_theme_value(value, theme, appearance)

`value` of a field of `theme` times the scale of its kind in `appearance`. A
[`FontRole`](@ref) takes the font that [`resolve_font_role`](@ref) gives, scaled once; a
[`TextRole`](@ref) does the same for its font, and takes the
colour that [`resolve_theme_color`](@ref) gives its colour. Every other value scales as [`scale_theme_value`](@ref)`(value, appearance)`
says. The scaled theme reads the font theme, so a role follows a change of it.
"""
scale_theme_value(value, theme, appearance::Appearance) = scale_theme_value(value, appearance)
scale_theme_value(role::FontRole, theme, appearance::Appearance) =
    scale_theme_value(resolve_font_role(role, appearance), appearance)
scale_theme_value(role::TextRole, theme, appearance::Appearance) =
    StyleText(scale_theme_value(role.font, theme, appearance),
              resolve_theme_color(role.color, appearance))

make_scaled_theme(theme::Theme) = make_scaled_theme(theme, Appearance())

# The appearance at no scale, which a theme that is not scaled is read with. It is
# made at the first read, and no one writes it.
const _UNIT_APPEARANCE = Ref{Any}(nothing)
function _get_unit_appearance()
    appearance = _UNIT_APPEARANCE[]
    appearance === nothing && (appearance = _UNIT_APPEARANCE[] = Appearance())
    appearance
end

"""
    get_theme_value(theme, name) -> value

The value of the field `name` of `theme` that a projection draws with. Of a
scaled theme it is the scaled value. Of a theme it is the value at no scale: a
length is its number, and a font role and a text role are the font and the text
that they give. So a builder can give a projection either, and an
interface with no scales gives a theme as it is.
"""
get_theme_value(theme::ScaledTheme, name::Symbol) = getproperty(theme, name)
get_theme_value(theme::Theme, name::Symbol) =
    scale_theme_value(getproperty(theme, name), theme, _get_unit_appearance())

# The values of a theme that is not scaled, by the names of its fields.
struct _ThemeValues
    theme::Theme
end

Base.getproperty(values::_ThemeValues, name::Symbol) =
    get_theme_value(getfield(values, :theme), name)

"""
    get_theme_values(theme) -> values

What gives the values of `theme` by the names of its fields, as
[`get_theme_value`](@ref) reads them: a scaled theme itself, or a view of a theme
at no scale. A builder reads a style of a projection from it.
"""
get_theme_values(theme::ScaledTheme) = theme
get_theme_values(theme::Theme) = _ThemeValues(theme)

# ── Save and load ───────────────────────────────────────────────────────────

const _APPEARANCE_FACTORS = (:zoom, :font_scale, :icon_scale, :spacing_scale,
                             :control_scale, :radius_scale, :line_scale)

"""
    get_appearance_file() -> String

The file that holds the saved appearance: `appearance.toml` in the folder of the
configuration of ProjecturEd ([`get_configuration_folder`](@ref)), beside
`settings.toml`.
"""
get_appearance_file() = joinpath(get_configuration_folder(), "appearance.toml")

"""
    save_appearance!(appearance, path = get_appearance_file()) -> path

Write `appearance` into the TOML file `path`: the zoom, the six scales, the five
colour settings, the roles of each colour theme that differ from the default of
its mode and contrast, the fields of the font theme that differ from the default
(a step is a table of its family `sans` or `mono`, its size, its weight and its
slant), and a table for each theme that it holds, with the base value of each
field. A font role that names a role of the font theme is a table of its `role`
and the `weight` and `italic` that it sets. A fixed colour is `#rrggbbaa`, a step of a ramp a table of
its hue and its step, a role a table of its role; a font is a table of its file
and its size, a size is a number, or a list for an inset (top, bottom, left,
right) and for a point (x, y). A value of a kind that the file can not say is
left out.
"""
function save_appearance!(appearance::Appearance, path::AbstractString = get_appearance_file())
    data = Dict{String,Any}(String(f) => Float64(getproperty(appearance.scale, f)) for f in _APPEARANCE_FACTORS)
    for field in _APPEARANCE_COLOR_SETTINGS
        data[String(field)] = String(getproperty(appearance.colors, field))
    end
    fine_tunes = Dict{String,Any}()
    for (variant, theme) in appearance.color_themes
        default = make_color_theme(variant)
        table = Dict{String,Any}()
        for field in get_theme_field_names(ColorTheme)
            value = getproperty(theme, field)
            value == getproperty(default, field) && continue
            encoded = _encode_appearance_value(value)
            encoded === nothing || (table[String(field)] = encoded)
        end
        isempty(table) || (fine_tunes[String(variant)] = table)
    end
    isempty(fine_tunes) || (data[_COLOR_THEME_KEY] = fine_tunes)
    font_table = Dict{String,Any}()
    default_fonts = FontTheme()
    for field in get_theme_field_names(FontTheme)
        value = getproperty(appearance.font_theme, field)
        value == getproperty(default_fonts, field) && continue
        font_table[String(field)] = _encode_appearance_value(value)
    end
    isempty(font_table) || (data[_FONT_THEME_KEY] = font_table)
    for (T, entry) in appearance.themes
        table = Dict{String,Any}()
        for field in get_theme_field_names(T)
            value = _encode_appearance_value(getproperty(entry.theme, field))
            value === nothing || (table[String(field)] = value)
        end
        data[string(nameof(T))] = table
    end
    # The themes that a loaded file named and no builder made are kept as they were.
    for (name, table) in appearance.saved_themes
        haskey(data, name) || (data[name] = table)
    end
    mkpath(dirname(path))
    open(io -> TOML.print(io, data; sorted = true), path, "w")
    path
end

"""
    load_appearance!(appearance, path = get_appearance_file()) -> appearance

Read the TOML file `path` into `appearance`, in place, so that every view built
with it follows. A factor, a colour setting or a field that the file does not name
takes its default, and a key that is not known is ignored. Each colour theme takes
the default of its mode and contrast, and then the roles that the file names. A theme that `appearance` holds
takes the values of its table at once. The table of a theme that it does not hold
yet waits in `saved_themes`, and the theme takes it when a builder makes it. A
missing file changes nothing.
"""
function load_appearance!(appearance::Appearance, path::AbstractString = get_appearance_file())
    isfile(path) || return appearance
    data = TOML.parsefile(path)
    for field in _APPEARANCE_FACTORS
        value = get(data, String(field), 1.0)
        setproperty!(appearance.scale, field, value isa Real && value > 0 ? Float64(value) : 1.0)
    end
    _load_color_settings!(appearance.colors, data)
    font_table = pop!(data, _FONT_THEME_KEY, Dict{String,Any}())
    _write_saved_font_theme!(appearance.font_theme, font_table isa AbstractDict ? font_table :
                                                                                  Dict{String,Any}())
    fine_tunes = pop!(data, _COLOR_THEME_KEY, Dict{String,Any}())
    for (variant, theme) in appearance.color_themes
        table = fine_tunes isa AbstractDict ? get(fine_tunes, String(variant), nothing) : nothing
        _write_saved_color_theme!(theme, make_color_theme(variant),
                                  table isa AbstractDict ? table : Dict{String,Any}())
    end
    held = Dict(string(nameof(T)) => entry.theme for (T, entry) in appearance.themes)
    empty!(appearance.saved_themes)
    for (name, table) in data
        table isa AbstractDict || continue
        theme = get(held, name, nothing)
        theme === nothing ? (appearance.saved_themes[name] = table) :
                            _write_saved_theme!(theme, table; defaults = true)
    end
    for (name, theme) in held
        haskey(data, name) || _write_saved_theme!(theme, Dict{String,Any}(); defaults = true)
    end
    appearance
end

# The keys of the colour settings in the file, and the key of the table of the
# roles of the colour themes that differ from their defaults.
const _APPEARANCE_COLOR_SETTINGS = (:color_mode, :color_contrast, :color_palette,
                                    :color_accent, :color_neutral)
const _COLOR_THEME_KEY = "ColorTheme"
const _FONT_THEME_KEY = "FontTheme"

# Write into the font theme `theme` each field of the default font theme, and then
# the fields that the table `saved` names.
function _write_saved_font_theme!(theme, saved::AbstractDict)
    default = FontTheme()
    for field in get_theme_field_names(FontTheme)
        value = getproperty(default, field)
        if haskey(saved, String(field))
            decoded = _decode_appearance_value(value, saved[String(field)])
            decoded === nothing || (value = decoded)
        end
        setproperty!(theme, field, value)
    end
    theme
end

# Read the colour settings of `data` into `colors`: a setting that `data` does not
# name, or names as no text or as a mode or a contrast that is not known, takes
# its default.
function _load_color_settings!(colors::AppearanceColors, data::AbstractDict)
    default = (color_mode = :system, color_contrast = :system, color_palette = DEFAULT_PALETTE_NAME,
               color_accent = :blue, color_neutral = :slate)
    for field in _APPEARANCE_COLOR_SETTINGS
        saved = get(data, String(field), nothing)
        value = getproperty(default, field)
        if saved isa AbstractString && !isempty(saved)
            value = value isa Symbol ? Symbol(saved) : String(saved)
            field === :color_mode && !(value in COLOR_MODES) && (value = default.color_mode)
            field === :color_contrast && !(value in COLOR_CONTRASTS) && (value = default.color_contrast)
        end
        setproperty!(colors, field, value)
    end
end

# Write into the colour theme `theme` each role of `default`, and then the roles
# that the table `saved` names.
function _write_saved_color_theme!(theme, default, saved::AbstractDict)
    for field in get_theme_field_names(ColorTheme)
        value = getproperty(default, field)
        if haskey(saved, String(field))
            decoded = _decode_appearance_value(value, saved[String(field)])
            decoded === nothing || (value = decoded)
        end
        setproperty!(theme, field, value)
    end
    theme
end

# Write the values of the table `saved` into `theme`. With `defaults`, a field that
# the table does not name takes the value of the default theme of its type.
function _write_saved_theme!(theme, saved::AbstractDict; defaults::Bool = false)
    T = get_theme_type(theme)
    default = defaults ? T() : nothing
    for field in get_theme_field_names(T)
        key = String(field)
        current = getproperty(theme, field)
        if haskey(saved, key)
            value = _decode_appearance_value(current, saved[key])
            value === nothing || setproperty!(theme, field, value)
        elseif defaults
            setproperty!(theme, field, getproperty(default, field))
        end
    end
    theme
end

# A value of a theme as the TOML file says it, or `nothing` for a kind that the
# file can not say.
_encode_appearance_value(color::StyleColor) = format_style_color(color)
function _encode_appearance_value(color::PaletteColor)
    table = Dict{String,Any}("hue" => String(color.hue), "step" => color.step)
    color.alpha == 1 || (table["alpha"] = color.alpha)
    color.minimum_contrast == 0 || (table["minimum_contrast"] = color.minimum_contrast)
    color.against === nothing || (table["against"] = format_style_color(color.against))
    table
end
function _encode_appearance_value(color::ColorRole)
    table = Dict{String,Any}("role" => String(color.role))
    color.alpha == 1 || (table["alpha"] = color.alpha)
    table
end
_encode_appearance_value(font::StyleFont) =
    Dict{String,Any}("family" => font.family, "size" => font.size,
                     "weight" => Int(font.weight), "italic" => font.italic)
_encode_appearance_value(text::StyleText) =
    Dict{String,Any}("font" => _encode_appearance_value(text.font),
                     "color" => _encode_appearance_value(text.color))
_encode_appearance_value(step::FontStep) =
    Dict{String,Any}("family" => String(step.family), "size" => step.size,
                     "weight" => Int(step.weight), "italic" => step.italic)
function _encode_appearance_value(role::FontRole)
    table = Dict{String,Any}("role" => String(role.role))
    role.weight === nothing || (table["weight"] = Int(role.weight))
    role.italic === nothing || (table["italic"] = role.italic)
    table
end
_encode_appearance_value(role::TextRole) =
    Dict{String,Any}("font" => _encode_appearance_value(role.font),
                     "color" => _encode_appearance_value(role.color))
_encode_appearance_value(stroke::StyleStroke) =
    Dict{String,Any}("color" => _encode_appearance_value(stroke.color), "width" => stroke.width)
_encode_appearance_value(length::ThemeLength) = _encode_appearance_value(length.value)
_encode_appearance_value(inset::Inset) = Any[inset.top[], inset.bottom[], inset.left[], inset.right[]]
_encode_appearance_value(point::Point2D) = Any[point.x[], point.y[]]
_encode_appearance_value(value::Union{Real, AbstractString}) = value
_encode_appearance_value(::SingleSpacing) = Dict{String,Any}("single" => true)
_encode_appearance_value(spacing::MultipleSpacing) = Dict{String,Any}("multiple" => spacing.factor)
_encode_appearance_value(spacing::ExactSpacing) = Dict{String,Any}("exact" => spacing.distance)
_encode_appearance_value(spacing::AtLeastSpacing) = Dict{String,Any}("at_least" => spacing.distance)
_encode_appearance_value(_) = nothing

# The value that the TOML value `saved` says, of the kind of `current`, or
# `nothing` when it says no such value.
# A colour field of a theme takes a colour of any kind: a text names a fixed
# colour, a table with a `role` a role, and a table with a `hue` and a `step` a step
# of a ramp. A colour of a text style and of a stroke is a fixed colour.
_decode_appearance_value(current::ThemeColor, saved) = _decode_theme_color(saved)
_decode_style_color(saved) = saved isa AbstractString ? convert_text_to_style_color(saved) : nothing
_decode_theme_color(saved::AbstractString) = convert_text_to_style_color(saved)
function _decode_theme_color(saved::AbstractDict)
    alpha = get(saved, "alpha", 1.0)
    alpha isa Real && 0 <= alpha <= 1 || return nothing
    role = get(saved, "role", nothing)
    role isa AbstractString && return ColorRole(Symbol(role); alpha)
    hue = get(saved, "hue", nothing)
    step = get(saved, "step", nothing)
    minimum_contrast = get(saved, "minimum_contrast", 0.0)
    against = get(saved, "against", nothing)
    against = against === nothing ? nothing : _decode_style_color(against)
    (hue isa AbstractString && step isa Integer && 1 <= step <= 12 &&
     minimum_contrast isa Real) || return nothing
    PaletteColor(Symbol(hue), step; alpha, minimum_contrast, against)
end
_decode_theme_color(saved) = nothing
function _decode_appearance_value(current::StyleFont, saved)
    saved isa AbstractDict || return nothing
    family = get(saved, "family", nothing)
    size = get(saved, "size", current.size)
    weight = get(saved, "weight", Int(current.weight))
    italic = get(saved, "italic", current.italic)
    (family isa AbstractString && size isa Integer && size > 0 &&
     weight isa Integer && 1 <= weight <= 1000 && italic isa Bool) || return nothing
    StyleFont(family, size; weight, italic)
end
# A role field can hold a font or a text that a person set as it is; the table of
# such a value names a size, and a role names none.
_is_absolute_font_table(saved) = saved isa AbstractDict && haskey(saved, "size")

function _decode_appearance_value(current::FontStep, saved)
    saved isa AbstractDict || return nothing
    family = get(saved, "family", nothing)
    size = get(saved, "size", current.size)
    weight = get(saved, "weight", Int(current.weight))
    italic = get(saved, "italic", current.italic)
    (family in ("sans", "mono") && size isa Integer && size > 0 &&
     weight isa Integer && 1 <= weight <= 1000 && italic isa Bool) || return nothing
    FontStep(Symbol(family), size; weight, italic)
end
function _decode_appearance_value(current::FontRole, saved)
    saved isa AbstractDict || return nothing
    _is_absolute_font_table(saved) &&
        return _decode_appearance_value(StyleFont(_DEFAULT_FONT_FAMILY, 1), saved)
    name = get(saved, "role", nothing)
    weight = get(saved, "weight", nothing)
    italic = get(saved, "italic", nothing)
    (name isa AbstractString && !isempty(name) &&
     (weight === nothing || weight isa Integer && 1 <= weight <= 1000) &&
     (italic === nothing || italic isa Bool)) || return nothing
    FontRole(Symbol(name); weight, italic)
end
# A text field holds a text role or a text that a person set as it is. The table of an
# exact font with a fixed colour is that text; the table of an exact font with a role
# of the colour theme is a text role with an exact font; the table of a font role is a
# text role.
function _decode_appearance_value(current::TextRole, saved)
    saved isa AbstractDict || return nothing
    saved_font = get(saved, "font", nothing)
    if _is_absolute_font_table(saved_font) && get(saved, "color", nothing) isa AbstractString
        return _decode_appearance_value(StyleText(StyleFont(_DEFAULT_FONT_FAMILY, 1),
                                                  current.color isa StyleColor ? current.color : color_default),
                                        saved)
    end
    font = _decode_appearance_value(current.font isa FontRole ? current.font : FontRole(:text), saved_font)
    color = _decode_appearance_value(current.color, get(saved, "color", nothing))
    TextRole(something(font, current.font), something(color, current.color))
end
function _decode_appearance_value(current::StyleText, saved)
    saved isa AbstractDict || return nothing
    font = _decode_appearance_value(current.font, get(saved, "font", nothing))
    color = _decode_style_color(get(saved, "color", nothing))
    StyleText(something(font, current.font), something(color, current.color))
end
function _decode_appearance_value(current::StyleStroke, saved)
    saved isa AbstractDict || return nothing
    color = _decode_style_color(get(saved, "color", nothing))
    width = get(saved, "width", current.width)
    width isa Real || return nothing
    StyleStroke(something(color, current.color), width, current.dash)
end
function _decode_appearance_value(current::ThemeLength, saved)
    value = _decode_appearance_value(current.value, saved)
    value === nothing ? nothing : Base.typename(typeof(current)).wrapper(value)
end
function _decode_appearance_value(::Inset, saved)
    (saved isa AbstractVector && length(saved) == 4 && all(v -> v isa Real, saved)) || return nothing
    Inset(saved...)
end
function _decode_appearance_value(::Point2D, saved)
    (saved isa AbstractVector && length(saved) == 2 && all(v -> v isa Real, saved)) || return nothing
    Point2D(saved...)
end
_decode_appearance_value(current::Integer, saved) = saved isa Integer ? saved : nothing
_decode_appearance_value(current::AbstractFloat, saved) = saved isa Real ? Float64(saved) : nothing
_decode_appearance_value(current::AbstractString, saved) = saved isa AbstractString ? String(saved) : nothing
# A line spacing is saved as a table of one key, its kind, and its number.
function _decode_appearance_value(current::LineSpacing, saved)
    saved isa AbstractDict || return nothing
    haskey(saved, "single") && return SingleSpacing()
    number(key) = (value = get(saved, key, nothing); value isa Real ? value : nothing)
    factor = number("multiple")
    factor === nothing || return MultipleSpacing(factor)
    exact = number("exact")
    exact === nothing || return ExactSpacing(exact)
    least = number("at_least")
    least === nothing || return AtLeastSpacing(least)
    nothing
end
_decode_appearance_value(current, saved) = nothing
