# Fragment of `SyntaxModule`.
#
# PrimitiveDocument → SyntaxLeaf projection. Converts `PrimitiveBool`,
# `PrimitiveNumber`, and `PrimitiveString` into `SyntaxLeaf` nodes
# with appropriate delimiters and colors, and a `PrimitiveInsertion` into the
# type-in that a person types a value into.
# ── PrimitiveBoolToSyntaxLeaf ────────────────────────────────────────────────
#
# Each leaf maps its paths (the selection, the mouse target) forward into cells of
# its own, so the primitive holds a path of its own domain. A part that the leaf
# printed, such as a quote of a string, is named by the leaf's own introduced step,
# and the forward map answers the path of that part in the leaf.

@projection UntrackedCell struct PrimitiveBoolToSyntaxLeaf
    style::StyleText
end

PrimitiveBoolToSyntaxLeaf(; theme = nothing,
                          style = get_syntax_style(theme, :bool_text)) =
    PrimitiveBoolToSyntaxLeaf(style)

function map_reference_forward(p::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.output))
        proj(^(p), inner) => inner
        ::PrimitiveBool.value{s:e} => @reference ::SyntaxLeaf.value::TextString{s:e}::Position
    end
end

function map_reference_backward(p::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.input))
        ::SyntaxLeaf.value{s:e} => @reference ::PrimitiveBool.value::Bool{s:e}::Position
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function print_document(p::PrimitiveBoolToSyntaxLeaf, recursion, b::PrimitiveBool, ctx)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(b, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    iomap = SimpleIoMap(p, b, SyntaxLeaf(
        TextString(() -> string(b.value), p.style);
        paths...))
    iomap_cell[] = iomap
    iomap
end

function read_intent(p::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : make_path_operation(op, path)
end

# A key that would edit the text of a Bool does nothing: a Bool switches by the
# keys of `@gestures PrimitiveBool` (`PrimitiveToText.jl`).
read_intent(::PrimitiveBoolToSyntaxLeaf, iomap::SimpleIoMap, ::ReplaceRangeOperation) = nothing

# ── PrimitiveNumberToSyntaxLeaf ──────────────────────────────────────────────

# With `allows_type_in`, a key whose text the number can not show, such as `-` or
# `12.`, replaces the number with a type-in of that text
# (`make_number_edit_operation`). Only a dispatch that also prints a
# `PrimitiveInsertion` turns it on, as `PrimitiveToSyntax` does.
@projection UntrackedCell struct PrimitiveNumberToSyntaxLeaf
    style::StyleText
    allows_type_in::Bool
end

PrimitiveNumberToSyntaxLeaf(; theme = nothing,
                            style = get_syntax_style(theme, :number_text),
                            allows_type_in::Bool = false) =
    PrimitiveNumberToSyntaxLeaf(style, allows_type_in)

function map_reference_forward(p::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.output))
        proj(^(p), inner) => inner
        ::PrimitiveNumber.value{s:e} => @reference ::SyntaxLeaf.value::TextString{s:e}::Position
    end
end

function map_reference_backward(p::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.input))
        ::SyntaxLeaf.value{s:e} => @reference ::PrimitiveNumber.value::Number{s:e}::Position
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function print_document(p::PrimitiveNumberToSyntaxLeaf, recursion, n::PrimitiveNumber, ctx)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(n, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    iomap = SimpleIoMap(p, n, SyntaxLeaf(
        TextString(() -> get_primitive_text(n), p.style);
        paths...))
    iomap_cell[] = iomap
    iomap
end

function read_intent(p::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : make_path_operation(op, path)
end

# A key in the number is a range replace that the default reader maps back to
# `value{s:e}`; with `allows_type_in`, a text that the number can not show makes
# a type-in instead.
function read_intent(p::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceRangeOperation)
    mapped = invoke(read_intent, Tuple{Projection,Any,Any}, p, iomap, op)
    p.allows_type_in && mapped isa ReplaceRangeOperation ? make_number_edit_operation(iomap.input, mapped) : mapped
end

# ── PrimitiveStringToSyntaxLeaf ──────────────────────────────────────────────

@projection UntrackedCell struct PrimitiveStringToSyntaxLeaf
    quote_style::StyleText
    value::StyleText
end

function PrimitiveStringToSyntaxLeaf(; theme = nothing,
                                     quote_style = get_syntax_style(theme, :quote_text),
                                     value = get_syntax_style(theme, :string_text))
    PrimitiveStringToSyntaxLeaf(quote_style, value)
end

function map_reference_forward(p::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.output))
        proj(^(p), inner) => inner
        ::PrimitiveString.value{s:e} => @reference ::SyntaxLeaf.value::TextString{s:e}::Position
    end
end

function map_reference_backward(p::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.input))
        ::SyntaxLeaf.value{s:e} => @reference ::PrimitiveString.value::String{s:e}::Position
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function print_document(p::PrimitiveStringToSyntaxLeaf, recursion, s::PrimitiveString, ctx)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(s, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    iomap = SimpleIoMap(p, s, SyntaxLeaf(
        TextString(() -> something(s.value, ""), p.value);
        open=TextString("\"", p.quote_style),
        close=TextString("\"", p.quote_style),
        paths...))
    iomap_cell[] = iomap
    iomap
end

function read_intent(p::PrimitiveStringToSyntaxLeaf, iomap::SimpleIoMap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : make_path_operation(op, path)
end

# String character-editing (insert / Backspace / Delete) is reified once as
# `@gestures PrimitiveString` in `PrimitiveToText.jl` (a document-level concern in
# the PrimitiveString's own `value[range]` vocabulary); this leaf reaches it
# through the generic `read_gesture` fallback, so no bespoke event reader lives
# here — only the structural `ReplaceSelectionOperation` mapping above.

# ── PrimitiveInsertionToSyntaxLeaf ───────────────────────────────────────────

"""
    PrimitiveInsertionToSyntaxLeaf(; theme = nothing)

The type-in of a `PrimitiveInsertion`: a source insertion whose text is green
when it parses as one of the allowed types of the insertion and red when it does
not. A key whose text one of them shows exactly replaces the insertion with it at
once; Enter replaces it with the first that the text parses as, so `1.50` becomes
`1.5`; Escape puts the first allowed type with no value. An empty type-in shows
its placeholder.
"""
PrimitiveInsertionToSyntaxLeaf(; theme = nothing) =
    InsertionToSyntaxLeaf(_commit_primitive_text; completion = _get_primitive_completion,
                          commit_at_key = _commit_exact_primitive_text,
                          cancel = ins -> make_empty_primitive_document(first(ins.allowed_types)),
                          placeholder = get_type_in_placeholder, theme)

function _commit_primitive_text(ins, text)
    document = find_primitive_document(ins.allowed_types, text)
    document === nothing ? nothing : with_value_caret(document, length(get_primitive_text(document)))
end

function _commit_exact_primitive_text(ins, text, caret)
    document = find_exact_primitive_document(ins.allowed_types, text)
    document === nothing ? nothing : with_value_caret(document, caret)
end

function _get_primitive_completion(ins)
    text = something(ins.value, "")
    isempty(text) && return (state = :empty, hint = "", extension = "")
    found = find_primitive_document(ins.allowed_types, text) !== nothing
    (state = found ? :unambiguous : :invalid, hint = "", extension = "")
end

# ── PrimitiveToSyntax (composite) ────────────────────────────────────────────


"""
    PrimitiveToSyntax(; theme = nothing, bool_kw = (), number_kw = (), string_kw = ())

Composite projection that converts all `PrimitiveDocument` types to
`SyntaxLeaf` nodes. Wrap the result in `RecursiveProjection` at the call
site if recursive child dispatch is needed. `theme`, a `SyntaxTheme` or a scaled
one, styles the leaves; with none, the leaves have the default styles.
"""
function PrimitiveToSyntax(; theme = nothing, bool_kw=(), number_kw=(), string_kw=())
    TypeDispatchingProjection(
        PrimitiveBool      => PrimitiveBoolToSyntaxLeaf(; theme, bool_kw...),
        PrimitiveNumber    => PrimitiveNumberToSyntaxLeaf(; theme, allows_type_in = true, number_kw...),
        PrimitiveString    => PrimitiveStringToSyntaxLeaf(; theme, string_kw...),
        PrimitiveInsertion => PrimitiveInsertionToSyntaxLeaf(; theme),
    )
end
