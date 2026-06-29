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
import ..ProjectionModule: var"@projection"
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24, font_ubuntu_monospace_italic_24
import ..ColorModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_green, color_solarized_magenta, color_solarized_cyan, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, EmptyReferencePath, append_reference, annotate_reference_types
import ..PrinterContextModule: PrinterContext, child_context, with_property, get_property
import ..SyntaxToTextModule: SyntaxToText
import ..TextToStringModule: TextToString
import ..SequentialProjectionModule: SequentialProjection
import ..RecursiveProjectionModule: RecursiveProjection

export NothingToSyntaxLeaf, BoolToSyntaxLeaf, NumberToSyntaxLeaf,
       StringToSyntaxLeaf, SymbolToSyntaxLeaf, CharToSyntaxLeaf,
       ObjectNodeToSyntaxNode, ObjectToSyntax, print_object, CellToSyntax,
       search_references, search_objects

# ── NothingToSyntaxLeaf ──────────────────────────────────────────────────────

@projection struct NothingToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)
    include_selection::Bool = false
end

function projection_print(p::NothingToSyntaxLeaf, recursion, ::Nothing, ctx)
    leaf = SyntaxLeaf(TextString("nothing", p.style))
    SimpleIoMap(p, nothing, leaf)
end

# ── BoolToSyntaxLeaf ─────────────────────────────────────────────────────────

@projection struct BoolToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
    include_selection::Bool = false
end

function projection_print(p::BoolToSyntaxLeaf, recursion, b::Bool, ctx)
    leaf = SyntaxLeaf(TextString(b ? "true" : "false", p.style))
    SimpleIoMap(p, b, leaf)
end

# ── NumberToSyntaxLeaf ───────────────────────────────────────────────────────

@projection struct NumberToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)
    include_selection::Bool = false
end

function projection_print(p::NumberToSyntaxLeaf, recursion, n::Number, ctx)
    leaf = SyntaxLeaf(TextString(string(n), p.style))
    SimpleIoMap(p, n, leaf)
end

# ── StringToSyntaxLeaf ───────────────────────────────────────────────────────

@projection struct StringToSyntaxLeaf
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
    value::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)
    include_selection::Bool = false
end

function projection_print(p::StringToSyntaxLeaf, recursion, s::AbstractString, ctx)
    leaf = SyntaxLeaf(
        TextString(s, p.value);
        open=TextString("\"", p.quote_style),
        close=TextString("\"", p.quote_style))
    SimpleIoMap(p, s, leaf)
end

# ── SymbolToSyntaxLeaf ───────────────────────────────────────────────────────

@projection struct SymbolToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_blue)
    include_selection::Bool = false
end

function projection_print(p::SymbolToSyntaxLeaf, recursion, s::Symbol, ctx)
    leaf = SyntaxLeaf(TextString(string(s), p.style))
    SimpleIoMap(p, s, leaf)
end

# ── CharToSyntaxLeaf ─────────────────────────────────────────────────────────

@projection struct CharToSyntaxLeaf
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_yellow)
    value::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)
    include_selection::Bool = false
end

function projection_print(p::CharToSyntaxLeaf, recursion, c::Char, ctx)
    leaf = SyntaxLeaf(
        TextString(string(c), p.value);
        open=TextString("'", p.quote_style),
        close=TextString("'", p.quote_style))
    SimpleIoMap(p, c, leaf)
end

# ── CellToSyntax ─────────────────────────────────────────────────────────────
# Unwraps a Cell and projects its contents transparently.

@projection struct CellToSyntax
    cycle::StyleText = StyleText(font_ubuntu_monospace_italic_24, color_solarized_gray)
end

function projection_print(p::CellToSyntax, recursion, cell::Cell, ctx)
    visited = get_property(ctx, :objects_seen, nothing)
    if visited !== nothing && haskey(visited, cell)
        cycle_leaf = SyntaxLeaf(TextString("⟨cycle: Cell⟩", p.cycle))
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

@projection struct ObjectNodeToSyntaxNode
    type_name::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_blue)
    field_name::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)
    undef::StyleText = StyleText(font_ubuntu_monospace_italic_24, color_solarized_gray)
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
        projection_printer_recurse(recursion, getfield(obj, fn),
                         child_context(ctx, FieldReference(string(fn)))).output :
        SyntaxLeaf(TextString("<undefined>", p.undef))
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

    # Collections (CellVector, raw arrays, tuples) render as a braced element
    # list with NO type-name leaf: the wrapper carries no selection and no
    # structural meaning, so it would only be noise. Elements keep their
    # ElementReference so the references stay valid. Tuples must go here too —
    # `fieldnames` of a Tuple type yields integer indices, not Symbols, so the
    # struct branch below cannot reflect over them (e.g. an RGBA color stored
    # as NTuple{4,UInt8}).
    if obj isa CellVector || obj isa AbstractArray || obj isa Tuple
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
        Nothing        => NothingToSyntaxLeaf(style=StyleText(font_ubuntu_monospace_regular_24, nothing_color), include_selection=include_selection),
        Bool           => BoolToSyntaxLeaf(style=StyleText(font_ubuntu_monospace_regular_24, bool_color), include_selection=include_selection),
        Number         => NumberToSyntaxLeaf(style=StyleText(font_ubuntu_monospace_regular_24, number_color), include_selection=include_selection),
        AbstractString => StringToSyntaxLeaf(value=StyleText(font_ubuntu_monospace_regular_24, string_color), include_selection=include_selection),
        Symbol         => SymbolToSyntaxLeaf(style=StyleText(font_ubuntu_monospace_regular_24, symbol_color), include_selection=include_selection),
        Char           => CharToSyntaxLeaf(value=StyleText(font_ubuntu_monospace_regular_24, char_color), include_selection=include_selection),
        Any            => ObjectNodeToSyntaxNode(type_name=StyleText(type_name_font, type_name_color),
                                                 field_name=StyleText(field_name_font, field_name_color),
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

# ── search_references / search_objects ─────────────────────────────────────────

_is_search_leaf(x) = x === nothing || x isa Number || x isa AbstractString ||
                     x isa Symbol || x isa Char

# A search query is either a predicate (called on each node) or a String / Regex.
# A String/Regex is turned into a predicate matching any *leaf* node whose textual
# form (the string / symbol / number / char rendered) contains the substring /
# matches the regex. Struct and collection nodes have no textual form, so they
# never match a String/Regex query — pass a predicate to match on type or shape.
_search_text(x::AbstractString) = x
_search_text(x::Symbol)         = string(x)
_search_text(x::Number)         = string(x)
_search_text(x::Char)           = string(x)
_search_text(::Any)             = nothing

_text_query(q::AbstractString) = x -> (t = _search_text(x); t !== nothing && occursin(q, t))
_text_query(q::Regex)          = x -> (t = _search_text(x); t !== nothing && occursin(q, t))

"""
    search_references(obj, predicate; include_selection=false, maxdepth=64) -> Vector{ReferencePath}
    search_references(obj, query::Union{AbstractString,Regex}; …)            -> Vector{ReferencePath}

Walk any object and return a `ReferencePath` for every node whose (Cell-unwrapped)
value satisfies `predicate`. Instead of a predicate you may pass a `String`
(substring match) or `Regex` — it matches any leaf node (string / symbol / number
/ char) whose textual form contains / matches the query, e.g.
`search_references(editor.document, "Alice")` or `search_references(doc, r"TODO|FIXME")`.
Cells are unwrapped transparently (no path step);
struct fields contribute a `FieldReference`, and array / `CellVector` elements an
`ElementReference` — so the returned paths resolve with `evaluate_reference` and
can be handed to `set_selection!` / `replace_selection!`.

The returned paths are **canonical at rest**: each navigation step is preceded by
a `TypeReference(typeof(node))` checkpoint (via [`annotate_reference_types`](@ref),
matching [`collect_references`](@ref)), so results are self-describing and carry
replay-validation checkpoints. `evaluate_reference` honours the checkpoints; pass a
result through `strip_reference_types` first if a consumer needs the plain
navigation-only path.

```julia
for ref in search_references(editor.document, v -> v isa JsonString && occursin("TODO", v.value))
    replace_selection!(editor.document, ref)
end
```

`include_selection` includes `selection` fields in the walk. Every distinct path
to a matching node is returned — a shared object reachable by several paths is a
different *location* (hence a different selection) each time, so all of them are
reported. Only paths that loop back through an object already on the current path
are dropped, which keeps cyclic graphs (e.g. a doubly-linked list's `prev`/`next`)
finite. `maxdepth` separately bounds recursion depth for structures that are never
the *same* object, e.g. an infinite lazy list whose nodes are generated fresh on
demand. See [`search_objects`](@ref) for the matching objects themselves (each once).
"""
function search_references(obj, predicate; include_selection::Bool=false, maxdepth::Int=64)
    results = ReferencePath[]
    _search_references!(results, _unwrap_cell(obj), predicate,
                        EmptyReferencePath(), IdDict{Any,Bool}(), include_selection, maxdepth)
    # Leave search results in canonical form: annotate each plain navigation path
    # with `TypeReference(typeof(node))` checkpoints against `obj`, matching
    # `collect_references`, so the references are self-describing and carry
    # replay-validation checkpoints (see annotate_reference_types).
    ReferencePath[annotate_reference_types(_unwrap_cell(obj), p) for p in results]
end

search_references(obj, query::Union{AbstractString,Regex}; kwargs...) =
    search_references(obj, _text_query(query); kwargs...)

function _search_references!(results, obj, predicate, path, seen, include_selection, depth)
    # Drop only paths that loop back through an object already on *this* path:
    # `seen` holds the current path's ancestors (copied per level), so distinct
    # paths to a shared object are all reported — they are different locations and
    # mean different selections — while a path returning to one of its own
    # ancestors is neither recorded nor descended (keeping cyclic graphs finite).
    if ismutable(obj)
        haskey(seen, obj) && return
        seen = copy(seen); seen[obj] = true
    end
    matched = try predicate(obj) catch; false end
    matched && push!(results, path)
    depth <= 0 && return
    _is_search_leaf(obj) && return
    if obj isa CellVector
        for i in 1:length(obj)
            _search_references!(results, _unwrap_cell(obj[i]), predicate,
                            append_reference(path, ElementReference(i)), seen, include_selection, depth - 1)
        end
    elseif obj isa AbstractArray
        for i in 1:length(obj)
            _search_references!(results, _unwrap_cell(obj[i]), predicate,
                            append_reference(path, ElementReference(i)), seen, include_selection, depth - 1)
        end
    else
        fnames = try fieldnames(typeof(obj)) catch; () end
        for fn in fnames
            (fn == :ref || (fn == :selection && !include_selection)) && continue
            isdefined(obj, fn) || continue
            _search_references!(results, _unwrap_cell(getfield(obj, fn)), predicate,
                            append_reference(path, FieldReference(string(fn))), seen, include_selection, depth - 1)
        end
    end
end

"""
    search_objects(obj, predicate; include_selection=false, maxdepth=64) -> Vector{Any}
    search_objects(obj, query::Union{AbstractString,Regex}; …)           -> Vector{Any}

Walk any object and return every (Cell-unwrapped) node that satisfies `predicate`,
**each object at most once** even when it is shared / reachable by several paths.
As with [`search_references`](@ref), a `String` (substring) or `Regex` may be passed
instead of a predicate to match leaf nodes by their textual form.
This is the object-valued counterpart to [`search_references`](@ref): use it when
you want the matching values themselves rather than where they live.

```julia
nums = search_objects(editor.document, v -> v isa JsonNumber)
```

`include_selection` includes `selection` fields in the walk. A single global
visited set makes the walk visit each object once, so shared subtrees / DAGs are
not re-walked and cyclic graphs terminate. `maxdepth` separately bounds recursion
depth for structures that are never the *same* object, e.g. an infinite lazy list
whose nodes are generated fresh on demand.
"""
function search_objects(obj, predicate; include_selection::Bool=false, maxdepth::Int=64)
    results = Any[]
    _search_objects!(results, _unwrap_cell(obj), predicate,
                     IdDict{Any,Bool}(), include_selection, maxdepth)
    results
end

search_objects(obj, query::Union{AbstractString,Regex}; kwargs...) =
    search_objects(obj, _text_query(query); kwargs...)

function _search_objects!(results, obj, predicate, seen, include_selection, depth)
    # Global visit-once: `seen` is shared across the whole walk, so each object is
    # processed (and therefore reported) a single time regardless of how many
    # paths reach it; this also makes shared subtrees / DAGs / cycles safe.
    haskey(seen, obj) && return
    seen[obj] = true
    (try predicate(obj) catch; false end) && push!(results, obj)
    depth <= 0 && return
    _is_search_leaf(obj) && return
    if obj isa CellVector
        for i in 1:length(obj)
            _search_objects!(results, _unwrap_cell(obj[i]), predicate, seen, include_selection, depth - 1)
        end
    elseif obj isa AbstractArray
        for i in 1:length(obj)
            _search_objects!(results, _unwrap_cell(obj[i]), predicate, seen, include_selection, depth - 1)
        end
    else
        fnames = try fieldnames(typeof(obj)) catch; () end
        for fn in fnames
            (fn == :ref || (fn == :selection && !include_selection)) && continue
            isdefined(obj, fn) || continue
            _search_objects!(results, _unwrap_cell(getfield(obj, fn)), predicate, seen, include_selection, depth - 1)
        end
    end
end

end # module
