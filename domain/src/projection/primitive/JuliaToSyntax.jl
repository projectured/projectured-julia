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
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read, map_reference_forward, map_reference_backward, Projection
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
import ..StyleTextModule: StyleText
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
    style::StyleText
end
JuliaIdentifierToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_blue)) =
    JuliaIdentifierToSyntaxLeaf(style)

function projection_print(p::JuliaIdentifierToSyntaxLeaf, recursion, v::JuliaIdentifier, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(() -> v.name, p.style);
        selection=getfield(v, :selection)))
end

# ── JuliaIntegerToSyntaxLeaf ────────────────────────────────────────────────

struct JuliaIntegerToSyntaxLeaf <: Projection
    style::StyleText
end
JuliaIntegerToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)) =
    JuliaIntegerToSyntaxLeaf(style)

function projection_print(p::JuliaIntegerToSyntaxLeaf, recursion, v::JuliaInteger, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(() -> string(v.value), p.style);
        selection=getfield(v, :selection)))
end

# ── JuliaFloatToSyntaxLeaf ──────────────────────────────────────────────────

struct JuliaFloatToSyntaxLeaf <: Projection
    style::StyleText
end
JuliaFloatToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)) =
    JuliaFloatToSyntaxLeaf(style)

function projection_print(p::JuliaFloatToSyntaxLeaf, recursion, v::JuliaFloat, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(() -> string(v.value), p.style);
        selection=getfield(v, :selection)))
end

# ── JuliaStringToSyntaxLeaf ─────────────────────────────────────────────────

struct JuliaStringToSyntaxLeaf <: Projection
    style::StyleText
    quote_style::StyleText
end
JuliaStringToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_green),
                          quote_style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JuliaStringToSyntaxLeaf(style, quote_style)

function projection_print(p::JuliaStringToSyntaxLeaf, recursion, v::JuliaString, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(() -> v.value, p.style);
        open=TextString("\"", p.quote_style),
        close=TextString("\"", p.quote_style),
        selection=getfield(v, :selection)))
end

# ── JuliaBoolToSyntaxLeaf ───────────────────────────────────────────────────

struct JuliaBoolToSyntaxLeaf <: Projection
    style::StyleText
end
JuliaBoolToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaBoolToSyntaxLeaf(style)

function projection_print(p::JuliaBoolToSyntaxLeaf, recursion, v::JuliaBool, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(() -> v.value ? "true" : "false", p.style);
        selection=getfield(v, :selection)))
end

# ── JuliaNothingToSyntaxLeaf ────────────────────────────────────────────────

struct JuliaNothingToSyntaxLeaf <: Projection
    style::StyleText
end
JuliaNothingToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaNothingToSyntaxLeaf(style)

function projection_print(p::JuliaNothingToSyntaxLeaf, recursion, v::JuliaNothing, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString("nothing", p.style);
        selection=getfield(v, :selection)))
end

# ── JuliaSymbolToSyntaxLeaf ─────────────────────────────────────────────────

struct JuliaSymbolToSyntaxLeaf <: Projection
    style::StyleText
end
JuliaSymbolToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_magenta)) =
    JuliaSymbolToSyntaxLeaf(style)

function projection_print(p::JuliaSymbolToSyntaxLeaf, recursion, v::JuliaSymbol, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(() -> v.name, p.style);
        open=TextString(":", p.style),
        selection=getfield(v, :selection)))
end

# ── JuliaCharToSyntaxLeaf ───────────────────────────────────────────────────

struct JuliaCharToSyntaxLeaf <: Projection
    style::StyleText
    quote_style::StyleText
end
JuliaCharToSyntaxLeaf(; style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_green),
                        quote_style=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JuliaCharToSyntaxLeaf(style, quote_style)

function projection_print(p::JuliaCharToSyntaxLeaf, recursion, v::JuliaChar, ctx)
    SimpleIoMap(p, v, SyntaxLeaf(
        TextString(() -> string(v.value), p.style);
        open=TextString("'", p.quote_style),
        close=TextString("'", p.quote_style),
        selection=getfield(v, :selection)))
end

# ── JuliaBinaryOpToSyntaxNode ───────────────────────────────────────────────

struct JuliaBinaryOpToSyntaxNode <: Projection
    op::StyleText
end
JuliaBinaryOpToSyntaxNode(; op=StyleText(font_ubuntu_monospace_regular_24, color_solarized_cyan)) =
    JuliaBinaryOpToSyntaxNode(op)

function projection_print(p::JuliaBinaryOpToSyntaxNode, recursion, m::JuliaBinaryOp, ctx)
    left_ref = child_context(ctx, @reference ^(ctx.reference).left)
    right_ref = child_context(ctx, @reference ^(ctx.reference).right)
    left_iomap = Cell(() -> projection_printer_recurse(recursion, m.left, left_ref))
    right_iomap = Cell(() -> projection_printer_recurse(recursion, m.right, right_ref))

    op_leaf = SyntaxLeaf(
        TextString(() -> _julia_operator_string(m.operator), p.op);
        open=TextString(" ", p.op.font, color_default),
        close=TextString(" ", p.op.font, color_default))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[left_iomap[].output, op_leaf, right_iomap[].output]))
    ChildrenIoMap(p, m, node, Cell(() -> IoMap[left_iomap[], right_iomap[]]))
end

# ── JuliaUnaryOpToSyntaxNode ────────────────────────────────────────────────

struct JuliaUnaryOpToSyntaxNode <: Projection
    op::StyleText
end
JuliaUnaryOpToSyntaxNode(; op=StyleText(font_ubuntu_monospace_regular_24, color_solarized_cyan)) =
    JuliaUnaryOpToSyntaxNode(op)

function projection_print(p::JuliaUnaryOpToSyntaxNode, recursion, u::JuliaUnaryOp, ctx)
    operand_ref = child_context(ctx, @reference ^(ctx.reference).operand)
    operand_iomap = Cell(() -> projection_printer_recurse(recursion, u.operand, operand_ref))

    op_leaf = SyntaxLeaf(
        TextString(() -> _julia_operator_string(u.operator), p.op))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[op_leaf, operand_iomap[].output]))
    ChildrenIoMap(p, u, node, Cell(() -> IoMap[operand_iomap[]]))
end

# ── JuliaCallToSyntaxNode ───────────────────────────────────────────────────

struct JuliaCallToSyntaxNode <: Projection
    delim::StyleText
end
JuliaCallToSyntaxNode(; delim=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JuliaCallToSyntaxNode(delim)

function projection_print(p::JuliaCallToSyntaxNode, recursion, c::JuliaCall, ctx)
    callee_ref = child_context(ctx, @reference ^(ctx.reference).callee)
    callee_iomap = Cell(() -> projection_printer_recurse(recursion, c.callee, callee_ref))

    arg_iomaps = Cell(() -> [projection_printer_recurse(recursion, arg,
                                child_context(ctx, @reference ^(ctx.reference).arguments[i]))
                             for (i, arg) in enumerate(c.arguments)])

    args_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in arg_iomaps[]]);
        open=TextString("(", p.delim),
        close=TextString(")", p.delim),
        sep=TextString(", ", p.delim))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[callee_iomap[].output, args_node]))
    ChildrenIoMap(p, c, node, Cell(() -> IoMap[callee_iomap[]; arg_iomaps[]]))
end

# ── JuliaTernaryToSyntaxNode ────────────────────────────────────────────────

struct JuliaTernaryToSyntaxNode <: Projection
    op::StyleText
end
JuliaTernaryToSyntaxNode(; op=StyleText(font_ubuntu_monospace_regular_24, color_solarized_cyan)) =
    JuliaTernaryToSyntaxNode(op)

function projection_print(p::JuliaTernaryToSyntaxNode, recursion, t::JuliaTernary, ctx)
    cond_ref = child_context(ctx, @reference ^(ctx.reference).condition)
    then_ref = child_context(ctx, @reference ^(ctx.reference).then_branch)
    else_ref = child_context(ctx, @reference ^(ctx.reference).else_branch)

    cond_iomap = Cell(() -> projection_printer_recurse(recursion, t.condition, cond_ref))
    then_iomap = Cell(() -> projection_printer_recurse(recursion, t.then_branch, then_ref))
    else_iomap = Cell(() -> projection_printer_recurse(recursion, t.else_branch, else_ref))

    q_leaf = SyntaxLeaf(
        TextString("?", p.op);
        open=TextString(" ", p.op.font, color_default),
        close=TextString(" ", p.op.font, color_default))
    c_leaf = SyntaxLeaf(
        TextString(":", p.op);
        open=TextString(" ", p.op.font, color_default),
        close=TextString(" ", p.op.font, color_default))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[cond_iomap[].output, q_leaf, then_iomap[].output, c_leaf, else_iomap[].output]))
    ChildrenIoMap(p, t, node, Cell(() -> IoMap[cond_iomap[], then_iomap[], else_iomap[]]))
end

# ── JuliaIndexToSyntaxNode ──────────────────────────────────────────────────

struct JuliaIndexToSyntaxNode <: Projection
    delim::StyleText
end
JuliaIndexToSyntaxNode(; delim=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JuliaIndexToSyntaxNode(delim)

function projection_print(p::JuliaIndexToSyntaxNode, recursion, x::JuliaIndex, ctx)
    coll_ref = child_context(ctx, @reference ^(ctx.reference).collection)
    coll_iomap = Cell(() -> projection_printer_recurse(recursion, x.collection, coll_ref))

    idx_iomaps = Cell(() -> [projection_printer_recurse(recursion, ix,
                                child_context(ctx, @reference ^(ctx.reference).indices[i]))
                             for (i, ix) in enumerate(x.indices)])

    idx_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in idx_iomaps[]]);
        open=TextString("[", p.delim),
        close=TextString("]", p.delim),
        sep=TextString(", ", p.delim))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[coll_iomap[].output, idx_node]))
    ChildrenIoMap(p, x, node, Cell(() -> IoMap[coll_iomap[]; idx_iomaps[]]))
end

# ── JuliaFieldAccessToSyntaxNode ────────────────────────────────────────────

struct JuliaFieldAccessToSyntaxNode <: Projection
    dot::StyleText
end
JuliaFieldAccessToSyntaxNode(; dot=StyleText(font_ubuntu_monospace_regular_24, color_solarized_cyan)) =
    JuliaFieldAccessToSyntaxNode(dot)

function projection_print(p::JuliaFieldAccessToSyntaxNode, recursion, f::JuliaFieldAccess, ctx)
    object_ref = child_context(ctx, @reference ^(ctx.reference).object)
    field_ref = child_context(ctx, @reference ^(ctx.reference).field)
    object_iomap = Cell(() -> projection_printer_recurse(recursion, f.object, object_ref))
    field_iomap = Cell(() -> projection_printer_recurse(recursion, f.field, field_ref))

    dot_leaf = SyntaxLeaf(TextString(".", p.dot))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[object_iomap[].output, dot_leaf, field_iomap[].output]))
    ChildrenIoMap(p, f, node, Cell(() -> IoMap[object_iomap[], field_iomap[]]))
end

# ── JuliaTupleToSyntaxNode ──────────────────────────────────────────────────

struct JuliaTupleToSyntaxNode <: Projection
    delim::StyleText
end
JuliaTupleToSyntaxNode(; delim=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JuliaTupleToSyntaxNode(delim)

function projection_print(p::JuliaTupleToSyntaxNode, recursion, t::JuliaTuple, ctx)
    elem_iomaps = Cell(() -> [projection_printer_recurse(recursion, e,
                                child_context(ctx, @reference ^(ctx.reference).elements[i]))
                              for (i, e) in enumerate(t.elements)])

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in elem_iomaps[]]);
        open=TextString("(", p.delim),
        close=TextString(")", p.delim),
        sep=TextString(", ", p.delim))
    ChildrenIoMap(p, t, node, elem_iomaps)
end

# ── JuliaArrayToSyntaxNode ──────────────────────────────────────────────────

struct JuliaArrayToSyntaxNode <: Projection
    delim::StyleText
end
JuliaArrayToSyntaxNode(; delim=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JuliaArrayToSyntaxNode(delim)

function projection_print(p::JuliaArrayToSyntaxNode, recursion, a::JuliaArray, ctx)
    elem_iomaps = Cell(() -> [projection_printer_recurse(recursion, e,
                                child_context(ctx, @reference ^(ctx.reference).elements[i]))
                              for (i, e) in enumerate(a.elements)])

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in elem_iomaps[]]);
        open=TextString("[", p.delim),
        close=TextString("]", p.delim),
        sep=TextString(", ", p.delim))
    ChildrenIoMap(p, a, node, elem_iomaps)
end

# ── JuliaRangeToSyntaxNode ──────────────────────────────────────────────────

struct JuliaRangeToSyntaxNode <: Projection
    op::StyleText
end
JuliaRangeToSyntaxNode(; op=StyleText(font_ubuntu_monospace_regular_24, color_solarized_cyan)) =
    JuliaRangeToSyntaxNode(op)

function projection_print(p::JuliaRangeToSyntaxNode, recursion, r::JuliaRange, ctx)
    start_ref = child_context(ctx, @reference ^(ctx.reference).start)
    step_ref = child_context(ctx, @reference ^(ctx.reference).step)
    stop_ref = child_context(ctx, @reference ^(ctx.reference).stop)

    start_iomap = Cell(() -> projection_printer_recurse(recursion, r.start, start_ref))
    stop_iomap = Cell(() -> projection_printer_recurse(recursion, r.stop, stop_ref))
    step_iomap = Cell(() -> begin
        s = r.step
        s === nothing ? nothing : projection_printer_recurse(recursion, s, step_ref)
    end)

    colon_leaf() = SyntaxLeaf(TextString(":", p.op))

    node = SyntaxNode(
        CellVector(() -> begin
            s = r.step
            if s === nothing
                SyntaxDocument[start_iomap[].output, colon_leaf(), stop_iomap[].output]
            else
                SyntaxDocument[start_iomap[].output, colon_leaf(), step_iomap[].output, colon_leaf(), stop_iomap[].output]
            end
        end))
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
    op::StyleText
end
JuliaTypeAnnotationToSyntaxNode(; op=StyleText(font_ubuntu_monospace_regular_24, color_solarized_cyan)) =
    JuliaTypeAnnotationToSyntaxNode(op)

function projection_print(p::JuliaTypeAnnotationToSyntaxNode, recursion, t::JuliaTypeAnnotation, ctx)
    value_ref = child_context(ctx, @reference ^(ctx.reference).value)
    type_ref = child_context(ctx, @reference ^(ctx.reference).type)
    value_iomap = Cell(() -> projection_printer_recurse(recursion, t.value, value_ref))
    type_iomap = Cell(() -> projection_printer_recurse(recursion, t.type, type_ref))

    dc_leaf = SyntaxLeaf(TextString("::", p.op))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[value_iomap[].output, dc_leaf, type_iomap[].output]))
    ChildrenIoMap(p, t, node, Cell(() -> IoMap[value_iomap[], type_iomap[]]))
end

# ── JuliaAssignmentToSyntaxNode ─────────────────────────────────────────────

struct JuliaAssignmentToSyntaxNode <: Projection
    op::StyleText
end
JuliaAssignmentToSyntaxNode(; op=StyleText(font_ubuntu_monospace_regular_24, color_solarized_cyan)) =
    JuliaAssignmentToSyntaxNode(op)

function projection_print(p::JuliaAssignmentToSyntaxNode, recursion, a::JuliaAssignment, ctx)
    target_ref = child_context(ctx, @reference ^(ctx.reference).target)
    value_ref = child_context(ctx, @reference ^(ctx.reference).value)
    target_iomap = Cell(() -> projection_printer_recurse(recursion, a.target, target_ref))
    value_iomap = Cell(() -> projection_printer_recurse(recursion, a.value, value_ref))

    op_leaf = SyntaxLeaf(
        TextString(() -> _julia_operator_string(a.operator), p.op);
        open=TextString(" ", p.op.font, color_default),
        close=TextString(" ", p.op.font, color_default))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[target_iomap[].output, op_leaf, value_iomap[].output]))
    ChildrenIoMap(p, a, node, Cell(() -> IoMap[target_iomap[], value_iomap[]]))
end

# ── JuliaForIteratorToSyntaxNode ────────────────────────────────────────────

struct JuliaForIteratorToSyntaxNode <: Projection
    keyword::StyleText
end
JuliaForIteratorToSyntaxNode(; keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaForIteratorToSyntaxNode(keyword)

function projection_print(p::JuliaForIteratorToSyntaxNode, recursion, it::JuliaForIterator, ctx)
    var_ref = child_context(ctx, @reference ^(ctx.reference).variable)
    iter_ref = child_context(ctx, @reference ^(ctx.reference).iterable)
    var_iomap = Cell(() -> projection_printer_recurse(recursion, it.variable, var_ref))
    iter_iomap = Cell(() -> projection_printer_recurse(recursion, it.iterable, iter_ref))

    in_leaf = SyntaxLeaf(
        TextString("in", p.keyword);
        open=TextString(" ", p.keyword.font, color_default),
        close=TextString(" ", p.keyword.font, color_default))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[var_iomap[].output, in_leaf, iter_iomap[].output]))
    ChildrenIoMap(p, it, node, Cell(() -> IoMap[var_iomap[], iter_iomap[]]))
end

# ── JuliaForToSyntaxNode ────────────────────────────────────────────────────

struct JuliaForToSyntaxNode <: Projection
    keyword::StyleText
    delim::StyleText
end
JuliaForToSyntaxNode(;
        keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta),
        delim=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JuliaForToSyntaxNode(keyword, delim)

function projection_print(p::JuliaForToSyntaxNode, recursion, f::JuliaFor, ctx)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)
    body_iomap = Cell(() -> projection_printer_recurse(recursion, f.body, body_ref))

    iter_iomaps = Cell(() -> [projection_printer_recurse(recursion, it,
                                  child_context(ctx, @reference ^(ctx.reference).iterators[i]))
                              for (i, it) in enumerate(f.iterators)])

    for_leaf = SyntaxLeaf(
        TextString("for", p.keyword);
        close=TextString(" ", p.keyword.font, color_default))

    iters_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in iter_iomaps[]]);
        sep=TextString(", ", p.delim))

    header_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[for_leaf, iters_node]))

    end_leaf = SyntaxLeaf(TextString("end", p.keyword))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[header_node, body_iomap[].output, end_leaf]))
    ChildrenIoMap(p, f, node, Cell(() -> IoMap[iter_iomaps[]; body_iomap[]]))
end

# ── JuliaWhileToSyntaxNode ──────────────────────────────────────────────────

struct JuliaWhileToSyntaxNode <: Projection
    keyword::StyleText
end
JuliaWhileToSyntaxNode(; keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaWhileToSyntaxNode(keyword)

function projection_print(p::JuliaWhileToSyntaxNode, recursion, w::JuliaWhile, ctx)
    cond_ref = child_context(ctx, @reference ^(ctx.reference).condition)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)
    cond_iomap = Cell(() -> projection_printer_recurse(recursion, w.condition, cond_ref))
    body_iomap = Cell(() -> projection_printer_recurse(recursion, w.body, body_ref))

    while_leaf = SyntaxLeaf(
        TextString("while", p.keyword);
        close=TextString(" ", p.keyword.font, color_default))

    header_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[while_leaf, cond_iomap[].output]))

    end_leaf = SyntaxLeaf(TextString("end", p.keyword))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[header_node, body_iomap[].output, end_leaf]))
    ChildrenIoMap(p, w, node, Cell(() -> IoMap[cond_iomap[], body_iomap[]]))
end

# ── JuliaReturnToSyntaxNode ─────────────────────────────────────────────────

struct JuliaReturnToSyntaxNode <: Projection
    keyword::StyleText
end
JuliaReturnToSyntaxNode(; keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaReturnToSyntaxNode(keyword)

function projection_print(p::JuliaReturnToSyntaxNode, recursion, r::JuliaReturn, ctx)
    value_ref = child_context(ctx, @reference ^(ctx.reference).value)
    value_iomap = Cell(() -> begin
        v = r.value
        v === nothing ? nothing : projection_printer_recurse(recursion, v, value_ref)
    end)

    return_leaf_alone = SyntaxLeaf(TextString("return", p.keyword))
    return_leaf_with_value = SyntaxLeaf(
        TextString("return", p.keyword);
        close=TextString(" ", p.keyword.font, color_default))

    node = SyntaxNode(
        CellVector(() -> begin
            v = r.value
            if v === nothing
                SyntaxDocument[return_leaf_alone]
            else
                SyntaxDocument[return_leaf_with_value, value_iomap[].output]
            end
        end))
    ChildrenIoMap(p, r, node, Cell(() -> begin
        v = r.value
        v === nothing ? IoMap[] : IoMap[value_iomap[]]
    end))
end

# ── JuliaBreakToSyntaxLeaf ──────────────────────────────────────────────────

struct JuliaBreakToSyntaxLeaf <: Projection
    keyword::StyleText
end
JuliaBreakToSyntaxLeaf(; keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaBreakToSyntaxLeaf(keyword)

function projection_print(p::JuliaBreakToSyntaxLeaf, recursion, b::JuliaBreak, ctx)
    SimpleIoMap(p, b, SyntaxLeaf(
        TextString("break", p.keyword);
        selection=getfield(b, :selection)))
end

# ── JuliaContinueToSyntaxLeaf ───────────────────────────────────────────────

struct JuliaContinueToSyntaxLeaf <: Projection
    keyword::StyleText
end
JuliaContinueToSyntaxLeaf(; keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaContinueToSyntaxLeaf(keyword)

function projection_print(p::JuliaContinueToSyntaxLeaf, recursion, c::JuliaContinue, ctx)
    SimpleIoMap(p, c, SyntaxLeaf(
        TextString("continue", p.keyword);
        selection=getfield(c, :selection)))
end

# ── JuliaTryToSyntaxNode ────────────────────────────────────────────────────

struct JuliaTryToSyntaxNode <: Projection
    keyword::StyleText
end
JuliaTryToSyntaxNode(; keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaTryToSyntaxNode(keyword)

function projection_print(p::JuliaTryToSyntaxNode, recursion, t::JuliaTry, ctx)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)
    catch_var_ref = child_context(ctx, @reference ^(ctx.reference).catch_var)
    catch_branch_ref = child_context(ctx, @reference ^(ctx.reference).catch_branch)
    finally_branch_ref = child_context(ctx, @reference ^(ctx.reference).finally_branch)

    body_iomap = Cell(() -> projection_printer_recurse(recursion, t.body, body_ref))
    catch_var_iomap = Cell(() -> begin
        v = t.catch_var
        v === nothing ? nothing : projection_printer_recurse(recursion, v, catch_var_ref)
    end)
    catch_branch_iomap = Cell(() -> begin
        v = t.catch_branch
        v === nothing ? nothing : projection_printer_recurse(recursion, v, catch_branch_ref)
    end)
    finally_branch_iomap = Cell(() -> begin
        v = t.finally_branch
        v === nothing ? nothing : projection_printer_recurse(recursion, v, finally_branch_ref)
    end)

    try_leaf = SyntaxLeaf(TextString("try", p.keyword))
    catch_leaf = SyntaxLeaf(TextString("catch", p.keyword))
    catch_leaf_with_var = SyntaxLeaf(
        TextString("catch", p.keyword);
        close=TextString(" ", p.keyword.font, color_default))
    finally_leaf = SyntaxLeaf(TextString("finally", p.keyword))
    end_leaf = SyntaxLeaf(TextString("end", p.keyword))

    catch_header_alone = catch_leaf
    catch_header_with_var = SyntaxNode(
        CellVector(() -> SyntaxDocument[catch_leaf_with_var, catch_var_iomap[].output]))

    node = SyntaxNode(
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
        end))
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
    keyword::StyleText
end
JuliaBeginToSyntaxNode(; keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaBeginToSyntaxNode(keyword)

function projection_print(p::JuliaBeginToSyntaxNode, recursion, b::JuliaBegin, ctx)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)
    body_iomap = Cell(() -> projection_printer_recurse(recursion, b.body, body_ref))

    begin_leaf = SyntaxLeaf(TextString("begin", p.keyword))
    end_leaf = SyntaxLeaf(TextString("end", p.keyword))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[begin_leaf, body_iomap[].output, end_leaf]))
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
    stmt_iomaps = Cell(() -> [projection_printer_recurse(recursion, s,
                                  child_context(ctx, @reference ^(ctx.reference).statements[i]))
                              for (i, s) in enumerate(b.statements)])

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in stmt_iomaps[]]);
        indentation=p.indentation)
    ChildrenIoMap(p, b, node, stmt_iomaps)
end

# ── JuliaIfToSyntaxNode ─────────────────────────────────────────────────────

struct JuliaIfToSyntaxNode <: Projection
    keyword::StyleText
end
JuliaIfToSyntaxNode(; keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta)) =
    JuliaIfToSyntaxNode(keyword)

function projection_print(p::JuliaIfToSyntaxNode, recursion, m::JuliaIf, ctx)
    cond_ref = child_context(ctx, @reference ^(ctx.reference).condition)
    then_ref = child_context(ctx, @reference ^(ctx.reference).then_branch)
    else_ref = child_context(ctx, @reference ^(ctx.reference).else_branch)

    cond_iomap = Cell(() -> projection_printer_recurse(recursion, m.condition, cond_ref))
    then_iomap = Cell(() -> projection_printer_recurse(recursion, m.then_branch, then_ref))
    else_iomap = Cell(() -> projection_printer_recurse(recursion, m.else_branch, else_ref))

    if_leaf = SyntaxLeaf(
        TextString("if", p.keyword);
        close=TextString(" ", p.keyword.font, color_default))

    header_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[if_leaf, cond_iomap[].output]))

    else_leaf = SyntaxLeaf(TextString("else", p.keyword))

    end_leaf = SyntaxLeaf(TextString("end", p.keyword))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[header_node, then_iomap[].output, else_leaf, else_iomap[].output, end_leaf]))
    ChildrenIoMap(p, m, node, Cell(() -> IoMap[cond_iomap[], then_iomap[], else_iomap[]]))
end

# ── JuliaFunctionToSyntaxNode ───────────────────────────────────────────────

struct JuliaFunctionToSyntaxNode <: Projection
    keyword::StyleText
    delim::StyleText
end
JuliaFunctionToSyntaxNode(;
        keyword=StyleText(font_ubuntu_monospace_bold_24, color_solarized_magenta),
        delim=StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)) =
    JuliaFunctionToSyntaxNode(keyword, delim)

function projection_print(p::JuliaFunctionToSyntaxNode, recursion, f::JuliaFunction, ctx)
    name_ref = child_context(ctx, @reference ^(ctx.reference).name)
    body_ref = child_context(ctx, @reference ^(ctx.reference).body)

    name_iomap = Cell(() -> projection_printer_recurse(recursion, f.name, name_ref))
    body_iomap = Cell(() -> projection_printer_recurse(recursion, f.body, body_ref))

    param_iomaps = Cell(() -> [projection_printer_recurse(recursion, param,
                                   child_context(ctx, @reference ^(ctx.reference).params[i]))
                               for (i, param) in enumerate(f.params)])

    function_leaf = SyntaxLeaf(
        TextString("function", p.keyword);
        close=TextString(" ", p.keyword.font, color_default))

    params_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in param_iomaps[]]);
        open=TextString("(", p.delim),
        close=TextString(")", p.delim),
        sep=TextString(", ", p.delim))

    header_node = SyntaxNode(
        CellVector(() -> SyntaxDocument[function_leaf, name_iomap[].output, params_node]))

    end_leaf = SyntaxLeaf(TextString("end", p.keyword))

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[header_node, body_iomap[].output, end_leaf]))
    ChildrenIoMap(p, f, node, Cell(() -> IoMap[name_iomap[]; param_iomaps[]; body_iomap[]]))
end

# ── Reference mapping & readers (deferred) ──────────────────────────────────
#
# None of the sub-projections above define `map_reference_forward`,
# `map_reference_backward`, or `projection_read`, so each falls through to the
# generic `Projection` defaults in common/Projection.jl: the node printers store
# `Cell(nothing)` for the output selection, and the default backward mapper wraps
# an output reference in a `proj(p, …)` step rather than translating it into a
# Julia-domain path. Consequence: a selection can be set and round-tripped at the
# projection-wrapped / whole-element granularity (which is what keeps
# `test_text_navigation(julia_example)` green), but the cursor does NOT map
# bidirectionally into nested Julia content (this is the High finding in
# plan/pending/consistency-report.md, §D).
#
# Per-node School-A mappers (delegating through the stored child IoMaps, like
# JsonToSyntax) are the eventual fix, but content mappers alone are not enough:
# the Julia syntax is dense with projection-introduced structural tokens
# (`function`, `(`, `)`, `==`, `*`, `-`, `if`, `else`, `end`, …) that have no
# Julia pre-image, so keyboard navigation can only traverse *through* them with
# the flat-offset projection-reference machinery that JsonToSyntax carries
# (`_syntax_to_flat`). Wiring that for Julia is a dedicated follow-up; until then
# the reference maps are intentionally left on the generic defaults.

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
