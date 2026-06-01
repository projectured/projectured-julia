"""
    ObjectToSyntaxModule

Object → SyntaxDocument projection. Reflects any Julia value into a nested
syntax tree using runtime type information. Structs produce a SyntaxNode
whose first child is the type-name leaf and whose remaining children are
per-field SyntaxNodes, each holding a field-name leaf and the recursively
projected field value. Primitive values (Nothing, Bool, Number,
AbstractString, Symbol, Char) produce SyntaxLeaf terminals.
"""
module ObjectToSyntaxModule

import ..ReactiveModule: Cell
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24, font_ubuntu_monospace_italic_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, EmptyReferencePath, append_reference
import ..ProjectionContextModule: ProjectionContext, child_context
import ..SyntaxToTextModule: SyntaxToText
import ..TextToStringModule: TextToString
import ..SequentialProjectionModule: SequentialProjection
import ..RecursiveProjectionModule: RecursiveProjection

export NothingToSyntaxLeaf, BoolToSyntaxLeaf, NumberToSyntaxLeaf,
       StringToSyntaxLeaf, SymbolToSyntaxLeaf, CharToSyntaxLeaf,
       ObjectNodeToSyntaxNode, ObjectToSyntax, print_object, CellToSyntax

# ── NothingToSyntaxLeaf ──────────────────────────────────────────────────────

struct NothingToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
    include_selection::Bool
end
NothingToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta, include_selection=false) =
    NothingToSyntaxLeaf(font, color, include_selection)

function projection_print(p::NothingToSyntaxLeaf, ::Nothing, recursion, ctx)
    leaf = SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString("nothing", p.font, p.color))
    SimpleIoMap(p, nothing, leaf)
end

# ── BoolToSyntaxLeaf ─────────────────────────────────────────────────────────

struct BoolToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
    include_selection::Bool
end
BoolToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_yellow, include_selection=false) =
    BoolToSyntaxLeaf(font, color, include_selection)

function projection_print(p::BoolToSyntaxLeaf, b::Bool, recursion, ctx)
    leaf = SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString(b ? "true" : "false", p.font, p.color))
    SimpleIoMap(p, b, leaf)
end

# ── NumberToSyntaxLeaf ───────────────────────────────────────────────────────

struct NumberToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
    include_selection::Bool
end
NumberToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta, include_selection=false) =
    NumberToSyntaxLeaf(font, color, include_selection)

function projection_print(p::NumberToSyntaxLeaf, n::Number, recursion, ctx)
    leaf = SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString(string(n), p.font, p.color))
    SimpleIoMap(p, n, leaf)
end

# ── StringToSyntaxLeaf ───────────────────────────────────────────────────────

struct StringToSyntaxLeaf <: Projection
    quote_font::StyleFont
    quote_color::StyleColor
    value_font::StyleFont
    value_color::StyleColor
    include_selection::Bool
end
StringToSyntaxLeaf(; quote_font=font_ubuntu_monospace_regular_24, quote_color=color_solarized_yellow,
                     value_font=font_ubuntu_monospace_regular_24, value_color=color_solarized_green,
                     include_selection=false) =
    StringToSyntaxLeaf(quote_font, quote_color, value_font, value_color, include_selection)

function projection_print(p::StringToSyntaxLeaf, s::AbstractString, recursion, ctx)
    leaf = SyntaxLeaf(
        TextString("\"", p.quote_font, p.quote_color),
        TextString("\"", p.quote_font, p.quote_color),
        TextString(s, p.value_font, p.value_color))
    SimpleIoMap(p, s, leaf)
end

# ── SymbolToSyntaxLeaf ───────────────────────────────────────────────────────

struct SymbolToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
    include_selection::Bool
end
SymbolToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_blue, include_selection=false) =
    SymbolToSyntaxLeaf(font, color, include_selection)

function projection_print(p::SymbolToSyntaxLeaf, s::Symbol, recursion, ctx)
    leaf = SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default), TextString(string(s), p.font, p.color))
    SimpleIoMap(p, s, leaf)
end

# ── CharToSyntaxLeaf ─────────────────────────────────────────────────────────

struct CharToSyntaxLeaf <: Projection
    quote_font::StyleFont
    quote_color::StyleColor
    value_font::StyleFont
    value_color::StyleColor
    include_selection::Bool
end
CharToSyntaxLeaf(; quote_font=font_ubuntu_monospace_regular_24, quote_color=color_solarized_yellow,
                   value_font=font_ubuntu_monospace_regular_24, value_color=color_solarized_green,
                   include_selection=false) =
    CharToSyntaxLeaf(quote_font, quote_color, value_font, value_color, include_selection)

function projection_print(p::CharToSyntaxLeaf, c::Char, recursion, ctx)
    leaf = SyntaxLeaf(
        TextString("'", p.quote_font, p.quote_color),
        TextString("'", p.quote_font, p.quote_color),
        TextString(string(c), p.value_font, p.value_color))
    SimpleIoMap(p, c, leaf)
end

# ── CellToSyntax ─────────────────────────────────────────────────────────────
# Unwraps a Cell and projects its contents transparently.

struct CellToSyntax <: Projection end

function projection_print(::CellToSyntax, cell::Cell, recursion, ctx)
    unwrapped = cell[]
    projection_print(recursion, unwrapped, recursion, ctx)
end

# ── ObjectNodeToSyntaxNode ───────────────────────────────────────────────────
#
# Maps any Julia value to a nested SyntaxNode:
#
#   SyntaxNode("", "", " ", indentation=1, [
#     SyntaxLeaf(TypeName),                        ← type-name leaf
#     SyntaxNode("", "", " ", indentation=1, [     ← one per field
#       SyntaxLeaf(field_name),
#       <projected field value>,
#     ]),
#     ...
#   ])
#
# Objects with no fields collapse to the type-name leaf alone.
# Undefined mutable-struct fields render as an "<undefined>" leaf.

struct ObjectNodeToSyntaxNode <: Projection
    type_name_font::StyleFont
    type_name_color::StyleColor
    field_name_font::StyleFont
    field_name_color::StyleColor
    undef_font::StyleFont
    undef_color::StyleColor
    include_selection::Bool
    open_delimiter::String
    close_delimiter::String
end
ObjectNodeToSyntaxNode(; type_name_font=font_ubuntu_monospace_bold_24, type_name_color=color_solarized_blue,
                         field_name_font=font_ubuntu_monospace_regular_24,    field_name_color=color_solarized_green,
                         undef_font=font_ubuntu_monospace_italic_24,   undef_color=color_solarized_gray,
                         include_selection=false,
                         open_delimiter="", close_delimiter="") =
    ObjectNodeToSyntaxNode(type_name_font, type_name_color,
                           field_name_font, field_name_color,
                           undef_font, undef_color, include_selection,
                           open_delimiter, close_delimiter)

function projection_print(p::ObjectNodeToSyntaxNode, obj, recursion, ctx)
    T = typeof(obj)

    # Special handling for Arrays: project elements directly
    if obj isa AbstractArray
        type_leaf = SyntaxLeaf(
            TextString("", p.type_name_font, color_default),
            TextString("", p.type_name_font, color_default),
            TextString(string(nameof(T)), p.type_name_font, p.type_name_color))
        if isempty(obj)
            return SimpleIoMap(p, obj, type_leaf)
        end
        element_nodes = SyntaxDocument[
            projection_print(recursion, obj[i], recursion,
                           child_context(ctx, ElementReference(i))).output
            for i in eachindex(obj)
        ]
        node = SyntaxNode(p.open_delimiter, p.close_delimiter, " ",
            SyntaxDocument[type_leaf; element_nodes];
            indentation=1)
        return SimpleIoMap(p, obj, node)
    end

    # Regular struct handling
    fnames = try fieldnames(T) catch; () end
    # Filter out technical fields like "ref" from Arrays, and selection if include_selection=false
    fnames = filter(fn -> fn != :ref && (fn != :selection || p.include_selection), fnames)
    type_leaf = SyntaxLeaf(
        TextString("", p.type_name_font, color_default),
        TextString("", p.type_name_font, color_default),
        TextString(string(nameof(T)), p.type_name_font, p.type_name_color))
    if isempty(fnames)
        return SimpleIoMap(p, obj, type_leaf)
    end
    field_nodes = SyntaxDocument[
        SyntaxNode("", "", " ",
            SyntaxDocument[
                SyntaxLeaf(TextString("", p.field_name_font, color_default), TextString("", p.field_name_font, color_default),
                           TextString(string(fn), p.field_name_font, p.field_name_color)),
                isdefined(obj, fn) ?
                    projection_print(recursion, getfield(obj, fn), recursion,
                                     child_context(ctx, FieldReference(string(fn)))).output :
                    SyntaxLeaf(TextString("", p.undef_font, color_default), TextString("", p.undef_font, color_default),
                               TextString("<undefined>", p.undef_font, p.undef_color))
            ];
            indentation=0)
        for fn in fnames
    ]
    node = SyntaxNode(p.open_delimiter, p.close_delimiter, " ",
        SyntaxDocument[type_leaf; field_nodes];
        indentation=1)
    SimpleIoMap(p, obj, node)
end

# ── Compound convenience constructor ────────────────────────────────────────

function ObjectToSyntax(; type_name_font=font_ubuntu_monospace_bold_24, type_name_color=color_solarized_blue,
                          field_name_font=font_ubuntu_monospace_regular_24,    field_name_color=color_solarized_green,
                          nothing_color=color_solarized_magenta,
                          bool_color=color_solarized_yellow,
                          number_color=color_solarized_magenta,
                          string_color=color_solarized_green,
                          symbol_color=color_solarized_blue,
                          char_color=color_solarized_green,
                          include_selection=false,
                          open_delimiter="", close_delimiter="")
    TypeDispatchingProjection(
        Cell           => CellToSyntax(),
        Nothing        => NothingToSyntaxLeaf(color=nothing_color, include_selection=include_selection),
        Bool           => BoolToSyntaxLeaf(color=bool_color, include_selection=include_selection),
        Number         => NumberToSyntaxLeaf(color=number_color, include_selection=include_selection),
        AbstractString => StringToSyntaxLeaf(value_color=string_color, include_selection=include_selection),
        Symbol         => SymbolToSyntaxLeaf(color=symbol_color, include_selection=include_selection),
        Char           => CharToSyntaxLeaf(value_color=char_color, include_selection=include_selection),
        Any            => ObjectNodeToSyntaxNode(type_name_font=type_name_font,
                                                 type_name_color=type_name_color,
                                                 field_name_font=field_name_font,
                                                 field_name_color=field_name_color,
                                                 include_selection=include_selection,
                                                 open_delimiter=open_delimiter,
                                                 close_delimiter=close_delimiter),
    )
end

# ── print_object ─────────────────────────────────────────────────────────────
"""
    print_object(obj; include_selection=false, open_delimiter="", close_delimiter="") -> String

Convenience function that chains ObjectToSyntax, SyntaxToText, and TextToString
projections to produce a string representation of any Julia object.

# Arguments
- `obj`: Any Julia value to convert to a string representation
- `include_selection`: If false, selection fields are not recursed into (default: false)
- `open_delimiter`: Opening delimiter for struct/array nodes (default: "")
- `close_delimiter`: Closing delimiter for struct/array nodes (default: "")

# Examples
```julia
print_object(42)              # "42"
print_object([1, 2, 3])      # Vector with elements
print_object(Point(3, 4))    # Struct with fields
print_object(obj, open_delimiter="{", close_delimiter="}")  # Add delimiters
```

# Notes
- Cells are unwrapped transparently
- Arrays are projected by iterating over elements (not as structs)
- The `ref` field is filtered out from struct field names
"""
function print_object(obj; include_selection=false, open_delimiter="", close_delimiter="")
    seq = SequentialProjection(
        RecursiveProjection(ObjectToSyntax(include_selection=include_selection, open_delimiter=open_delimiter, close_delimiter=close_delimiter)),
        RecursiveProjection(SyntaxToText()),
        RecursiveProjection(TextToString())
    )
    iomap = projection_print(seq, obj, seq, ProjectionContext())
    return iomap.output[]
end

end # module
