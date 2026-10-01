# Fragment of `SyntaxModule`.
#
# PrimitiveDocument → SyntaxLeaf projection. Converts `PrimitiveBool`,
# `PrimitiveNumber`, and `PrimitiveString` into `SyntaxLeaf` nodes
# with appropriate delimiters and colors.
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
                          style = _get_syntax_style(scale_theme(theme), StyleText, :bool_text)) =
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

# ── PrimitiveNumberToSyntaxLeaf ──────────────────────────────────────────────

@projection UntrackedCell struct PrimitiveNumberToSyntaxLeaf
    style::StyleText
end

PrimitiveNumberToSyntaxLeaf(; theme = nothing,
                            style = _get_syntax_style(scale_theme(theme), StyleText, :number_text)) =
    PrimitiveNumberToSyntaxLeaf(style)

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
        TextString(() -> string(n.value), p.style);
        paths...))
    iomap_cell[] = iomap
    iomap
end

function read_intent(p::PrimitiveNumberToSyntaxLeaf, iomap::SimpleIoMap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : make_path_operation(op, path)
end

# ── PrimitiveStringToSyntaxLeaf ──────────────────────────────────────────────

@projection UntrackedCell struct PrimitiveStringToSyntaxLeaf
    quote_style::StyleText
    value::StyleText
end

function PrimitiveStringToSyntaxLeaf(; theme = nothing,
                                     quote_style = _get_syntax_style(scale_theme(theme), StyleText, :quote_text),
                                     value = _get_syntax_style(scale_theme(theme), StyleText, :string_text))
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

# ── PrimitiveToSyntax (composite) ────────────────────────────────────────────


"""
    PrimitiveToSyntax(; theme = nothing, bool_kw = (), number_kw = (), string_kw = ())

Composite projection that converts all `PrimitiveDocument` types to
`SyntaxLeaf` nodes. Wrap the result in `RecursiveProjection` at the call
site if recursive child dispatch is needed. `theme`, a `SyntaxTheme` or a scaled
one, styles the leaves; with none, the leaves have the default styles.
"""
function PrimitiveToSyntax(; theme = nothing, bool_kw=(), number_kw=(), string_kw=())
    theme = scale_theme(theme)
    TypeDispatchingProjection(
        PrimitiveBool   => PrimitiveBoolToSyntaxLeaf(; theme, bool_kw...),
        PrimitiveNumber => PrimitiveNumberToSyntaxLeaf(; theme, number_kw...),
        PrimitiveString => PrimitiveStringToSyntaxLeaf(; theme, string_kw...),
    )
end
