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
import ..ProjectionModule: var"@projection"
import ..JuliaModule: JuliaDocument,
                      JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool,
                      JuliaNothing, JuliaSymbol, JuliaChar,
                      JuliaBinaryOp, JuliaUnaryOp, JuliaCall, JuliaTernary,
                      JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange,
                      JuliaTypeAnnotation,
                      JuliaAssignment, JuliaFor, JuliaForIterator, JuliaWhile,
                      JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry, JuliaBegin,
                      JuliaIf, JuliaFunction, JuliaBlock, JuliaUsing, JuliaLambda, JuliaInsertion, _julia_operator_string
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_cyan,
                      color_solarized_green, color_solarized_magenta, color_solarized_gray,
                      color_solarized_violet
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..DocumentInsertionToSyntaxModule: JuliaInsertionToSyntaxLeaf
import ..IoMapModule: ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference,
                          FieldReference, ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceBuilderModule: var"@reference"
import ..ProjectionTemplateModule: var"@projection_template", project, collection
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
       JuliaUsingToSyntaxNode, JuliaLambdaToSyntaxNode,
       JuliaToSyntax

# ── JuliaIdentifierToSyntaxLeaf ─────────────────────────────────────────────

# A standalone identifier is a *variable* reference — rendered in a distinct
# variable colour (violet), separate from keywords (magenta), function names
# (blue, applied by `JuliaCallToSyntaxNode`), literals (green) and operators.
@projection struct JuliaIdentifierToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
end

@projection_template JuliaIdentifierToSyntaxLeaf JuliaIdentifier (p, v) ->
    SyntaxLeaf(TextString(() -> v.name, p.style))

# ── JuliaIntegerToSyntaxLeaf ────────────────────────────────────────────────

@projection struct JuliaIntegerToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template JuliaIntegerToSyntaxLeaf JuliaInteger (p, v) ->
    SyntaxLeaf(TextString(() -> string(v.value), p.style))

# ── JuliaFloatToSyntaxLeaf ──────────────────────────────────────────────────

@projection struct JuliaFloatToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template JuliaFloatToSyntaxLeaf JuliaFloat (p, v) ->
    SyntaxLeaf(TextString(() -> string(v.value), p.style))

# ── JuliaStringToSyntaxLeaf ─────────────────────────────────────────────────

@projection struct JuliaStringToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaStringToSyntaxLeaf JuliaString (p, v) ->
    SyntaxLeaf(TextString(() -> v.value, p.style);
               open=TextString("\"", p.quote_style),
               close=TextString("\"", p.quote_style))

# ── JuliaBoolToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JuliaBoolToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaBoolToSyntaxLeaf JuliaBool (p, v) ->
    SyntaxLeaf(TextString(() -> v.value ? "true" : "false", p.style))

# ── JuliaNothingToSyntaxLeaf ────────────────────────────────────────────────

@projection struct JuliaNothingToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaNothingToSyntaxLeaf JuliaNothing (p, v) ->
    SyntaxLeaf(TextString("nothing", p.style))

# ── JuliaSymbolToSyntaxLeaf ─────────────────────────────────────────────────

@projection struct JuliaSymbolToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JuliaSymbolToSyntaxLeaf JuliaSymbol (p, v) ->
    SyntaxLeaf(TextString(() -> v.name, p.style);
               open=TextString(":", p.style))

# ── JuliaCharToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JuliaCharToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_style::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaCharToSyntaxLeaf JuliaChar (p, v) ->
    SyntaxLeaf(TextString(() -> string(v.value), p.style);
               open=TextString("'", p.quote_style),
               close=TextString("'", p.quote_style))

# ── JuliaBinaryOpToSyntaxNode ───────────────────────────────────────────────

@projection struct JuliaBinaryOpToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaBinaryOpToSyntaxNode JuliaBinaryOp (p, m) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ project(:left),
                 SyntaxLeaf(TextString(() -> _julia_operator_string(m.operator), p.op);
                            open=TextString(" ", p.op.font, color_default),
                            close=TextString(" ", p.op.font, color_default)),
                 project(:right) ],
               0, false, nothing)

# ── JuliaUnaryOpToSyntaxNode ────────────────────────────────────────────────

@projection struct JuliaUnaryOpToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaUnaryOpToSyntaxNode JuliaUnaryOp (p, u) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ SyntaxLeaf(TextString(() -> _julia_operator_string(u.operator), p.op)),
                 project(:operand) ],
               0, false, nothing)

# ── JuliaCallToSyntaxNode ───────────────────────────────────────────────────

@projection struct JuliaCallToSyntaxNode
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    # A call's function name is coloured distinctly from a plain variable.
    callee::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
end

function projection_print(p::JuliaCallToSyntaxNode, recursion, c::JuliaCall, ctx)
    callee_ref = child_context(ctx, @reference ^(ctx.reference).callee)
    # A bare identifier callee is a function name → render it through a
    # function-coloured identifier leaf; anything else (a field access, an
    # expression) recurses normally.
    callee_leaf = JuliaIdentifierToSyntaxLeaf(p.callee)
    callee_iomap = Cell(() -> c.callee isa JuliaIdentifier ?
        projection_print(callee_leaf, recursion, c.callee, callee_ref) :
        projection_printer_recurse(recursion, c.callee, callee_ref))

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

@projection struct JuliaTernaryToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaTernaryToSyntaxNode JuliaTernary (p, t) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ project(:condition),
                 SyntaxLeaf(TextString("?", p.op);
                            open=TextString(" ", p.op.font, color_default),
                            close=TextString(" ", p.op.font, color_default)),
                 project(:then_branch),
                 SyntaxLeaf(TextString(":", p.op);
                            open=TextString(" ", p.op.font, color_default),
                            close=TextString(" ", p.op.font, color_default)),
                 project(:else_branch) ],
               0, false, nothing)

# ── JuliaIndexToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaIndexToSyntaxNode
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaIndexToSyntaxNode JuliaIndex (p, x) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ project(:collection),
          SyntaxNode(collection(:indices);
                     open=TextString("[", p.delim),
                     close=TextString("]", p.delim),
                     sep=TextString(", ", p.delim)) ],
        0, false, nothing)

# ── JuliaFieldAccessToSyntaxNode ────────────────────────────────────────────

@projection struct JuliaFieldAccessToSyntaxNode
    dot::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaFieldAccessToSyntaxNode JuliaFieldAccess (p, f) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ project(:object),
                 SyntaxLeaf(TextString(".", p.dot)),
                 project(:field) ],
               0, false, nothing)

# ── JuliaTupleToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaTupleToSyntaxNode
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaTupleToSyntaxNode JuliaTuple (p, t) ->
    SyntaxNode(collection(:elements);
               open=TextString("(", p.delim),
               close=TextString(")", p.delim),
               sep=TextString(", ", p.delim))

# ── JuliaArrayToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaArrayToSyntaxNode
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaArrayToSyntaxNode JuliaArray (p, a) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", p.delim),
               close=TextString("]", p.delim),
               sep=TextString(", ", p.delim))

# ── JuliaRangeToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaRangeToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

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

@projection struct JuliaTypeAnnotationToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaTypeAnnotationToSyntaxNode JuliaTypeAnnotation (p, t) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ project(:value),
                 SyntaxLeaf(TextString("::", p.op)),
                 project(:type) ],
               0, false, nothing)

# ── JuliaAssignmentToSyntaxNode ─────────────────────────────────────────────

@projection struct JuliaAssignmentToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaAssignmentToSyntaxNode JuliaAssignment (p, a) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ project(:target),
                 SyntaxLeaf(TextString(() -> _julia_operator_string(a.operator), p.op);
                            open=TextString(" ", p.op.font, color_default),
                            close=TextString(" ", p.op.font, color_default)),
                 project(:value) ],
               0, false, nothing)

# ── JuliaForIteratorToSyntaxNode ────────────────────────────────────────────

@projection struct JuliaForIteratorToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaForIteratorToSyntaxNode JuliaForIterator (p, it) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ project(:variable),
                 SyntaxLeaf(TextString("in", p.keyword);
                            open=TextString(" ", p.keyword.font, color_default),
                            close=TextString(" ", p.keyword.font, color_default)),
                 project(:iterable) ],
               0, false, nothing)

# ── JuliaForToSyntaxNode ────────────────────────────────────────────────────

@projection struct JuliaForToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaForToSyntaxNode JuliaFor (p, f) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ SyntaxNode(TextString(""), TextString(""), TextString(""),
              [ SyntaxLeaf(TextString("for", p.keyword);
                           close=TextString(" ", p.keyword.font, color_default)),
                SyntaxNode(collection(:iterators); sep=TextString(", ", p.delim)) ],
              0, false, nothing),
          project(:body),
          SyntaxLeaf(TextString("end", p.keyword)) ],
        0, false, nothing)

# ── JuliaWhileToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaWhileToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaWhileToSyntaxNode JuliaWhile (p, w) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ SyntaxNode(TextString(""), TextString(""), TextString(""),
              [ SyntaxLeaf(TextString("while", p.keyword);
                           close=TextString(" ", p.keyword.font, color_default)),
                project(:condition) ],
              0, false, nothing),
          project(:body),
          SyntaxLeaf(TextString("end", p.keyword)) ],
        0, false, nothing)

# ── JuliaReturnToSyntaxNode ─────────────────────────────────────────────────

@projection struct JuliaReturnToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

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

# ── JuliaLambdaToSyntaxNode ─────────────────────────────────────────────────

@projection struct JuliaLambdaToSyntaxNode
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    arrow::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JuliaLambdaToSyntaxNode JuliaLambda (p, l) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ SyntaxNode(collection(:parameters);
                     open=TextString("(", p.delim),
                     close=TextString(") -> ", p.arrow),
                     sep=TextString(", ", p.delim)),
          project(:body) ],
        0, false, nothing)

# ── JuliaUsingToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaUsingToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    path::StyleText    = StyleText(font_ubuntu_monospace_regular_20, color_default)
end

# `using`/`import` keyword (highlighted) followed by the module path leaf. Both
# are introduced display leaves (the path is a flat string, not a nested
# expression), so the node has no recursive children; reference mapping uses the
# template's generic ∅↔∅ default (see the note above the composite table).
@projection_template JuliaUsingToSyntaxNode JuliaUsing (p, u) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ SyntaxLeaf(TextString(() -> string(u.keyword), p.keyword);
                            close=TextString(" ", p.keyword.font, color_default)),
                 SyntaxLeaf(TextString(() -> string(u.path), p.path)) ],
               0, false, nothing)

# ── JuliaBreakToSyntaxLeaf ──────────────────────────────────────────────────

@projection struct JuliaBreakToSyntaxLeaf
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaBreakToSyntaxLeaf JuliaBreak (p, b) ->
    SyntaxLeaf(TextString("break", p.keyword))

# ── JuliaContinueToSyntaxLeaf ───────────────────────────────────────────────

@projection struct JuliaContinueToSyntaxLeaf
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaContinueToSyntaxLeaf JuliaContinue (p, c) ->
    SyntaxLeaf(TextString("continue", p.keyword))

# ── JuliaTryToSyntaxNode ────────────────────────────────────────────────────

@projection struct JuliaTryToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

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

@projection struct JuliaBeginToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaBeginToSyntaxNode JuliaBegin (p, b) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
               [ SyntaxLeaf(TextString("begin", p.keyword)),
                 project(:body),
                 SyntaxLeaf(TextString("end", p.keyword)) ],
               0, false, nothing)

# ── JuliaBlockToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaBlockToSyntaxNode
    font::StyleFont = font_ubuntu_monospace_regular_20
    indentation::Int = 1
end

@projection_template JuliaBlockToSyntaxNode JuliaBlock (p, b) ->
    SyntaxNode(collection(:statements); indentation=p.indentation)

# ── JuliaIfToSyntaxNode ─────────────────────────────────────────────────────

@projection struct JuliaIfToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaIfToSyntaxNode JuliaIf (p, m) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ SyntaxNode(TextString(""), TextString(""), TextString(""),
              [ SyntaxLeaf(TextString("if", p.keyword);
                           close=TextString(" ", p.keyword.font, color_default)),
                project(:condition) ],
              0, false, nothing),
          project(:then_branch),
          SyntaxLeaf(TextString("else", p.keyword)),
          project(:else_branch),
          SyntaxLeaf(TextString("end", p.keyword)) ],
        0, false, nothing)

# ── JuliaFunctionToSyntaxNode ───────────────────────────────────────────────

@projection struct JuliaFunctionToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaFunctionToSyntaxNode JuliaFunction (p, f) ->
    SyntaxNode(TextString(""), TextString(""), TextString(""),
        [ SyntaxNode(TextString(""), TextString(""), TextString(""),
              [ SyntaxLeaf(TextString("function", p.keyword);
                           close=TextString(" ", p.keyword.font, color_default)),
                project(:name),
                SyntaxNode(collection(:params);
                           open=TextString("(", p.delim),
                           close=TextString(")", p.delim),
                           sep=TextString(", ", p.delim)) ],
              0, false, nothing),
          project(:body),
          SyntaxLeaf(TextString("end", p.keyword)) ],
        0, false, nothing)

# ── Reference mapping & readers ─────────────────────────────────────────────
#
# The projections written with `@projection_template` above (every leaf, the
# `collection(:…)` nodes, and the flat fixed-children nodes) get their reference
# mapping and readers for free from the template engine's generic `RuleIoMap`
# machinery: opaque leaves map `∅↔∅` (mirroring the old generic default), and the
# collection / fixed nodes delegate each recursive child through its stored child
# IoMap (School A), like JsonToSyntax.
#
# The remaining hand-written composite nodes (`JuliaCall`, `JuliaIndex`,
# `JuliaRange`, `JuliaFor`, `JuliaWhile`, `JuliaReturn`, `JuliaLambda`,
# `JuliaTry`, `JuliaIf`, `JuliaFunction`) still use `ChildrenIoMap` without
# per-node `map_reference_*`/`projection_read`, so they fall through to the
# generic `Projection` defaults (whole-element / proj-wrapped granularity). They
# have a nested structural sub-node (a header wrapping a keyword + a recursive
# child, or a bracketed argument/index/parameter collection) or a variable-length
# child list, neither of which the current template node forms express.
#
# Independently, the leaves are still *opaque* (no `bound(…)` marker), so a cursor
# does NOT descend into a leaf's own text: an identifier/number/string edits at
# whole-element granularity only. Making the leaves `bound` would need the
# flat-offset projection-reference machinery JsonToSyntax carries
# (`_syntax_to_flat`) to traverse the projection-introduced structural tokens
# (`function`, `(`, `)`, `==`, `if`, `end`, …) that have no Julia pre-image; that
# is the still-deferred follow-up (the High finding in
# plan/pending/consistency-report.md, §D — the source of the 28 unreached
# `…name{k}` carets in `test_text_navigation(julia_example; check_reaches_all=true)`).

# ── JuliaToSyntax (composite) ───────────────────────────────────────────────

function JuliaToSyntax()
    TypeDispatchingProjection(
        JuliaInsertion       => JuliaInsertionToSyntaxLeaf(),
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
        JuliaUsing           => JuliaUsingToSyntaxNode(),
        JuliaLambda          => JuliaLambdaToSyntaxNode(),
    )
end

end # module
