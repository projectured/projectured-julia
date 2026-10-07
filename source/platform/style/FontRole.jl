# Fragment of `StyleModule` — a font and a text of a theme that follow a base
# font of the theme.

"""
    FontRole(; base = :font, family = nothing, weight = nothing, italic = nothing,
               relative_size = 1.0)

A font of a theme that follows a base font of the same theme: the field `base`
names the base font. The role takes the family, the weight and the slant of the
base, unless it sets its own, and the size of the base times `relative_size`.

A title is `FontRole(weight = 700, relative_size = 1.5)`: the bold face of the
family of the base, half again as large. When a person changes the family or the
size of the base, every role of the theme follows. [`apply_font_role`](@ref)
gives the font.

The scaled theme holds the font that the role gives, so a projection reads a
`StyleFont` as from any other field.
"""
struct FontRole
    base::Symbol
    family::Union{Nothing,String}
    weight::Union{Nothing,Int16}
    italic::Union{Nothing,Bool}
    relative_size::Float64
end

FontRole(; base::Symbol = :font, family::Union{Nothing,AbstractString} = nothing,
         weight::Union{Nothing,Integer} = nothing, italic::Union{Nothing,Bool} = nothing,
         relative_size::Real = 1.0) =
    FontRole(base, family === nothing ? nothing : String(family),
             weight === nothing ? nothing : Int16(weight), italic, Float64(relative_size))

"""
    TextRole(color; base = :font, family = nothing, weight = nothing, italic = nothing,
                    relative_size = 1.0)

A text of a theme: a [`FontRole`](@ref) and a colour of any kind of
[`ThemeColor`](@ref). It is to `StyleText` what a font role is to `StyleFont`,
and the scaled theme holds the `StyleText` that it gives. A symbol names a role
of the colour theme: `TextRole(:keyword; weight = 700)` is
`TextRole(ColorRole(:keyword); weight = 700)`.
"""
struct TextRole
    font::FontRole
    color::ThemeColor
end

TextRole(color::ThemeColor; base::Symbol = :font, family::Union{Nothing,AbstractString} = nothing,
         weight::Union{Nothing,Integer} = nothing, italic::Union{Nothing,Bool} = nothing,
         relative_size::Real = 1.0) =
    TextRole(FontRole(; base, family, weight, italic, relative_size), color)
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
the colour theme and a base font of the theme, or a fixed `StyleText`, which the
appearance tab can set in place of the role.
"""
const ThemeText = Union{StyleText, TextRole}

"""
    ThemeFont

What a font field of a theme holds: a [`FontRole`](@ref), which follows a base font
of the theme, or a fixed `StyleFont`, which the appearance tab can set in place of
the role.
"""
const ThemeFont = Union{StyleFont, FontRole}
