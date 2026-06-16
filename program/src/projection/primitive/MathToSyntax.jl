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
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
import ..MathModule: MathDocument, MathInsertion, MathVariable, MathBinaryOperation, MathParenthesized, MathAssignment, _operator_string
import ..PrimitiveModule: PrimitiveNumber
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_cyan, color_solarized_magenta, color_solarized_yellow, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
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

struct MathInsertionToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
MathInsertionToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_gray) =
    MathInsertionToSyntaxLeaf(font, color)

function projection_print(p::MathInsertionToSyntaxLeaf, recursion, m::MathInsertion, ctx)
    output_selection = Cell(() -> map_reference_forward(p, nothing, m.selection))
    SimpleIoMap(p, m, SyntaxLeaf(TextString("", p.font, color_default), TextString("", p.font, color_default),
                                  TextString("⌷", p.font, p.color), output_selection))
end

# ── MathVariableToSyntaxLeaf ──────────────────────────────────────────────────

struct MathVariableToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
MathVariableToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_blue) =
    MathVariableToSyntaxLeaf(font, color)

function map_reference_forward(::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        name{k} => @reference value{k}
    end
end

function map_reference_backward(::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value{k} => @reference name{k}
    end
end

function projection_print(p::MathVariableToSyntaxLeaf, recursion, v::MathVariable, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString("", p.font, color_default),
        TextString("", p.font, color_default),
        TextString(() -> v.name, p.font, p.color),
        getfield(v, :selection)))
end

function projection_read(::MathVariableToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReferencePath || return nothing
    h = path.head
    h isa FieldReference && h.name == "value" || return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(FieldReference("name"), path.tail))
end

# ── MathBinaryOperationToSyntaxNode ───────────────────────────────────────────

struct MathBinaryOperationToSyntaxNode <: Projection
    op_font::StyleFont
    op_color::StyleColor
end
MathBinaryOperationToSyntaxNode(; op_font=font_ubuntu_monospace_regular_24, op_color=color_solarized_cyan) =
    MathBinaryOperationToSyntaxNode(op_font, op_color)

# Selection mapping (School A). The output node's children are
# [left (index 1), operator leaf (index 2), right (index 3)]; the operator is
# projection-introduced. .left / .right delegate the tail through the stored
# child IO maps (child_iomaps = [left, right]) rather than re-walking math types.
function map_reference_forward(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        left.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
        right.rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[3].^(inner)
        end
    end
end

function map_reference_backward(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.leaf_path... => begin
            child_i = s + 1
            cims = iomap.child_iomaps[]
            if child_i == 1
                child = cims[1]
                translated = map_reference_backward(child.projection, child, leaf_path)
                translated === nothing && return nothing
                @reference left.^(translated)
            elseif child_i == 3
                child = cims[2]
                translated = map_reference_backward(child.projection, child, leaf_path)
                translated === nothing && return nothing
                @reference right.^(translated)
            else
                nothing
            end
        end
    end
end

function projection_print(p::MathBinaryOperationToSyntaxNode, recursion, m::MathBinaryOperation, ctx)
    reference = ctx.reference
    left_ctx  = child_context(ctx, @reference ^(reference).left)
    right_ctx = child_context(ctx, @reference ^(reference).right)
    left_iomap = Cell(() -> projection_printer_recurse(recursion, m.left, left_ctx))
    right_iomap = Cell(() -> projection_printer_recurse(recursion, m.right, right_ctx))

    op_leaf = SyntaxLeaf(
        TextString("", p.op_font, color_default),
        TextString("", p.op_font, color_default),
        TextString(() -> _operator_string(m.operator), p.op_font, p.op_color),
        Cell(nothing))

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
        TextString("", p.op_font, color_default),
        TextString("", p.op_font, color_default),
        TextString(" ", p.op_font, color_default),
        CellVector(() -> SyntaxDocument[left_iomap[].output, op_leaf, right_iomap[].output]),
        0,
        Cell(false),
        sel)
    ChildrenIoMap(p, m, node, Cell(() -> [left_iomap[], right_iomap[]]))
end

function projection_read(p::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── MathParenthesizedToSyntaxNode ─────────────────────────────────────────────

struct MathParenthesizedToSyntaxNode <: Projection
    delim_font::StyleFont
    delim_color::StyleColor
end
MathParenthesizedToSyntaxNode(; delim_font=font_ubuntu_monospace_regular_24, delim_color=color_solarized_gray) =
    MathParenthesizedToSyntaxNode(delim_font, delim_color)

# Selection mapping (School A). The single content child is output index 1; the
# parentheses are projection-introduced. child_iomaps holds the one content IO map.
function map_reference_forward(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        content.rest... => begin
            child = iomap.child_iomaps[]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
    end
end

function map_reference_backward(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.leaf_path... => begin
            s + 1 == 1 || return nothing
            child = iomap.child_iomaps[]
            translated = map_reference_backward(child.projection, child, leaf_path)
            translated === nothing && return nothing
            @reference content.^(translated)
        end
    end
end

function projection_print(p::MathParenthesizedToSyntaxNode, recursion, m::MathParenthesized, ctx)
    reference = ctx.reference
    content_ctx = child_context(ctx, @reference ^(reference).content)
    content_iomap = Cell(() -> projection_printer_recurse(recursion, m.content, content_ctx))

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
        TextString("(", p.delim_font, p.delim_color),
        TextString(")", p.delim_font, p.delim_color),
        TextString("", p.delim_font, color_default),
        CellVector(() -> SyntaxDocument[content_iomap[].output]),
        0,
        Cell(false),
        sel)
    ChildrenIoMap(p, m, node, content_iomap)
end

function projection_read(p::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

# ── MathAssignmentToSyntaxNode ────────────────────────────────────────────────

struct MathAssignmentToSyntaxNode <: Projection
    eq_font::StyleFont
    eq_color::StyleColor
end
MathAssignmentToSyntaxNode(; eq_font=font_ubuntu_monospace_regular_24, eq_color=color_solarized_yellow) =
    MathAssignmentToSyntaxNode(eq_font, eq_color)

# Selection mapping (School A). Output children are
# [target (index 1), '=' leaf (index 2), value (index 3)]; the '=' is
# projection-introduced. child_iomaps = [target, value].
function map_reference_forward(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        target.rest... => begin
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
        value.rest... => begin
            child = iomap.child_iomaps[][2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[3].^(inner)
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
                @reference target.^(translated)
            elseif child_i == 3
                child = cims[2]
                translated = map_reference_backward(child.projection, child, leaf_path)
                translated === nothing && return nothing
                @reference value.^(translated)
            else
                nothing
            end
        end
    end
end

function projection_print(p::MathAssignmentToSyntaxNode, recursion, m::MathAssignment, ctx)
    reference = ctx.reference
    target_ctx = child_context(ctx, @reference ^(reference).target)
    value_ctx  = child_context(ctx, @reference ^(reference).value)
    target_iomap = Cell(() -> projection_printer_recurse(recursion, m.target, target_ctx))
    value_iomap = Cell(() -> projection_printer_recurse(recursion, m.value, value_ctx))

    eq_leaf = SyntaxLeaf(
        TextString("", p.eq_font, color_default),
        TextString("", p.eq_font, color_default),
        TextString("=", p.eq_font, p.eq_color),
        Cell(nothing))

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
        TextString("", p.eq_font, color_default),
        TextString("", p.eq_font, color_default),
        TextString(" ", p.eq_font, color_default),
        CellVector(() -> SyntaxDocument[target_iomap[].output, eq_leaf, value_iomap[].output]),
        0,
        Cell(false),
        sel)
    ChildrenIoMap(p, m, node, Cell(() -> [target_iomap[], value_iomap[]]))
end

function projection_read(p::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
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
