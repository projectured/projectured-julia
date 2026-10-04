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
# generic. A brace, an operator glyph or a name that a rule printed is named by
# the rule's own introduced step.
# ── MathInsertionToSyntaxLeaf ─────────────────────────────────────────────────

@projection UntrackedCell struct MathInsertionToSyntaxLeaf
    style::StyleText = get_math_style(nothing, :chrome_text)
end

function print_document(p::MathInsertionToSyntaxLeaf, recursion, m::MathInsertion, ctx)
    output_selection =
        Cell(@computation map_reference_forward(p, nothing, m.selection))
    SimpleIoMap(p, m, SyntaxLeaf(TextString("⌷", p.style); selection=output_selection))
end

# ── MathVariableToSyntaxLeaf ──────────────────────────────────────────────────

@projection UntrackedCell struct MathVariableToSyntaxLeaf
    style::StyleText = get_math_style(nothing, :variable_text)
end

function map_reference_forward(p::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.output))
        proj(^(p), inner) => inner
        ::MathVariable.name{s:e} => @reference ::SyntaxLeaf.value::TextString{s:e}::Position
    end
end

function map_reference_backward(p::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.input))
        ::SyntaxLeaf.value{s:e} => @reference ::MathVariable.name::String{s:e}::Position
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function print_document(p::MathVariableToSyntaxLeaf, recursion, v::MathVariable, ctx)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(v, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    iomap = SimpleIoMap(p, v, SyntaxLeaf(TextString(() -> v.name, p.style); paths...))
    iomap_cell[] = iomap
    iomap
end

function read_intent(p::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : make_path_operation(op, path)
end

# ── MathBinaryOperationToSyntaxNode ───────────────────────────────────────────

@projection UntrackedCell struct MathBinaryOperationToSyntaxNode
    op::StyleText = get_math_style(nothing, :operator_text)
end

# Selection mapping (School A). The output node's children are
# [left (index 1), operator leaf (index 2), right (index 3)]; the operator is
# projection-introduced. .left / .right delegate the tail through the stored
# child IO maps (child_iomaps = [left, right]) rather than re-walking math types.
function map_reference_forward(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        proj(^(p), inner) => inner
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
                make_introduced_reference(p, iomap, reference)
            end
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function print_document(p::MathBinaryOperationToSyntaxNode, recursion, m::MathBinaryOperation, ctx)
    left_ctx  = make_child_context(ctx, m, @reference_step left)
    right_ctx = make_child_context(ctx, m, @reference_step right)
    left_iomap = Cell(@computation print_child(recursion, m.left, left_ctx))
    right_iomap = Cell(@computation print_child(recursion, m.right, right_ctx))

    op_leaf = SyntaxLeaf(TextString(() -> _operator_string(m.operator), p.op))

    iomap_cell = Cell(nothing)
    mouse_target = Cell(@computation(map_mouse_target_forward(m, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)))
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
            return find_introduced_path(p, path)
        end
        return nothing
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[left_iomap[].output, op_leaf, right_iomap[].output]);
        sep=TextString(" ", p.op.font),
        selection=sel, mouse_target)
    iomap = ChildrenIoMap(p, m, node, Cell(@computation [left_iomap[], right_iomap[]]))
    iomap_cell[] = iomap
    iomap
end

function read_intent(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

# ── MathParenthesizedToSyntaxNode ─────────────────────────────────────────────

@projection UntrackedCell struct MathParenthesizedToSyntaxNode
    delim::StyleText = get_math_style(nothing, :chrome_text)
end

# Selection mapping (School A). The single content child is output index 1; the
# parentheses are projection-introduced. child_iomaps holds the one content IO map.
function map_reference_forward(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        proj(^(p), inner) => inner
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
            s + 1 == 1 || return make_introduced_reference(p, iomap, reference)
            child = iomap.child_iomaps
            translated = map_reference_backward(child.projection, child, leaf_path)
            translated === nothing && return nothing
            @reference ::MathParenthesized.content.^(translated)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function print_document(p::MathParenthesizedToSyntaxNode, recursion, m::MathParenthesized, ctx)
    content_ctx = make_child_context(ctx, m, @reference_step content)
    content_iomap = Cell(@computation print_child(recursion, m.content, content_ctx))

    iomap_cell = Cell(nothing)
    mouse_target = Cell(@computation(map_mouse_target_forward(m, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)))
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
            return find_introduced_path(p, path)
        end
        return nothing
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[content_iomap[].output]);
        open=TextString(() -> get_math_delimiter_strings(m.kind)[1], p.delim),
        close=TextString(() -> get_math_delimiter_strings(m.kind)[2], p.delim),
        selection=sel, mouse_target)
    iomap = ChildrenIoMap(p, m, node, content_iomap)
    iomap_cell[] = iomap
    iomap
end

function read_intent(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

# ── MathAssignmentToSyntaxNode ────────────────────────────────────────────────

@projection UntrackedCell struct MathAssignmentToSyntaxNode
    eq::StyleText = get_math_style(nothing, :equals_text)
end

# Selection mapping (School A). Output children are
# [target (index 1), '=' leaf (index 2), value (index 3)]; the '=' is
# projection-introduced. child_iomaps = [target, value].
function map_reference_forward(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        proj(^(p), inner) => inner
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
                make_introduced_reference(p, iomap, reference)
            end
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function print_document(p::MathAssignmentToSyntaxNode, recursion, m::MathAssignment, ctx)
    target_ctx = make_child_context(ctx, m, @reference_step target)
    value_ctx  = make_child_context(ctx, m, @reference_step value)
    target_iomap = Cell(@computation print_child(recursion, m.target, target_ctx))
    value_iomap = Cell(@computation print_child(recursion, m.value, value_ctx))

    eq_leaf = SyntaxLeaf(TextString("=", p.eq))

    iomap_cell = Cell(nothing)
    mouse_target = Cell(@computation(map_mouse_target_forward(m, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)))
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
            return find_introduced_path(p, path)
        end
        return nothing
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[target_iomap[].output, eq_leaf, value_iomap[].output]);
        sep=TextString(" ", p.eq.font),
        selection=sel, mouse_target)
    iomap = ChildrenIoMap(p, m, node, Cell(@computation [target_iomap[], value_iomap[]]))
    iomap_cell[] = iomap
    iomap
end

function read_intent(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

# ── Shared styles for the template rules ─────────────────────────────────────

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

@projection UntrackedCell struct MathSymbolToSyntaxLeaf
    style::StyleText = get_math_style(nothing, :symbol_text)
end

@projection_template MathSymbolToSyntaxLeaf MathSymbol (p, doc) ->
    SyntaxLeaf(TextString(() -> get_math_symbol_glyph(doc.name), p.style))

# ── MathTextToSyntaxLeaf ─────────────────────────────────────────────────────

@projection UntrackedCell struct MathTextToSyntaxLeaf
    style::StyleText = get_math_style(nothing, :word_text)
end

@projection_template MathTextToSyntaxLeaf MathText (p, doc) ->
    SyntaxLeaf(bound(:content, String, TextString(() -> doc.content, p.style)))

# ── MathSpaceToSyntaxLeaf ────────────────────────────────────────────────────

@projection UntrackedCell struct MathSpaceToSyntaxLeaf
    style::StyleText = get_math_style(nothing, :chrome_text)
end

# `\\,`, `\\:`, `\\;` and `\\quad`, so that an explicit space and the gap between
# the elements of a row do not print alike.
const _MATH_SPACE_TEXTS = Dict{Symbol,String}(:thin => "\\,", :medium => "\\:", :thick => "\\;", :quad => "\\quad")

@projection_template MathSpaceToSyntaxLeaf MathSpace (p, doc) ->
    SyntaxLeaf(TextString(() -> get(_MATH_SPACE_TEXTS, doc.kind, "\\,"), p.style))

# ── MathRowToSyntaxNode ──────────────────────────────────────────────────────
#
# Juxtaposition prints as its elements with one space between them.

@projection UntrackedCell struct MathRowToSyntaxNode
    style::StyleText = get_math_style(nothing, :chrome_text)
end

@projection_template MathRowToSyntaxNode MathRow (p, doc) ->
    SyntaxNode(collection(:elements); sep=TextString(" ", p.style))

# ── MathUnaryOperationToSyntaxNode ───────────────────────────────────────────

@projection UntrackedCell struct MathUnaryOperationToSyntaxNode
    op::StyleText = get_math_style(nothing, :operator_text)
    chrome::StyleText = get_math_style(nothing, :chrome_text)
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

@projection UntrackedCell struct MathFractionToSyntaxNode
    op::StyleText = get_math_style(nothing, :operator_text)
    chrome::StyleText = get_math_style(nothing, :chrome_text)
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

@projection UntrackedCell struct MathScriptToSyntaxNode
    chrome::StyleText = get_math_style(nothing, :chrome_text)
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

@projection UntrackedCell struct MathRadicalToSyntaxNode
    name::StyleText = get_math_style(nothing, :name_text)
    chrome::StyleText = get_math_style(nothing, :chrome_text)
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

@projection UntrackedCell struct MathBigOperatorToSyntaxNode
    name::StyleText = get_math_style(nothing, :name_text)
    chrome::StyleText = get_math_style(nothing, :chrome_text)
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

@projection UntrackedCell struct MathDifferentialToSyntaxNode
    name::StyleText = get_math_style(nothing, :name_text)
end

@projection_template MathDifferentialToSyntaxNode MathDifferential (p, doc) ->
    SyntaxConcatenation(() -> Any[
        SyntaxLeaf(TextString(() -> doc.kind === :partial ? "\\partial " : "d", p.name)),
        project(:variable)])

# ── MathDerivativeToSyntaxNode ───────────────────────────────────────────────

@projection UntrackedCell struct MathDerivativeToSyntaxNode
    name::StyleText = get_math_style(nothing, :name_text)
    op::StyleText = get_math_style(nothing, :operator_text)
    chrome::StyleText = get_math_style(nothing, :chrome_text)
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

@projection UntrackedCell struct MathFunctionToSyntaxNode
    name::StyleText = get_math_style(nothing, :name_text)
    chrome::StyleText = get_math_style(nothing, :chrome_text)
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

@projection UntrackedCell struct MathAccentToSyntaxNode
    name::StyleText = get_math_style(nothing, :name_text)
    chrome::StyleText = get_math_style(nothing, :chrome_text)
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

@projection UntrackedCell struct MathMatrixToSyntaxNode
    name::StyleText = get_math_style(nothing, :name_text)
    chrome::StyleText = get_math_style(nothing, :chrome_text)
end

@projection_template MathMatrixToSyntaxNode MathMatrix (p, doc) ->
    SyntaxConcatenation(() -> Any[
        SyntaxLeaf(TextString(() -> "\\matrix[" * string(doc.columns) * "]", p.name)),
        SyntaxNode(collection(:elements);
                   open=TextString("{", p.chrome),
                   close=TextString("}", p.chrome),
                   sep=TextString(", ", p.chrome))])

# ── MathCaseToSyntaxNode / MathCasesToSyntaxNode ─────────────────────────────

@projection UntrackedCell struct MathCaseToSyntaxNode
    keyword::StyleText = get_math_style(nothing, :name_text)
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

@projection UntrackedCell struct MathCasesToSyntaxNode
    name::StyleText = get_math_style(nothing, :name_text)
    chrome::StyleText = get_math_style(nothing, :chrome_text)
end

@projection_template MathCasesToSyntaxNode MathCases (p, doc) ->
    SyntaxConcatenation(() -> Any[
        SyntaxLeaf(TextString("\\cases", p.name)),
        SyntaxNode(collection(:cases);
                   open=TextString("{", p.chrome),
                   close=TextString("}", p.chrome),
                   sep=TextString("; ", p.chrome))])

# ── MathToSyntax (composite) ──────────────────────────────────────────────────

"""
    MathToSyntax(; theme = nothing, syntax_theme = nothing) -> TypeDispatchingProjection

The Math notation, one rule per document type. The builder gives each
projection the style of its role with `get_math_style`, from `theme`, a
`MathTheme` scaled or not, or the default styles for `nothing`; `syntax_theme`
styles the shared `PrimitiveNumberToSyntaxLeaf`, which is the syntax slice's own.
"""
function MathToSyntax(; theme = nothing, syntax_theme = nothing)
    get_style(name) = get_math_style(theme, name)
    chrome_style      = (style = get_style(:chrome_text),)
    op_chrome_style   = (op = get_style(:operator_text), chrome = get_style(:chrome_text))
    name_chrome_style = (name = get_style(:name_text), chrome = get_style(:chrome_text))
    TypeDispatchingProjection(
        MathInsertion        => MathInsertionToSyntaxLeaf(; chrome_style...),
        MathVariable         => MathVariableToSyntaxLeaf(; style = get_style(:variable_text)),
        MathSymbol           => MathSymbolToSyntaxLeaf(; style = get_style(:symbol_text)),
        MathText             => MathTextToSyntaxLeaf(; style = get_style(:word_text)),
        MathSpace            => MathSpaceToSyntaxLeaf(; chrome_style...),
        MathRow              => MathRowToSyntaxNode(; chrome_style...),
        MathBinaryOperation  => MathBinaryOperationToSyntaxNode(; op = get_style(:operator_text)),
        MathUnaryOperation   => MathUnaryOperationToSyntaxNode(; op_chrome_style...),
        MathParenthesized    => MathParenthesizedToSyntaxNode(; delim = get_style(:chrome_text)),
        MathAssignment       => MathAssignmentToSyntaxNode(; eq = get_style(:equals_text)),
        MathFraction         => MathFractionToSyntaxNode(; op_chrome_style...),
        MathScript           => MathScriptToSyntaxNode(; chrome = get_style(:chrome_text)),
        MathRadical          => MathRadicalToSyntaxNode(; name_chrome_style...),
        MathBigOperator      => MathBigOperatorToSyntaxNode(; name_chrome_style...),
        MathDifferential     => MathDifferentialToSyntaxNode(; name = get_style(:name_text)),
        MathDerivative       => MathDerivativeToSyntaxNode(; name = get_style(:name_text),
                                                              op = get_style(:operator_text),
                                                              chrome = get_style(:chrome_text)),
        MathFunction         => MathFunctionToSyntaxNode(; name_chrome_style...),
        MathAccent           => MathAccentToSyntaxNode(; name_chrome_style...),
        MathMatrix           => MathMatrixToSyntaxNode(; name_chrome_style...),
        MathCase             => MathCaseToSyntaxNode(; keyword = get_style(:name_text)),
        MathCases            => MathCasesToSyntaxNode(; name_chrome_style...),
        PrimitiveNumber      => PrimitiveNumberToSyntaxLeaf(; theme = syntax_theme),
    )
end

# ── Natural-projection registration ─────────────────────────────────────────
# The row that teaches the render-anything projection what this domain is. The
# factory form, so every renderer builds its own projection instance.

# One module, one `__init__`. The slice registers its natural-notation seams
# here, the format its reader reads, and the file extension it owns.
function __init__()
    register_natural_syntax!(:math, (; appearance) -> Pair{Type,Any}[MathDocument => MathToSyntax(;
        theme = get_scaled_theme!(appearance, MathTheme),
        syntax_theme = get_scaled_theme!(appearance, SyntaxTheme))])
    register_natural_graphics!(:math, (; measure, appearance) ->
        make_math_to_graphics_dispatch(measure = measure,
                                       theme = get_scaled_theme!(appearance, MathTheme)))
    register_natural_domain!(MathDocument; rung = :syntax,
                             make = (; appearance) -> MathToSyntax(;
                                 theme = get_scaled_theme!(appearance, MathTheme),
                                 syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)),
                             format = :math, extension = ".math", parse = parse_math)
    register_file_document_type!(".math", MathFile)
end
