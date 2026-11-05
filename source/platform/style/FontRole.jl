# Fragment of `StyleModule` — a step of the type scale, and a font and a text of a
# theme that follow a base font of the theme or a role of the font theme.

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
    FontRole(; base = :font, family = nothing, weight = nothing, italic = nothing,
               relative_size = 1.0)
    FontRole(role; weight = nothing, italic = nothing)

A font of a theme that follows another font. It has two forms.

The form with `base` follows a font of its own theme: the field `base` names the
base font. The role takes the family, the weight and the slant of the base, unless
it sets its own, and the size of the base times `relative_size`. A title is
`FontRole(weight = 700, relative_size = 1.5)`: the bold face of the family of the
base, half again as large. When a person changes the family or the size of the
base, every role of the theme follows. [`apply_font_role`](@ref) gives the font.

The form with a role name follows the font theme of the appearance: `role` names a
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
    base::Symbol
    family::Union{Nothing,String}
    weight::Union{Nothing,Int16}
    italic::Union{Nothing,Bool}
    relative_size::Float64
    role::Union{Nothing,Symbol}
end

FontRole(; base::Symbol = :font, family::Union{Nothing,AbstractString} = nothing,
         weight::Union{Nothing,Integer} = nothing, italic::Union{Nothing,Bool} = nothing,
         relative_size::Real = 1.0) =
    FontRole(base, family === nothing ? nothing : String(family),
             weight === nothing ? nothing : Int16(weight), italic, Float64(relative_size), nothing)

FontRole(role::Symbol; weight::Union{Nothing,Integer} = nothing,
         italic::Union{Nothing,Bool} = nothing) =
    FontRole(:font, nothing, weight === nothing ? nothing : Int16(weight), italic, 1.0, role)

"""
    TextRole(color; base = :font, family = nothing, weight = nothing, italic = nothing,
                    relative_size = 1.0)
    TextRole(color; font_role, weight = nothing, italic = nothing)

A text of a theme: a [`FontRole`](@ref) and a colour of any kind of
[`ThemeColor`](@ref). It is to `StyleText` what a font role is to `StyleFont`,
and the scaled theme holds the `StyleText` that it gives. A symbol names a role
of the colour theme: `TextRole(:keyword; weight = 700)` is
`TextRole(ColorRole(:keyword); weight = 700)`.

With `font_role`, the font is `FontRole(font_role; weight, italic)`, a role of the
font theme of the appearance: `TextRole(:text_muted; font_role = :quiet)`. The
keywords `base`, `family` and `relative_size` belong to the font that follows a
base font of its theme, so giving one of them with `font_role` throws an
`ArgumentError`.
"""
struct TextRole
    font::FontRole
    color::ThemeColor
end

function TextRole(color::ThemeColor; base::Union{Nothing,Symbol} = nothing,
                  family::Union{Nothing,AbstractString} = nothing,
                  weight::Union{Nothing,Integer} = nothing, italic::Union{Nothing,Bool} = nothing,
                  relative_size::Union{Nothing,Real} = nothing,
                  font_role::Union{Nothing,Symbol} = nothing)
    if font_role !== nothing
        (base === nothing && family === nothing && relative_size === nothing) ||
            throw(ArgumentError("`font_role` names a role of the font theme, so `base`, " *
                                "`family` and `relative_size` do not apply to it"))
        return TextRole(FontRole(font_role; weight, italic), color)
    end
    TextRole(FontRole(; base = something(base, :font), family, weight, italic,
                      relative_size = something(relative_size, 1.0)), color)
end
TextRole(role::Symbol; keywords...) = TextRole(ColorRole(role); keywords...)

"""
    apply_font_role(role, base) -> StyleFont

The font that `role` gives over the font `base`: the family, the weight and the
slant of `role` where it sets them and of `base` where it does not, and the size
of `base` times the relative size of `role`, to the nearest whole pixel and at
least 1.
"""
apply_font_role(role::FontRole, base::StyleFont) =
    StyleFont(something(role.family, base.family),
              max(1, round(Int, base.size * role.relative_size));
              weight = something(role.weight, base.weight),
              italic = something(role.italic, base.italic))

"""
    get_role_base(role, theme) -> StyleFont

The base font of `role` in `theme`: the font in the field that `role.base` names.
A role follows a font, not another role, so a field that holds anything else
throws an `ArgumentError`.
"""
function get_role_base(role::FontRole, theme)
    base = getproperty(theme, role.base)
    base isa StyleFont ||
        throw(ArgumentError("a font role follows a font, but the field `$(role.base)` " *
                            "of $(nameof(get_theme_type(theme))) holds $(typeof(base))"))
    base
end

"""
    ThemeText

What a text field of a theme holds: a [`TextRole`](@ref), which follows a role of
the colour theme and either a base font of the theme or a role of the font
theme of the appearance, or a fixed `StyleText`, which the appearance tab can set
in place of the role.
"""
const ThemeText = Union{StyleText, TextRole}

"""
    ThemeFont

What a font field of a theme holds: a [`FontRole`](@ref), which follows a base font
of the theme or a role of the font theme of the appearance, or a fixed `StyleFont`,
which the appearance tab can set in place of the role.
"""
const ThemeFont = Union{StyleFont, FontRole}
