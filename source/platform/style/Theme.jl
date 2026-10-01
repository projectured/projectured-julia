# Fragment of `StyleModule` — a theme, its scaled theme, and the kinds of length
# that say which scale applies to a value.

"""
    Theme

The supertype of a theme: a document that holds the fonts, the colors and the
sizes that the projections of one domain draw with. `@theme` declares one.
"""
abstract type Theme <: Document end

"""
    ScaledTheme

The supertype of a scaled theme: for each field of a theme, a computed cell that
holds the value of the theme times the scale of its kind. A projection reads a
scaled theme; a person edits the theme. `@theme` declares the scaled theme with
the theme, and `make_scaled_theme` makes one.
"""
abstract type ScaledTheme end

# ── The kinds of length ─────────────────────────────────────────────────────

"""
    ThemeLength

The supertype of a length of a theme whose type says which scale applies to it:
`Spacing`, `Radius`, `LineWidth`, `ControlSize` and `IconSize`. Each holds a
number, an `Inset` or a `Point2D` in logical pixels.
"""
abstract type ThemeLength end

"""
    Spacing(value)

A space of a theme: a padding, a margin, a gap or an indent. The spacing scale
applies to it.
"""
struct Spacing{T} <: ThemeLength
    value::T
end

"""
    Radius(value)

The radius of a corner of a theme. The radius scale applies to it.
"""
struct Radius{T} <: ThemeLength
    value::T
end

"""
    LineWidth(value)

The width of a line of a theme: a border, a separator, a rule or a ring. The
line scale applies to it.
"""
struct LineWidth{T} <: ThemeLength
    value::T
end

"""
    ControlSize(value)

The size of a part of a control that is not text: the box of a checkbox, the
circle of a radio button, the track of a switch, the knob of a slider, the bar of
a scroll bar. The control scale applies to it.
"""
struct ControlSize{T} <: ThemeLength
    value::T
end

"""
    IconSize(value)

The size of an icon of a theme. The icon scale applies to it.
"""
struct IconSize{T} <: ThemeLength
    value::T
end

"""
    scale_length(length, factor)

`length` times `factor`. A whole number stays a whole number, and a length above 0
stays at least 1, so a line or a gap never disappears. An `Inset` and a `Point2D`
scale each of their parts.
"""
scale_length(length::Integer, factor::Real) =
    length <= 0 ? Int(length) : max(1, round(Int, length * factor))
scale_length(length::AbstractFloat, factor::Real) = length * factor
scale_length(inset::Inset, factor::Real) =
    Inset(scale_length(inset.top[], factor), scale_length(inset.bottom[], factor),
          scale_length(inset.left[], factor), scale_length(inset.right[], factor))
scale_length(point::Point2D, factor::Real) =
    Point2D(scale_length(point.x[], factor), scale_length(point.y[], factor))

# ── The scaled theme ────────────────────────────────────────────────────────

"""
    make_scaled_theme(theme, appearance = Appearance()) -> ScaledTheme

A new scaled theme of `theme`: for each field, a computed cell that holds the
value of `theme` times the scale of its kind in `appearance`. The cells follow a
change of the field and of the scale. `@theme` adds the method for each theme.
"""
function make_scaled_theme end

"""
    get_theme_field_names(T) -> Tuple of Symbol

The fields that the declaration of the theme type `T` names, in their order: the
values that a person edits and that a file saves. `@theme` adds the method.
"""
function get_theme_field_names end

"""
    get_theme_type(theme) -> Type

The type that the declaration of the theme `theme` names. `@document` gives a
declared name to the cell layout of a document, so the concrete type of a theme
is a variant of that name; an `Appearance` keeps its themes by the declared name.
`@theme` adds the method.
"""
function get_theme_type end

"""
    get_base_theme(scaled) -> Theme

The theme that a scaled theme scales.
"""
get_base_theme(scaled::ScaledTheme) = getfield(scaled, :theme)

"""
    @theme struct T … end

Declare the theme `T` of a domain, and its scaled theme `ScaledT`.

- `T` is a document whose fields are cells; a person edits them, and Save and
  Load keep them. Each field needs a default, so `T()` is the default theme.
- `ScaledT` holds, for each field, a computed cell: the value of the field times
  the scale of its kind. The type of the field names the kind: `StyleFont`,
  `StyleText`, `StyleStroke`, `Spacing`, `Radius`, `LineWidth`, `ControlSize` or
  `IconSize`. Any other value takes no scale.
- `make_scaled_theme(theme::T, appearance)` makes a `ScaledT`,
  `get_theme_field_names(T)` answers the names of the fields, and
  `get_theme_type(theme)` answers `T`.

A projection reads a scaled theme, not a theme.

# Example

    @theme struct JsonTheme
        key_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
        indent::Spacing     = Spacing(16)
    end
    scaled = make_scaled_theme(JsonTheme(), Appearance(spacing_scale = 1.5))
    scaled.indent                      # 24
"""
macro theme(definition)
    (definition isa Expr && definition.head === :struct) ||
        throw(ArgumentError("@theme expects a struct definition"))
    definition.args[1] && throw(ArgumentError("@theme makes an immutable struct"))
    name = definition.args[2]
    name isa Symbol ||
        throw(ArgumentError("@theme sets the supertype of `$name` itself: write `struct Name`"))
    definition.args[2] = Expr(:(<:), name, GlobalRef(StyleModule, :Theme))
    fields = Symbol[]
    for line in definition.args[3].args
        line isa LineNumberNode && continue
        declaration = line isa Expr && line.head === :(=) ? line.args[1] : line
        (declaration isa Expr && declaration.head === :(::) && declaration.args[1] isa Symbol) ||
            throw(ArgumentError("@theme: each field is `name::Type = default`, got `$line`"))
        line isa Expr && line.head === :(=) ||
            throw(ArgumentError("@theme: the field `$(declaration.args[1])` needs a default"))
        declaration.args[1] === :theme &&
            throw(ArgumentError("@theme: a field can not be named `theme`, the scaled theme holds its theme under that name"))
        push!(fields, declaration.args[1])
    end
    scaled_name = Symbol("Scaled", name)
    theme = gensym(:theme)
    appearance = gensym(:appearance)
    cells = [:($Cell($Computation(() -> $scale_theme_value($theme.$f, $appearance))))
             for f in fields]
    scaled_fields = [:($f::$Cell) for f in fields]
    document = Expr(:macrocall, GlobalRef(DocumentModule, Symbol("@document")),
                    __source__, definition)
    esc(quote
        $document
        struct $scaled_name <: $ScaledTheme
            theme::$name
            $(scaled_fields...)
        end
        Base.getproperty(scaled::$scaled_name, field::Symbol) =
            field === :theme ? getfield(scaled, :theme) : getfield(scaled, field)[]
        $StyleModule.make_scaled_theme($theme::$name, $appearance::$Appearance) =
            $scaled_name($theme, $(cells...))
        $StyleModule.get_theme_field_names(::Type{$name}) = $(Tuple(fields))
        $StyleModule.get_theme_type(::$name) = $name
        $name
    end)
end
