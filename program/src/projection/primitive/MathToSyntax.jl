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
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
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

function projection_print(p::MathInsertionToSyntaxLeaf, m::MathInsertion, recursion, reference)
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

function projection_print(p::MathVariableToSyntaxLeaf, v::MathVariable, recursion, reference)
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

function map_reference_forward(::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _forward_math_path(iomap.input::MathBinaryOperation, reference)
end

function map_reference_backward(::MathBinaryOperationToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _translate_binop_path(iomap.input::MathBinaryOperation, reference)
end

function projection_print(p::MathBinaryOperationToSyntaxNode, m::MathBinaryOperation, recursion, reference)
    left_ref  = @reference ^(reference).left
    right_ref = @reference ^(reference).right
    left_iomap = Cell(() -> projection_print(recursion, m.left, recursion, left_ref))
    right_iomap = Cell(() -> projection_print(recursion, m.right, recursion, right_ref))

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
    result = _translate_binop_path(iomap.input::MathBinaryOperation, op.path)
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

function map_reference_forward(::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _forward_math_path(iomap.input::MathParenthesized, reference)
end

function map_reference_backward(::MathParenthesizedToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _translate_paren_path(iomap.input::MathParenthesized, reference)
end

function projection_print(p::MathParenthesizedToSyntaxNode, m::MathParenthesized, recursion, reference)
    content_ref = @reference ^(reference).content
    content_iomap = Cell(() -> projection_print(recursion, m.content, recursion, content_ref))

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
    result = _translate_paren_path(iomap.input::MathParenthesized, op.path)
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

function map_reference_forward(::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _forward_math_path(iomap.input::MathAssignment, reference)
end

function map_reference_backward(::MathAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    return _translate_assign_path(iomap.input::MathAssignment, reference)
end

function projection_print(p::MathAssignmentToSyntaxNode, m::MathAssignment, recursion, reference)
    target_ref = @reference ^(reference).target
    value_ref  = @reference ^(reference).value
    target_iomap = Cell(() -> projection_print(recursion, m.target, recursion, target_ref))
    value_iomap = Cell(() -> projection_print(recursion, m.value, recursion, value_ref))

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
    result = _translate_assign_path(iomap.input::MathAssignment, op.path)
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

# ── Path translation (SyntaxDocument → Math domain) ──────────────────────────

function _translate_binop_path(m::MathBinaryOperation, path::ReferencePath)
    @reference_case path begin
        children{s:_}.leaf_path... => begin
            child_i = s + 1
            if child_i == 1
                translated = _translate_math_path(m.left, leaf_path)
                translated === nothing && return nothing
                @reference left.^(translated)
            elseif child_i == 3
                translated = _translate_math_path(m.right, leaf_path)
                translated === nothing && return nothing
                @reference right.^(translated)
            else
                nothing
            end
        end
    end
end

function _translate_paren_path(m::MathParenthesized, path::ReferencePath)
    @reference_case path begin
        children{s:_}.leaf_path... => begin
            s + 1 == 1 || return nothing
            translated = _translate_math_path(m.content, leaf_path)
            translated === nothing && return nothing
            @reference content.^(translated)
        end
    end
end

function _translate_assign_path(m::MathAssignment, path::ReferencePath)
    @reference_case path begin
        children{s:_}.leaf_path... => begin
            child_i = s + 1
            if child_i == 1
                translated = _translate_math_path(m.target, leaf_path)
                translated === nothing && return nothing
                @reference target.^(translated)
            elseif child_i == 3
                translated = _translate_math_path(m.value, leaf_path)
                translated === nothing && return nothing
                @reference value.^(translated)
            else
                nothing
            end
        end
    end
end

function _translate_math_path(v::MathVariable, path::ReferencePath)
    @reference_case path begin
        value.rest... => @reference name.^(rest)
    end
end

function _translate_math_path(v::PrimitiveNumber, path::ReferencePath)
    @reference_case path begin
        value.rest... => path
    end
end

function _translate_math_path(v::MathBinaryOperation, path::ReferencePath)
    return _translate_binop_path(v, path)
end

function _translate_math_path(v::MathParenthesized, path::ReferencePath)
    return _translate_paren_path(v, path)
end

function _translate_math_path(v::MathAssignment, path::ReferencePath)
    return _translate_assign_path(v, path)
end

function _translate_math_path(v, path::ReferencePath)
    return nothing
end

# ── Forward path translation (Math domain → SyntaxDocument) ──────────────────

function _forward_math_path(v::MathVariable, path::ReferencePath)
    @reference_case path begin
        name.rest... => @reference value.^(rest)
    end
end

function _forward_math_path(v::PrimitiveNumber, path::ReferencePath)
    @reference_case path begin
        value.rest... => path
    end
end

function _forward_math_path(v::MathBinaryOperation, path::ReferencePath)
    @reference_case path begin
        left.rest... => begin
            inner = _forward_math_path(v.left, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
        right.rest... => begin
            inner = _forward_math_path(v.right, rest)
            inner === nothing && return nothing
            @reference children[3].^(inner)
        end
    end
end

function _forward_math_path(v::MathParenthesized, path::ReferencePath)
    @reference_case path begin
        content.rest... => begin
            inner = _forward_math_path(v.content, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
    end
end

function _forward_math_path(v::MathAssignment, path::ReferencePath)
    @reference_case path begin
        target.rest... => begin
            inner = _forward_math_path(v.target, rest)
            inner === nothing && return nothing
            @reference children[1].^(inner)
        end
        value.rest... => begin
            inner = _forward_math_path(v.value, rest)
            inner === nothing && return nothing
            @reference children[3].^(inner)
        end
    end
end

function _forward_math_path(v, path::ReferencePath)
    return nothing
end

end # module
