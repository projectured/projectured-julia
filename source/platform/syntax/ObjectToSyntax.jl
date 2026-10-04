# Fragment of `SyntaxModule`.
#
# Object → SyntaxDocument projection. Reflects any Julia value into a nested
# syntax tree using runtime type information. Structs produce a SyntaxNode
# whose first child is the type-name leaf and whose remaining children are
# per-field SyntaxNodes, each holding a field-name leaf and the recursively
# projected field value. Primitive values (Nothing, Bool, Number,
# AbstractString, Symbol, Char) produce SyntaxLeaf terminals.
# ── NothingToSyntaxLeaf ──────────────────────────────────────────────────────

@projection UntrackedCell struct NothingToSyntaxLeaf
    style::StyleText
    include_selection::Bool
end

NothingToSyntaxLeaf(; theme = nothing, style = get_syntax_style(theme, :nothing_text),
       include_selection::Bool = false) = NothingToSyntaxLeaf(style, include_selection)

function print_document(p::NothingToSyntaxLeaf, recursion, ::Nothing, ctx)
    leaf = SyntaxLeaf(TextString("nothing", p.style))
    SimpleIoMap(p, nothing, leaf)
end

# ── BoolToSyntaxLeaf ─────────────────────────────────────────────────────────

@projection UntrackedCell struct BoolToSyntaxLeaf
    style::StyleText
    include_selection::Bool
end

BoolToSyntaxLeaf(; theme = nothing, style = get_syntax_style(theme, :reflected_bool_text),
       include_selection::Bool = false) = BoolToSyntaxLeaf(style, include_selection)

function print_document(p::BoolToSyntaxLeaf, recursion, b::Bool, ctx)
    leaf = SyntaxLeaf(TextString(b ? "true" : "false", p.style))
    SimpleIoMap(p, b, leaf)
end

# ── NumberToSyntaxLeaf ───────────────────────────────────────────────────────

@projection UntrackedCell struct NumberToSyntaxLeaf
    style::StyleText
    include_selection::Bool
end

NumberToSyntaxLeaf(; theme = nothing, style = get_syntax_style(theme, :number_text),
       include_selection::Bool = false) = NumberToSyntaxLeaf(style, include_selection)

function print_document(p::NumberToSyntaxLeaf, recursion, n::Number, ctx)
    leaf = SyntaxLeaf(TextString(string(n), p.style))
    SimpleIoMap(p, n, leaf)
end

# ── StringToSyntaxLeaf ───────────────────────────────────────────────────────

@projection UntrackedCell struct StringToSyntaxLeaf
    quote_style::StyleText
    value::StyleText
    include_selection::Bool
end

function StringToSyntaxLeaf(; theme = nothing,
                quote_style = get_syntax_style(theme, :quote_text),
                value = get_syntax_style(theme, :string_text),
                include_selection::Bool = false)
    StringToSyntaxLeaf(quote_style, value, include_selection)
end

function print_document(p::StringToSyntaxLeaf, recursion, s::AbstractString, ctx)
    leaf = SyntaxLeaf(
        TextString(s, p.value);
        open=TextString("\"", p.quote_style),
        close=TextString("\"", p.quote_style))
    SimpleIoMap(p, s, leaf)
end

# ── SymbolToSyntaxLeaf ───────────────────────────────────────────────────────

@projection UntrackedCell struct SymbolToSyntaxLeaf
    style::StyleText
    include_selection::Bool
end

SymbolToSyntaxLeaf(; theme = nothing, style = get_syntax_style(theme, :symbol_text),
       include_selection::Bool = false) = SymbolToSyntaxLeaf(style, include_selection)

function print_document(p::SymbolToSyntaxLeaf, recursion, s::Symbol, ctx)
    leaf = SyntaxLeaf(TextString(string(s), p.style))
    SimpleIoMap(p, s, leaf)
end

# ── CharToSyntaxLeaf ─────────────────────────────────────────────────────────

@projection UntrackedCell struct CharToSyntaxLeaf
    quote_style::StyleText
    value::StyleText
    include_selection::Bool
end

function CharToSyntaxLeaf(; theme = nothing,
                quote_style = get_syntax_style(theme, :quote_text),
                value = get_syntax_style(theme, :string_text),
                include_selection::Bool = false)
    CharToSyntaxLeaf(quote_style, value, include_selection)
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

@projection UntrackedCell struct CellToSyntax
    cycle::StyleText
end

CellToSyntax(; theme = nothing, cycle = get_syntax_style(theme, :note_text)) =
    CellToSyntax(cycle)

function print_document(p::CellToSyntax, recursion, cell::Cell, ctx)
    visited = get_property(ctx, :objects_seen, nothing)
    if visited !== nothing && haskey(visited, cell)
        cycle_leaf = SyntaxLeaf(TextString("⟨cycle: Cell⟩", p.cycle))
        return SimpleIoMap(p, cell, cycle_leaf)
    end
    new_visited = visited === nothing ? IdDict{Any,Bool}() : copy(visited)
    new_visited[cell] = true
    ctx = with_property(ctx, :objects_seen, new_visited)
    # Reactive: re-project when the cell's value is swapped (its `objectid` changes —
    # true for a scalar edit like `now = 5.0`, a reassigned collection, or a new child
    # document). Reading `cell[]` inside the reconcile is what makes the output track
    # the cell, so a `sync_document!`/`setproperty!` write repaints without rebuilding
    # the whole projection.
    inner = make_reconciled_child_iomap_cell(() -> cell[],
                                              v -> print_child(recursion, v, ctx))
    SimpleIoMap(p, cell, Cell(@computation inner[].output))
end

# ── ObjectNodeToSyntaxNode ───────────────────────────────────────────────────
#
# Maps any Julia value to a nested SyntaxNode:
#
#   SyntaxNode([
#     SyntaxLeaf(TypeName),                        ← type-name leaf
#     SyntaxNode([                                 ← one per field
#       SyntaxLeaf(field_name),
#       <projected field value>,
#     ]; sep = " ", indentation = 1),
#     ...
#   ]; sep = " ", indentation = 1)
#
# Objects with no fields collapse to the type-name leaf alone.
# Undefined mutable-struct fields render as an "<undefined>" leaf.

@projection UntrackedCell struct ObjectNodeToSyntaxNode
    type_name::StyleText
    field_name::StyleText
    undef::StyleText
    delimiter::StyleText
    include_selection::Bool
    open_delimiter::String
    close_delimiter::String
    newlines::Bool
    filter::Any
end

function ObjectNodeToSyntaxNode(; theme = nothing,
                                type_name = get_syntax_style(theme, :type_name_text),
                                field_name = get_syntax_style(theme, :field_name_text),
                                undef = get_syntax_style(theme, :note_text),
                                delimiter = get_syntax_style(theme, :object_delimiter_text),
                                include_selection::Bool = false, open_delimiter::AbstractString = "",
                                close_delimiter::AbstractString = "", newlines::Bool = true,
                                filter = nothing)
    ObjectNodeToSyntaxNode(type_name, field_name, undef, delimiter, include_selection, String(open_delimiter),
                           String(close_delimiter), newlines, filter)
end

# A delimiter or a separator of a reflected object, in the delimiter text of the
# theme, so its size follows the theme and the indentation that takes its font
# follows too. An empty one stays empty, so the node has no span.
_object_delimiter(p::ObjectNodeToSyntaxNode, text::AbstractString) =
    isempty(text) ? text : TextString(text, p.delimiter)

# Unwrap a Cell for predicate/filter testing; pass non-cells through.
_unwrap_cell(x) = x isa Cell ? x[] : x

# Build the type-name leaf for `T`.
_type_leaf(p::ObjectNodeToSyntaxNode, name::AbstractString) =
    SyntaxLeaf(TextString(name, p.type_name))

# A field's static name leaf plus its child IoMap — projecting the field's *cell*
# (reactive via CellToSyntax for an `@document` field) or its raw value. A `nothing`
# iomap marks an undefined field. Built once; the value is read reactively below.
_field_entry(p::ObjectNodeToSyntaxNode, recursion, obj, ctx, fn::Symbol) =
    (SyntaxLeaf(TextString(string(fn), p.field_name)),
     isdefined(obj, fn) ?
        print_child(recursion, getfield(obj, fn),
                    make_child_context(ctx, FieldReferenceStep(string(fn)))) :
        nothing)

# The (reactive) syntax output of a field entry — read inside the output cell so a
# field change repaints; the `<undefined>` leaf for an absent field.
_field_value(p::ObjectNodeToSyntaxNode, fim) =
    fim === nothing ? SyntaxLeaf(TextString("<undefined>", p.undef)) : fim.output

# The visible elements of a collection (after `filter`), read inside the reconcile so
# appends/deletes repaint. Element order = collection order. A slot another task
# has reserved and not yet filled is skipped: a vector a running task appends to
# is read while it grows.
_visible_elements(p::ObjectNodeToSyntaxNode, obj) = begin
    els = Any[obj[i] for i in 1:length(obj) if _is_slot_assigned(obj, i)]
    p.filter === nothing ? els : Any[x for x in els if p.filter(_unwrap_cell(x))]
end

# Only an array has a slot with nothing in it yet; every other collection
# answers each index it has.
_is_slot_assigned(obj::Array, i::Integer) = isassigned(obj, i)
_is_slot_assigned(obj, i::Integer) = true

# PAR-NO-NESTED-CELL exception: this projection prints any value, and a cell that
# `CellToSyntax` does not take is a value here too. The input of an IO map is a
# reactive field, which does not take a cell of another kind, so that cell goes
# into a `Cell` of its own and the IO map reads back the cell.
_get_object_input(obj::AbstractCell) = obj isa Cell ? obj : Cell(obj)
_get_object_input(obj) = obj

function print_document(p::ObjectNodeToSyntaxNode, recursion, obj, ctx)
    T = typeof(obj)

    # Cycle detection for mutable ancestors. Self-referential graphs (e.g.
    # the gallery's introspection tab, which embeds the running document
    # inside one of its own tabs) always close the loop through a mutable
    # value — Julia immutables can't reference themselves directly. Tracking
    # only mutables avoids false positives for value-equal immutable leaves
    # (fonts, colors, TextStrings) that legitimately appear many times in
    # the same tree.
    if ismutable(obj)
        visited = get_property(ctx, :objects_seen, nothing)
        if visited !== nothing && haskey(visited, obj)
            return SimpleIoMap(p, _get_object_input(obj), _type_leaf(p, "⟨cycle: $(nameof(T))⟩"))
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
        # Reconcile the element IoMaps by identity: unchanged elements reuse theirs, a
        # new/moved slot rebuilds. The output cell re-derives the braced list when the
        # element set changes (append/pop/reassign).
        elem_ims = make_reconciled_child_iomaps_cell(
            () -> _visible_elements(p, obj),
            (i, x) -> print_child(recursion, x, make_child_context(ctx, ElementReferenceStep(i))))
        output = Cell(@computation(SyntaxNode(SyntaxDocument[im.output for im in elem_ims[]];
            open = _object_delimiter(p, p.open_delimiter), close = _object_delimiter(p, p.close_delimiter),
            sep = _object_delimiter(p, " "), indentation = ind)))
        return SimpleIoMap(p, _get_object_input(obj), output)
    end

    # Struct: render as `TypeName { field … }` — the type name labels the
    # brace block (outside it), and the fields are indented one level inside.
    fnames = try fieldnames(T) catch; () end
    fnames = filter(fn -> fn != :ref && fn != :mouse_target && (fn != :selection || p.include_selection), fnames)
    if p.filter !== nothing
        fnames = filter(fn -> isdefined(obj, fn) && p.filter(_unwrap_cell(getfield(obj, fn))), fnames)
    end
    type_leaf = _type_leaf(p, string(nameof(T)))
    # No fields → just the type name, no empty braces.
    isempty(fnames) && return SimpleIoMap(p, _get_object_input(obj), type_leaf)
    # Field structure (which fields) is stable; build each field's entry once, then
    # assemble the node in a computed cell that reads each field's (reactive) value.
    entries = [_field_entry(p, recursion, obj, ctx, fn) for fn in fnames]
    output = Cell(@computation begin
        field_nodes = SyntaxDocument[
            SyntaxNode(SyntaxDocument[nl, _field_value(p, fim)]; sep = _object_delimiter(p, " "))
            for (nl, fim) in entries]
        fields_block = SyntaxNode(field_nodes; open = _object_delimiter(p, p.open_delimiter),
            close = _object_delimiter(p, p.close_delimiter), sep = _object_delimiter(p, " "),
            indentation = ind)
        SyntaxNode(SyntaxDocument[type_leaf, fields_block]; sep = _object_delimiter(p, " "))
    end)
    SimpleIoMap(p, _get_object_input(obj), output)
end

# ── Compound convenience constructor ────────────────────────────────────────

# `theme`, a `SyntaxTheme` scaled or not, styles the leaves. A font or a color
# that a keyword names replaces the one of the theme in its style, which then
# keeps that value.
function ObjectToSyntax(; theme = nothing,
                          type_name_font = nothing, type_name_color = nothing,
                          field_name_font = nothing, field_name_color = nothing,
                          nothing_color = nothing,
                          bool_color = nothing,
                          number_color = nothing,
                          string_color = nothing,
                          symbol_color = nothing,
                          char_color = nothing,
                          include_selection=false,
                          open_delimiter="", close_delimiter="",
                          newlines::Bool=true, filter=nothing)
    style(name, font, color) = (font === nothing && color === nothing) ?
        get_syntax_style(theme, name) :
        _replace_style(unwrap_cell(get_syntax_style(theme, name)), font, color)
    TypeDispatchingProjection(
        Cell           => CellToSyntax(; theme),
        Nothing        => NothingToSyntaxLeaf(style=style(:nothing_text, nothing, nothing_color), include_selection=include_selection),
        Bool           => BoolToSyntaxLeaf(style=style(:reflected_bool_text, nothing, bool_color), include_selection=include_selection),
        Number         => NumberToSyntaxLeaf(style=style(:number_text, nothing, number_color), include_selection=include_selection),
        AbstractString => StringToSyntaxLeaf(; theme, value=style(:string_text, nothing, string_color), include_selection=include_selection),
        Symbol         => SymbolToSyntaxLeaf(style=style(:symbol_text, nothing, symbol_color), include_selection=include_selection),
        Char           => CharToSyntaxLeaf(; theme, value=style(:string_text, nothing, char_color), include_selection=include_selection),
        Any            => ObjectNodeToSyntaxNode(; theme,
                                                 type_name=style(:type_name_text, type_name_font, type_name_color),
                                                 field_name=style(:field_name_text, field_name_font, field_name_color),
                                                 include_selection=include_selection,
                                                 open_delimiter=open_delimiter,
                                                 close_delimiter=close_delimiter,
                                                 newlines=newlines,
                                                 filter = filter),
    )
end

# `style` with `font` and `color` in place of its own, where they are not `nothing`.
_replace_style(style::StyleText, font, color) =
    StyleText(something(font, style.font), something(color, style.color))

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
    out = iomap.output
    # The sibling separator (" ") leaves a trailing space before each newline;
    # strip per-line trailing whitespace so the rendering is clean.
    newlines ? join((rstrip(l) for l in split(out, '\n')), '\n') : out
end
