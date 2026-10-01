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

# ── Save and load ───────────────────────────────────────────────────────────

const _APPEARANCE_FACTORS = (:zoom, :font_scale, :icon_scale, :spacing_scale,
                             :control_scale, :radius_scale, :line_scale)

"""
    get_appearance_file() -> String

The file that holds the saved appearance: `appearance.toml` in the folder of the
configuration of ProjecturEd, `\$XDG_CONFIG_HOME/projectured/`, by default
`~/.config/projectured/`.
"""
get_appearance_file() =
    joinpath(get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config")), "projectured", "appearance.toml")

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
_encode_appearance_value(color::StyleColor) =
    "#" * join(string(round(Int, clamp(c, 0, 1) * 255); base = 16, pad = 2)
               for c in (color.red, color.green, color.blue, color.alpha))
function _encode_appearance_value(font::StyleFont)
    file = normpath(dirname(font.filename)) == normpath(_FONT_DIR) ? basename(font.filename) : font.filename
    Dict{String,Any}("file" => file, "size" => font.size)
end
_encode_appearance_value(text::StyleText) =
    Dict{String,Any}("font" => _encode_appearance_value(text.font),
                     "color" => _encode_appearance_value(text.color))
_encode_appearance_value(stroke::StyleStroke) =
    Dict{String,Any}("color" => _encode_appearance_value(stroke.color), "width" => stroke.width)
_encode_appearance_value(length::ThemeLength) = _encode_appearance_value(length.value)
_encode_appearance_value(inset::Inset) = Any[inset.top[], inset.bottom[], inset.left[], inset.right[]]
_encode_appearance_value(point::Point2D) = Any[point.x[], point.y[]]
_encode_appearance_value(value::Union{Real, AbstractString}) = value
_encode_appearance_value(_) = nothing

# The value that the TOML value `saved` says, of the kind of `current`, or
# `nothing` when it says no such value.
function _decode_appearance_value(current::StyleColor, saved)
    saved isa AbstractString || return nothing
    m = match(r"^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$", saved)
    m === nothing && return nothing
    channels = [parse(Int, m[1][i:i+1]; base = 16) for i in (1, 3, 5)]
    alpha = m[2] === nothing ? 255 : parse(Int, m[2]; base = 16)
    StyleColor((channels ./ 255)..., alpha / 255)
end
function _decode_appearance_value(current::StyleFont, saved)
    saved isa AbstractDict || return nothing
    file = get(saved, "file", nothing)
    size = get(saved, "size", current.size)
    (file isa AbstractString && size isa Integer && size > 0) || return nothing
    StyleFont(isabspath(file) ? file : joinpath(_FONT_DIR, file), size)
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
_decode_appearance_value(current, saved) = nothing
