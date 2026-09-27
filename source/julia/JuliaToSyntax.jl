# Fragment of `JuliaModule`.
#
# Julia → SyntaxDocument projection. Maps each Julia expression type to a syntax
# tree with colorized tokens:
# - Identifiers in blue
# - Keywords (function, if, else, for, while, return, break, continue,
#   try, catch, finally, begin, end, in) in bold magenta
# - Operators (==, *, -, +, ::, etc.) in cyan
# - Integer, float, string and char literals in green
# - Booleans, nothing and symbols in bold magenta
# - Delimiters (parentheses, brackets, commas) in gray
# ── JuliaIdentifierToSyntaxLeaf ─────────────────────────────────────────────

# A standalone identifier is a *variable* reference — rendered in a distinct
# variable colour (violet), separate from keywords (magenta), function names
# (blue, applied by `JuliaCallToSyntaxNode`), literals (green) and operators.
@projection struct JuliaIdentifierToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
end

@projection_template JuliaIdentifierToSyntaxLeaf JuliaIdentifier (p, v) ->
    SyntaxLeaf(TextString(() -> v.name, p.style))

# ── JuliaIntegerToSyntaxLeaf ────────────────────────────────────────────────

@projection struct JuliaIntegerToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template JuliaIntegerToSyntaxLeaf JuliaInteger (p, v) ->
    SyntaxLeaf(TextString(() -> string(v.value), p.style))

# ── JuliaFloatToSyntaxLeaf ──────────────────────────────────────────────────

@projection struct JuliaFloatToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template JuliaFloatToSyntaxLeaf JuliaFloat (p, v) ->
    SyntaxLeaf(TextString(() -> string(v.value), p.style))

# ── JuliaStringToSyntaxLeaf ─────────────────────────────────────────────────

@projection struct JuliaStringToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

# The value is escaped on the way out — a quote, a backslash — and the parser
# unescapes it on the way in, so any string round-trips as source.
@projection_template JuliaStringToSyntaxLeaf JuliaString (p, v) ->
    SyntaxLeaf(TextString(() -> _julia_string_escape(v.value), p.style);
               open=TextString("\"", p.quote_style),
               close=TextString("\"", p.quote_style))

# ── JuliaBoolToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JuliaBoolToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

# Guard the `? :` against a transient non-`Bool` value (a mid-edit `bound` read can clear
# the type-erased `value` cell) — the same crash `JsonBoolToSyntaxLeaf` fixes. Rendering
# empty for the cleared state matches this file's plain-thunk style (cf. `string(v.value)`).
@projection_template JuliaBoolToSyntaxLeaf JuliaBool (p, v) ->
    SyntaxLeaf(TextString(() -> v.value isa Bool ? (v.value ? "true" : "false") : "", p.style))

# ── JuliaNothingToSyntaxLeaf ────────────────────────────────────────────────

@projection struct JuliaNothingToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaNothingToSyntaxLeaf JuliaNothing (p, v) ->
    SyntaxLeaf(TextString("nothing", p.style))

# ── JuliaSymbolToSyntaxLeaf ─────────────────────────────────────────────────

@projection struct JuliaSymbolToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JuliaSymbolToSyntaxLeaf JuliaSymbol (p, v) ->
    SyntaxLeaf(TextString(() -> v.name, p.style);
               open=TextString(":", p.style))

# ── JuliaCharToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct JuliaCharToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    quote_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaCharToSyntaxLeaf JuliaChar (p, v) ->
    SyntaxLeaf(TextString(() -> string(v.value), p.style);
               open=TextString("'", p.quote_style),
               close=TextString("'", p.quote_style))

# ── Operator precedence, and the parentheses it demands ─────────────────────
#
# The tree knows how its operands group; the printed text only knows
# precedence. So an operand that binds *looser* than its parent has to be
# parenthesized, or the text regroups into a different expression — `!(a || b)`
# printed bare becomes `!a || b`, which is not the same thing and does not
# announce itself.

const _JULIA_COMPARISONS = (:(==), :(!=), :(<), :(>), :(<=), :(>=), :(===), :(!==),
                             :isa, :in, :∈, :∉)

# A broadcast operator binds as the operator without its dot: `.+` as `+`.
_strip_operator_dot(op::Symbol) =
    (text = string(op); length(text) > 1 && startswith(text, '.') ? Symbol(text[2:end]) : op)

# The order of the Julia manual, from the loosest: a pair, `||`, `&&`, the
# comparisons, `|>`, the additions, the multiplications, and `^`. An operator
# that the table does not name binds between the multiplications and `^`.
_julia_precedence(op::Symbol) = _get_undotted_operator_precedence(_strip_operator_dot(op))
_get_undotted_operator_precedence(op::Symbol) =
    op === :(=>) ? 0 :
    op === :|| ? 1 :
    op === :&& ? 2 :
    op in _JULIA_COMPARISONS ? 3 :
    op === :|> ? 4 :
    op in (:+, :-) ? 5 :
    op in (:*, :/, :%, :÷) ? 6 :
    op === :^ ? 8 : 7

# `=>`, `&&`, `||` and `^` associate to the right in Julia, and the arithmetic
# and comparison operators and `|>` to the left. The side an operator already
# associates toward needs no parentheses at equal precedence; the other side does.
# The parser folds a chained comparison `a < b < c` to the left, so it prints
# back as written.
_julia_right_associative(op::Symbol) = _strip_operator_dot(op) in (:(=>), :&&, :||, :^)

_julia_operand_parens(operand, outer::Symbol, on_right::Bool) = begin
    operand isa JuliaBinaryOperation || return false
    inner = _julia_precedence(operand.operator)
    outer_precedence = _julia_precedence(outer)
    tight = _julia_right_associative(outer) ? !on_right : on_right
    tight ? inner <= outer_precedence : inner < outer_precedence
end

_julia_parenthesize(marker, style) =
    SyntaxNode([marker];
               open = TextString("(", style.font, color_solarized_gray),
               close = TextString(")", style.font, color_solarized_gray))

# ── JuliaBinaryOperationToSyntaxNode ───────────────────────────────────────────────

@projection struct JuliaBinaryOperationToSyntaxNode
    op::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaBinaryOperationToSyntaxNode JuliaBinaryOperation (p, m) ->
    SyntaxConcatenation(() -> begin
        operator = m.operator
        left  = _julia_operand_parens(m.left,  operator, false) ?
                _julia_parenthesize(project(:left),  p.op) : project(:left)
        right = _julia_operand_parens(m.right, operator, true) ?
                _julia_parenthesize(project(:right), p.op) : project(:right)
        [ left,
          SyntaxLeaf(TextString(() -> _julia_operator_string(m.operator), p.op);
                     open=TextString(" ", p.op.font, color_default),
                     close=TextString(" ", p.op.font, color_default)),
          right ]
    end)

# ── JuliaUnaryOperationToSyntaxNode ────────────────────────────────────────────────

@projection struct JuliaUnaryOperationToSyntaxNode
    op::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

# A unary operator binds tighter than every binary one, so a binary operand is
# always parenthesized.
@projection_template JuliaUnaryOperationToSyntaxNode JuliaUnaryOperation (p, u) ->
    SyntaxConcatenation(() -> begin
        operand = u.operand isa JuliaBinaryOperation ?
                  _julia_parenthesize(project(:operand), p.op) : project(:operand)
        [ SyntaxLeaf(TextString(() -> _julia_operator_string(u.operator), p.op)), operand ]
    end)

# ── JuliaCallToSyntaxNode ───────────────────────────────────────────────────

@projection struct JuliaCallToSyntaxNode
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    # A call's function name is coloured distinctly from a plain variable.
    callee::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
end

# F1 (nested `(args)` sub-node) + F3 (callee override): a bare identifier callee is
# a function name → render it through a function-coloured identifier leaf; anything
# else (a field access, an expression) recurses through its own projection.
#
# The arguments and the keyword arguments are two sub-nodes: `(a, b` and
# `; k = 1)`. The second one opens with `; ` only when it holds a keyword, so a call
# with none reads `(a, b)`, and it closes the call.
@projection_template JuliaCallToSyntaxNode JuliaCall (p, c) ->
    SyntaxConcatenation([ project(:callee; as = v -> v isa JuliaIdentifier ? JuliaIdentifierToSyntaxLeaf(p.callee) : nothing),
                          SyntaxNode(collection(:arguments);
                                     open=TextString("(", p.delim),
                                     sep=TextString(", ", p.delim)),
                          SyntaxNode(collection(:keyword_arguments);
                                     open=TextString(Cell(@computation isempty(c.keyword_arguments) ? "" : "; "),
                                                     Cell(p.delim.font), Cell(p.delim.color),
                                                     Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing)),
                                     close=TextString(")", p.delim),
                                     sep=TextString(", ", p.delim)) ])

# ── JuliaMacroCallToSyntaxNode ──────────────────────────────────────────────
# Renders `@name arg1 arg2 …`. The name is a plain string leaf (it
# already carries its leading `@`); arguments are space-separated,
# each projected via its own type dispatch.

@projection struct JuliaMacroCallToSyntaxNode
    name_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    sep_style::ImmutableCell{StyleText}  = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaMacroCallToSyntaxNode JuliaMacroCall (p, m) ->
    SyntaxConcatenation([ SyntaxLeaf(TextString(() -> m.name, p.name_style)),
                          SyntaxNode(collection(:arguments);
                                     open=TextString(" ", p.sep_style),
                                     close=TextString("", p.sep_style),
                                     sep=TextString(" ", p.sep_style)) ])

# ── JuliaConstToSyntaxNode ─────────────────────────────────────────────────
# `const NAME = value` — the `const` keyword in front of the inner
# assignment. Keyword uses the JuliaKeyword palette color (magenta).

@projection struct JuliaConstToSyntaxNode
    keyword_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaConstToSyntaxNode JuliaConst (p, c) ->
    SyntaxConcatenation([ SyntaxLeaf(TextString("const ", p.keyword_style)),
                          project(:assignment) ])

# ── JuliaDocstringToSyntaxNode ─────────────────────────────────────────────
# Renders the natural docstring form:
#     \"\"\"
#     <text>
#     \"\"\"
#     <subject>
# The `SyntaxToText` stage carries per-leaf line breaks through, so the
# triple-quote fences and the subject land on their own lines.

@projection struct JuliaDocstringToSyntaxNode
    doc_style::ImmutableCell{StyleText}   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
    fence_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaDocstringToSyntaxNode JuliaDocstring (p, d) ->
    SyntaxConcatenation([
        SyntaxLeaf(TextString("\"\"\"\n", p.fence_style)),
        SyntaxLeaf(TextString(() -> d.text, p.doc_style)),
        SyntaxLeaf(TextString("\n\"\"\"\n", p.fence_style)),
        project(:subject),
    ])

# ── JuliaAbstractTypeToSyntaxNode ──────────────────────────────────────────

@projection struct JuliaAbstractTypeToSyntaxNode
    keyword_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    sep_style::ImmutableCell{StyleText}     = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaAbstractTypeToSyntaxNode JuliaAbstractType (p, a) ->
    SyntaxConcatenation([
        SyntaxLeaf(TextString("abstract type ", p.keyword_style)),
        project(:header),
        SyntaxLeaf(TextString(" end", p.keyword_style)),
    ])

# ── JuliaStructToSyntaxNode ─────────────────────────────────────────────────

@projection struct JuliaStructToSyntaxNode
    keyword_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    sep_style::ImmutableCell{StyleText}     = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaStructToSyntaxNode JuliaStruct (p, s) ->
    SyntaxConcatenation([
        SyntaxLeaf(TextString(() -> s.mutable ? "mutable struct " : "struct ", p.keyword_style)),
        project(:header),
        SyntaxLeaf(TextString("\n", p.sep_style)),
        project(:body),
        # `body` is a `JuliaBlock` whose own trailing chrome already
        # emits a "\n" after the last field; no leading "\n" here or
        # a blank line opens up before `end`.
        SyntaxLeaf(TextString("end", p.keyword_style)),
    ])

# ── JuliaModuleDefinitionToSyntaxNode ─────────────────────────────────────────────
#
# The body is a `JuliaBlock`, so it indents and supplies its own surrounding
# newlines — the same shape `JuliaStructToSyntaxNode` relies on, and the reason
# neither node writes a newline before `end`.

@projection struct JuliaModuleDefinitionToSyntaxNode
    keyword_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    name_style::ImmutableCell{StyleText}    = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    sep_style::ImmutableCell{StyleText}     = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaModuleDefinitionToSyntaxNode JuliaModuleDefinition (p, m) ->
    SyntaxConcatenation([
        SyntaxLeaf(TextString(() -> m.bare ? "baremodule " : "module ", p.keyword_style)),
        SyntaxLeaf(bound(:name, String,
                         make_hinted_text(() -> m.name; empty_thunk = () -> isempty(m.name),
                                          placeholder = "enter module name",
                                          style = p.name_style))),
        project(:body),
        SyntaxLeaf(TextString(() -> "end # module " * m.name, p.keyword_style)),
    ])

# ── JuliaSubtypeToSyntaxNode ───────────────────────────────────────────────

@projection struct JuliaSubtypeToSyntaxNode
    op_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

# `A <: B`, and `<:B` for the anonymous bound — where there is nothing on the
# left there is no space either.
@projection_template JuliaSubtypeToSyntaxNode JuliaSubtype (p, s) ->
    SyntaxConcatenation([
        project(:lhs),
        SyntaxLeaf(TextString(() -> s.lhs isa JuliaEmpty ? "<:" : " <: ", p.op_style)),
        project(:rhs),
    ])

# ── JuliaCurlyToSyntaxNode ─────────────────────────────────────────────────

@projection struct JuliaCurlyToSyntaxNode
    brace_style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaCurlyToSyntaxNode JuliaCurly (p, c) ->
    SyntaxConcatenation([
        project(:callee),
        SyntaxNode(collection(:params);
                   open=TextString("{", p.brace_style),
                   close=TextString("}", p.brace_style),
                   sep=TextString(", ", p.brace_style)),
    ])

# ── JuliaTernaryToSyntaxNode ────────────────────────────────────────────────

@projection struct JuliaTernaryToSyntaxNode
    op::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
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
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaIndexToSyntaxNode JuliaIndex (p, x) ->
    SyntaxConcatenation([ project(:collection),
                          SyntaxNode(collection(:indices);
                                     open=TextString("[", p.delim),
                                     close=TextString("]", p.delim),
                                     sep=TextString(", ", p.delim)) ])

# ── JuliaFieldAccessToSyntaxNode ────────────────────────────────────────────

@projection struct JuliaFieldAccessToSyntaxNode
    dot::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaFieldAccessToSyntaxNode JuliaFieldAccess (p, f) ->
    SyntaxConcatenation([ project(:object),
                          SyntaxLeaf(TextString(".", p.dot)),
                          project(:field) ])

# ── JuliaTupleToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaTupleToSyntaxNode
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaTupleToSyntaxNode JuliaTuple (p, t) ->
    SyntaxNode(collection(:elements);
               open=TextString("(", p.delim),
               close=TextString(")", p.delim),
               sep=TextString(", ", p.delim))

# ── JuliaArrayToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaArrayToSyntaxNode
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaArrayToSyntaxNode JuliaArray (p, a) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", p.delim),
               close=TextString("]", p.delim),
               sep=TextString(", ", p.delim))

# ── JuliaRangeToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaRangeToSyntaxNode
    op::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

# F2: the child list depends on the optional `step` — a reactive marker thunk.
@projection_template JuliaRangeToSyntaxNode JuliaRange (p, r) ->
    SyntaxConcatenation(() -> r.step === nothing ?
                            [ project(:start), SyntaxLeaf(TextString(":", p.op)), project(:stop) ] :
                            [ project(:start), SyntaxLeaf(TextString(":", p.op)),
                              project(:step),  SyntaxLeaf(TextString(":", p.op)), project(:stop) ])

# ── JuliaTypeAnnotationToSyntaxNode ─────────────────────────────────────────

@projection struct JuliaTypeAnnotationToSyntaxNode
    op::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaTypeAnnotationToSyntaxNode JuliaTypeAnnotation (p, t) ->
    SyntaxConcatenation([ project(:value),
                          SyntaxLeaf(TextString("::", p.op)),
                          project(:type) ])

# The anonymous `::T` form — nothing before the `::`, just the type.

@projection struct JuliaAnonymousTypeAnnotationToSyntaxNode
    op::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaAnonymousTypeAnnotationToSyntaxNode JuliaAnonymousTypeAnnotation (p, t) ->
    SyntaxConcatenation([ SyntaxLeaf(TextString("::", p.op)),
                          project(:type) ])

# ── JuliaEmptyToSyntaxLeaf ─────────────────────────────────────────────────
# Renders JuliaEmpty as literally nothing — the empty concatenation is
# the smallest span that satisfies the SyntaxDocument contract without
# adding any character to the output.

@projection struct JuliaEmptyToSyntaxLeaf end

@projection_template JuliaEmptyToSyntaxLeaf JuliaEmpty (p, e) ->
    SyntaxConcatenation(Any[])

# ── JuliaAssignmentToSyntaxNode ─────────────────────────────────────────────

@projection struct JuliaAssignmentToSyntaxNode
    op::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
end

@projection_template JuliaAssignmentToSyntaxNode JuliaAssignment (p, a) ->
    SyntaxConcatenation([ project(:target),
                          SyntaxLeaf(TextString(() -> _julia_operator_string(a.operator), p.op);
                                     open=TextString(" ", p.op.font, color_default),
                                     close=TextString(" ", p.op.font, color_default)),
                          project(:value) ])

# ── JuliaForIteratorToSyntaxNode ────────────────────────────────────────────

@projection struct JuliaForIteratorToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaForIteratorToSyntaxNode JuliaForIterator (p, it) ->
    SyntaxConcatenation([ project(:variable),
                          SyntaxLeaf(TextString("in", p.keyword);
                                     open=TextString(" ", p.keyword.font, color_default),
                                     close=TextString(" ", p.keyword.font, color_default)),
                          project(:iterable) ])

# ── JuliaForToSyntaxNode ────────────────────────────────────────────────────

@projection struct JuliaForToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaForToSyntaxNode JuliaFor (p, f) ->
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("for", p.keyword);
                                                           close=TextString(" ", p.keyword.font, color_default)),
                                                SyntaxNode(collection(:iterators); sep=TextString(", ", p.delim)) ]),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── JuliaWhileToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaWhileToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaWhileToSyntaxNode JuliaWhile (p, w) ->
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("while", p.keyword);
                                                           close=TextString(" ", p.keyword.font, color_default)),
                                                project(:condition) ]),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── JuliaReturnToSyntaxNode ─────────────────────────────────────────────────

@projection struct JuliaReturnToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
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
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
    arrow::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JuliaLambdaToSyntaxNode JuliaLambda (p, l) ->
    SyntaxConcatenation([ SyntaxNode(collection(:parameters);
                                     open=TextString(Cell(@computation l.parenthesized ? "(" : ""),
                                                     Cell(p.delim.font), Cell(p.delim.color),
                                                     Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing)),
                                     close=TextString(Cell(@computation l.parenthesized ? ") -> " : " -> "),
                                                      Cell(p.arrow.font), Cell(p.arrow.color),
                                                      Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing)),
                                     sep=TextString(", ", p.delim)),
                          project(:body) ])

# ── The rest of ordinary Julia ──────────────────────────────────────────────
#
# One rule each, all `@projection_template`, all mirroring the parser arms in
# `JuliaParser.jl`. Nothing here is clever: the point of the group is that a
# real source file parses and prints back, so that a page can embed a function
# out of one.

const _JULIA_DELIM  = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
const _JULIA_KEYWORD = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)

@projection struct JuliaSplatToSyntaxNode
    delim::ImmutableCell{StyleText} = _JULIA_DELIM
end

@projection_template JuliaSplatToSyntaxNode JuliaSplat (p, s) ->
    SyntaxNode([project(:value)]; close=TextString("...", p.delim))

@projection struct JuliaBroadcastToSyntaxNode
    delim::ImmutableCell{StyleText}  = _JULIA_DELIM
    callee::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
end

@projection_template JuliaBroadcastToSyntaxNode JuliaBroadcast (p, b) ->
    SyntaxNode([project(:callee),
                SyntaxNode(collection(:arguments);
                           open=TextString(".(", p.delim),
                           close=TextString(")", p.delim),
                           sep=TextString(", ", p.delim))])

# An interpolated string: the literal chunks print as themselves, everything
# else inside a dollar-brace. The quotes belong to the whole thing, not to the chunks,
# which is why this is a node and not a leaf.
@projection struct JuliaStringInterpolationToSyntaxNode
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template JuliaStringInterpolationToSyntaxNode JuliaStringInterpolation (p, s) ->
    SyntaxNode(collection(:parts);
               open=TextString("\"", p.delim),
               close=TextString("\"", p.delim))

# A literal run inside an interpolated string: its text, and nothing around it.
@projection struct JuliaStringChunkToSyntaxLeaf
    style::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template JuliaStringChunkToSyntaxLeaf JuliaStringChunk (p, c) ->
    SyntaxLeaf(TextString(() -> c.text, p.style))

@projection struct JuliaInterpolationToSyntaxNode
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_magenta)
end

@projection_template JuliaInterpolationToSyntaxNode JuliaInterpolation (p, i) ->
    SyntaxNode([project(:value)];
               open=TextString("\$(", p.delim), close=TextString(")", p.delim))

@projection struct JuliaWhereToSyntaxNode
    keyword::ImmutableCell{StyleText} = _JULIA_KEYWORD
    delim::ImmutableCell{StyleText}   = _JULIA_DELIM
end

@projection_template JuliaWhereToSyntaxNode JuliaWhere (p, w) ->
    SyntaxNode([project(:body),
                SyntaxNode(collection(:parameters);
                           open=TextString(" where {", p.keyword),
                           close=TextString("}", p.delim),
                           sep=TextString(", ", p.delim))])

# `[expr for i in r]`, `Any[…]`, `(expr for i in r)`. The element type prints
# before the bracket when there is one; `JuliaEmpty` prints nothing, so the
# untyped form needs no separate rule.
@projection struct JuliaComprehensionToSyntaxNode
    keyword::ImmutableCell{StyleText} = _JULIA_KEYWORD
    delim::ImmutableCell{StyleText}   = _JULIA_DELIM
end

@projection_template JuliaComprehensionToSyntaxNode JuliaComprehension (p, c) ->
    SyntaxNode([project(:element_type),
                SyntaxNode([project(:expression),
                            SyntaxNode(collection(:iterators);
                                       open=TextString(" for ", p.keyword),
                                       sep=TextString(", ", p.delim)),
                            SyntaxNode([project(:condition)];
                                       open=TextString(() -> c.condition isa JuliaEmpty ? "" : " if ",
                                                       p.keyword))];
                           open=TextString(c.brackets ? "[" : "(", p.delim),
                           close=TextString(c.brackets ? "]" : ")", p.delim))])

@projection struct JuliaDoToSyntaxNode
    keyword::ImmutableCell{StyleText} = _JULIA_KEYWORD
end

# `call do params` … `end`, in the shape every other block-bodied construct
# uses: a header concatenation, the body (which supplies its own newline and
# indentation), then `end`.
@projection_template JuliaDoToSyntaxNode JuliaDo (p, d) ->
    SyntaxConcatenation([ SyntaxConcatenation([ project(:call),
                                                SyntaxNode(collection(:parameters);
                                                           open=TextString(" do ", p.keyword),
                                                           sep=TextString(", ", p.keyword)) ]),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

@projection struct JuliaLetToSyntaxNode
    keyword::ImmutableCell{StyleText} = _JULIA_KEYWORD
    delim::ImmutableCell{StyleText}   = _JULIA_DELIM
end

@projection_template JuliaLetToSyntaxNode JuliaLet (p, l) ->
    SyntaxConcatenation([ SyntaxNode(collection(:bindings);
                                     open=TextString("let ", p.keyword),
                                     sep=TextString(", ", p.delim)),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

@projection struct JuliaNamedTupleToSyntaxNode
    delim::ImmutableCell{StyleText} = _JULIA_DELIM
end

@projection_template JuliaNamedTupleToSyntaxNode JuliaNamedTuple (p, n) ->
    SyntaxNode(collection(:entries);
               open=TextString("(; ", p.delim),
               close=TextString(")", p.delim),
               sep=TextString(", ", p.delim))

# ── JuliaUsingToSyntaxNode ──────────────────────────────────────────────────

@projection struct JuliaUsingToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    path::ImmutableCell{StyleText}    = StyleText(font_ubuntu_monospace_regular_20, color_default)
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
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaBreakToSyntaxLeaf JuliaBreak (p, b) ->
    SyntaxLeaf(TextString("break", p.keyword))

# ── JuliaContinueToSyntaxLeaf ───────────────────────────────────────────────

@projection struct JuliaContinueToSyntaxLeaf
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaContinueToSyntaxLeaf JuliaContinue (p, c) ->
    SyntaxLeaf(TextString("continue", p.keyword))

# ── JuliaTryToSyntaxNode ────────────────────────────────────────────────────

@projection struct JuliaTryToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
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
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
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

# ── JuliaToplevelToSyntaxNode ───────────────────────────────────────────────

@projection struct JuliaToplevelToSyntaxNode
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

# The statements on one line, with `; ` between them, and a `;` after the last
# one when the line ends with it.
@projection_template JuliaToplevelToSyntaxNode JuliaToplevel (p, t) ->
    SyntaxNode(collection(:statements);
               sep=TextString("; ", p.delim),
               close=TextString(() -> t.trailing_semicolon ? ";" : "", p.delim))

# ── JuliaIfToSyntaxNode ─────────────────────────────────────────────────────

@projection struct JuliaIfToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

# `if cond … [else …] end`. The template renders every element
# unconditionally; we make the surrounding whitespace + `else`
# keyword thunks so an empty else-branch collapses to nothing, and
# a `JuliaIf` else-branch renders as `elseif` (dropping the plain
# `else` line — the nested if prints its own `if`).
@projection_template JuliaIfToSyntaxNode JuliaIf (p, m) ->
    SyntaxConcatenation([
        SyntaxLeaf(TextString("if ", p.keyword)),
        project(:condition),
        project(:then_branch),
        SyntaxLeaf(TextString(() -> _if_else_prefix(m.else_branch), p.keyword)),
        project(:else_branch),
        SyntaxLeaf(TextString(() -> _if_end_line(m.else_branch), p.keyword)),
    ])

# The keyword that leads the else-branch. `JuliaBlock` already emits
# both a leading AND a trailing "\n" (line-chrome around every
# statement plus one before the close). So the prefix is a plain
# `else` — the block on either side supplies the newlines, and any
# extra "\n" here would double-space.
#   empty   → ""     (no else clause)
#   JuliaIf → "else" (nested child prints its own `if` → `elseif`)
#   other   → "else"
_if_else_prefix(else_branch) = _is_empty_else(else_branch) ? "" : "else"

# The closing `end` line. The then/else block's own trailing chrome
# supplies the leading newline. Nested JuliaIf else-branches print
# their own `end`, so suppress ours.
_if_end_line(else_branch) = else_branch isa JuliaIf ? "" : "end"

# `if … end` with no explicit else parses to `JuliaEmpty`; also
# treat `JuliaNothing` and empty blocks as absent so hand-crafted
# ASTs land the same way.
_is_empty_else(x) =
    x isa JuliaEmpty ||
    x isa JuliaNothing ||
    (x isa JuliaBlock && isempty(getfield(x, :statements)[]))

# ── JuliaFunctionToSyntaxNode ───────────────────────────────────────────────

@projection struct JuliaFunctionToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    delim::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

# The result type prints after the parameter list; `JuliaEmpty` prints nothing,
# so a function without one needs no separate rule.
@projection_template JuliaFunctionToSyntaxNode JuliaFunction (p, f) ->
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("function", p.keyword);
                                                           close=TextString(" ", p.keyword.font, color_default)),
                                                project(:name),
                                                SyntaxNode(collection(:params);
                                                           open=TextString("(", p.delim),
                                                           close=TextString(")", p.delim),
                                                           sep=TextString(", ", p.delim)),
                                                SyntaxNode([project(:result_type)];
                                                           open=TextString(() -> f.result_type isa JuliaEmpty ? "" : "::",
                                                                           p.delim)),
                                                project(:where_clause) ]),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── JuliaFunctionDeclarationToSyntaxNode ────────────────────────────────────

# ` where {T, S}` — printed by the clause itself, so a function without one
# holds a `JuliaEmpty` and prints nothing.
@projection struct JuliaWhereParametersToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
    delim::ImmutableCell{StyleText}   = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)
end

@projection_template JuliaWhereParametersToSyntaxNode JuliaWhereParameters (p, w) ->
    SyntaxNode(collection(:parameters);
               open=TextString(" where {", p.keyword),
               close=TextString("}", p.delim),
               sep=TextString(", ", p.delim))

@projection struct JuliaFunctionDeclarationToSyntaxNode
    keyword::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
end

@projection_template JuliaFunctionDeclarationToSyntaxNode JuliaFunctionDeclaration (p, f) ->
    SyntaxNode([project(:name)];
               open=TextString("function ", p.keyword),
               close=TextString(" end", p.keyword))

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

# ── JuliaObjectToSyntaxLeaf ─────────────────────────────────────────────────

"""
    JuliaObjectToSyntaxLeaf()

An object that stands in Julia code, a document that is not Julia, such as a
widget a person pasted into a form, as one leaf: its title in angle marks,
`⟨Table⟩`, or its type name when it has no title. A line of syntax holds only
text, so the object can not draw as itself here.

The leaf takes no key, so a key never reaches the object's own table: the
object is selected, copied and replaced whole. It shows a selection only when
the object is selected whole.
"""
@projection struct JuliaObjectToSyntaxLeaf
    label::ImmutableCell{StyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_violet)
end

function print_document(p::JuliaObjectToSyntaxLeaf, recursion, object, ctx)
    selection = Cell(@computation(getfield(object, :selection)[] isa EmptyReference ?
                                  EmptyReference() : nothing))
    SimpleIoMap(p, object, SyntaxLeaf(TextString(_get_julia_object_label(object), p.label);
                                      selection))
end

_get_julia_object_label(object) =
    "⟨" * string(something(get_document_title(object), nameof(typeof(object)))) * "⟩"

map_reference_forward(::JuliaObjectToSyntaxLeaf, iomap, reference) =
    reference isa EmptyReference ? EmptyReference() : nothing

# Any place in the label names the object whole.
map_reference_backward(::JuliaObjectToSyntaxLeaf, iomap, reference) = EmptyReference()

read_intent(::JuliaObjectToSyntaxLeaf, iomap, ::Union{KeyPress, KeyDown}) = nothing

# ── JuliaToSyntax (composite) ───────────────────────────────────────────────

"""
    JuliaToSyntax(entries::Pair...) -> TypeDispatchingProjection

The Julia notation, one entry for each type of the domain. A domain that embeds
Julia code, such as a state machine, a process or a formula, passes the entries
of its own types. They come after the entries of the Julia nodes and before the
last entry, which draws any other document as an object that stands in the code.
The dispatch takes the first entry that matches, so a node of the embedding
domain never reaches the last entry.

# Example

    FsmToSyntax() = JuliaToSyntax(FsmState => FsmStateToSyntaxNode(), …)
"""
function JuliaToSyntax(entries::Pair...)
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
        JuliaBinaryOperation        => JuliaBinaryOperationToSyntaxNode(),
        JuliaUnaryOperation         => JuliaUnaryOperationToSyntaxNode(),
        JuliaCall            => JuliaCallToSyntaxNode(),
        JuliaSplat           => JuliaSplatToSyntaxNode(),
        JuliaBroadcast       => JuliaBroadcastToSyntaxNode(),
        JuliaStringInterpolation => JuliaStringInterpolationToSyntaxNode(),
        JuliaStringChunk     => JuliaStringChunkToSyntaxLeaf(),
        JuliaInterpolation   => JuliaInterpolationToSyntaxNode(),
        JuliaWhere           => JuliaWhereToSyntaxNode(),
        JuliaComprehension   => JuliaComprehensionToSyntaxNode(),
        JuliaDo              => JuliaDoToSyntaxNode(),
        JuliaLet             => JuliaLetToSyntaxNode(),
        JuliaNamedTuple      => JuliaNamedTupleToSyntaxNode(),
        JuliaMacroCall       => JuliaMacroCallToSyntaxNode(),
        JuliaConst           => JuliaConstToSyntaxNode(),
        JuliaDocstring       => JuliaDocstringToSyntaxNode(),
        JuliaAbstractType    => JuliaAbstractTypeToSyntaxNode(),
        JuliaStruct          => JuliaStructToSyntaxNode(),
        JuliaSubtype         => JuliaSubtypeToSyntaxNode(),
        JuliaCurly           => JuliaCurlyToSyntaxNode(),
        JuliaAnonymousTypeAnnotation => JuliaAnonymousTypeAnnotationToSyntaxNode(),
        JuliaEmpty                   => JuliaEmptyToSyntaxLeaf(),
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
        JuliaToplevel        => JuliaToplevelToSyntaxNode(),
        JuliaIf              => JuliaIfToSyntaxNode(),
        JuliaFunction        => JuliaFunctionToSyntaxNode(),
        JuliaFunctionDeclaration => JuliaFunctionDeclarationToSyntaxNode(),
        JuliaWhereParameters => JuliaWhereParametersToSyntaxNode(),
        JuliaUsing           => JuliaUsingToSyntaxNode(),
        JuliaModuleDefinition       => JuliaModuleDefinitionToSyntaxNode(),
        JuliaLambda          => JuliaLambdaToSyntaxNode(),
        # The types of a domain that embeds Julia code.
        entries...,
        # Last, because the first entry that matches is the one used: a node that
        # is not Julia is an object that stands in the code.
        Document             => JuliaObjectToSyntaxLeaf(),
    )
end

function _julia_string_escape(s::AbstractString)
    buf = IOBuffer()
    for ch in s
        ch == '\\' ? write(buf, "\\\\") :
        ch == '"'  ? write(buf, "\\\"") :
        ch == '\n' ? write(buf, "\\n")  :
        ch == '\r' ? write(buf, "\\r")  :
        ch == '\t' ? write(buf, "\\t")  :
                     write(buf, ch)
    end
    String(take!(buf))
end

# ── Natural-format registration ─────────────────────────────────────────────
# Julia's seams for import_document / export_document / read+write_document_file.
make_document_seed(::Val{:jl}) = JuliaInsertion()

# ── What this domain's natural notation is ──────────────────────────────────
# One statement: the rung it starts at and how to build it, the format it is
# written in, the extension that names the format back, and how to read that text
# in again. Runtime state, so `__init__` rather than a top-level call.
