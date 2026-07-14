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

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, Projection
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
import ..SyntaxModule: SyntaxLeaf, SyntaxNode, SyntaxConcatenation
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..DocumentInsertionToSyntaxModule: JuliaInsertionToSyntaxLeaf
import ..ProjectionTemplateModule: var"@projection_template", project, collection
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
    SyntaxConcatenation([ project(:left),
                          SyntaxLeaf(TextString(() -> _julia_operator_string(m.operator), p.op);
                                     open=TextString(" ", p.op.font, color_default),
                                     close=TextString(" ", p.op.font, color_default)),
                          project(:right) ])

# ── JuliaUnaryOpToSyntaxNode ────────────────────────────────────────────────

@projection struct JuliaUnaryOpToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaUnaryOpToSyntaxNode JuliaUnaryOp (p, u) ->
    SyntaxConcatenation([ SyntaxLeaf(TextString(() -> _julia_operator_string(u.operator), p.op)),
                          project(:operand) ])

# ── JuliaCallToSyntaxNode ───────────────────────────────────────────────────

@projection struct JuliaCallToSyntaxNode
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    # A call's function name is coloured distinctly from a plain variable.
    callee::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
end

# F1 (nested `(args)` sub-node) + F3 (callee override): a bare identifier callee is
# a function name → render it through a function-coloured identifier leaf; anything
# else (a field access, an expression) recurses through its own projection.
@projection_template JuliaCallToSyntaxNode JuliaCall (p, c) ->
    SyntaxConcatenation([ project(:callee; as = v -> v isa JuliaIdentifier ? JuliaIdentifierToSyntaxLeaf(p.callee) : nothing),
                          SyntaxNode(collection(:arguments);
                                     open=TextString("(", p.delim),
                                     close=TextString(")", p.delim),
                                     sep=TextString(", ", p.delim)) ])

# ── JuliaTernaryToSyntaxNode ────────────────────────────────────────────────

@projection struct JuliaTernaryToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaTernaryToSyntaxNode JuliaTernary (p, t) ->
    SyntaxConcatenation([ project(:condition),
                          SyntaxLeaf(TextString("?", p.op);
                                     open=TextString(" ", p.op.font, color_default),
                                     close=TextString(" ", p.op.font, color_default)),
                          project(:then_branch),
                          SyntaxLeaf(TextString(":", p.op);
                                     open=TextString(" ", p.op.font, color_default),
                                     close=TextString(" ", p.op.font, color_default)),
                          project(:else_branch) ])

# ── JuliaIndexToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaIndexToSyntaxNode
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaIndexToSyntaxNode JuliaIndex (p, x) ->
    SyntaxConcatenation([ project(:collection),
                          SyntaxNode(collection(:indices);
                                     open=TextString("[", p.delim),
                                     close=TextString("]", p.delim),
                                     sep=TextString(", ", p.delim)) ])

# ── JuliaFieldAccessToSyntaxNode ────────────────────────────────────────────

@projection struct JuliaFieldAccessToSyntaxNode
    dot::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaFieldAccessToSyntaxNode JuliaFieldAccess (p, f) ->
    SyntaxConcatenation([ project(:object),
                          SyntaxLeaf(TextString(".", p.dot)),
                          project(:field) ])

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

# F2: the child list depends on the optional `step` — a reactive marker thunk.
@projection_template JuliaRangeToSyntaxNode JuliaRange (p, r) ->
    SyntaxConcatenation(() -> r.step === nothing ?
                            [ project(:start), SyntaxLeaf(TextString(":", p.op)), project(:stop) ] :
                            [ project(:start), SyntaxLeaf(TextString(":", p.op)),
                              project(:step),  SyntaxLeaf(TextString(":", p.op)), project(:stop) ])

# ── JuliaTypeAnnotationToSyntaxNode ─────────────────────────────────────────

@projection struct JuliaTypeAnnotationToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaTypeAnnotationToSyntaxNode JuliaTypeAnnotation (p, t) ->
    SyntaxConcatenation([ project(:value),
                          SyntaxLeaf(TextString("::", p.op)),
                          project(:type) ])

# ── JuliaAssignmentToSyntaxNode ─────────────────────────────────────────────

@projection struct JuliaAssignmentToSyntaxNode
    op::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaAssignmentToSyntaxNode JuliaAssignment (p, a) ->
    SyntaxConcatenation([ project(:target),
                          SyntaxLeaf(TextString(() -> _julia_operator_string(a.operator), p.op);
                                     open=TextString(" ", p.op.font, color_default),
                                     close=TextString(" ", p.op.font, color_default)),
                          project(:value) ])

# ── JuliaForIteratorToSyntaxNode ────────────────────────────────────────────

@projection struct JuliaForIteratorToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaForIteratorToSyntaxNode JuliaForIterator (p, it) ->
    SyntaxConcatenation([ project(:variable),
                          SyntaxLeaf(TextString("in", p.keyword);
                                     open=TextString(" ", p.keyword.font, color_default),
                                     close=TextString(" ", p.keyword.font, color_default)),
                          project(:iterable) ])

# ── JuliaForToSyntaxNode ────────────────────────────────────────────────────

@projection struct JuliaForToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaForToSyntaxNode JuliaFor (p, f) ->
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("for", p.keyword);
                                                           close=TextString(" ", p.keyword.font, color_default)),
                                                SyntaxNode(collection(:iterators); sep=TextString(", ", p.delim)) ]),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── JuliaWhileToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaWhileToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaWhileToSyntaxNode JuliaWhile (p, w) ->
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("while", p.keyword);
                                                           close=TextString(" ", p.keyword.font, color_default)),
                                                project(:condition) ]),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── JuliaReturnToSyntaxNode ─────────────────────────────────────────────────

@projection struct JuliaReturnToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

# F2: bare `return` vs `return <value>` — a reactive marker thunk on optional `value`.
@projection_template JuliaReturnToSyntaxNode JuliaReturn (p, r) ->
    SyntaxConcatenation(() -> r.value === nothing ?
                            [ SyntaxLeaf(TextString("return", p.keyword)) ] :
                            [ SyntaxLeaf(TextString("return", p.keyword);
                                         close=TextString(" ", p.keyword.font, color_default)),
                              project(:value) ])

# ── JuliaLambdaToSyntaxNode ─────────────────────────────────────────────────

@projection struct JuliaLambdaToSyntaxNode
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    arrow::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JuliaLambdaToSyntaxNode JuliaLambda (p, l) ->
    SyntaxConcatenation([ SyntaxNode(collection(:parameters);
                                     open=TextString("(", p.delim),
                                     close=TextString(") -> ", p.arrow),
                                     sep=TextString(", ", p.delim)),
                          project(:body) ])

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
    SyntaxConcatenation([ SyntaxLeaf(TextString(() -> string(u.keyword), p.keyword);
                                     close=TextString(" ", p.keyword.font, color_default)),
                          SyntaxLeaf(TextString(() -> string(u.path), p.path)) ])

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

# F2 + F1: an optional `catch`/`catch <var>`/`finally` child list (reactive marker
# thunk), where the `catch <var>` form is a nested header sub-node.
@projection_template JuliaTryToSyntaxNode JuliaTry (p, t) ->
    SyntaxConcatenation(() -> begin
                            kids = Any[ SyntaxLeaf(TextString("try", p.keyword)), project(:body) ]
                            if t.catch_branch !== nothing
                                push!(kids, t.catch_var === nothing ?
                                    SyntaxLeaf(TextString("catch", p.keyword)) :
                                    SyntaxConcatenation([ SyntaxLeaf(TextString("catch", p.keyword);
                                                                     close=TextString(" ", p.keyword.font, color_default)),
                                                          project(:catch_var) ]))
                                push!(kids, project(:catch_branch))
                            end
                            if t.finally_branch !== nothing
                                push!(kids, SyntaxLeaf(TextString("finally", p.keyword)), project(:finally_branch))
                            end
                            push!(kids, SyntaxLeaf(TextString("end", p.keyword)))
                            kids
                        end)

# ── JuliaBeginToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaBeginToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaBeginToSyntaxNode JuliaBegin (p, b) ->
    SyntaxConcatenation([ SyntaxLeaf(TextString("begin", p.keyword)),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

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
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("if", p.keyword);
                                                           close=TextString(" ", p.keyword.font, color_default)),
                                                project(:condition) ]),
                          project(:then_branch),
                          SyntaxLeaf(TextString("else", p.keyword)),
                          project(:else_branch),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── JuliaFunctionToSyntaxNode ───────────────────────────────────────────────

@projection struct JuliaFunctionToSyntaxNode
    keyword::StyleText = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    delim::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaFunctionToSyntaxNode JuliaFunction (p, f) ->
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("function", p.keyword);
                                                           close=TextString(" ", p.keyword.font, color_default)),
                                                project(:name),
                                                SyntaxNode(collection(:params);
                                                           open=TextString("(", p.delim),
                                                           close=TextString(")", p.delim),
                                                           sep=TextString(", ", p.delim)) ]),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── Reference mapping & readers ─────────────────────────────────────────────
#
# Every projection here is written with `@projection_template`; all 32 get their
# reference mapping and readers for free from the template engine's generic
# `RuleIoMap` machinery. Opaque leaves map `∅↔∅` (mirroring the old generic
# default); the collection / fixed nodes delegate each recursive child through its
# stored child IoMap (School A), like JsonToSyntax. The composite/statement nodes
# use the general node markers: a keyword/bracket header is a nested
# `SyntaxNode` sub-node (F1), a function-name-coloured callee is
# `project(:callee; as=…)` (F3), and a variable-length child list (Range's
# `step`, Return's `value`, Try's optional `catch`/`finally`) is a reactive
# marker thunk (F2).
#
# Independently, the leaves are still *opaque* (no `bound(…)` marker), so a cursor
# does NOT descend into a leaf's own text: an identifier/number/string edits at
# whole-element granularity only. Making the leaves `bound` would need the
# flat-offset projection-reference machinery JsonToSyntax carries
# (`_syntax_to_flat`) to traverse the projection-introduced structural tokens
# (`function`, `(`, `)`, `==`, `if`, `end`, …) that have no Julia pre-image; that
# is the still-deferred follow-up (the High finding in
# plan/pending/consistency-report.md, §D — the source of the 28 unreached
# `…name{k}` carets in `test_position_navigation(julia_example; check_reaches_all=true)`).

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
