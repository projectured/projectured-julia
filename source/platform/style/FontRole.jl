# Fragment of `StyleModule` — a step of the type scale, and a font and a text of a
# theme that follow a role of the font theme.

"""
    FontStep(family, size; weight = 400, italic = false)

One step of the type scale: `family` is `:sans` or `:mono`, the kind of the family
that the font theme names for it; `size` is in logical pixels, above 0; `weight`
is from 1 to 1000 and `italic` says whether it leans.

The fields of [`FontTheme`](@ref) hold one. A step names a kind of family and no
family, so a change of `sans_family` or `mono_family` moves every step of that
kind.

# Example

    FontStep(:sans, 13; weight = 500)     # a label
    FontStep(:mono, 14)                   # code in a document
"""
struct FontStep
    family::Symbol
    size::Int
    weight::Int16
    italic::Bool
    function FontStep(family::Symbol, size::Integer, weight::Integer, italic::Bool)
        family in (:sans, :mono) ||
            throw(ArgumentError("the family of a step is :sans or :mono, not $(repr(family))"))
        size > 0 || throw(ArgumentError("the size of a step is above 0, not $size"))
        1 <= weight <= 1000 || throw(ArgumentError("a weight is from 1 to 1000, not $weight"))
        new(family, Int(size), Int16(weight), italic)
    end
end

FontStep(family::Symbol, size::Integer; weight::Integer = 400, italic::Bool = false) =
    FontStep(family, size, weight, italic)

"""
    FontRole(role; weight = nothing, italic = nothing)

A font of a theme that follows the font theme of the appearance: `role` names a
field of [`FontTheme`](@ref), and the font takes its family, its size, its weight
and its slant, with the `weight` and the `italic` of the role over those of the
step. `FontRole(:quiet)` is the quiet text, and `FontRole(:document_code; weight = 700)`
is code in bold. A change of the font theme moves every role that names it.
[`resolve_font_role`](@ref) gives the font; a name that is no field of the font
theme throws an `ArgumentError` when it is resolved.

The scaled theme holds the font that the role gives, so a projection reads a
`StyleFont` as from any other field.
"""
struct FontRole
    role::Symbol
    weight::Union{Nothing,Int16}
    italic::Union{Nothing,Bool}
end

FontRole(role::Symbol; weight::Union{Nothing,Integer} = nothing,
         italic::Union{Nothing,Bool} = nothing) =
    FontRole(role, weight === nothing ? nothing : Int16(weight), italic)

"""
    ThemeFont

What a font field of a theme holds: a [`FontRole`](@ref), which follows a role of the
font theme of the appearance, or a fixed `StyleFont`, which the appearance tab can set
in place of the role.
"""
const ThemeFont = Union{StyleFont, FontRole}

"""
    TextRole(color; font_role = :text, weight = nothing, italic = nothing)
    TextRole(color; font)

A text of a theme: a [`ThemeFont`](@ref), which is a [`FontRole`](@ref) or an exact
`StyleFont`, and a colour of any kind of [`ThemeColor`](@ref). It is to `StyleText` what a font role is to `StyleFont`,
and the scaled theme holds the `StyleText` that it gives. A symbol names a role
of the colour theme: `TextRole(:keyword; font_role = :document_code, weight = 700)` is
`TextRole(ColorRole(:keyword); font_role = :document_code, weight = 700)`.

With `font_role`, the font is `FontRole(font_role; weight, italic)`, a role of the
font theme of the appearance: `TextRole(:text_muted; font_role = :quiet)`.

With `font`, an exact `StyleFont`, the text keeps that font and takes the colour
from the role: `TextRole(:warning_text; font = StyleFont("Lucide", 13))`. The scaled
theme scales the font with the font scale and no role changes its size, so it is the
form of an icon. Every other font keyword (`font_role`, `weight`, `italic`) throws an
`ArgumentError` with it.
"""
struct TextRole
    font::ThemeFont
    color::ThemeColor
end

function TextRole(color::ThemeColor; weight::Union{Nothing,Integer} = nothing,
                  italic::Union{Nothing,Bool} = nothing,
                  font_role::Union{Nothing,Symbol} = nothing,
                  font::Union{Nothing,StyleFont} = nothing)
    if font !== nothing
        (weight === nothing && italic === nothing && font_role === nothing) ||
            throw(ArgumentError("`font` is an exact font, so `font_role`, `weight` and " *
                                "`italic` do not apply to it"))
        return TextRole(font, color)
    end
    TextRole(FontRole(something(font_role, :text); weight, italic), color)
end
TextRole(role::Symbol; keywords...) = TextRole(ColorRole(role); keywords...)

"""
    ThemeText

What a text field of a theme holds: a [`TextRole`](@ref), which follows a role of
the colour theme and a role of the font theme of the appearance, or a fixed `StyleText`,
which the appearance tab can set in place of the role.
"""
const ThemeText = Union{StyleText, TextRole}
