"""
    JuliaToSyntaxModule

Julia → SyntaxDocument projection. Maps each Julia expression type to a syntax
tree with colorized tokens:
- Identifiers in blue
- Keywords (function, if, else, for, while, return, break, continue,
  try, catch, finally, begin, end, in) in bold magenta
- Operators (==, *, -, +, ::, etc.) in cyan
- Integer, float, string and char literals in green
- Booleans, nothing and symbols in bold magenta
- Delimiters (parentheses, brackets, commas) in gray
"""
module JuliaToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..JuliaModule: JuliaDocument,
                      JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool,
                      JuliaNothing, JuliaSymbol, JuliaChar,
                      JuliaBinaryOp, JuliaUnaryOp, JuliaCall, JuliaTernary,
                      JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange,
                      JuliaTypeAnnotation,
                      JuliaAssignment, JuliaFor, JuliaForIterator, JuliaWhile,
                      JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry, JuliaBegin,
                      JuliaIf, JuliaFunction, JuliaBlock, _julia_operator_string
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_cyan,
                      color_solarized_green, color_solarized_magenta, color_solarized_gray
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference,
                          FieldReference, ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: child_context
import ..OperationModule: ReplaceSelectionOperation
export JuliaIdentifierToSyntaxLeaf, JuliaIntegerToSyntaxLeaf,
       JuliaFloatToSyntaxLeaf, JuliaStringToSyntaxLeaf, JuliaBoolToSyntaxLeaf,
       JuliaNothingToSyntaxLeaf, JuliaSymbolToSyntaxLeaf, JuliaCharToSyntaxLeaf,
       JuliaBinaryOpToSyntaxNode, JuliaUnaryOpToSyntaxNode, JuliaCallToSyntaxNode,
       JuliaTernaryToSyntaxNode, JuliaIndexToSyntaxNode, JuliaFieldAccessToSyntaxNode,
       JuliaTupleToSyntaxNode, JuliaArrayToSyntaxNode, JuliaRangeToSyntaxNode,
       JuliaTypeAnnotationToSyntaxNode,
       JuliaAssignmentToSyntaxNode, JuliaForToSyntaxNode, JuliaForIteratorToSyntaxNode,
       JuliaWhileToSyntaxNode, JuliaReturnToSyntaxNode,
       JuliaBreakToSyntaxLeaf, JuliaContinueToSyntaxLeaf,
       JuliaTryToSyntaxNode, JuliaBeginToSyntaxNode,
       JuliaIfToSyntaxNode, JuliaFunctionToSyntaxNode, JuliaBlockToSyntaxNode,
       JuliaToSyntax

# ── Leaf helpers ─────────────────────────────────────────────────────────────

_empty(font) = TextString("", font, color_default)
_text(value, font, color) = TextString(value, font, color)

# ── JuliaIdentifierToSyntaxLeaf ─────────────────────────────────────────────

struct JuliaIdentifierToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JuliaIdentifierToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_blue) =
    JuliaIdentifierToSyntaxLeaf(font, color)

function projection_print(p::JuliaIdentifierToSyntaxLeaf, recursion, v::JuliaIdentifier, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        _empty(p.font), _empty(p.font),
        TextString(() -> v.name, p.font, p.color),
        getfield(v, :selection)))
end

# ── JuliaIntegerToSyntaxLeaf ────────────────────────────────────────────────

struct JuliaIntegerToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JuliaIntegerToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_green) =
    JuliaIntegerToSyntaxLeaf(font, color)

function projection_print(p::JuliaIntegerToSyntaxLeaf, recursion, v::JuliaInteger, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        _empty(p.font), _empty(p.font),
        TextString(() -> string(v.value), p.font, p.color),
        getfield(v, :selection)))
end

# ── JuliaFloatToSyntaxLeaf ──────────────────────────────────────────────────

struct JuliaFloatToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JuliaFloatToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_green) =
    JuliaFloatToSyntaxLeaf(font, color)

function projection_print(p::JuliaFloatToSyntaxLeaf, recursion, v::JuliaFloat, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        _empty(p.font), _empty(p.font),
        TextString(() -> string(v.value), p.font, p.color),
        getfield(v, :selection)))
end

# ── JuliaStringToSyntaxLeaf ─────────────────────────────────────────────────

struct JuliaStringToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
    quote_color::StyleColor
end
JuliaStringToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24,
                         color=color_solarized_green,
                         quote_color=color_solarized_gray) =
    JuliaStringToSyntaxLeaf(font, color, quote_color)

function projection_print(p::JuliaStringToSyntaxLeaf, recursion, v::JuliaString, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString("\"", p.font, p.quote_color),
        TextString("\"", p.font, p.quote_color),
        TextString(() -> v.value, p.font, p.color),
        getfield(v, :selection)))
end

# ── JuliaBoolToSyntaxLeaf ───────────────────────────────────────────────────

struct JuliaBoolToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JuliaBoolToSyntaxLeaf(; font=font_ubuntu_monospace_bold_24, color=color_solarized_magenta) =
    JuliaBoolToSyntaxLeaf(font, color)

function projection_print(p::JuliaBoolToSyntaxLeaf, recursion, v::JuliaBool, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        _empty(p.font), _empty(p.font),
        TextString(() -> v.value ? "true" : "false", p.font, p.color),
        getfield(v, :selection)))
end

# ── JuliaNothingToSyntaxLeaf ────────────────────────────────────────────────

struct JuliaNothingToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JuliaNothingToSyntaxLeaf(; font=font_ubuntu_monospace_bold_24, color=color_solarized_magenta) =
    JuliaNothingToSyntaxLeaf(font, color)

function projection_print(p::JuliaNothingToSyntaxLeaf, recursion, v::JuliaNothing, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        _empty(p.font), _empty(p.font),
        TextString("nothing", p.font, p.color),
        getfield(v, :selection)))
end

# ── JuliaSymbolToSyntaxLeaf ─────────────────────────────────────────────────

struct JuliaSymbolToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
end
JuliaSymbolToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24, color=color_solarized_magenta) =
    JuliaSymbolToSyntaxLeaf(font, color)

function projection_print(p::JuliaSymbolToSyntaxLeaf, recursion, v::JuliaSymbol, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(":", p.font, p.color),
        _empty(p.font),
        TextString(() -> v.name, p.font, p.color),
        getfield(v, :selection)))
end

# ── JuliaCharToSyntaxLeaf ───────────────────────────────────────────────────

struct JuliaCharToSyntaxLeaf <: Projection
    font::StyleFont
    color::StyleColor
    quote_color::StyleColor
end
JuliaCharToSyntaxLeaf(; font=font_ubuntu_monospace_regular_24,
                       color=color_solarized_green,
                       quote_color=color_solarized_gray) =
    JuliaCharToSyntaxLeaf(font, color, quote_color)

function projection_print(p::JuliaCharToSyntaxLeaf, recursion, v::JuliaChar, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString("'", p.font, p.quote_color),
        TextString("'", p.font, p.quote_color),
        TextString(() -> string(v.value), p.font, p.color),
        getfield(v, :selection)))
end

# ── JuliaBinaryOpToSyntaxNode ───────────────────────────────────────────────

struct JuliaBinaryOpToSyntaxNode <: Projection
    op_font::StyleFont
    op_color::StyleColor
end
JuliaBinaryOpToSyntaxNode(; op_font=font_ubuntu_monospace_regular_24, op_color=color_solarized_cyan) =
    JuliaBinaryOpToSyntaxNode(op_font, op_color)

function projection_print(p::JuliaBinaryOpToSyntaxNode, recursion, m::JuliaBinaryOp, ctx)
    left_ref = child_context(ctx, @reference ^(ctx.reference).left)
    right_ref = child_context(ctx, @reference ^(ctx.reference).right)
    left_iomap = Cell(() -> projection_print(recursion, recursion, m.left, left_ref))
    right_iomap = Cell(() -> projection_print(recursion, recursion, m.right, right_ref))

    op_leaf = SyntaxLeaf(
        TextString(" ", p.op_font, color_default),
        TextString(" ", p.op_font, color_default),
        TextString(() -> _julia_operator_string(m.operator), p.op_font, p.op_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.op_font), _empty(p.op_font), _empty(p.op_font),
        CellVector(() -> SyntaxDocument[left_iomap[].output, op_leaf, right_iomap[].output]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, m, node, Cell(() -> IoMap[left_iomap[], right_iomap[]]))
end

# ── JuliaUnaryOpToSyntaxNode ────────────────────────────────────────────────

struct JuliaUnaryOpToSyntaxNode <: Projection
    op_font::StyleFont
    op_color::StyleColor
end
JuliaUnaryOpToSyntaxNode(; op_font=font_ubuntu_monospace_regular_24, op_color=color_solarized_cyan) =
    JuliaUnaryOpToSyntaxNode(op_font, op_color)

function projection_print(p::JuliaUnaryOpToSyntaxNode, recursion, u::JuliaUnaryOp, ctx)
    operand_ref = child_context(ctx, @reference ^(ctx.reference).operand)
    operand_iomap = Cell(() -> projection_print(recursion, recursion, u.operand, operand_ref))

    op_leaf = SyntaxLeaf(
        _empty(p.op_font), _empty(p.op_font),
        TextString(() -> _julia_operator_string(u.operator), p.op_font, p.op_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.op_font), _empty(p.op_font), _empty(p.op_font),
        CellVector(() -> SyntaxDocument[op_leaf, operand_iomap[].output]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, u, node, Cell(() -> IoMap[operand_iomap[]]))
end

# ── JuliaCallToSyntaxNode ───────────────────────────────────────────────────

struct JuliaCallToSyntaxNode <: Projection
    delim_font::StyleFont
    delim_color::StyleColor
end
JuliaCallToSyntaxNode(; delim_font=font_ubuntu_monospace_regular_24, delim_color=color_solarized_gray) =
    JuliaCallToSyntaxNode(delim_font, delim_color)

function projection_print(p::JuliaCallToSyntaxNode, recursion, c::JuliaCall, ctx)
    callee_ref = child_context(ctx, @reference ^(ctx.reference).callee)
    callee_iomap = Cell(() -> projection_print(recursion, recursion, c.callee, callee_ref))

    arg_iomaps = Cell(() -> [projection_print(recursion, recursion, arg,
                                child_context(ctx, @reference ^(ctx.reference).arguments[i]))
                             for (i, arg) in enumerate(c.arguments)])

    args_node = SyntaxNode(
        TextString("(", p.delim_font, p.delim_color),
        TextString(")", p.delim_font, p.delim_color),
        TextString(", ", p.delim_font, p.delim_color),
        CellVector(() -> SyntaxDocument[im.output for im in arg_iomaps[]]),
        0, Cell(false), Cell(nothing))

    node = SyntaxNode(
        _empty(p.delim_font), _empty(p.delim_font), _empty(p.delim_font),
        CellVector(() -> SyntaxDocument[callee_iomap[].output, args_node]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, c, node, Cell(() -> IoMap[callee_iomap[]; arg_iomaps[]]))
end

# ── JuliaTernaryToSyntaxNode ────────────────────────────────────────────────

struct JuliaTernaryToSyntaxNode <: Projection
    op_font::StyleFont
    op_color::StyleColor
end
JuliaTernaryToSyntaxNode(; op_font=font_ubuntu_monospace_regular_24, op_color=color_solarized_cyan) =
    JuliaTernaryToSyntaxNode(op_font, op_color)

function projection_print(p::JuliaTernaryToSyntaxNode, recursion, t::JuliaTernary, ctx)
    cond_ref = child_context(ctx, @reference ^(ctx.reference).condition)
    then_ref = child_context(ctx, @reference ^(ctx.reference).then_branch)
    else_ref = child_context(ctx, @reference ^(ctx.reference).else_branch)

    cond_iomap = Cell(() -> projection_print(recursion, recursion, t.condition, cond_ref))
    then_iomap = Cell(() -> projection_print(recursion, recursion, t.then_branch, then_ref))
    else_iomap = Cell(() -> projection_print(recursion, recursion, t.else_branch, else_ref))

    q_leaf = SyntaxLeaf(
        TextString(" ", p.op_font, color_default),
        TextString(" ", p.op_font, color_default),
        TextString("?", p.op_font, p.op_color), Cell(nothing))
    c_leaf = SyntaxLeaf(
        TextString(" ", p.op_font, color_default),
        TextString(" ", p.op_font, color_default),
        TextString(":", p.op_font, p.op_color), Cell(nothing))

    node = SyntaxNode(
        _empty(p.op_font), _empty(p.op_font), _empty(p.op_font),
        CellVector(() -> SyntaxDocument[cond_iomap[].output, q_leaf, then_iomap[].output, c_leaf, else_iomap[].output]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, t, node, Cell(() -> IoMap[cond_iomap[], then_iomap[], else_iomap[]]))
end

# ── JuliaIndexToSyntaxNode ──────────────────────────────────────────────────

struct JuliaIndexToSyntaxNode <: Projection
    delim_font::StyleFont
    delim_color::StyleColor
end
JuliaIndexToSyntaxNode(; delim_font=font_ubuntu_monospace_regular_24, delim_color=color_solarized_gray) =
    JuliaIndexToSyntaxNode(delim_font, delim_color)

function projection_print(p::JuliaIndexToSyntaxNode, recursion, x::JuliaIndex, ctx)
    coll_ref = child_context(ctx, @reference ^(ctx.reference).collection)
    coll_iomap = Cell(() -> projection_print(recursion, recursion, x.collection, coll_ref))

    idx_iomaps = Cell(() -> [projection_print(recursion, recursion, ix,
                                child_context(ctx, @reference ^(ctx.reference).indices[i]))
                             for (i, ix) in enumerate(x.indices)])

    idx_node = SyntaxNode(
        TextString("[", p.delim_font, p.delim_color),
        TextString("]", p.delim_font, p.delim_color),
        TextString(", ", p.delim_font, p.delim_color),
        CellVector(() -> SyntaxDocument[im.output for im in idx_iomaps[]]),
        0, Cell(false), Cell(nothing))

    node = SyntaxNode(
        _empty(p.delim_font), _empty(p.delim_font), _empty(p.delim_font),
        CellVector(() -> SyntaxDocument[coll_iomap[].output, idx_node]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, x, node, Cell(() -> IoMap[coll_iomap[]; idx_iomaps[]]))
end

# ── JuliaFieldAccessToSyntaxNode ────────────────────────────────────────────

struct JuliaFieldAccessToSyntaxNode <: Projection
    dot_font::StyleFont
    dot_color::StyleColor
end
JuliaFieldAccessToSyntaxNode(; dot_font=font_ubuntu_monospace_regular_24, dot_color=color_solarized_cyan) =
    JuliaFieldAccessToSyntaxNode(dot_font, dot_color)

function projection_print(p::JuliaFieldAccessToSyntaxNode, recursion, f::JuliaFieldAccess, ctx)
    object_ref = child_context(ctx, @reference ^(ctx.reference).object)
    field_ref = child_context(ctx, @reference ^(ctx.reference).field)
    object_iomap = Cell(() -> projection_print(recursion, recursion, f.object, object_ref))
    field_iomap = Cell(() -> projection_print(recursion, recursion, f.field, field_ref))

    dot_leaf = SyntaxLeaf(
        _empty(p.dot_font), _empty(p.dot_font),
        TextString(".", p.dot_font, p.dot_color), Cell(nothing))

    node = SyntaxNode(
        _empty(p.dot_font), _empty(p.dot_font), _empty(p.dot_font),
        CellVector(() -> SyntaxDocument[object_iomap[].output, dot_leaf, field_iomap[].output]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, f, node, Cell(() -> IoMap[object_iomap[], field_iomap[]]))
end

# ── JuliaTupleToSyntaxNode ──────────────────────────────────────────────────

struct JuliaTupleToSyntaxNode <: Projection
    delim_font::StyleFont
    delim_color::StyleColor
end
JuliaTupleToSyntaxNode(; delim_font=font_ubuntu_monospace_regular_24, delim_color=color_solarized_gray) =
    JuliaTupleToSyntaxNode(delim_font, delim_color)

function projection_print(p::JuliaTupleToSyntaxNode, recursion, t::JuliaTuple, ctx)
    elem_iomaps = Cell(() -> [projection_print(recursion, recursion, e,
                                child_context(ctx, @reference ^(ctx.reference).elements[i]))
                              for (i, e) in enumerate(t.elements)])

    node = SyntaxNode(
        TextString("(", p.delim_font, p.delim_color),
        TextString(")", p.delim_font, p.delim_color),
        TextString(", ", p.delim_font, p.delim_color),
        CellVector(() -> SyntaxDocument[im.output for im in elem_iomaps[]]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, t, node, elem_iomaps)
end

# ── JuliaArrayToSyntaxNode ──────────────────────────────────────────────────

struct JuliaArrayToSyntaxNode <: Projection
    delim_font::StyleFont
    delim_color::StyleColor
end
JuliaArrayToSyntaxNode(; delim_font=font_ubuntu_monospace_regular_24, delim_color=color_solarized_gray) =
    JuliaArrayToSyntaxNode(delim_font, delim_color)

function projection_print(p::JuliaArrayToSyntaxNode, recursion, a::JuliaArray, ctx)
    elem_iomaps = Cell(() -> [projection_print(recursion, recursion, e,
                                child_context(ctx, @reference ^(ctx.reference).elements[i]))
                              for (i, e) in enumerate(a.elements)])

    node = SyntaxNode(
        TextString("[", p.delim_font, p.delim_color),
        TextString("]", p.delim_font, p.delim_color),
        TextString(", ", p.delim_font, p.delim_color),
        CellVector(() -> SyntaxDocument[im.output for im in elem_iomaps[]]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, a, node, elem_iomaps)
end

# ── JuliaRangeToSyntaxNode ──────────────────────────────────────────────────

struct JuliaRangeToSyntaxNode <: Projection
    op_font::StyleFont
    op_color::StyleColor
end
JuliaRangeToSyntaxNode(; op_font=font_ubuntu_monospace_regular_24, op_color=color_solarized_cyan) =
    JuliaRangeToSyntaxNode(op_font, op_color)

function projection_print(p::JuliaRangeToSyntaxNode, recursion, r::JuliaRange, ctx)
    start_ref = child_context(ctx, @reference ^(ctx.reference).start)
    step_ref = child_context(ctx, @reference ^(ctx.reference).step)
    stop_ref = child_context(ctx, @reference ^(ctx.reference).stop)

    start_iomap = Cell(() -> projection_print(recursion, recursion, r.start, start_ref))
    stop_iomap = Cell(() -> projection_print(recursion, recursion, r.stop, stop_ref))
    step_iomap = Cell(() -> begin
        s = r.step
        s === nothing ? nothing : projection_print(recursion, recursion, s, step_ref)
    end)

    colon_leaf() = SyntaxLeaf(_empty(p.op_font), _empty(p.op_font),
                              TextString(":", p.op_font, p.op_color), Cell(nothing))

    node = SyntaxNode(
        _empty(p.op_font), _empty(p.op_font), _empty(p.op_font),
        CellVector(() -> begin
            s = r.step
            if s === nothing
                SyntaxDocument[start_iomap[].output, colon_leaf(), stop_iomap[].output]
            else
                SyntaxDocument[start_iomap[].output, colon_leaf(), step_iomap[].output, colon_leaf(), stop_iomap[].output]
            end
        end),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, r, node, Cell(() -> begin
        s = r.step
        if s === nothing
            IoMap[start_iomap[], stop_iomap[]]
        else
            IoMap[start_iomap[], step_iomap[], stop_iomap[]]
        end
    end))
end

# ── JuliaTypeAnnotationToSyntaxNode ─────────────────────────────────────────

struct JuliaTypeAnnotationToSyntaxNode <: Projection
    op_font::StyleFont
    op_color::StyleColor
end
JuliaTypeAnnotationToSyntaxNode(; op_font=font_ubuntu_monospace_regular_24, op_color=color_solarized_cyan) =
    JuliaTypeAnnotationToSyntaxNode(op_font, op_color)

function projection_print(p::JuliaTypeAnnotationToSyntaxNode, recursion, t::JuliaTypeAnnotation, ctx)
    value_ref = child_context(ctx, @reference ^(ctx.reference).value)
    type_ref = child_context(ctx, @reference ^(ctx.reference).type)
    value_iomap = Cell(() -> projection_print(recursion, recursion, t.value, value_ref))
    type_iomap = Cell(() -> projection_print(recursion, recursion, t.type, type_ref))

    dc_leaf = SyntaxLeaf(_empty(p.op_font), _empty(p.op_font),
                         TextString("::", p.op_font, p.op_color), Cell(nothing))

    node = SyntaxNode(
        _empty(p.op_font), _empty(p.op_font), _empty(p.op_font),
        CellVector(() -> SyntaxDocument[value_iomap[].output, dc_leaf, type_iomap[].output]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, t, node, Cell(() -> IoMap[value_iomap[], type_iomap[]]))
end

# ── JuliaAssignmentToSyntaxNode ─────────────────────────────────────────────

struct JuliaAssignmentToSyntaxNode <: Projection
    op_font::StyleFont
    op_color::StyleColor
end
JuliaAssignmentToSyntaxNode(; op_font=font_ubuntu_monospace_regular_24, op_color=color_solarized_cyan) =
    JuliaAssignmentToSyntaxNode(op_font, op_color)

function projection_print(p::JuliaAssignmentToSyntaxNode, recursion, a::JuliaAssignment, ctx)
    target_ref = child_context(ctx, @reference ^(ctx.reference).target)
    value_ref = child_context(ctx, @reference ^(ctx.reference).value)
    target_iomap = Cell(() -> projection_print(recursion, recursion, a.target, target_ref))
    value_iomap = Cell(() -> projection_print(recursion, recursion, a.value, value_ref))

    op_leaf = SyntaxLeaf(
        TextString(" ", p.op_font, color_default),
        TextString(" ", p.op_font, color_default),
        TextString(() -> _julia_operator_string(a.operator), p.op_font, p.op_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.op_font), _empty(p.op_font), _empty(p.op_font),
        CellVector(() -> SyntaxDocument[target_iomap[].output, op_leaf, value_iomap[].output]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, a, node, Cell(() -> IoMap[target_iomap[], value_iomap[]]))
end

# ── JuliaForIteratorToSyntaxNode ────────────────────────────────────────────

struct JuliaForIteratorToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
JuliaForIteratorToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta) =
    JuliaForIteratorToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::JuliaForIteratorToSyntaxNode, recursion, it::JuliaForIterator, ctx)
    var_ref = child_context(ctx, @reference ^(ctx.reference).variable)
    iter_ref = child_context(ctx, @reference ^(ctx.reference).iterable)
    var_iomap = Cell(() -> projection_print(recursion, recursion, it.variable, var_ref))
    iter_iomap = Cell(() -> projection_print(recursion, recursion, it.iterable, iter_ref))

    in_leaf = SyntaxLeaf(
        TextString(" ", p.keyword_font, color_default),
        TextString(" ", p.keyword_font, color_default),
        TextString("in", p.keyword_font, p.keyword_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[var_iomap[].output, in_leaf, iter_iomap[].output]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, it, node, Cell(() -> IoMap[var_iomap[], iter_iomap[]]))
end

# ── JuliaForToSyntaxNode ────────────────────────────────────────────────────

struct JuliaForToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
    delim_font::StyleFont
    delim_color::StyleColor
end
JuliaForToSyntaxNode(;
        keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta,
        delim_font=font_ubuntu_monospace_regular_24, delim_color=color_solarized_gray) =
    JuliaForToSyntaxNode(keyword_font, keyword_color, delim_font, delim_color)

function projection_print(p::JuliaForToSyntaxNode, recursion, f::JuliaFor, ctx)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)
    body_iomap = Cell(() -> projection_print(recursion, recursion, f.body, body_ref))

    iter_iomaps = Cell(() -> [projection_print(recursion, recursion, it,
                                  child_context(ctx, @reference ^(ctx.reference).iterators[i]))
                              for (i, it) in enumerate(f.iterators)])

    for_leaf = SyntaxLeaf(
        _empty(p.keyword_font),
        TextString(" ", p.keyword_font, color_default),
        TextString("for", p.keyword_font, p.keyword_color),
        Cell(nothing))

    iters_node = SyntaxNode(
        _empty(p.delim_font), _empty(p.delim_font),
        TextString(", ", p.delim_font, p.delim_color),
        CellVector(() -> SyntaxDocument[im.output for im in iter_iomaps[]]),
        0, Cell(false), Cell(nothing))

    header_node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[for_leaf, iters_node]),
        0, Cell(false), Cell(nothing))

    end_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("end", p.keyword_font, p.keyword_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[header_node, body_iomap[].output, end_leaf]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, f, node, Cell(() -> IoMap[iter_iomaps[]; body_iomap[]]))
end

# ── JuliaWhileToSyntaxNode ──────────────────────────────────────────────────

struct JuliaWhileToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
JuliaWhileToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta) =
    JuliaWhileToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::JuliaWhileToSyntaxNode, recursion, w::JuliaWhile, ctx)
    cond_ref = child_context(ctx, @reference ^(ctx.reference).condition)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)
    cond_iomap = Cell(() -> projection_print(recursion, recursion, w.condition, cond_ref))
    body_iomap = Cell(() -> projection_print(recursion, recursion, w.body, body_ref))

    while_leaf = SyntaxLeaf(
        _empty(p.keyword_font),
        TextString(" ", p.keyword_font, color_default),
        TextString("while", p.keyword_font, p.keyword_color),
        Cell(nothing))

    header_node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[while_leaf, cond_iomap[].output]),
        0, Cell(false), Cell(nothing))

    end_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("end", p.keyword_font, p.keyword_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[header_node, body_iomap[].output, end_leaf]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, w, node, Cell(() -> IoMap[cond_iomap[], body_iomap[]]))
end

# ── JuliaReturnToSyntaxNode ─────────────────────────────────────────────────

struct JuliaReturnToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
JuliaReturnToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta) =
    JuliaReturnToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::JuliaReturnToSyntaxNode, recursion, r::JuliaReturn, ctx)
    value_ref = child_context(ctx, @reference ^(ctx.reference).value)
    value_iomap = Cell(() -> begin
        v = r.value
        v === nothing ? nothing : projection_print(recursion, recursion, v, value_ref)
    end)

    return_leaf_alone = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("return", p.keyword_font, p.keyword_color),
        Cell(nothing))
    return_leaf_with_value = SyntaxLeaf(
        _empty(p.keyword_font),
        TextString(" ", p.keyword_font, color_default),
        TextString("return", p.keyword_font, p.keyword_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> begin
            v = r.value
            if v === nothing
                SyntaxDocument[return_leaf_alone]
            else
                SyntaxDocument[return_leaf_with_value, value_iomap[].output]
            end
        end),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, r, node, Cell(() -> begin
        v = r.value
        v === nothing ? IoMap[] : IoMap[value_iomap[]]
    end))
end

# ── JuliaBreakToSyntaxLeaf ──────────────────────────────────────────────────

struct JuliaBreakToSyntaxLeaf <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
JuliaBreakToSyntaxLeaf(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta) =
    JuliaBreakToSyntaxLeaf(keyword_font, keyword_color)

function projection_print(p::JuliaBreakToSyntaxLeaf, recursion, b::JuliaBreak, ctx)
    SimpleIoMap(p, b, SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("break", p.keyword_font, p.keyword_color),
        getfield(b, :selection)))
end

# ── JuliaContinueToSyntaxLeaf ───────────────────────────────────────────────

struct JuliaContinueToSyntaxLeaf <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
JuliaContinueToSyntaxLeaf(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta) =
    JuliaContinueToSyntaxLeaf(keyword_font, keyword_color)

function projection_print(p::JuliaContinueToSyntaxLeaf, recursion, c::JuliaContinue, ctx)
    SimpleIoMap(p, c, SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("continue", p.keyword_font, p.keyword_color),
        getfield(c, :selection)))
end

# ── JuliaTryToSyntaxNode ────────────────────────────────────────────────────

struct JuliaTryToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
JuliaTryToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta) =
    JuliaTryToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::JuliaTryToSyntaxNode, recursion, t::JuliaTry, ctx)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)
    catch_var_ref = child_context(ctx, @reference ^(ctx.reference).catch_var)
    catch_branch_ref = child_context(ctx, @reference ^(ctx.reference).catch_branch)
    finally_branch_ref = child_context(ctx, @reference ^(ctx.reference).finally_branch)

    body_iomap = Cell(() -> projection_print(recursion, recursion, t.body, body_ref))
    catch_var_iomap = Cell(() -> begin
        v = t.catch_var
        v === nothing ? nothing : projection_print(recursion, recursion, v, catch_var_ref)
    end)
    catch_branch_iomap = Cell(() -> begin
        v = t.catch_branch
        v === nothing ? nothing : projection_print(recursion, recursion, v, catch_branch_ref)
    end)
    finally_branch_iomap = Cell(() -> begin
        v = t.finally_branch
        v === nothing ? nothing : projection_print(recursion, recursion, v, finally_branch_ref)
    end)

    try_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("try", p.keyword_font, p.keyword_color),
        Cell(nothing))
    catch_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("catch", p.keyword_font, p.keyword_color),
        Cell(nothing))
    catch_leaf_with_var = SyntaxLeaf(
        _empty(p.keyword_font),
        TextString(" ", p.keyword_font, color_default),
        TextString("catch", p.keyword_font, p.keyword_color),
        Cell(nothing))
    finally_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("finally", p.keyword_font, p.keyword_color),
        Cell(nothing))
    end_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("end", p.keyword_font, p.keyword_color),
        Cell(nothing))

    catch_header_alone = catch_leaf
    catch_header_with_var = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[catch_leaf_with_var, catch_var_iomap[].output]),
        0, Cell(false), Cell(nothing))

    node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> begin
            result = SyntaxDocument[try_leaf, body_iomap[].output]
            cb = t.catch_branch
            if cb !== nothing
                header = t.catch_var === nothing ? catch_header_alone : catch_header_with_var
                push!(result, header, catch_branch_iomap[].output)
            end
            fb = t.finally_branch
            if fb !== nothing
                push!(result, finally_leaf, finally_branch_iomap[].output)
            end
            push!(result, end_leaf)
            result
        end),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, t, node, Cell(() -> begin
        result = IoMap[body_iomap[]]
        t.catch_var !== nothing && push!(result, catch_var_iomap[])
        t.catch_branch !== nothing && push!(result, catch_branch_iomap[])
        t.finally_branch !== nothing && push!(result, finally_branch_iomap[])
        result
    end))
end

# ── JuliaBeginToSyntaxNode ──────────────────────────────────────────────────

struct JuliaBeginToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
JuliaBeginToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta) =
    JuliaBeginToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::JuliaBeginToSyntaxNode, recursion, b::JuliaBegin, ctx)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)
    body_iomap = Cell(() -> projection_print(recursion, recursion, b.body, body_ref))

    begin_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("begin", p.keyword_font, p.keyword_color),
        Cell(nothing))
    end_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("end", p.keyword_font, p.keyword_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[begin_leaf, body_iomap[].output, end_leaf]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, b, node, Cell(() -> IoMap[body_iomap[]]))
end

# ── JuliaBlockToSyntaxNode ──────────────────────────────────────────────────

struct JuliaBlockToSyntaxNode <: Projection
    font::StyleFont
    indentation::Int
end
JuliaBlockToSyntaxNode(; font=font_ubuntu_monospace_regular_24, indentation=1) =
    JuliaBlockToSyntaxNode(font, indentation)

function projection_print(p::JuliaBlockToSyntaxNode, recursion, b::JuliaBlock, ctx)
    stmt_iomaps = Cell(() -> [projection_print(recursion, recursion, s,
                                  child_context(ctx, @reference ^(ctx.reference).statements[i]))
                              for (i, s) in enumerate(b.statements)])

    node = SyntaxNode(
        _empty(p.font), _empty(p.font), _empty(p.font),
        CellVector(() -> SyntaxDocument[im.output for im in stmt_iomaps[]]),
        p.indentation, Cell(false), Cell(nothing))
    ChildrenIoMap(p, b, node, stmt_iomaps)
end

# ── JuliaIfToSyntaxNode ─────────────────────────────────────────────────────

struct JuliaIfToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
end
JuliaIfToSyntaxNode(; keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta) =
    JuliaIfToSyntaxNode(keyword_font, keyword_color)

function projection_print(p::JuliaIfToSyntaxNode, recursion, m::JuliaIf, ctx)
    cond_ref = child_context(ctx, @reference ^(ctx.reference).condition)
    then_ref = child_context(ctx, @reference ^(ctx.reference).then_branch)
    else_ref = child_context(ctx, @reference ^(ctx.reference).else_branch)

    cond_iomap = Cell(() -> projection_print(recursion, recursion, m.condition, cond_ref))
    then_iomap = Cell(() -> projection_print(recursion, recursion, m.then_branch, then_ref))
    else_iomap = Cell(() -> projection_print(recursion, recursion, m.else_branch, else_ref))

    if_leaf = SyntaxLeaf(
        _empty(p.keyword_font),
        TextString(" ", p.keyword_font, color_default),
        TextString("if", p.keyword_font, p.keyword_color),
        Cell(nothing))

    header_node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[if_leaf, cond_iomap[].output]),
        0, Cell(false), Cell(nothing))

    else_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("else", p.keyword_font, p.keyword_color),
        Cell(nothing))

    end_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("end", p.keyword_font, p.keyword_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[header_node, then_iomap[].output, else_leaf, else_iomap[].output, end_leaf]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, m, node, Cell(() -> IoMap[cond_iomap[], then_iomap[], else_iomap[]]))
end

# ── JuliaFunctionToSyntaxNode ───────────────────────────────────────────────

struct JuliaFunctionToSyntaxNode <: Projection
    keyword_font::StyleFont
    keyword_color::StyleColor
    delim_font::StyleFont
    delim_color::StyleColor
end
JuliaFunctionToSyntaxNode(;
        keyword_font=font_ubuntu_monospace_bold_24, keyword_color=color_solarized_magenta,
        delim_font=font_ubuntu_monospace_regular_24, delim_color=color_solarized_gray) =
    JuliaFunctionToSyntaxNode(keyword_font, keyword_color, delim_font, delim_color)

function projection_print(p::JuliaFunctionToSyntaxNode, recursion, f::JuliaFunction, ctx)
    name_ref = child_context(ctx, @reference ^(ctx.reference).name)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)

    name_iomap = Cell(() -> projection_print(recursion, recursion, f.name, name_ref))
    body_iomap = Cell(() -> projection_print(recursion, recursion, f.body, body_ref))

    param_iomaps = Cell(() -> [projection_print(recursion, recursion, param,
                                   child_context(ctx, @reference ^(ctx.reference).params[i]))
                               for (i, param) in enumerate(f.params)])

    function_leaf = SyntaxLeaf(
        _empty(p.keyword_font),
        TextString(" ", p.keyword_font, color_default),
        TextString("function", p.keyword_font, p.keyword_color),
        Cell(nothing))

    params_node = SyntaxNode(
        TextString("(", p.delim_font, p.delim_color),
        TextString(")", p.delim_font, p.delim_color),
        TextString(", ", p.delim_font, p.delim_color),
        CellVector(() -> SyntaxDocument[im.output for im in param_iomaps[]]),
        0, Cell(false), Cell(nothing))

    header_node = SyntaxNode(
        _empty(p.delim_font), _empty(p.delim_font), _empty(p.delim_font),
        CellVector(() -> SyntaxDocument[function_leaf, name_iomap[].output, params_node]),
        0, Cell(false), Cell(nothing))

    end_leaf = SyntaxLeaf(
        _empty(p.keyword_font), _empty(p.keyword_font),
        TextString("end", p.keyword_font, p.keyword_color),
        Cell(nothing))

    node = SyntaxNode(
        _empty(p.keyword_font), _empty(p.keyword_font), _empty(p.keyword_font),
        CellVector(() -> SyntaxDocument[header_node, body_iomap[].output, end_leaf]),
        0, Cell(false), Cell(nothing))
    ChildrenIoMap(p, f, node, Cell(() -> IoMap[name_iomap[]; param_iomaps[]; body_iomap[]]))
end

# ── JuliaToSyntax (composite) ───────────────────────────────────────────────

function JuliaToSyntax()
    TypeDispatchingProjection(
        JuliaIdentifier      => JuliaIdentifierToSyntaxLeaf(),
        JuliaInteger         => JuliaIntegerToSyntaxLeaf(),
        JuliaFloat           => JuliaFloatToSyntaxLeaf(),
        JuliaString          => JuliaStringToSyntaxLeaf(),
        JuliaBool            => JuliaBoolToSyntaxLeaf(),
        JuliaNothing         => JuliaNothingToSyntaxLeaf(),
        JuliaSymbol          => JuliaSymbolToSyntaxLeaf(),
        JuliaChar            => JuliaCharToSyntaxLeaf(),
        JuliaBinaryOp        => JuliaBinaryOpToSyntaxNode(),
        JuliaUnaryOp         => JuliaUnaryOpToSyntaxNode(),
        JuliaCall            => JuliaCallToSyntaxNode(),
        JuliaTernary         => JuliaTernaryToSyntaxNode(),
        JuliaIndex           => JuliaIndexToSyntaxNode(),
        JuliaFieldAccess     => JuliaFieldAccessToSyntaxNode(),
        JuliaTuple           => JuliaTupleToSyntaxNode(),
        JuliaArray           => JuliaArrayToSyntaxNode(),
        JuliaRange           => JuliaRangeToSyntaxNode(),
        JuliaTypeAnnotation  => JuliaTypeAnnotationToSyntaxNode(),
        JuliaAssignment      => JuliaAssignmentToSyntaxNode(),
        JuliaForIterator     => JuliaForIteratorToSyntaxNode(),
        JuliaFor             => JuliaForToSyntaxNode(),
        JuliaWhile           => JuliaWhileToSyntaxNode(),
        JuliaReturn          => JuliaReturnToSyntaxNode(),
        JuliaBreak           => JuliaBreakToSyntaxLeaf(),
        JuliaContinue        => JuliaContinueToSyntaxLeaf(),
        JuliaTry             => JuliaTryToSyntaxNode(),
        JuliaBegin           => JuliaBeginToSyntaxNode(),
        JuliaBlock           => JuliaBlockToSyntaxNode(),
        JuliaIf              => JuliaIfToSyntaxNode(),
        JuliaFunction        => JuliaFunctionToSyntaxNode(),
    )
end

end # module
