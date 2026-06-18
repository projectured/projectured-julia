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
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24, font_ubuntu_monospace_italic_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, EmptyReferencePath, append_reference
import ..PrinterContextModule: PrinterContext, child_context, with_property, get_property
import ..SyntaxToTextModule: SyntaxToText
import ..TextToStringModule: TextToString
import ..SequentialProjectionModule: SequentialProjection
import ..RecursiveProjectionModule: RecursiveProjection

export NothingToSyntaxLeaf, BoolToSyntaxLeaf, NumberToSyntaxLeaf,
       StringToSyntaxLeaf, SymbolToSyntaxLeaf, CharToSyntaxLeaf,
       ObjectNodeToSyntaxNode, ObjectToSyntax, print_object, CellToSyntax,
       search_object

# ── NothingToSyntaxLeaf ──────────────────────────────────────────────────────

struct NothingToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
    include_selection::Bool
end
NothingToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta, include_selection=false) =
    NothingToSyntaxLeaf(font, color, include_selection)

function projection_print(p::NothingToSyntaxLeaf, recursion, ::Nothing, ctx)
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

function projection_print(p::BoolToSyntaxLeaf, recursion, b::Bool, ctx)
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

function projection_print(p::NumberToSyntaxLeaf, recursion, n::Number, ctx)
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

function projection_print(p::StringToSyntaxLeaf, recursion, s::AbstractString, ctx)
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

function projection_print(p::SymbolToSyntaxLeaf, recursion, s::Symbol, ctx)
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

function projection_print(p::CharToSyntaxLeaf, recursion, c::Char, ctx)
    leaf = SyntaxLeaf(
        TextString("'", p.quote_font, p.quote_color),
        TextString("'", p.quote_font, p.quote_color),
        TextString(string(c), p.value_font, p.value_color))
    SimpleIoMap(p, c, leaf)
end

# ── CellToSyntax ─────────────────────────────────────────────────────────────
# Unwraps a Cell and projects its contents transparently.

struct CellToSyntax <: Projection
    cycle_font::StyleFont
    cycle_color::StyleColor
end
CellToSyntax(; cycle_font=font_ubuntu_monospace_italic_24, cycle_color=color_solarized_gray) =
    CellToSyntax(cycle_font, cycle_color)

function projection_print(p::CellToSyntax, recursion, cell::Cell, ctx)
    visited = get_property(ctx, :objects_seen, nothing)
    if visited !== nothing && haskey(visited, cell)
        cycle_leaf = SyntaxLeaf(
            TextString("", p.cycle_font, color_default),
            TextString("", p.cycle_font, color_default),
            TextString("⟨cycle: Cell⟩", p.cycle_font, p.cycle_color))
        return SimpleIoMap(p, cell, cycle_leaf)
    end
    new_visited = visited === nothing ? IdDict{Any,Bool}() : copy(visited)
    new_visited[cell] = true
    ctx = with_property(ctx, :objects_seen, new_visited)
    unwrapped = cell[]
    projection_printer_recurse(recursion, unwrapped, ctx)
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
    newlines::Bool
    filter::Any
end
ObjectNodeToSyntaxNode(; type_name_font=font_ubuntu_monospace_bold_24, type_name_color=color_solarized_blue,
                         field_name_font=font_ubuntu_monospace_regular_24,    field_name_color=color_solarized_green,
                         undef_font=font_ubuntu_monospace_italic_24,   undef_color=color_solarized_gray,
                         include_selection=false,
                         open_delimiter="", close_delimiter="",
                         newlines::Bool=true, filter=nothing) =
    ObjectNodeToSyntaxNode(type_name_font, type_name_color,
                           field_name_font, field_name_color,
                           undef_font, undef_color, include_selection,
                           open_delimiter, close_delimiter,
                           newlines, filter)

# Unwrap a Cell for predicate/filter testing; pass non-cells through.
_unwrap_cell(x) = x isa Cell ? x[] : x

# Build the type-name leaf for `T`.
_type_leaf(p::ObjectNodeToSyntaxNode, name::AbstractString) =
    SyntaxLeaf(TextString("", p.type_name_font, color_default),
               TextString("", p.type_name_font, color_default),
               TextString(name, p.type_name_font, p.type_name_color))

# Build one `field_name <value>` node (inline: name leaf + projected value).
function _field_node(p::ObjectNodeToSyntaxNode, recursion, obj, ctx, fn::Symbol)
    name_leaf = SyntaxLeaf(
        TextString("", p.field_name_font, color_default),
        TextString("", p.field_name_font, color_default),
        TextString(string(fn), p.field_name_font, p.field_name_color))
    value_node = isdefined(obj, fn) ?
        projection_printer_recurse(recursion, getfield(obj, fn),
                         child_context(ctx, FieldReference(string(fn)))).output :
        SyntaxLeaf(TextString("", p.undef_font, color_default),
                   TextString("", p.undef_font, color_default),
                   TextString("<undefined>", p.undef_font, p.undef_color))
    SyntaxNode("", "", " ", SyntaxDocument[name_leaf, value_node]; indentation=0)
end

function projection_print(p::ObjectNodeToSyntaxNode, recursion, obj, ctx)
    T = typeof(obj)

    # Cycle detection for mutable ancestors. Self-referential graphs (e.g.
    # the workbench rendered inside one of its own pages) always close the
    # loop through a mutable value — Julia immutables can't reference
    # themselves directly. Tracking only mutables avoids false positives
    # for value-equal immutable leaves (fonts, colors, TextStrings) that
    # legitimately appear many times in the same tree.
    if ismutable(obj)
        visited = get_property(ctx, :objects_seen, nothing)
        if visited !== nothing && haskey(visited, obj)
            return SimpleIoMap(p, obj, _type_leaf(p, "⟨cycle: $(nameof(T))⟩"))
        end
        new_visited = visited === nothing ? IdDict{Any,Bool}() : copy(visited)
        new_visited[obj] = true
        ctx = with_property(ctx, :objects_seen, new_visited)
    end

    ind = p.newlines ? 1 : 0

    # Collections (CellVector and raw arrays) render as a braced element list
    # with NO type-name leaf: the CellVector/Array wrapper carries no selection
    # and no structural meaning, so it would only be noise. Elements keep their
    # ElementReference so the references stay valid.
    if obj isa CellVector || obj isa AbstractArray
        idxs = p.filter === nothing ? collect(1:length(obj)) :
               [i for i in 1:length(obj) if p.filter(_unwrap_cell(obj[i]))]
        element_nodes = SyntaxDocument[
            projection_printer_recurse(recursion, obj[i],
                           child_context(ctx, ElementReference(i))).output
            for i in idxs
        ]
        node = SyntaxNode(p.open_delimiter, p.close_delimiter, " ",
            element_nodes; indentation = ind)
        return SimpleIoMap(p, obj, node)
    end

    # Struct: render as `TypeName { field … }` — the type name labels the
    # brace block (outside it), and the fields are indented one level inside.
    fnames = try fieldnames(T) catch; () end
    fnames = filter(fn -> fn != :ref && (fn != :selection || p.include_selection), fnames)
    if p.filter !== nothing
        fnames = filter(fn -> isdefined(obj, fn) && p.filter(_unwrap_cell(getfield(obj, fn))), fnames)
    end
    type_leaf = _type_leaf(p, string(nameof(T)))
    # No fields → just the type name, no empty braces.
    isempty(fnames) && return SimpleIoMap(p, obj, type_leaf)
    field_nodes = SyntaxDocument[_field_node(p, recursion, obj, ctx, fn) for fn in fnames]
    fields_block = SyntaxNode(p.open_delimiter, p.close_delimiter, " ",
        field_nodes; indentation = ind)
    node = SyntaxNode("", "", " ",
        SyntaxDocument[type_leaf, fields_block]; indentation = 0)
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
                          open_delimiter="", close_delimiter="",
                          newlines::Bool=true, filter=nothing)
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
                                                 close_delimiter=close_delimiter,
                                                 newlines=newlines, filter=filter),
    )
end

# ── print_object ─────────────────────────────────────────────────────────────
"""
    print_object(obj; include_selection=false, open_delimiter="", close_delimiter="",
                 newlines=true, indent=2, filter=nothing) -> String

Convenience function that chains ObjectToSyntax, SyntaxToText, and TextToString
projections to produce a string representation of any Julia object.

# Arguments
- `obj`: Any Julia value to convert to a string representation
- `include_selection`: If false, selection fields are not recursed into (default: false)
- `open_delimiter`: Opening delimiter for struct/array nodes (default: "")
- `close_delimiter`: Closing delimiter for struct/array nodes (default: "")
- `newlines`: If true, each node prints on its own line; if false, the whole
  result is rendered on a single line (default: true)
- `indent`: Spaces per nesting level; `0` means no indentation (default: 2).
  Pairs with `newlines` — `newlines=true, indent=2` is the readable tree,
  `newlines=false` is a compact one-liner.
- `filter`: Optional predicate `value -> Bool`; when given, only struct fields and
  array/collection elements whose (Cell-unwrapped) value satisfies it are shown.

# Examples
```julia
print_object(42)              # "42"
print_object([1, 2, 3])      # Vector with elements
print_object(Point(3, 4))    # Struct with fields
print_object(obj; newlines=false)              # one-liner
print_object(obj; indent=4)                    # wider indentation
print_object(obj; filter=v -> !(v isa Bool))   # hide boolean fields
```

# Notes
- Cells are unwrapped transparently
- Arrays are projected by iterating over elements (not as structs)
- The `ref` field is filtered out from struct field names
"""
function print_object(obj; include_selection=false, open_delimiter="{", close_delimiter="}",
                      newlines::Bool=true, indent::Int=2, filter=nothing)
    seq = SequentialProjection(
        RecursiveProjection(ObjectToSyntax(include_selection=include_selection,
                                           open_delimiter=open_delimiter, close_delimiter=close_delimiter,
                                           newlines=newlines, filter=filter)),
        RecursiveProjection(SyntaxToText(indent_size=indent)),
        RecursiveProjection(TextToString())
    )
    iomap = projection_print(seq, seq, obj, PrinterContext())
    out = iomap.output[]
    # The sibling separator (" ") leaves a trailing space before each newline;
    # strip per-line trailing whitespace so the rendering is clean.
    newlines ? join((rstrip(l) for l in split(out, '\n')), '\n') : out
end

# ── search_object ────────────────────────────────────────────────────────────

_is_search_leaf(x) = x === nothing || x isa Number || x isa AbstractString ||
                     x isa Symbol || x isa Char

"""
    search_object(obj, predicate; include_selection=false, maxdepth=64) -> Vector{ReferencePath}

Walk any object and return a `ReferencePath` for every node whose (Cell-unwrapped)
value satisfies `predicate`. Cells are unwrapped transparently (no path step);
struct fields contribute a `FieldReference`, and array / `CellVector` elements an
`ElementReference` — so the returned paths resolve with `evaluate_reference` and
can be handed to `set_selection!` / `replace_selection!`.

```julia
for ref in search_object(editor.document, v -> v isa JsonString && occursin("TODO", v.value))
    replace_selection!(editor.document, ref)
end
```

`include_selection` includes `selection` fields in the walk; `maxdepth` bounds
recursion. Mutable nodes are cycle-guarded so self-referential graphs terminate.
"""
function search_object(obj, predicate; include_selection::Bool=false, maxdepth::Int=64)
    results = ReferencePath[]
    _search_object!(results, _unwrap_cell(obj), predicate,
                    EmptyReferencePath(), IdDict{Any,Bool}(), include_selection, maxdepth)
    results
end

function _search_object!(results, obj, predicate, path, seen, include_selection, depth)
    matched = try predicate(obj) catch; false end
    matched && push!(results, path)
    depth <= 0 && return
    _is_search_leaf(obj) && return
    if ismutable(obj)
        haskey(seen, obj) && return
        seen = copy(seen); seen[obj] = true
    end
    if obj isa CellVector
        for i in 1:length(obj)
            _search_object!(results, _unwrap_cell(obj[i]), predicate,
                            append_reference(path, ElementReference(i)), seen, include_selection, depth - 1)
        end
    elseif obj isa AbstractArray
        for i in 1:length(obj)
            _search_object!(results, _unwrap_cell(obj[i]), predicate,
                            append_reference(path, ElementReference(i)), seen, include_selection, depth - 1)
        end
    else
        fnames = try fieldnames(typeof(obj)) catch; () end
        for fn in fnames
            (fn == :ref || (fn == :selection && !include_selection)) && continue
            isdefined(obj, fn) || continue
            _search_object!(results, _unwrap_cell(getfield(obj, fn)), predicate,
                            append_reference(path, FieldReference(string(fn))), seen, include_selection, depth - 1)
        end
    end
end

end # module
