# Fragment of `StyleModule` — the kinds of colour that a field of a theme holds:
# a step of a ramp of the palette, and a role of the colour theme. The scaled
# theme computes the `StyleColor` of each from the colour settings of the
# appearance, as it computes a length from a scale.

"""
    PaletteColor(hue, step; alpha = 1, minimum_contrast = 0, against = nothing)

A colour that names a step of a ramp of the palette: `hue` is one of
[`PALETTE_HUES`](@ref), `:accent` for the hue of the accent of the appearance,
or the name of a ramp of the palette, and `step` is from 1 to 12. The scaled theme
computes the colour from the palette, the mode, the neutral and the accent of the
appearance, so it follows a change of each. `alpha` multiplies the alpha of the
step.

With a `minimum_contrast` above 0, the colour reaches that contrast ratio against
`against`: the backgrounds of the palette (steps 1 and 2 of the neutral) for
`nothing`, or the colour that it names. A step that has less moves along its
ramp toward the end with more contrast, just far enough, so the hue stays.

The fields of [`ColorTheme`](@ref) hold one; a field of any other theme can hold
one too, and it follows the palette and the mode.

# Example

    PaletteColor(:neutral, 11)                        # muted text
    PaletteColor(:orange, 11; minimum_contrast = 4.5) # a token that reaches 4.5:1
    PaletteColor(:accent, 9; alpha = 0.25)            # a selection band
"""
struct PaletteColor
    hue::Symbol
    step::Int
    alpha::Float64
    minimum_contrast::Float64
    against::Union{Nothing,StyleColor}
    function PaletteColor(hue::Symbol, step::Integer, alpha::Real, minimum_contrast::Real,
                          against::Union{Nothing,StyleColor})
        1 <= step <= 12 || throw(ArgumentError("a step of a ramp is from 1 to 12, not $step"))
        0 <= alpha <= 1 || throw(ArgumentError("an alpha is from 0 to 1, not $alpha"))
        new(hue, Int(step), Float64(alpha), Float64(minimum_contrast), against)
    end
end

PaletteColor(hue::Symbol, step::Integer; alpha::Real = 1.0, minimum_contrast::Real = 0.0,
             against::Union{Nothing,StyleColor} = nothing) =
    PaletteColor(hue, step, alpha, minimum_contrast, against)

"""
    ColorRole(role; alpha = 1)

A colour that names a role of the colour theme of the appearance:
`ColorRole(:keyword)`, `ColorRole(:text_muted)`. The scaled theme computes the
colour that the [`ColorTheme`](@ref) of the present mode and contrast gives the
role, so a field follows a change of the colour settings and a fine-tune of the
role. `alpha` multiplies the alpha of the role.

A field of a theme of a domain holds one, for example
`key_text::ThemeText = TextRole(:field)`.
"""
struct ColorRole
    role::Symbol
    alpha::Float64
    function ColorRole(role::Symbol, alpha::Real)
        0 <= alpha <= 1 || throw(ArgumentError("an alpha is from 0 to 1, not $alpha"))
        new(role, Float64(alpha))
    end
end

ColorRole(role::Symbol; alpha::Real = 1.0) = ColorRole(role, alpha)

"""
    ThemeColor

What a colour field of a theme holds: a `StyleColor`, which no setting changes,
a [`PaletteColor`](@ref) or a [`ColorRole`](@ref).
"""
const ThemeColor = Union{StyleColor, PaletteColor, ColorRole}

"""
    format_theme_color(color) -> String

`color` as a person reads it: `#rrggbbaa` for a `StyleColor`, `blue 11` for a
step of a ramp and `@keyword` for a role, with the alpha in percent when it is
below 1.
"""
format_theme_color(color::StyleColor) = format_style_color(color)
format_theme_color(color::PaletteColor) =
    string(color.hue, " ", color.step, _format_alpha(color.alpha))
format_theme_color(color::ColorRole) = string("@", color.role, _format_alpha(color.alpha))

_format_alpha(alpha::Real) = alpha == 1 ? "" : string(" at ", round(Int, alpha * 100), "%")
