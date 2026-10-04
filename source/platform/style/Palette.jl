# Fragment of `StyleModule` — the palettes: for each hue a ramp of 12 steps in a
# light and in a dark mode, the registry that finds a palette by its name, and
# the colour of a step of a ramp.

"""
    PALETTE_HUES

The nine hues that every palette gives: `:neutral` and the hues of the eight
accents of Solarized, with `:amber` for its yellow, `:teal` for its cyan and
`:pink` for its magenta.
"""
const PALETTE_HUES = (:neutral, :red, :orange, :amber, :green, :teal, :blue, :violet, :pink)

"""
    Palette

The supertype of a palette: a ramp of 12 steps for each of the
[`PALETTE_HUES`](@ref), in the light mode and in the dark mode, with one purpose
for each step:

| Step | Purpose |
| --- | --- |
| 1 | the background of a window |
| 2 | a raised or a sunken surface |
| 3, 4, 5 | the fill of a part: at rest, under the pointer, pressed or chosen |
| 6, 7, 8 | a faint line, a line, a strong line |
| 9, 10 | a solid fill, and the same under the pointer |
| 11 | a text of low contrast, and a token |
| 12 | a text of high contrast |

A palette answers [`get_palette_name`](@ref), [`get_palette_neutrals`](@ref) and
[`find_palette_ramp`](@ref).
"""
abstract type Palette end

"""
    TablePalette(name; light, dark, hues, neutrals)

A palette whose ramps are data. `light` and `dark` map the name of each ramp to
its 12 colours, as `#rrggbb` texts or as colours; `hues` maps each hue of
[`PALETTE_HUES`](@ref) but `:neutral` to the name of its ramp; `neutrals` names
the ramps that are neutral, the default first. [`make_resampled_ramp`](@ref) and
[`make_generated_ramp`](@ref) make the ramps of a palette that is not data.
"""
struct TablePalette <: Palette
    name::String
    light::Dict{Symbol,NTuple{12,StyleColor}}
    dark::Dict{Symbol,NTuple{12,StyleColor}}
    hues::Dict{Symbol,Symbol}
    neutrals::Vector{Symbol}
end

function TablePalette(name::AbstractString; light::AbstractDict, dark::AbstractDict,
                      hues::AbstractDict, neutrals::AbstractVector)
    ramps(table) = Dict{Symbol,NTuple{12,StyleColor}}(
        ramp => map(_convert_ramp_value, Tuple(texts)) for (ramp, texts) in table)
    palette = TablePalette(String(name), ramps(light), ramps(dark), Dict{Symbol,Symbol}(hues),
                           collect(Symbol, neutrals))
    for hue in PALETTE_HUES
        hue === :neutral || haskey(palette.hues, hue) ||
            throw(ArgumentError("the palette $(repr(name)) gives no ramp of the hue $(repr(hue))"))
    end
    isempty(palette.neutrals) && throw(ArgumentError("the palette $(repr(name)) has no neutral"))
    for ramp in vcat(collect(values(palette.hues)), palette.neutrals)
        haskey(palette.light, ramp) && haskey(palette.dark, ramp) ||
            throw(ArgumentError("the palette $(repr(name)) has no light and dark ramp $(repr(ramp))"))
    end
    palette
end

function _convert_ramp_value(text::AbstractString)
    color = convert_text_to_style_color(text)
    color === nothing && throw(ArgumentError("$(repr(text)) is no colour of a ramp"))
    color
end
_convert_ramp_value(color::StyleColor) = color

"""
    get_palette_name(palette) -> String

The name of `palette`, by which [`find_palette`](@ref) finds it.
"""
get_palette_name(palette::TablePalette) = palette.name

"""
    get_palette_neutrals(palette) -> Vector{Symbol}

The names of the neutral ramps of `palette`, the default first.
"""
get_palette_neutrals(palette::TablePalette) = palette.neutrals

"""
    find_palette_ramp(palette, hue, mode; neutral = nothing) -> NTuple{12,StyleColor} or nothing

The 12 colours of the ramp of `hue` in `mode`, `:light` or `:dark`: a hue of
[`PALETTE_HUES`](@ref) or the name of a ramp. The neutral is the ramp that
`neutral` names when it is a neutral of the palette, and the default neutral when
it is not. `nothing` for a hue that the palette does not have.
"""
function find_palette_ramp(palette::TablePalette, hue::Symbol, mode::Symbol;
                           neutral::Union{Nothing,Symbol} = nothing)
    ramps = mode === :dark ? palette.dark : palette.light
    name = hue === :neutral ?
        (neutral !== nothing && neutral in palette.neutrals ? neutral : first(palette.neutrals)) :
        get(palette.hues, hue, hue)
    get(ramps, name, nothing)
end

# ── The registry ────────────────────────────────────────────────────────────

const _PALETTES = Dict{String,Palette}()

"""
    DEFAULT_PALETTE_NAME

The name of the palette of a new appearance, and of the palette that a name with
no palette falls back to: `"radix"`.
"""
const DEFAULT_PALETTE_NAME = "radix"

"""
    register_palette!(palette) -> palette

Put `palette` into the registry under its name, in place of a palette of the same
name.
"""
register_palette!(palette::Palette) = (_PALETTES[get_palette_name(palette)] = palette; palette)

"""
    find_palette(name) -> Palette or nothing

The palette of the registry named `name`, or `nothing`.
"""
find_palette(name::AbstractString) = get(_PALETTES, name, nothing)

"""
    get_palette_names() -> Vector{String}

The names of the palettes of the registry, in alphabetical order.
"""
get_palette_names() = sort!(collect(keys(_PALETTES)))

# ── The colour of a step ────────────────────────────────────────────────────

"""
    compute_palette_color(palette, color, mode; neutral = nothing, accent = :blue) -> StyleColor

The colour of the [`PaletteColor`](@ref) `color` in `palette` and `mode`: the
step of the ramp of its hue, where `:accent` names `accent` and the neutral is as
[`find_palette_ramp`](@ref) says. A hue that the palette does not have takes the
ramp of `:blue`. A minimum contrast moves the colour along its ramp until it
reaches it, and the alpha of `color` multiplies the alpha of the step.
"""
function compute_palette_color(palette::Palette, color::PaletteColor, mode::Symbol;
                               neutral::Union{Nothing,Symbol} = nothing, accent::Symbol = :blue)
    hue = color.hue === :accent ? accent : color.hue
    ramp = something(find_palette_ramp(palette, hue, mode; neutral),
                     find_palette_ramp(palette, :blue, mode; neutral))
    result = ramp[color.step]
    if color.minimum_contrast > 0
        backgrounds = if color.against === nothing
            backdrop = find_palette_ramp(palette, :neutral, mode; neutral)
            (backdrop[1], backdrop[2])
        else
            (color.against,)
        end
        result = _compute_contrasting_color(result, ramp, backgrounds, color.minimum_contrast)
    end
    color.alpha == 1 ? result :
        StyleColor(result.red, result.green, result.blue, result.alpha * color.alpha)
end

# The least contrast of `color` against `backgrounds`.
_compute_least_contrast(color::StyleColor, backgrounds) =
    minimum(compute_contrast_ratio(color, background) for background in backgrounds)

# `color` moved toward the end of `ramp` with more contrast against
# `backgrounds`, just far enough to reach `minimum`, or that end when no point
# before it reaches it. A colour that reaches it already stays as it is.
function _compute_contrasting_color(color::StyleColor, ramp, backgrounds, minimum::Real)
    _compute_least_contrast(color, backgrounds) >= minimum && return color
    target = argmax(end_color -> _compute_least_contrast(end_color, backgrounds), (ramp[1], ramp[12]))
    _compute_least_contrast(target, backgrounds) >= minimum || return target
    low, high = 0.0, 1.0
    for _ in 1:24
        middle = (low + high) / 2
        _compute_least_contrast(color_interpolate(color, target, middle), backgrounds) >= minimum ?
            (high = middle) : (low = middle)
    end
    color_interpolate(color, target, high)
end

# ── Ramps that are not data ─────────────────────────────────────────────────

"""
    compute_step_lightness(hue, mode) -> NTuple{12,Float64}

The OKLCH lightness of each step of the ramp of `hue` in `mode`, in the Radix
palette: the lightness that gives each step its purpose. A palette that is not
data takes it, so its steps keep the same purposes.
"""
compute_step_lightness(hue::Symbol, mode::Symbol) =
    map(color -> convert_color_to_oklch(color)[1],
        something(find_palette_ramp(RADIX_PALETTE, hue, mode), find_palette_ramp(RADIX_PALETTE, :blue, mode)))

"""
    compute_step_chroma(hue, mode) -> NTuple{12,Float64}

The OKLCH chroma of each step of the ramp of `hue` in `mode`, in the Radix
palette, as a part of the chroma of step 9: low at the backgrounds, highest at
the solid fill.
"""
function compute_step_chroma(hue::Symbol, mode::Symbol)
    ramp = something(find_palette_ramp(RADIX_PALETTE, hue, mode), find_palette_ramp(RADIX_PALETTE, :blue, mode))
    chroma = map(color -> convert_color_to_oklch(color)[2], ramp)
    chroma ./ max(chroma[9], 1e-6)
end

"""
    make_resampled_ramp(anchors, hue, mode) -> NTuple{12,StyleColor}

A ramp of 12 steps from the colours `anchors` of a ramp of another design, such as
the 11 shades of a Tailwind colour: each step is the point of the anchors, mixed
in OKLab, at the lightness that [`compute_step_lightness`](@ref) gives the step
of `hue` in `mode`. A step lighter than the lightest anchor takes it, and a step
darker than the darkest takes that.
"""
function make_resampled_ramp(anchors::AbstractVector, hue::Symbol, mode::Symbol)
    colors = sort([_convert_ramp_value(anchor) for anchor in anchors];
                  by = color -> -convert_color_to_oklch(color)[1])
    lightness = [convert_color_to_oklch(color)[1] for color in colors]
    map(compute_step_lightness(hue, mode)) do target
        target >= lightness[1] && return colors[1]
        target <= lightness[end] && return colors[end]
        i = findlast(l -> l >= target, lightness)
        _mix_colors_in_oklab(colors[i], colors[i + 1],
                             (lightness[i] - target) / (lightness[i] - lightness[i + 1]))
    end
end

"""
    make_generated_ramp(color, hue, mode; anchor = true) -> NTuple{12,StyleColor}

A ramp of 12 steps around the colour `color`, in OKLCH: each step has the hue
angle of `color`, the lightness that [`compute_step_lightness`](@ref) gives the
step of `hue` in `mode`, and the chroma of `color` times the part that
[`compute_step_chroma`](@ref) gives the step. With `anchor`, step 9 is `color`
itself, and the steps of the lines and of the solid fill around it, 6 to 10,
move their lightness toward it, so the ramp keeps its order; the backgrounds and
the texts keep the lightness of their purpose.
"""
function make_generated_ramp(color::StyleColor, hue::Symbol, mode::Symbol; anchor::Bool = true)
    lightness, chroma, angle = convert_color_to_oklch(color)
    profile = compute_step_lightness(hue, mode)
    shift = anchor ? lightness - profile[9] : 0.0
    steps = map((l, c, w) -> convert_oklch_to_color(clamp(l + shift * w, 0.0, 1.0), chroma * c, angle),
                profile, compute_step_chroma(hue, mode), _ANCHOR_WEIGHTS)
    anchor ? ntuple(i -> i == 9 ? color : steps[i], 12) : steps
end

# How far each step follows the lightness of the anchor of a generated ramp.
const _ANCHOR_WEIGHTS = (0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.4, 0.7, 1.0, 0.9, 0.0, 0.0)
