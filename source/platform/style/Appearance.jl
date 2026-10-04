# Fragment of `StyleModule` — the appearance of an editor: the zoom, the six
# scales, and the theme and the scaled theme of each domain.

"""
    Appearance(; zoom = 1.0, font_scale = 1.0, icon_scale = 1.0, spacing_scale = 1.0,
                 control_scale = 1.0, radius_scale = 1.0, line_scale = 1.0)

What a person sets about the look of one editor: the zoom of the interface, the
six scales, and for each domain its theme and its scaled theme, found by the type
of the theme. `saved_themes` holds the values of each theme that a loaded file
names and that the appearance does not hold yet, by the name of its type; the
theme takes them when it is made (see [`load_appearance!`](@ref)).

`scroll_position` is the place of the appearance tab: view state, which a file
does not keep. The tab keeps it here, and not in the pane that it prints, because
the tab is printed again at each change of the appearance: the `appearance`
wrapper prints the whole view again, and a new pane would start at its top. The
tab gives its pane this cell, so a step of a size or a typed digit of a colour far
down the tab leaves the tab where it is. Every view of the tab shows this place.
`open_sections` holds the names of the theme types whose sections the tab shows
open, for the same reason; it is view state too.

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
    saved_themes::Dict{String,Any} = Dict{String,Any}()
    scroll_position::Point2D = Point2D(0, 0)
    open_sections::Vector{String} = String[]
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
theme that follows the scales of `appearance`, and answer the scaled theme. When a
loaded file named values for the type of `theme`, `theme` takes them first. A main
builder calls it to give a domain a theme other than its default, such as a
preset of the widgets.
"""
function set_theme!(appearance::Appearance, theme::Theme)
    saved = pop!(appearance.saved_themes, string(nameof(get_theme_type(theme))), nothing)
    saved === nothing || _write_saved_theme!(theme, saved)
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
    with_font_size(font, scale_length(font.size, appearance.font_scale))
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

"""
    scale_theme_value(value, theme, appearance)

`value` of a field of `theme` times the scale of its kind in `appearance`. A
[`FontRole`](@ref) takes the font that it gives over its base font in `theme`, and
then the font scale; a [`TextRole`](@ref) does the same for its font and keeps its
color. Every other value scales as [`scale_theme_value`](@ref)`(value, appearance)`
says. The scaled theme reads the base font, so a role follows a change of it.
"""
scale_theme_value(value, theme, appearance::Appearance) = scale_theme_value(value, appearance)
scale_theme_value(role::FontRole, theme, appearance::Appearance) =
    scale_theme_value(apply_font_role(role, get_role_base(role, theme)), appearance)
scale_theme_value(role::TextRole, theme, appearance::Appearance) =
    StyleText(scale_theme_value(role.font, theme, appearance), role.color)

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
that they give over their base. So a builder can give a projection either, and an
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

Write `appearance` into the TOML file `path`: the zoom, the six scales, and a table
for each theme that it holds, with the base value of each field. A color is
`#rrggbbaa`, a font is a table of its file and its size, a size is a number, or a
list for an inset (top, bottom, left, right) and for a point (x, y). A value of a
kind that the file can not say is left out.
"""
function save_appearance!(appearance::Appearance, path::AbstractString = get_appearance_file())
    data = Dict{String,Any}(String(f) => Float64(getproperty(appearance, f)) for f in _APPEARANCE_FACTORS)
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
with it follows. A factor or a field that the file does not name takes its
default, and a key that is not known is ignored. A theme that `appearance` holds
takes the values of its table at once. The table of a theme that it does not hold
yet waits in `saved_themes`, and the theme takes it when a builder makes it. A
missing file changes nothing.
"""
function load_appearance!(appearance::Appearance, path::AbstractString = get_appearance_file())
    isfile(path) || return appearance
    data = TOML.parsefile(path)
    for field in _APPEARANCE_FACTORS
        value = get(data, String(field), 1.0)
        setproperty!(appearance, field, value isa Real && value > 0 ? Float64(value) : 1.0)
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
_encode_appearance_value(font::StyleFont) =
    Dict{String,Any}("family" => font.family, "size" => font.size,
                     "weight" => Int(font.weight), "italic" => font.italic)
_encode_appearance_value(text::StyleText) =
    Dict{String,Any}("font" => _encode_appearance_value(text.font),
                     "color" => _encode_appearance_value(text.color))
function _encode_appearance_value(role::FontRole)
    table = Dict{String,Any}("base" => String(role.base), "relative_size" => role.relative_size)
    role.family === nothing || (table["family"] = role.family)
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
_decode_appearance_value(current::StyleColor, saved) =
    saved isa AbstractString ? convert_text_to_style_color(saved) : nothing
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

function _decode_appearance_value(current::FontRole, saved)
    saved isa AbstractDict || return nothing
    _is_absolute_font_table(saved) &&
        return _decode_appearance_value(StyleFont(_DEFAULT_FONT_FAMILY, 1), saved)
    base = get(saved, "base", String(current.base))
    relative_size = get(saved, "relative_size", current.relative_size)
    family = get(saved, "family", nothing)
    weight = get(saved, "weight", nothing)
    italic = get(saved, "italic", nothing)
    (base isa AbstractString && relative_size isa Real && relative_size > 0 &&
     (family === nothing || family isa AbstractString) &&
     (weight === nothing || weight isa Integer && 1 <= weight <= 1000) &&
     (italic === nothing || italic isa Bool)) || return nothing
    FontRole(; base = Symbol(base), family, weight, italic, relative_size)
end
function _decode_appearance_value(current::TextRole, saved)
    saved isa AbstractDict || return nothing
    _is_absolute_font_table(get(saved, "font", nothing)) &&
        return _decode_appearance_value(StyleText(StyleFont(_DEFAULT_FONT_FAMILY, 1), current.color), saved)
    font = _decode_appearance_value(current.font, get(saved, "font", nothing))
    color = _decode_appearance_value(current.color, get(saved, "color", nothing))
    TextRole(something(font, current.font), something(color, current.color))
end
function _decode_appearance_value(current::StyleText, saved)
    saved isa AbstractDict || return nothing
    font = _decode_appearance_value(current.font, get(saved, "font", nothing))
    color = _decode_appearance_value(current.color, get(saved, "color", nothing))
    StyleText(something(font, current.font), something(color, current.color))
end
function _decode_appearance_value(current::StyleStroke, saved)
    saved isa AbstractDict || return nothing
    color = _decode_appearance_value(current.color, get(saved, "color", nothing))
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
