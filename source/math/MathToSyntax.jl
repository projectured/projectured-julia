# Fragment of `MathModule`.
#
# Math → SyntaxDocument projection: the **linear** form of a formula, one line of
# text. It is the save path (`print_natural_text` runs it) and the plain-text view;
# `MathToGraphics` draws the two-dimensional one.
#
# A construct that has no plain-text form prints its LaTeX-like name, so the line
# stays unambiguous and a future LaTeX reader has something to read:
# `\\sqrt{x}`, `\\sum_{k=0}^{n} body`, `x_{i}^{2}`, `\\bar{x}`.
#
# Colorized tokens:
# - Variables in blue
# - Operators (+, -, *, /) in cyan
# - Parentheses in gray
# - Assignment (=) in yellow
# - Symbols in violet, function names in green
# - Numbers in magenta (via PrimitiveNumberToSyntaxLeaf)
#
# The rules from `MathSymbolToSyntaxLeaf` on are `@projection_template`
# builders, so printing, reference mapping and the structural readers are
# generic. Each compound rule collapses an unmapped caret to a bounded flat
# offset (`_syntax_to_flat`), because a formula is full of
# projection-introduced chrome.
# ── MathInsertionToSyntaxLeaf ─────────────────────────────────────────────────

@projection struct MathInsertionToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

function print_document(p::MathInsertionToSyntaxLeaf, recursion, m::MathInsertion, ctx)
    output_selection =
        Cell(@computation map_reference_forward(p, nothing, m.selection))
    SimpleIoMap(p, m, SyntaxLeaf(TextString("⌷", p.style); selection=output_selection))
end

# ── MathVariableToSyntaxLeaf ──────────────────────────────────────────────────

@projection struct MathVariableToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
end

function map_reference_forward(::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::MathVariable.name{k} => @reference ::SyntaxLeaf.value::TextString{k}::Position
    end
end

function map_reference_backward(::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value{k} => @reference ::MathVariable.name::String{k}::Position
    end
end

function print_document(p::MathVariableToSyntaxLeaf, recursion, v::MathVariable, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(() -> v.name, p.style);
        selection=getfield(v, :selection)))
end

function read_intent(::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReference || return nothing
    h = path.head
    h isa FieldReferenceStep && h.name == "value" || return nothing
    return ReplaceSelectionOperation(ConcreteReference(FieldReferenceStep("name"), path.tail))
end

# ── MathBinaryOperationToSyntaxNode ───────────────────────────────────────────

@projection struct MathBinaryOperationToSyntaxNode
    op::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

# Selection mapping (School A). The output node's children are
# [left (index 1), operator leaf (index 2), right (index 3)]; the operator is
# projection-introduced. .left / .right delegate the tail through the stored
# child IO maps (child_iomaps = [left, right]) rather than re-walking math types.
function map_reference_forward(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::MathBinaryOperation.left.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
        ::MathBinaryOperation.right.rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[3].^(inner)
        end
    end
end

function map_reference_backward(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.leaf_path... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            if child_i == 1
                child = cims[1]
                translated = map_reference_backward(child.projection, child, leaf_path)
                translated === nothing && return nothing
                @reference ::MathBinaryOperation.left.^(translated)
            elseif child_i == 3
                child = cims[2]
                translated = map_reference_backward(child.projection, child, leaf_path)
                translated === nothing && return nothing
                @reference ::MathBinaryOperation.right.^(translated)
            else
                nothing
            end
        end
    end
end

function print_document(p::MathBinaryOperationToSyntaxNode, recursion, m::MathBinaryOperation, ctx)
    left_ctx  = make_child_context(ctx, m, @reference_step left)
    right_ctx = make_child_context(ctx, m, @reference_step right)
    left_iomap = Cell(@computation print_child(recursion, m.left, left_ctx))
    right_iomap = Cell(@computation print_child(recursion, m.right, right_ctx))

    op_leaf = SyntaxLeaf(TextString(() -> _operator_string(m.operator), p.op))

    sel = Cell(@computation begin
        path = m.selection
        path isa ConcreteReference || return nothing
        h = path.head
        if h isa FieldReferenceStep
            if h.name == "left"
                li = left_iomap[]
                child_sel = li.output.selection
                child_sel === nothing && return nothing
                return ConcreteReference(FieldReferenceStep("children"),
                           ConcreteReference(ElementReferenceStep(1), child_sel))
            elseif h.name == "right"
                ri = right_iomap[]
                child_sel = ri.output.selection
                child_sel === nothing && return nothing
                return ConcreteReference(FieldReferenceStep("children"),
                           ConcreteReference(ElementReferenceStep(3), child_sel))
            end
        elseif h isa ProjectionReferenceStep
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[left_iomap[].output, op_leaf, right_iomap[].output]);
        sep=TextString(" ", p.op.font, color_default),
        selection=sel)
    ChildrenIoMap(p, m, node, Cell(@computation [left_iomap[], right_iomap[]]))
end

function read_intent(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(
        make_introduced_reference(p, iomap.input, ConcreteReference(PositionReferenceStep(flat))))
end

# ── MathParenthesizedToSyntaxNode ─────────────────────────────────────────────

@projection struct MathParenthesizedToSyntaxNode
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

# Selection mapping (School A). The single content child is output index 1; the
# parentheses are projection-introduced. child_iomaps holds the one content IO map.
function map_reference_forward(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::MathParenthesized.content.rest... => begin
            child = iomap.child_iomaps
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
    end
end

function map_reference_backward(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.leaf_path... => begin
            s + 1 == 1 || return nothing
            child = iomap.child_iomaps
            translated = map_reference_backward(child.projection, child, leaf_path)
            translated === nothing && return nothing
            @reference ::MathParenthesized.content.^(translated)
        end
    end
end

function print_document(p::MathParenthesizedToSyntaxNode, recursion, m::MathParenthesized, ctx)
    content_ctx = make_child_context(ctx, m, @reference_step content)
    content_iomap = Cell(@computation print_child(recursion, m.content, content_ctx))

    sel = Cell(@computation begin
        path = m.selection
        path isa ConcreteReference || return nothing
        h = path.head
        if h isa FieldReferenceStep && h.name == "content"
            ci = content_iomap[]
            child_sel = ci.output.selection
            child_sel === nothing && return nothing
            return ConcreteReference(FieldReferenceStep("children"),
                       ConcreteReference(ElementReferenceStep(1), child_sel))
        elseif h isa ProjectionReferenceStep
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[content_iomap[].output]);
        open=TextString(() -> get_math_delimiter_strings(m.kind)[1], p.delim),
        close=TextString(() -> get_math_delimiter_strings(m.kind)[2], p.delim),
        selection=sel)
    ChildrenIoMap(p, m, node, content_iomap)
end

function read_intent(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(
        make_introduced_reference(p, iomap.input, ConcreteReference(PositionReferenceStep(flat))))
end

# ── MathAssignmentToSyntaxNode ────────────────────────────────────────────────

@projection struct MathAssignmentToSyntaxNode
    eq::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
end

# Selection mapping (School A). Output children are
# [target (index 1), '=' leaf (index 2), value (index 3)]; the '=' is
# projection-introduced. child_iomaps = [target, value].
function map_reference_forward(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::MathAssignment.target.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
        ::MathAssignment.value.rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[3].^(inner)
        end
    end
end

function map_reference_backward(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.leaf_path... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            if child_i == 1
                child = cims[1]
                translated = map_reference_backward(child.projection, child, leaf_path)
                translated === nothing && return nothing
                @reference ::MathAssignment.target.^(translated)
            elseif child_i == 3
                child = cims[2]
                translated = map_reference_backward(child.projection, child, leaf_path)
                translated === nothing && return nothing
                @reference ::MathAssignment.value.^(translated)
            else
                nothing
            end
        end
    end
end

function print_document(p::MathAssignmentToSyntaxNode, recursion, m::MathAssignment, ctx)
    target_ctx = make_child_context(ctx, m, @reference_step target)
    value_ctx  = make_child_context(ctx, m, @reference_step value)
    target_iomap = Cell(@computation print_child(recursion, m.target, target_ctx))
    value_iomap = Cell(@computation print_child(recursion, m.value, value_ctx))

    eq_leaf = SyntaxLeaf(TextString("=", p.eq))

    sel = Cell(@computation begin
        path = m.selection
        path isa ConcreteReference || return nothing
        h = path.head
        if h isa FieldReferenceStep
            if h.name == "target"
                ti = target_iomap[]
                child_sel = ti.output.selection
                child_sel === nothing && return nothing
                return ConcreteReference(FieldReferenceStep("children"),
                           ConcreteReference(ElementReferenceStep(1), child_sel))
            elseif h.name == "value"
                vi = value_iomap[]
                child_sel = vi.output.selection
                child_sel === nothing && return nothing
                return ConcreteReference(FieldReferenceStep("children"),
                           ConcreteReference(ElementReferenceStep(3), child_sel))
            end
        elseif h isa ProjectionReferenceStep
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[target_iomap[].output, eq_leaf, value_iomap[].output]);
        sep=TextString(" ", p.eq.font, color_default),
        selection=sel)
    ChildrenIoMap(p, m, node, Cell(@computation [target_iomap[], value_iomap[]]))
end

function read_intent(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(
        make_introduced_reference(p, iomap.input, ConcreteReference(PositionReferenceStep(flat))))
end

# ── Shared styles for the template rules ─────────────────────────────────────

const _VARIABLE = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
const _OPERATOR = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
const _CHROME   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
const _SYMBOL   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
const _NAME     = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
const _WORD     = StyleText(font_ubuntu_monospace_regular_20, color_default)

# An operand that is itself a sequence needs parentheses when it lands in a
# position where the line would otherwise regroup it: a fraction's numerator, a
# script's base, a function's argument.
_math_is_sequence(doc) =
    doc isa MathBinaryOperation || doc isa MathAssignment || doc isa MathRow ||
    doc isa MathFraction || doc isa MathUnaryOperation

# Append `marker` to `children`, in parentheses when `wrap` asks for them.
function _push_operand!(children, wrap::Bool, marker, style)
    if wrap
        push!(children, SyntaxLeaf(TextString("(", style)))
        push!(children, marker)
        push!(children, SyntaxLeaf(TextString(")", style)))
    else
        push!(children, marker)
    end
    children
end

# `_{…}` / `^{…}` around an optional script, limit or index.
function _push_braced!(children, prefix::AbstractString, marker, style)
    push!(children, SyntaxLeaf(TextString(prefix, style)))
    push!(children, marker)
    push!(children, SyntaxLeaf(TextString("}", style)))
    children
end

# ── MathSymbolToSyntaxLeaf ───────────────────────────────────────────────────
#
# The leaf renders the *glyph* of the name, not the name, so the text is not a
# pre-image of the `name` field. It is projection-introduced text, like an Fsm
# referent name.

@projection struct MathSymbolToSyntaxLeaf
    style::ImmutableCell{StyleText} = _SYMBOL
end

@projection_template MathSymbolToSyntaxLeaf MathSymbol (p, doc) ->
    SyntaxLeaf(TextString(() -> get_math_symbol_glyph(doc.name), p.style))

# ── MathTextToSyntaxLeaf ─────────────────────────────────────────────────────

@projection struct MathTextToSyntaxLeaf
    style::ImmutableCell{StyleText} = _WORD
end

@projection_template MathTextToSyntaxLeaf MathText (p, doc) ->
    SyntaxLeaf(bound(:content, String, TextString(() -> doc.content, p.style)))

# ── MathSpaceToSyntaxLeaf ────────────────────────────────────────────────────

@projection struct MathSpaceToSyntaxLeaf
    style::ImmutableCell{StyleText} = _CHROME
end

# `\\,`, `\\:`, `\\;` and `\\quad`, so that an explicit space and the gap between
# the elements of a row do not print alike.
const _MATH_SPACE_TEXTS = Dict{Symbol,String}(:thin => "\\,", :medium => "\\:", :thick => "\\;", :quad => "\\quad")

@projection_template MathSpaceToSyntaxLeaf MathSpace (p, doc) ->
    SyntaxLeaf(TextString(() -> get(_MATH_SPACE_TEXTS, doc.kind, "\\,"), p.style))

# ── MathRowToSyntaxNode ──────────────────────────────────────────────────────
#
# Juxtaposition prints as its elements with one space between them.

@projection struct MathRowToSyntaxNode
    style::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathRowToSyntaxNode MathRow (p, doc) ->
    SyntaxNode(collection(:elements); sep=TextString(" ", p.style))

# ── MathUnaryOperationToSyntaxNode ───────────────────────────────────────────

@projection struct MathUnaryOperationToSyntaxNode
    op::ImmutableCell{StyleText} = _OPERATOR
    chrome::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathUnaryOperationToSyntaxNode MathUnaryOperation (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[]
        text = SyntaxLeaf(TextString(() -> _operator_string(doc.operator), p.op))
        doc.postfix || push!(children, text)
        _push_operand!(children, _math_is_sequence(doc.operand), project(:operand), p.chrome)
        doc.postfix && push!(children, text)
        children
    end)

# ── MathFractionToSyntaxNode ─────────────────────────────────────────────────

@projection struct MathFractionToSyntaxNode
    op::ImmutableCell{StyleText} = _OPERATOR
    chrome::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathFractionToSyntaxNode MathFraction (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[]
        _push_operand!(children, _math_is_sequence(doc.numerator), project(:numerator), p.chrome)
        push!(children, SyntaxLeaf(TextString("/", p.op)))
        _push_operand!(children, _math_is_sequence(doc.denominator), project(:denominator), p.chrome)
        children
    end)

# ── MathScriptToSyntaxNode ───────────────────────────────────────────────────

@projection struct MathScriptToSyntaxNode
    chrome::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathScriptToSyntaxNode MathScript (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[]
        _push_operand!(children, _math_is_sequence(doc.base), project(:base), p.chrome)
        doc.subscript === nothing ||
            _push_braced!(children, "_{", project(:subscript), p.chrome)
        doc.superscript === nothing ||
            _push_braced!(children, "^{", project(:superscript), p.chrome)
        children
    end)

# ── MathRadicalToSyntaxNode ──────────────────────────────────────────────────

@projection struct MathRadicalToSyntaxNode
    name::ImmutableCell{StyleText} = _NAME
    chrome::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathRadicalToSyntaxNode MathRadical (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("\\sqrt", p.name)) ]
        if doc.index !== nothing
            push!(children, SyntaxLeaf(TextString("[", p.chrome)))
            push!(children, project(:index))
            push!(children, SyntaxLeaf(TextString("]", p.chrome)))
        end
        push!(children, SyntaxLeaf(TextString("{", p.chrome)))
        push!(children, project(:radicand))
        push!(children, SyntaxLeaf(TextString("}", p.chrome)))
        children
    end)

# ── MathBigOperatorToSyntaxNode ──────────────────────────────────────────────

@projection struct MathBigOperatorToSyntaxNode
    name::ImmutableCell{StyleText} = _NAME
    chrome::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathBigOperatorToSyntaxNode MathBigOperator (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString(() -> get_math_big_operator_name(doc.operator), p.name)) ]
        doc.lower === nothing || _push_braced!(children, "_{", project(:lower), p.chrome)
        doc.upper === nothing || _push_braced!(children, "^{", project(:upper), p.chrome)
        push!(children, SyntaxLeaf(TextString(" ", p.chrome)))
        _push_operand!(children, _math_is_sequence(doc.body), project(:body), p.chrome)
        children
    end)

# ── MathDifferentialToSyntaxNode ─────────────────────────────────────────────

@projection struct MathDifferentialToSyntaxNode
    name::ImmutableCell{StyleText} = _NAME
end

@projection_template MathDifferentialToSyntaxNode MathDifferential (p, doc) ->
    SyntaxConcatenation(() -> Any[
        SyntaxLeaf(TextString(() -> doc.kind === :partial ? "\\partial " : "d", p.name)),
        project(:variable)])

# ── MathDerivativeToSyntaxNode ───────────────────────────────────────────────

@projection struct MathDerivativeToSyntaxNode
    name::ImmutableCell{StyleText} = _NAME
    op::ImmutableCell{StyleText} = _OPERATOR
    chrome::ImmutableCell{StyleText} = _CHROME
end

# `d(P)/d(t)`, and `d^2(P)/d(t)^2` for a higher order.
@projection_template MathDerivativeToSyntaxNode MathDerivative (p, doc) ->
    SyntaxConcatenation(() -> begin
        sign  = () -> doc.kind === :partial ? "\\partial" : "d"
        order = () -> doc.order == 1 ? "" : "^" * string(doc.order)
        children = Any[ SyntaxLeaf(TextString(() -> sign() * order(), p.name)) ]
        _push_operand!(children, true, project(:body), p.chrome)
        push!(children, SyntaxLeaf(TextString("/", p.op)))
        push!(children, SyntaxLeaf(TextString(sign, p.name)))
        _push_operand!(children, true, project(:variable), p.chrome)
        push!(children, SyntaxLeaf(TextString(order, p.name)))
        children
    end)

# ── MathFunctionToSyntaxNode ─────────────────────────────────────────────────

@projection struct MathFunctionToSyntaxNode
    name::ImmutableCell{StyleText} = _NAME
    chrome::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathFunctionToSyntaxNode MathFunction (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(bound(:name, String, TextString(() -> doc.name, p.name))) ]
        doc.base === nothing || _push_braced!(children, "_{", project(:base), p.chrome)
        if doc.parenthesized
            _push_operand!(children, true, project(:argument), p.chrome)
        else
            push!(children, SyntaxLeaf(TextString(" ", p.chrome)))
            push!(children, project(:argument))
        end
        children
    end)

# ── MathAccentToSyntaxNode ───────────────────────────────────────────────────

@projection struct MathAccentToSyntaxNode
    name::ImmutableCell{StyleText} = _NAME
    chrome::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathAccentToSyntaxNode MathAccent (p, doc) ->
    SyntaxConcatenation(() -> Any[
        SyntaxLeaf(TextString(() -> "\\" * String(doc.accent) * "{", p.name)),
        project(:base),
        SyntaxLeaf(TextString("}", p.chrome))])

# ── MathMatrixToSyntaxNode ───────────────────────────────────────────────────
#
# `\matrix[2]{a, b, c, d}` — the column count sits in the head, so the row
# structure survives the one-line form.

@projection struct MathMatrixToSyntaxNode
    name::ImmutableCell{StyleText} = _NAME
    chrome::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathMatrixToSyntaxNode MathMatrix (p, doc) ->
    SyntaxConcatenation(() -> Any[
        SyntaxLeaf(TextString(() -> "\\matrix[" * string(doc.columns) * "]", p.name)),
        SyntaxNode(collection(:elements);
                   open=TextString("{", p.chrome),
                   close=TextString("}", p.chrome),
                   sep=TextString(", ", p.chrome))])

# ── MathCaseToSyntaxNode / MathCasesToSyntaxNode ─────────────────────────────

@projection struct MathCaseToSyntaxNode
    keyword::ImmutableCell{StyleText} = _NAME
end

@projection_template MathCaseToSyntaxNode MathCase (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ project(:value) ]
        if doc.condition === nothing
            push!(children, SyntaxLeaf(TextString(" otherwise", p.keyword)))
        else
            push!(children, SyntaxLeaf(TextString(" if ", p.keyword)))
            push!(children, project(:condition))
        end
        children
    end)

@projection struct MathCasesToSyntaxNode
    name::ImmutableCell{StyleText} = _NAME
    chrome::ImmutableCell{StyleText} = _CHROME
end

@projection_template MathCasesToSyntaxNode MathCases (p, doc) ->
    SyntaxConcatenation(() -> Any[
        SyntaxLeaf(TextString("\\cases", p.name)),
        SyntaxNode(collection(:cases);
                   open=TextString("{", p.chrome),
                   close=TextString("}", p.chrome),
                   sep=TextString("; ", p.chrome))])

# ── Structural-caret navigation ──────────────────────────────────────────────
#
# A formula is mostly projection-introduced chrome: every brace, every operator
# glyph and every LaTeX-like name. A caret on that chrome maps back to nothing
# through the wiring, and the engine's fallback would then grow the path on
# every round trip. Collapse it to a bounded flat offset instead — the
# `XmlElementToSyntaxNode` precedent, which the original three compound rules
# above already use.

for T in (:MathRowToSyntaxNode, :MathUnaryOperationToSyntaxNode,
          :MathFractionToSyntaxNode, :MathScriptToSyntaxNode,
          :MathRadicalToSyntaxNode, :MathBigOperatorToSyntaxNode,
          :MathDifferentialToSyntaxNode, :MathDerivativeToSyntaxNode,
          :MathFunctionToSyntaxNode, :MathAccentToSyntaxNode,
          :MathMatrixToSyntaxNode, :MathCaseToSyntaxNode, :MathCasesToSyntaxNode)
    @eval function read_intent(p::$T, iomap::RuleIoMap, op::ReplaceSelectionOperation)
        result = map_reference_backward(p, iomap, op.path)
        result !== nothing && return ReplaceSelectionOperation(result)
        flat = _syntax_to_flat(iomap.output, op.path, SyntaxCompoundToText(), 0)
        flat < 0 && return nothing
        ReplaceSelectionOperation(
            make_introduced_reference(p, iomap.input, ConcreteReference(PositionReferenceStep(flat))))
    end
end

# ── MathToSyntax (composite) ──────────────────────────────────────────────────

function MathToSyntax()
    TypeDispatchingProjection(
        MathInsertion        => MathInsertionToSyntaxLeaf(),
        MathVariable         => MathVariableToSyntaxLeaf(),
        MathSymbol           => MathSymbolToSyntaxLeaf(),
        MathText             => MathTextToSyntaxLeaf(),
        MathSpace            => MathSpaceToSyntaxLeaf(),
        MathRow              => MathRowToSyntaxNode(),
        MathBinaryOperation  => MathBinaryOperationToSyntaxNode(),
        MathUnaryOperation   => MathUnaryOperationToSyntaxNode(),
        MathParenthesized    => MathParenthesizedToSyntaxNode(),
        MathAssignment       => MathAssignmentToSyntaxNode(),
        MathFraction         => MathFractionToSyntaxNode(),
        MathScript           => MathScriptToSyntaxNode(),
        MathRadical          => MathRadicalToSyntaxNode(),
        MathBigOperator      => MathBigOperatorToSyntaxNode(),
        MathDifferential     => MathDifferentialToSyntaxNode(),
        MathDerivative       => MathDerivativeToSyntaxNode(),
        MathFunction         => MathFunctionToSyntaxNode(),
        MathAccent           => MathAccentToSyntaxNode(),
        MathMatrix           => MathMatrixToSyntaxNode(),
        MathCase             => MathCaseToSyntaxNode(),
        MathCases            => MathCasesToSyntaxNode(),
        PrimitiveNumber      => PrimitiveNumberToSyntaxLeaf(),
    )
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that teaches the render-anything projection what this domain is. The
# factory form, so every renderer builds its own projection instance.

# One module, one `__init__`. The slice registers its natural-notation seams
# here, the format its reader reads, and the file extension it owns.
function __init__()
    register_natural_syntax!(:math, () -> Pair{Type,Any}[MathDocument => MathToSyntax()])
    register_natural_graphics!(:math, (; measure) ->
        make_math_to_graphics_dispatch(measure = measure))
    register_natural_domain!(MathDocument; rung = :syntax, make = () -> MathToSyntax(),
                             format = :math, extension = ".math", parse = parse_math)
    register_file_document_type!(".math", MathFile)
end
