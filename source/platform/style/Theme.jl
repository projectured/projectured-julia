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

"""
    convert_theme_value(T, value)

`value` in the kind of length that the declared type `T` of a field names. A field
of a document is a plain cell, so its declared type is not checked; this gives a
bare number of a field declared `Radius` the kind `Radius`, so it takes the radius
scale. A value of the kind already, and a field of any other type, stay as they
are.
"""
convert_theme_value(::Type, value) = value
convert_theme_value(::Type{<:Spacing}, value) = value isa Spacing ? value : Spacing(value)
convert_theme_value(::Type{<:Radius}, value) = value isa Radius ? value : Radius(value)
convert_theme_value(::Type{<:LineWidth}, value) = value isa LineWidth ? value : LineWidth(value)
convert_theme_value(::Type{<:ControlSize}, value) =
    value isa ControlSize ? value : ControlSize(value)
convert_theme_value(::Type{<:IconSize}, value) = value isa IconSize ? value : IconSize(value)

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
    get_theme_presets(T) -> Vector{Pair{String,Any}}

The presets of the theme type `T`: the name of each and a function with no
argument that makes it. The appearance tab offers them at the head of the section
of `T`. A theme type with no method has none.
"""
get_theme_presets(::Type) = Pair{String,Any}[]

"""
    find_theme_field_text(T, name) -> String | Nothing

The docstring of the field `name` of the theme type `T`: the string before the
field in its `@theme` declaration, or `nothing` for a field with none.
"""
find_theme_field_text(T::Type, name::Symbol) = get(get_theme_field_texts(T), name, nothing)

"""
    get_theme_field_texts(T) -> NamedTuple

The docstrings of the fields of the theme type `T`, by the name of the field.
`@theme` adds the method; a type with no method has none.
"""
get_theme_field_texts(::Type) = (;)

"""
    get_base_theme(scaled) -> Theme

The theme that a scaled theme scales.
"""
get_base_theme(scaled::ScaledTheme) = getfield(scaled, :theme)

"""
    get_theme_appearance(scaled) -> Appearance

The appearance whose scales a scaled theme follows. A projection reads a scale
from it for a length that is not a value of its theme.
"""
get_theme_appearance(scaled::ScaledTheme) = getfield(scaled, :appearance)

"""
    make_theme_cell(T, theme, f) -> UntrackedCell{T}

A style field of a projection that reads `f(values)` at each read, with no edge,
where `values` gives the values of `theme` by the names of its fields
([`get_theme_value`](@ref)): of a scaled theme its scaled values, of a theme its
values at no scale. A view shows a change of the theme when it prints again, so
the field needs no edge. A projection declared `@projection UntrackedCell struct`
holds it as it is. The builder of the projection calls it; the projection does
not know the theme.
"""
make_theme_cell(::Type{T}, theme, f) where {T} =
    UntrackedCell{T}(Computation(() -> f(get_theme_values(theme))))

# An inset and a point hold cells of their own, and a read of a side records an
# edge to it. So a derived inset or point is made once for each state of the
# theme and kept in a computed cell, and the style field reads that cell with no
# edge. A new one at each read would give a printer an edge to a new cell at each
# print.
function make_theme_cell(::Type{T}, theme, f) where {T <: Union{Inset, Point2D}}
    kept = Cell(Computation(() -> f(get_theme_values(theme))))
    UntrackedCell{T}(Computation(() -> kept[]))
end

"""
    get_theme_defaults(T) -> NamedTuple

The values of the default theme `T()` at no scale, one for each field, as plain
values: a length is a number of pixels. A projection built with no theme holds
them, so it reads no cell and makes no theme. They are made once for each theme
type, and no one edits them.
"""
function get_theme_defaults(T::Type)
    lock(_THEME_DEFAULTS_LOCK) do
        get!(_THEME_DEFAULTS, T) do
            scaled = make_scaled_theme(T())
            names = get_theme_field_names(T)
            NamedTuple{names}(Tuple(getproperty(scaled, name) for name in names))
        end
    end
end

const _THEME_DEFAULTS = IdDict{Type,Any}()
const _THEME_DEFAULTS_LOCK = ReentrantLock()

"""
    make_style_field(K, theme, T; name) -> T or UntrackedCell{T}

The style field of type `T` of a projection that holds the field `name` of the
theme type `K`. With a theme of `K`, scaled or not, it is a cell that reads the
value of `theme` at each read, with no edge ([`make_theme_cell`](@ref)). With
`nothing`, it is the plain value of the default theme
([`get_theme_defaults`](@ref)), and the projection reads no cell. `@theme` writes
a function for each theme type that calls it, such as `get_json_style`.
"""
make_style_field(::Type{K}, ::Nothing, ::Type{T}; name::Symbol) where {K,T} =
    convert(T, getproperty(get_theme_defaults(K), name))
make_style_field(::Type{K}, theme, ::Type{T}; name::Symbol) where {K,T} =
    make_theme_cell(T, theme, values -> getproperty(values, name))

"""
    make_style_field(K, theme; name) -> value or UntrackedCell

[`make_style_field`](@ref) of the type of the default value of the field `name`
of `K`, or of `Any` when that default is `nothing`.
"""
function make_style_field(::Type{K}, theme; name::Symbol) where {K}
    default = getproperty(get_theme_defaults(K), name)
    theme === nothing && return default
    make_style_field(K, theme, default === nothing ? Any : typeof(default); name)
end

# The name of the function that `@theme` writes for the theme type `type_name`:
# `get_json_style` for `JsonTheme`, `get_db_catalog_style` for `DbCatalogTheme`.
function _get_style_function_name(type_name::Symbol)
    stem = replace(String(type_name), r"Theme$" => "")
    words = [lowercase(m.match) for m in eachmatch(r"[A-Z][a-z0-9]*|[a-z0-9]+", stem)]
    Symbol("get_", join(words, "_"), "_style")
end

"""
    make_theme_values_field(K, theme) -> NamedTuple or UntrackedCell{NamedTuple}

The style field of a projection that holds every value of the theme type `K` as
one `NamedTuple`, by the names of the fields. With a theme of `K`, scaled or not,
it is a cell that reads the values of `theme` at each read, with no edge; with `nothing`,
it is the plain values of the default theme. A printer with many helpers reads
the field once at each print, with `unwrap_cell`, and gives the tuple to them.
"""
function make_theme_values_field(::Type{K}, theme) where {K}
    theme === nothing && return get_theme_defaults(K)
    names = get_theme_field_names(K)
    make_theme_cell(NamedTuple, theme,
                    values -> NamedTuple{names}(Tuple(getproperty(values, name) for name in names)))
end

"""
    @theme struct T … end

Declare the theme `T` of a domain, and its scaled theme `ScaledT`.

- `T` is a document whose fields are cells; a person edits them, and Save and
  Load keep them. Each field needs a default, so `T()` is the default theme.
- `ScaledT` holds, for each field, a computed cell: the value of the field times
  the scale of its kind. The type of the field names the kind: `StyleFont`,
  `StyleText`, `FontRole`, `TextRole`, `StyleStroke`, `Spacing`, `Radius`,
  `LineWidth`, `ControlSize` or `IconSize`. Any other value takes no scale. A bare
  number in a field declared with a kind of length takes that kind, so
  `T(radius = 2)` scales as a radius. A `FontRole` or a `TextRole` takes the font
  that it gives over its base font in `T`, so its cell follows the base too.
- `make_scaled_theme(theme::T, appearance)` makes a `ScaledT`,
  `get_theme_field_names(T)` answers the names of the fields, and
  `get_theme_type(theme)` answers `T`.
- A string before a field is the docstring of the field, as in a plain struct.
  `get_theme_field_texts(T)` holds them by name, so a type with no docstring of
  its own keeps them too; `find_theme_field_text(T, name)` answers one, and the
  appearance tab shows it.
- `get_<name>_style(theme, field)`, such as `get_json_style`, gives the style of
  the field: a cell that reads `theme`, scaled or not, with no edge, or the plain
  default value when `theme` is `nothing` ([`make_style_field`](@ref)). The macro
  exports it.

A projection holds its styles and no theme. A builder fills them with
`get_<name>_style`, from the scaled theme of its appearance or from a theme as it
is.

# Example

    @theme struct JsonTheme
        "The font that the texts of this theme follow."
        font::StyleFont     = StyleFont("Ubuntu Mono", 20)
        "The text of a key."
        key_text::TextRole  = TextRole(color_solarized_blue; weight = 700)
        "The indent of a nested value."
        indent::Spacing     = Spacing(16)
    end
    scaled = make_scaled_theme(JsonTheme(), Appearance(spacing_scale = 1.5))
    scaled.indent                      # 24
    scaled.key_text.font               # StyleFont("Ubuntu Mono", 20; weight = 700)
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
    types = Any[]
    texts = Pair{Symbol,String}[]
    text = nothing
    for line in definition.args[3].args
        line isa LineNumberNode && continue
        line isa String && (text = String(strip(line)); continue)
        declaration = line isa Expr && line.head === :(=) ? line.args[1] : line
        (declaration isa Expr && declaration.head === :(::) && declaration.args[1] isa Symbol) ||
            throw(ArgumentError("@theme: each field is `name::Type = default`, " *
                                "with a string before it as its docstring, got `$line`"))
        line isa Expr && line.head === :(=) ||
            throw(ArgumentError("@theme: the field `$(declaration.args[1])` needs a default"))
        declaration.args[1] in (:theme, :appearance) &&
            throw(ArgumentError("@theme: a field can not be named `$(declaration.args[1])`, " *
                                "the scaled theme holds its theme and its appearance under these names"))
        declaration.args[1] in (:selection, :mouse_target) &&
            throw(ArgumentError("@theme: a field can not be named `$(declaration.args[1])`, " *
                                "a document keeps its own `$(declaration.args[1])` under that name"))
        push!(fields, declaration.args[1])
        push!(types, declaration.args[2])
        text === nothing || push!(texts, declaration.args[1] => text)
        text = nothing
    end
    scaled_name = Symbol("Scaled", name)
    style_name = _get_style_function_name(name)
    style_doc = """
        $style_name(theme, field) -> style

    The style of the field `field` of `$name`: a cell that reads `theme`, scaled or
    not, with no edge, or the plain default value when `theme` is `nothing`. A
    builder gives it to a projection.
    """
    theme = gensym(:theme)
    appearance = gensym(:appearance)
    cells = [:($Cell($Computation(() -> $scale_theme_value(
                 $convert_theme_value($type, $theme.$f), $theme, $appearance))))
             for (f, type) in zip(fields, types)]
    scaled_fields = [:($f::$Cell) for f in fields]
    document = Expr(:macrocall, GlobalRef(DocumentModule, Symbol("@document")),
                    __source__, definition)
    esc(quote
        $document
        struct $scaled_name <: $ScaledTheme
            theme::$name
            appearance::$Appearance
            $(scaled_fields...)
        end
        Base.getproperty(scaled::$scaled_name, field::Symbol) =
            field === :theme || field === :appearance ? getfield(scaled, field) :
                                                        getfield(scaled, field)[]
        $StyleModule.make_scaled_theme($theme::$name, $appearance::$Appearance) =
            $scaled_name($theme, $appearance, $(cells...))
        $StyleModule.get_theme_field_names(::Type{$name}) = $(Tuple(fields))
        $StyleModule.get_theme_field_texts(::Type{$name}) = $(NamedTuple(texts))
        $StyleModule.get_theme_type(::$name) = $name
        $(Expr(:macrocall, GlobalRef(Core, Symbol("@doc")), __source__, style_doc,
               :($style_name(theme, field::Symbol) =
                     $StyleModule.make_style_field($name, theme; name = field))))
        export $style_name
        $name
    end)
end
