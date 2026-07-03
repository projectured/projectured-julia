"""
    MathToSyntaxModule

Math → SyntaxDocument projection. Maps each math expression type to a matching
syntax tree shape with colorized tokens:
- Variables in blue
- Operators (+, -, *, /) in cyan
- Parentheses in gray
- Assignment (=) in yellow
- Numbers in magenta (via PrimitiveNumberToSyntaxLeaf)
"""
module MathToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..MathModule: MathDocument, MathInsertion, MathVariable, MathBinaryOperation, MathParenthesized, MathAssignment, _operator_string
import ..PrimitiveModule: PrimitiveNumber
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_cyan, color_solarized_magenta, color_solarized_yellow, color_solarized_gray
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference, ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: child_context
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveToSyntaxModule: PrimitiveNumberToSyntaxLeaf
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
export MathInsertionToSyntaxLeaf, MathVariableToSyntaxLeaf,
       MathBinaryOperationToSyntaxNode, MathParenthesizedToSyntaxNode,
       MathAssignmentToSyntaxNode, MathToSyntax

# ── MathInsertionToSyntaxLeaf ─────────────────────────────────────────────────

@projection struct MathInsertionToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

function print_document(p::MathInsertionToSyntaxLeaf, recursion, m::MathInsertion, ctx)
    output_selection = Cell(() -> map_reference_forward(p, nothing, m.selection))
    SimpleIoMap(p, m, SyntaxLeaf(TextString("⌷", p.style); selection=output_selection))
end

# ── MathVariableToSyntaxLeaf ──────────────────────────────────────────────────

@projection struct MathVariableToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
end

function map_reference_forward(::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::MathVariable.name{k} => @reference ::SyntaxLeaf.value::TextString{k}
    end
end

function map_reference_backward(::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value{k} => @reference ::MathVariable.name::String{k}
    end
end

function print_document(p::MathVariableToSyntaxLeaf, recursion, v::MathVariable, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(() -> v.name, p.style);
        selection=getfield(v, :selection)))
end

function read_intent(::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(FieldReference("name"), path.tail))
end

# ── MathBinaryOperationToSyntaxNode ───────────────────────────────────────────

@projection struct MathBinaryOperationToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

# Selection mapping (School A). The output node's children are
# [left (index 1), operator leaf (index 2), right (index 3)]; the operator is
# projection-introduced. .left / .right delegate the tail through the stored
# child IO maps (child_iomaps = [left, right]) rather than re-walking math types.
function map_reference_forward(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::MathBinaryOperation.left.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[1].^(inner)
        end
        ::MathBinaryOperation.right.rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[3].^(inner)
        end
    end
end

function map_reference_backward(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.leaf_path... => begin
            child_i = s + 1
            cims = iomap.child_iomaps[]
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
    reference = ctx.reference
    left_ctx  = child_context(ctx, @reference ^(reference).left)
    right_ctx = child_context(ctx, @reference ^(reference).right)
    left_iomap = Cell(() -> print_child(recursion, m.left, left_ctx))
    right_iomap = Cell(() -> print_child(recursion, m.right, right_ctx))

    op_leaf = SyntaxLeaf(TextString(() -> _operator_string(m.operator), p.op))

    sel = Cell(() -> begin
        path = m.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa FieldReference
            if h.name == "left"
                li = left_iomap[]
                child_sel = li.output.selection
                child_sel === nothing && return nothing
                return ConcreteReferencePath(FieldReference("children"),
                           ConcreteReferencePath(ElementReference(1), child_sel))
            elseif h.name == "right"
                ri = right_iomap[]
                child_sel = ri.output.selection
                child_sel === nothing && return nothing
                return ConcreteReferencePath(FieldReference("children"),
                           ConcreteReferencePath(ElementReference(3), child_sel))
            end
        elseif h isa ProjectionReference
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[left_iomap[].output, op_leaf, right_iomap[].output]);
        sep=TextString(" ", p.op.font, color_default),
        selection=sel)
    ChildrenIoMap(p, m, node, Cell(() -> [left_iomap[], right_iomap[]]))
end

function read_intent(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── MathParenthesizedToSyntaxNode ─────────────────────────────────────────────

@projection struct MathParenthesizedToSyntaxNode
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

# Selection mapping (School A). The single content child is output index 1; the
# parentheses are projection-introduced. child_iomaps holds the one content IO map.
function map_reference_forward(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::MathParenthesized.content.rest... => begin
            child = iomap.child_iomaps[]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[1].^(inner)
        end
    end
end

function map_reference_backward(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::SyntaxNode.children{s:_}.leaf_path... => begin
            s + 1 == 1 || return nothing
            child = iomap.child_iomaps[]
            translated = map_reference_backward(child.projection, child, leaf_path)
            translated === nothing && return nothing
            @reference ::MathParenthesized.content.^(translated)
        end
    end
end

function print_document(p::MathParenthesizedToSyntaxNode, recursion, m::MathParenthesized, ctx)
    reference = ctx.reference
    content_ctx = child_context(ctx, @reference ^(reference).content)
    content_iomap = Cell(() -> print_child(recursion, m.content, content_ctx))

    sel = Cell(() -> begin
        path = m.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa FieldReference && h.name == "content"
            ci = content_iomap[]
            child_sel = ci.output.selection
            child_sel === nothing && return nothing
            return ConcreteReferencePath(FieldReference("children"),
                       ConcreteReferencePath(ElementReference(1), child_sel))
        elseif h isa ProjectionReference
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[content_iomap[].output]);
        open=TextString("(", p.delim),
        close=TextString(")", p.delim),
        selection=sel)
    ChildrenIoMap(p, m, node, content_iomap)
end

function read_intent(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── MathAssignmentToSyntaxNode ────────────────────────────────────────────────

@projection struct MathAssignmentToSyntaxNode
    eq::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_yellow)
end

# Selection mapping (School A). Output children are
# [target (index 1), '=' leaf (index 2), value (index 3)]; the '=' is
# projection-introduced. child_iomaps = [target, value].
function map_reference_forward(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ::MathAssignment.target.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[1].^(inner)
        end
        ::MathAssignment.value.rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[3].^(inner)
        end
    end
end

function map_reference_backward(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.leaf_path... => begin
            child_i = s + 1
            cims = iomap.child_iomaps[]
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
    reference = ctx.reference
    target_ctx = child_context(ctx, @reference ^(reference).target)
    value_ctx  = child_context(ctx, @reference ^(reference).value)
    target_iomap = Cell(() -> print_child(recursion, m.target, target_ctx))
    value_iomap = Cell(() -> print_child(recursion, m.value, value_ctx))

    eq_leaf = SyntaxLeaf(TextString("=", p.eq))

    sel = Cell(() -> begin
        path = m.selection
        path isa ConcreteReferencePath || return nothing
        h = path.head
        if h isa FieldReference
            if h.name == "target"
                ti = target_iomap[]
                child_sel = ti.output.selection
                child_sel === nothing && return nothing
                return ConcreteReferencePath(FieldReference("children"),
                           ConcreteReferencePath(ElementReference(1), child_sel))
            elseif h.name == "value"
                vi = value_iomap[]
                child_sel = vi.output.selection
                child_sel === nothing && return nothing
                return ConcreteReferencePath(FieldReference("children"),
                           ConcreteReferencePath(ElementReference(3), child_sel))
            end
        elseif h isa ProjectionReference
            return path
        end
        return nothing
    end)

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[target_iomap[].output, eq_leaf, value_iomap[].output]);
        sep=TextString(" ", p.eq.font, color_default),
        selection=sel)
    ChildrenIoMap(p, m, node, Cell(() -> [target_iomap[], value_iomap[]]))
end

function read_intent(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── MathToSyntax (composite) ──────────────────────────────────────────────────

function MathToSyntax()
    TypeDispatchingProjection(
        MathInsertion        => MathInsertionToSyntaxLeaf(),
        MathVariable         => MathVariableToSyntaxLeaf(),
        MathBinaryOperation  => MathBinaryOperationToSyntaxNode(),
        MathParenthesized    => MathParenthesizedToSyntaxNode(),
        MathAssignment       => MathAssignmentToSyntaxNode(),
        PrimitiveNumber      => PrimitiveNumberToSyntaxLeaf(),
    )
end

end # module
