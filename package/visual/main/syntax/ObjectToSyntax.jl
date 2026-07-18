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

import ..CellModule: Cell
import ..DocumentModule: is_element_collection
import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20, font_ubuntu_monospace_italic_20
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText, DStyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ElementReferenceStep, FieldReferenceStep
import ..PrinterContextModule: PrinterContext, make_child_context, with_property, get_property
import ..SyntaxToTextModule: SyntaxToText
import ..TextToStringModule: TextToString
import ..ChainingProjectionModule: ChainingProjection
import ..RecursiveProjectionModule: RecursiveProjection

export NothingToSyntaxLeaf, BoolToSyntaxLeaf, NumberToSyntaxLeaf,
       StringToSyntaxLeaf, SymbolToSyntaxLeaf, CharToSyntaxLeaf,
       ObjectNodeToSyntaxNode, ObjectToSyntax, print_object, CellToSyntax

# ── NothingToSyntaxLeaf ──────────────────────────────────────────────────────

@projection struct NothingToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    include_selection::Bool = false
end

function print_document(p::NothingToSyntaxLeaf, recursion, ::Nothing, ctx)
    leaf = SyntaxLeaf(TextString("nothing", p.style))
    SimpleIoMap(p, nothing, leaf)
end

# ── BoolToSyntaxLeaf ─────────────────────────────────────────────────────────

@projection struct BoolToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    include_selection::Bool = false
end

function print_document(p::BoolToSyntaxLeaf, recursion, b::Bool, ctx)
    leaf = SyntaxLeaf(TextString(b ? "true" : "false", p.style))
    SimpleIoMap(p, b, leaf)
end

# ── NumberToSyntaxLeaf ───────────────────────────────────────────────────────

@projection struct NumberToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
    include_selection::Bool = false
end

function print_document(p::NumberToSyntaxLeaf, recursion, n::Number, ctx)
    leaf = SyntaxLeaf(TextString(string(n), p.style))
    SimpleIoMap(p, n, leaf)
end

# ── StringToSyntaxLeaf ───────────────────────────────────────────────────────

@projection struct StringToSyntaxLeaf
    quote_style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    value::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    include_selection::Bool = false
end

function print_document(p::StringToSyntaxLeaf, recursion, s::AbstractString, ctx)
    leaf = SyntaxLeaf(
        TextString(s, p.value);
        open=TextString("\"", p.quote_style),
        close=TextString("\"", p.quote_style))
    SimpleIoMap(p, s, leaf)
end

# ── SymbolToSyntaxLeaf ───────────────────────────────────────────────────────

@projection struct SymbolToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    include_selection::Bool = false
end

function print_document(p::SymbolToSyntaxLeaf, recursion, s::Symbol, ctx)
    leaf = SyntaxLeaf(TextString(string(s), p.style))
    SimpleIoMap(p, s, leaf)
end

# ── CharToSyntaxLeaf ─────────────────────────────────────────────────────────

@projection struct CharToSyntaxLeaf
    quote_style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
    value::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    include_selection::Bool = false
end

function print_document(p::CharToSyntaxLeaf, recursion, c::Char, ctx)
    leaf = SyntaxLeaf(
        TextString(string(c), p.value);
        open=TextString("'", p.quote_style),
        close=TextString("'", p.quote_style))
    SimpleIoMap(p, c, leaf)
end

# ── CellToSyntax ─────────────────────────────────────────────────────────────
# Unwraps a Cell and projects its contents transparently.

@projection struct CellToSyntax
    cycle::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_italic_20, color_solarized_gray)
end

function print_document(p::CellToSyntax, recursion, cell::Cell, ctx)
    visited = get_property(ctx, :objects_seen, nothing)
    if visited !== nothing && haskey(visited, cell)
        cycle_leaf = SyntaxLeaf(TextString("⟨cycle: Cell⟩", p.cycle))
        return SimpleIoMap(p, cell, cycle_leaf)
    end
    new_visited = visited === nothing ? IdDict{Any,Bool}() : copy(visited)
    new_visited[cell] = true
    ctx = with_property(ctx, :objects_seen, new_visited)
    unwrapped = cell[]
    print_child(recursion, unwrapped, ctx)
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

@projection struct ObjectNodeToSyntaxNode
    type_name::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    field_name::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    undef::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_italic_20, color_solarized_gray)
    include_selection::Bool = false
    open_delimiter::String = ""
    close_delimiter::String = ""
    newlines::Bool = true
    filter::Any = nothing
end

# Unwrap a Cell for predicate/filter testing; pass non-cells through.
_unwrap_cell(x) = x isa Cell ? x[] : x

# Build the type-name leaf for `T`.
_type_leaf(p::ObjectNodeToSyntaxNode, name::AbstractString) =
    SyntaxLeaf(TextString(name, p.type_name))

# Build one `field_name <value>` node (inline: name leaf + projected value).
function _field_node(p::ObjectNodeToSyntaxNode, recursion, obj, ctx, fn::Symbol)
    name_leaf = SyntaxLeaf(TextString(string(fn), p.field_name))
    value_node = isdefined(obj, fn) ?
        print_child(recursion, getfield(obj, fn),
                         make_child_context(ctx, FieldReferenceStep(string(fn)))).output :
        SyntaxLeaf(TextString("<undefined>", p.undef))
    SyntaxNode("", "", " ", SyntaxDocument[name_leaf, value_node]; indentation=0)
end

function print_document(p::ObjectNodeToSyntaxNode, recursion, obj, ctx)
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

    # Collections (CellVector, raw arrays, tuples) render as a braced element
    # list with NO type-name leaf: the wrapper carries no selection and no
    # structural meaning, so it would only be noise. Elements keep their
    # ElementReferenceStep so the references stay valid. Tuples must go here too —
    # `fieldnames` of a Tuple type yields integer indices, not Symbols, so the
    # struct branch below cannot reflect over them (e.g. an RGBA color stored
    # as NTuple{4,UInt8}).
    if is_element_collection(obj) || obj isa AbstractArray || obj isa Tuple
        idxs = p.filter === nothing ? collect(1:length(obj)) :
               [i for i in 1:length(obj) if p.filter(_unwrap_cell(obj[i]))]
        element_nodes = SyntaxDocument[
            print_child(recursion, obj[i],
                           make_child_context(ctx, ElementReferenceStep(i))).output
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

function ObjectToSyntax(; type_name_font=font_ubuntu_monospace_bold_20, type_name_color=color_solarized_blue,
                          field_name_font=font_ubuntu_monospace_regular_20,    field_name_color=color_solarized_green,
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
        Nothing        => NothingToSyntaxLeaf(style=StyleText(font_ubuntu_monospace_regular_20, nothing_color), include_selection=include_selection),
        Bool           => BoolToSyntaxLeaf(style=StyleText(font_ubuntu_monospace_regular_20, bool_color), include_selection=include_selection),
        Number         => NumberToSyntaxLeaf(style=StyleText(font_ubuntu_monospace_regular_20, number_color), include_selection=include_selection),
        AbstractString => StringToSyntaxLeaf(value=StyleText(font_ubuntu_monospace_regular_20, string_color), include_selection=include_selection),
        Symbol         => SymbolToSyntaxLeaf(style=StyleText(font_ubuntu_monospace_regular_20, symbol_color), include_selection=include_selection),
        Char           => CharToSyntaxLeaf(value=StyleText(font_ubuntu_monospace_regular_20, char_color), include_selection=include_selection),
        # A predicate is data, not a reactive thunk. The `filter` cell field would
        # read a bare `Function` as its thunk and *call* it (with no args) on every
        # read, so hold it AS the cell's value via the `as_value` constructor.
        Any            => ObjectNodeToSyntaxNode(type_name=StyleText(type_name_font, type_name_color),
                                                 field_name=StyleText(field_name_font, field_name_color),
                                                 include_selection=include_selection,
                                                 open_delimiter=open_delimiter,
                                                 close_delimiter=close_delimiter,
                                                 newlines=newlines,
                                                 filter = filter === nothing ? nothing : Cell(filter; as_value=true)),
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
    seq = ChainingProjection(
        RecursiveProjection(ObjectToSyntax(include_selection=include_selection,
                                           open_delimiter=open_delimiter, close_delimiter=close_delimiter,
                                           newlines=newlines, filter=filter)),
        RecursiveProjection(SyntaxToText(indent_size=indent)),
        RecursiveProjection(TextToString())
    )
    iomap = print_document(seq, seq, obj, PrinterContext())
    out = iomap.output[]
    # The sibling separator (" ") leaves a trailing space before each newline;
    # strip per-line trailing whitespace so the rendering is clean.
    newlines ? join((rstrip(l) for l in split(out, '\n')), '\n') : out
end


end # module
