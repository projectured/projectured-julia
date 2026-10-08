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
@projection UntrackedCell struct JuliaIdentifierToSyntaxLeaf
    style::StyleText = get_julia_style(nothing, :identifier_text)
end

@projection_template JuliaIdentifierToSyntaxLeaf JuliaIdentifier (p, v) ->
    SyntaxLeaf(TextString(() -> v.name, p.style))

# ── JuliaIntegerToSyntaxLeaf ────────────────────────────────────────────────

@projection UntrackedCell struct JuliaIntegerToSyntaxLeaf
    style::StyleText = get_julia_style(nothing, :number_text)
end

@projection_template JuliaIntegerToSyntaxLeaf JuliaInteger (p, v) ->
    SyntaxLeaf(TextString(() -> string(v.value), p.style))

# ── JuliaFloatToSyntaxLeaf ──────────────────────────────────────────────────

@projection UntrackedCell struct JuliaFloatToSyntaxLeaf
    style::StyleText = get_julia_style(nothing, :number_text)
end

@projection_template JuliaFloatToSyntaxLeaf JuliaFloat (p, v) ->
    SyntaxLeaf(TextString(() -> string(v.value), p.style))

# ── JuliaStringToSyntaxLeaf ─────────────────────────────────────────────────

@projection UntrackedCell struct JuliaStringToSyntaxLeaf
    style::StyleText = get_julia_style(nothing, :string_text)
    quote_style::StyleText = get_julia_style(nothing, :punctuation_text)
end

# The value is escaped on the way out — a quote, a backslash — and the parser
# unescapes it on the way in, so any string round-trips as source.
@projection_template JuliaStringToSyntaxLeaf JuliaString (p, v) ->
    SyntaxLeaf(TextString(() -> _julia_string_escape(v.value), p.style);
               open=TextString("\"", p.quote_style),
               close=TextString("\"", p.quote_style))

# ── JuliaBoolToSyntaxLeaf ───────────────────────────────────────────────────

@projection UntrackedCell struct JuliaBoolToSyntaxLeaf
    style::StyleText = get_julia_style(nothing, :bool_text)
end

# Guard the `? :` against a transient non-`Bool` value (a mid-edit `bound` read can clear
# the type-erased `value` cell) — the same crash `JsonBoolToSyntaxLeaf` fixes. Rendering
# empty for the cleared state matches this file's plain-thunk style (cf. `string(v.value)`).
@projection_template JuliaBoolToSyntaxLeaf JuliaBool (p, v) ->
    SyntaxLeaf(TextString(() -> v.value isa Bool ? (v.value ? "true" : "false") : "", p.style))

# ── JuliaNothingToSyntaxLeaf ────────────────────────────────────────────────

@projection UntrackedCell struct JuliaNothingToSyntaxLeaf
    style::StyleText = get_julia_style(nothing, :nothing_text)
end

@projection_template JuliaNothingToSyntaxLeaf JuliaNothing (p, v) ->
    SyntaxLeaf(TextString("nothing", p.style))

# ── JuliaSymbolToSyntaxLeaf ─────────────────────────────────────────────────

@projection UntrackedCell struct JuliaSymbolToSyntaxLeaf
    style::StyleText = get_julia_style(nothing, :symbol_text)
end

@projection_template JuliaSymbolToSyntaxLeaf JuliaSymbol (p, v) ->
    SyntaxLeaf(TextString(() -> v.name, p.style);
               open=TextString(":", p.style))

# ── JuliaCharToSyntaxLeaf ───────────────────────────────────────────────────

@projection UntrackedCell struct JuliaCharToSyntaxLeaf
    style::StyleText = get_julia_style(nothing, :char_text)
    quote_style::StyleText = get_julia_style(nothing, :punctuation_text)
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
               open = TextString("(", style.font, style.color),
               close = TextString(")", style.font, style.color))

# ── JuliaBinaryOperationToSyntaxNode ───────────────────────────────────────────────

@projection UntrackedCell struct JuliaBinaryOperationToSyntaxNode
    op::StyleText = get_julia_style(nothing, :operator_text)
    delimiter::StyleText = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaBinaryOperationToSyntaxNode JuliaBinaryOperation (p, m) ->
    SyntaxConcatenation(() -> begin
        operator = m.operator
        left  = _julia_operand_parens(m.left,  operator, false) ?
                _julia_parenthesize(project(:left),  p.delimiter) : project(:left)
        right = _julia_operand_parens(m.right, operator, true) ?
                _julia_parenthesize(project(:right), p.delimiter) : project(:right)
        [ left,
          SyntaxLeaf(TextString(() -> _julia_operator_string(m.operator), p.op);
                     open=TextString(" ", p.op.font),
                     close=TextString(" ", p.op.font)),
          right ]
    end)

# ── JuliaUnaryOperationToSyntaxNode ────────────────────────────────────────────────

@projection UntrackedCell struct JuliaUnaryOperationToSyntaxNode
    op::StyleText = get_julia_style(nothing, :operator_text)
    delimiter::StyleText = get_julia_style(nothing, :punctuation_text)
end

# A unary operator binds tighter than every binary one, so a binary operand is
# always parenthesized.
@projection_template JuliaUnaryOperationToSyntaxNode JuliaUnaryOperation (p, u) ->
    SyntaxConcatenation(() -> begin
        operand = u.operand isa JuliaBinaryOperation ?
                  _julia_parenthesize(project(:operand), p.delimiter) : project(:operand)
        [ SyntaxLeaf(TextString(() -> _julia_operator_string(u.operator), p.op)), operand ]
    end)

# ── JuliaCallToSyntaxNode ───────────────────────────────────────────────────

@projection UntrackedCell struct JuliaCallToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
    # A call's function name is coloured distinctly from a plain variable.
    callee::StyleText = get_julia_style(nothing, :callee_text)
end

# F1 (nested `(args)` sub-node) + F3 (callee override): a bare identifier callee is
# a function name → render it through a function-coloured identifier leaf; anything
# else (a field access, an expression) recurses through its own projection.
#
# The arguments and the keyword arguments are two sub-nodes: `(a, b` and
# `; k = 1)`. The second one opens with `; ` only when it holds a keyword, so a call
# with none reads `(a, b)`, and it closes the call.
@projection_template JuliaCallToSyntaxNode JuliaCall (p, c) ->
    SyntaxConcatenation([ project(:callee; as = v -> v isa JuliaIdentifier ? JuliaIdentifierToSyntaxLeaf(style = p.callee) : nothing),
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

@projection UntrackedCell struct JuliaMacroCallToSyntaxNode
    name_style::StyleText = get_julia_style(nothing, :callee_text)
    sep_style::StyleText  = get_julia_style(nothing, :punctuation_text)
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

@projection UntrackedCell struct JuliaConstToSyntaxNode
    keyword_style::StyleText = get_julia_style(nothing, :keyword_text)
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

@projection UntrackedCell struct JuliaDocstringToSyntaxNode
    doc_style::StyleText   = get_julia_style(nothing, :string_text)
    fence_style::StyleText = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaDocstringToSyntaxNode JuliaDocstring (p, d) ->
    SyntaxConcatenation([
        SyntaxLeaf(TextString("\"\"\"\n", p.fence_style)),
        SyntaxLeaf(TextString(() -> d.text, p.doc_style)),
        SyntaxLeaf(TextString("\n\"\"\"\n", p.fence_style)),
        project(:subject),
    ])

# ── JuliaAbstractTypeToSyntaxNode ──────────────────────────────────────────

@projection UntrackedCell struct JuliaAbstractTypeToSyntaxNode
    keyword_style::StyleText = get_julia_style(nothing, :keyword_text)
    sep_style::StyleText     = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaAbstractTypeToSyntaxNode JuliaAbstractType (p, a) ->
    SyntaxConcatenation([
        SyntaxLeaf(TextString("abstract type ", p.keyword_style)),
        project(:header),
        SyntaxLeaf(TextString(" end", p.keyword_style)),
    ])

# ── JuliaStructToSyntaxNode ─────────────────────────────────────────────────

@projection UntrackedCell struct JuliaStructToSyntaxNode
    keyword_style::StyleText = get_julia_style(nothing, :keyword_text)
    sep_style::StyleText     = get_julia_style(nothing, :punctuation_text)
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

@projection UntrackedCell struct JuliaModuleDefinitionToSyntaxNode
    keyword_style::StyleText = get_julia_style(nothing, :keyword_text)
    name_style::StyleText    = get_julia_style(nothing, :name_text)
    sep_style::StyleText     = get_julia_style(nothing, :punctuation_text)
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

@projection UntrackedCell struct JuliaSubtypeToSyntaxNode
    op_style::StyleText = get_julia_style(nothing, :operator_text)
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

@projection UntrackedCell struct JuliaCurlyToSyntaxNode
    brace_style::StyleText = get_julia_style(nothing, :punctuation_text)
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

@projection UntrackedCell struct JuliaTernaryToSyntaxNode
    op::StyleText = get_julia_style(nothing, :operator_text)
end

@projection_template JuliaTernaryToSyntaxNode JuliaTernary (p, t) ->
    SyntaxConcatenation([ project(:condition),
                          SyntaxLeaf(TextString("?", p.op);
                                     open=TextString(" ", p.op.font),
                                     close=TextString(" ", p.op.font)),
                          project(:then_branch),
                          SyntaxLeaf(TextString(":", p.op);
                                     open=TextString(" ", p.op.font),
                                     close=TextString(" ", p.op.font)),
                          project(:else_branch) ])

# ── JuliaIndexToSyntaxNode ──────────────────────────────────────────────────

@projection UntrackedCell struct JuliaIndexToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaIndexToSyntaxNode JuliaIndex (p, x) ->
    SyntaxConcatenation([ project(:collection),
                          SyntaxNode(collection(:indices);
                                     open=TextString("[", p.delim),
                                     close=TextString("]", p.delim),
                                     sep=TextString(", ", p.delim)) ])

# ── JuliaFieldAccessToSyntaxNode ────────────────────────────────────────────

@projection UntrackedCell struct JuliaFieldAccessToSyntaxNode
    dot::StyleText = get_julia_style(nothing, :operator_text)
end

@projection_template JuliaFieldAccessToSyntaxNode JuliaFieldAccess (p, f) ->
    SyntaxConcatenation([ project(:object),
                          SyntaxLeaf(TextString(".", p.dot)),
                          project(:field) ])

# ── JuliaTupleToSyntaxNode ──────────────────────────────────────────────────

@projection UntrackedCell struct JuliaTupleToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaTupleToSyntaxNode JuliaTuple (p, t) ->
    SyntaxNode(collection(:elements);
               open=TextString("(", p.delim),
               close=TextString(")", p.delim),
               sep=TextString(", ", p.delim))

# ── JuliaArrayToSyntaxNode ──────────────────────────────────────────────────

@projection UntrackedCell struct JuliaArrayToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaArrayToSyntaxNode JuliaArray (p, a) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", p.delim),
               close=TextString("]", p.delim),
               sep=TextString(", ", p.delim))

# ── JuliaRangeToSyntaxNode ──────────────────────────────────────────────────

@projection UntrackedCell struct JuliaRangeToSyntaxNode
    op::StyleText = get_julia_style(nothing, :operator_text)
end

# F2: the child list depends on the optional `step` — a reactive marker thunk.
@projection_template JuliaRangeToSyntaxNode JuliaRange (p, r) ->
    SyntaxConcatenation(() -> r.step === nothing ?
                            [ project(:start), SyntaxLeaf(TextString(":", p.op)), project(:stop) ] :
                            [ project(:start), SyntaxLeaf(TextString(":", p.op)),
                              project(:step),  SyntaxLeaf(TextString(":", p.op)), project(:stop) ])

# ── JuliaTypeAnnotationToSyntaxNode ─────────────────────────────────────────

@projection UntrackedCell struct JuliaTypeAnnotationToSyntaxNode
    op::StyleText = get_julia_style(nothing, :operator_text)
end

@projection_template JuliaTypeAnnotationToSyntaxNode JuliaTypeAnnotation (p, t) ->
    SyntaxConcatenation([ project(:value),
                          SyntaxLeaf(TextString("::", p.op)),
                          project(:type) ])

# The anonymous `::T` form — nothing before the `::`, just the type.

@projection UntrackedCell struct JuliaAnonymousTypeAnnotationToSyntaxNode
    op::StyleText = get_julia_style(nothing, :operator_text)
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

@projection UntrackedCell struct JuliaAssignmentToSyntaxNode
    op::StyleText = get_julia_style(nothing, :operator_text)
end

@projection_template JuliaAssignmentToSyntaxNode JuliaAssignment (p, a) ->
    SyntaxConcatenation([ project(:target),
                          SyntaxLeaf(TextString(() -> _julia_operator_string(a.operator), p.op);
                                     open=TextString(" ", p.op.font),
                                     close=TextString(" ", p.op.font)),
                          project(:value) ])

# ── JuliaForIteratorToSyntaxNode ────────────────────────────────────────────

@projection UntrackedCell struct JuliaForIteratorToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
end

@projection_template JuliaForIteratorToSyntaxNode JuliaForIterator (p, it) ->
    SyntaxConcatenation([ project(:variable),
                          SyntaxLeaf(TextString("in", p.keyword);
                                     open=TextString(" ", p.keyword.font),
                                     close=TextString(" ", p.keyword.font)),
                          project(:iterable) ])

# ── JuliaForToSyntaxNode ────────────────────────────────────────────────────

@projection UntrackedCell struct JuliaForToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaForToSyntaxNode JuliaFor (p, f) ->
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("for", p.keyword);
                                                           close=TextString(" ", p.keyword.font)),
                                                SyntaxNode(collection(:iterators); sep=TextString(", ", p.delim)) ]),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── JuliaWhileToSyntaxNode ──────────────────────────────────────────────────

@projection UntrackedCell struct JuliaWhileToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
end

@projection_template JuliaWhileToSyntaxNode JuliaWhile (p, w) ->
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("while", p.keyword);
                                                           close=TextString(" ", p.keyword.font)),
                                                project(:condition) ]),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── JuliaReturnToSyntaxNode ─────────────────────────────────────────────────

@projection UntrackedCell struct JuliaReturnToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
end

# F2: bare `return` vs `return <value>` — a reactive marker thunk on optional `value`.
@projection_template JuliaReturnToSyntaxNode JuliaReturn (p, r) ->
    SyntaxConcatenation(() -> r.value === nothing ?
                            [ SyntaxLeaf(TextString("return", p.keyword)) ] :
                            [ SyntaxLeaf(TextString("return", p.keyword);
                                         close=TextString(" ", p.keyword.font)),
                              project(:value) ])

# ── JuliaLambdaToSyntaxNode ─────────────────────────────────────────────────

@projection UntrackedCell struct JuliaLambdaToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
    arrow::StyleText = get_julia_style(nothing, :operator_text)
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

@projection UntrackedCell struct JuliaSplatToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaSplatToSyntaxNode JuliaSplat (p, s) ->
    SyntaxNode([project(:value)]; close=TextString("...", p.delim))

@projection UntrackedCell struct JuliaBroadcastToSyntaxNode
    delim::StyleText  = get_julia_style(nothing, :punctuation_text)
    callee::StyleText = get_julia_style(nothing, :callee_text)
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
@projection UntrackedCell struct JuliaStringInterpolationToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :string_text)
end

@projection_template JuliaStringInterpolationToSyntaxNode JuliaStringInterpolation (p, s) ->
    SyntaxNode(collection(:parts);
               open=TextString("\"", p.delim),
               close=TextString("\"", p.delim))

# A literal run inside an interpolated string: its text, and nothing around it.
@projection UntrackedCell struct JuliaStringChunkToSyntaxLeaf
    style::StyleText = get_julia_style(nothing, :string_text)
end

@projection_template JuliaStringChunkToSyntaxLeaf JuliaStringChunk (p, c) ->
    SyntaxLeaf(TextString(() -> c.text, p.style))

@projection UntrackedCell struct JuliaInterpolationToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :operator_text)
end

@projection_template JuliaInterpolationToSyntaxNode JuliaInterpolation (p, i) ->
    SyntaxNode([project(:value)];
               open=TextString("\$(", p.delim), close=TextString(")", p.delim))

@projection UntrackedCell struct JuliaWhereToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
    delim::StyleText   = get_julia_style(nothing, :punctuation_text)
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
@projection UntrackedCell struct JuliaComprehensionToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
    delim::StyleText   = get_julia_style(nothing, :punctuation_text)
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

@projection UntrackedCell struct JuliaDoToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
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

@projection UntrackedCell struct JuliaLetToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
    delim::StyleText   = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaLetToSyntaxNode JuliaLet (p, l) ->
    SyntaxConcatenation([ SyntaxNode(collection(:bindings);
                                     open=TextString("let ", p.keyword),
                                     sep=TextString(", ", p.delim)),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

@projection UntrackedCell struct JuliaNamedTupleToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaNamedTupleToSyntaxNode JuliaNamedTuple (p, n) ->
    SyntaxNode(collection(:entries);
               open=TextString("(; ", p.delim),
               close=TextString(")", p.delim),
               sep=TextString(", ", p.delim))

# ── JuliaUsingToSyntaxNode ──────────────────────────────────────────────────

@projection UntrackedCell struct JuliaUsingToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
    path::StyleText    = get_julia_style(nothing, :plain_text)
end

# `using`/`import` keyword (highlighted) followed by the module path leaf. Both
# are introduced display leaves (the path is a flat string, not a nested
# expression), so the node has no recursive children; reference mapping uses the
# template's generic ∅↔∅ default (see the note above the composite table).
@projection_template JuliaUsingToSyntaxNode JuliaUsing (p, u) ->
    SyntaxConcatenation([ SyntaxLeaf(TextString(() -> string(u.keyword), p.keyword);
                                     close=TextString(" ", p.keyword.font)),
                          SyntaxLeaf(TextString(() -> string(u.path), p.path)) ])

# ── JuliaBreakToSyntaxLeaf ──────────────────────────────────────────────────

@projection UntrackedCell struct JuliaBreakToSyntaxLeaf
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
end

@projection_template JuliaBreakToSyntaxLeaf JuliaBreak (p, b) ->
    SyntaxLeaf(TextString("break", p.keyword))

# ── JuliaContinueToSyntaxLeaf ───────────────────────────────────────────────

@projection UntrackedCell struct JuliaContinueToSyntaxLeaf
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
end

@projection_template JuliaContinueToSyntaxLeaf JuliaContinue (p, c) ->
    SyntaxLeaf(TextString("continue", p.keyword))

# ── JuliaTryToSyntaxNode ────────────────────────────────────────────────────

@projection UntrackedCell struct JuliaTryToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
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
                                                                     close=TextString(" ", p.keyword.font)),
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

@projection UntrackedCell struct JuliaBeginToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
end

@projection_template JuliaBeginToSyntaxNode JuliaBegin (p, b) ->
    SyntaxConcatenation([ SyntaxLeaf(TextString("begin", p.keyword)),
                          project(:body),
                          SyntaxLeaf(TextString("end", p.keyword)) ])

# ── JuliaBlockToSyntaxNode ──────────────────────────────────────────────────

@projection UntrackedCell struct JuliaBlockToSyntaxNode
    indentation::Int = 1
end

@projection_template JuliaBlockToSyntaxNode JuliaBlock (p, b) ->
    SyntaxNode(collection(:statements); indentation=p.indentation)

# ── JuliaToplevelToSyntaxNode ───────────────────────────────────────────────

@projection UntrackedCell struct JuliaToplevelToSyntaxNode
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
end

# The statements on one line, with `; ` between them, and a `;` after the last
# one when the line ends with it.
@projection_template JuliaToplevelToSyntaxNode JuliaToplevel (p, t) ->
    SyntaxNode(collection(:statements);
               sep=TextString("; ", p.delim),
               close=TextString(() -> t.trailing_semicolon ? ";" : "", p.delim))

# ── JuliaIfToSyntaxNode ─────────────────────────────────────────────────────

@projection UntrackedCell struct JuliaIfToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
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

@projection UntrackedCell struct JuliaFunctionToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
    delim::StyleText = get_julia_style(nothing, :punctuation_text)
end

# The result type prints after the parameter list; `JuliaEmpty` prints nothing,
# so a function without one needs no separate rule.
@projection_template JuliaFunctionToSyntaxNode JuliaFunction (p, f) ->
    SyntaxConcatenation([ SyntaxConcatenation([ SyntaxLeaf(TextString("function", p.keyword);
                                                           close=TextString(" ", p.keyword.font)),
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
@projection UntrackedCell struct JuliaWhereParametersToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
    delim::StyleText   = get_julia_style(nothing, :punctuation_text)
end

@projection_template JuliaWhereParametersToSyntaxNode JuliaWhereParameters (p, w) ->
    SyntaxNode(collection(:parameters);
               open=TextString(" where {", p.keyword),
               close=TextString("}", p.delim),
               sep=TextString(", ", p.delim))

@projection UntrackedCell struct JuliaFunctionDeclarationToSyntaxNode
    keyword::StyleText = get_julia_style(nothing, :keyword_text)
end

@projection_template JuliaFunctionDeclarationToSyntaxNode JuliaFunctionDeclaration (p, f) ->
    SyntaxNode([project(:name)];
               open=TextString("function ", p.keyword),
               close=TextString(" end", p.keyword))

# ── Reference mapping & readers ─────────────────────────────────────────────
#
# Every projection here is written with `@projection_template`; all 32 get their
# reference mapping and readers for free from the template engine's generic
# `TemplateIoMap` machinery. Opaque leaves map `∅↔∅` (mirroring the old generic
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
# whole-element granularity only. Making the leaves `bound` would need a caret on
# the projection-introduced structural tokens (`function`, `(`, `)`, `==`, `if`,
# `end`, …), which have no Julia pre-image, named by the projection's own
# introduced step. That is the still-deferred follow-up (the High finding in
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
@projection UntrackedCell struct JuliaObjectToSyntaxLeaf
    label::StyleText = get_julia_style(nothing, :identifier_text)
end

function print_document(p::JuliaObjectToSyntaxLeaf, recursion, object, ctx)
    paths = make_output_path_cells(object, path -> path isa EmptyReference ? EmptyReference() : nothing)
    SimpleIoMap(p, object, SyntaxLeaf(TextString(_get_julia_object_label(object), p.label);
                                      paths...))
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
    JuliaToSyntax(entries::Pair...; theme = nothing, syntax_theme = nothing) -> TypeDispatchingProjection

The Julia notation, one entry for each type of the domain. A domain that embeds
Julia code, such as a state machine, a process or a formula, passes the entries
of its own types. They come after the entries of the Julia nodes and before the
last entry, which draws any other document as an object that stands in the code.
The dispatch takes the first entry that matches, so a node of the embedding
domain never reaches the last entry.

The builder gives each projection the style of its role with `get_julia_style`,
from `theme`, a `JuliaTheme` scaled or not, or the default styles for
`nothing`; a domain that embeds Julia code passes its own `syntax_theme`
through, for an entry of its own that styles through `SyntaxModule`.

# Example

    FsmToSyntax() = JuliaToSyntax(FsmState => FsmStateToSyntaxNode(), …)
"""
function JuliaToSyntax(entries::Pair...; theme = nothing, syntax_theme = nothing)
    get_style(name) = get_julia_style(theme, name)
    string_style        = (style = get_style(:string_text),)
    number_style        = (style = get_style(:number_text),)
    op_delimiter_style  = (op = get_style(:operator_text), delimiter = get_style(:punctuation_text))
    delim_callee_style  = (delim = get_style(:punctuation_text), callee = get_style(:callee_text))
    keyword_sep_style   = (keyword_style = get_style(:keyword_text), sep_style = get_style(:punctuation_text))
    op_only_style       = (op = get_style(:operator_text),)
    delim_only_style    = (delim = get_style(:punctuation_text),)
    keyword_only_style  = (keyword = get_style(:keyword_text),)
    keyword_delim_style = (keyword = get_style(:keyword_text), delim = get_style(:punctuation_text))
    TypeDispatchingProjection(
        JuliaInsertion       => JuliaInsertionToSyntaxLeaf(; theme),
        JuliaIdentifier      => JuliaIdentifierToSyntaxLeaf(; style = get_style(:identifier_text)),
        JuliaInteger         => JuliaIntegerToSyntaxLeaf(; number_style...),
        JuliaFloat           => JuliaFloatToSyntaxLeaf(; number_style...),
        JuliaString          => JuliaStringToSyntaxLeaf(; string_style...,
                                                        quote_style = get_style(:punctuation_text)),
        JuliaBool            => JuliaBoolToSyntaxLeaf(; style = get_style(:bool_text)),
        JuliaNothing         => JuliaNothingToSyntaxLeaf(; style = get_style(:nothing_text)),
        JuliaSymbol          => JuliaSymbolToSyntaxLeaf(; style = get_style(:symbol_text)),
        JuliaChar            => JuliaCharToSyntaxLeaf(; style = get_style(:char_text),
                                                      quote_style = get_style(:punctuation_text)),
        JuliaBinaryOperation        => JuliaBinaryOperationToSyntaxNode(; op_delimiter_style...),
        JuliaUnaryOperation         => JuliaUnaryOperationToSyntaxNode(; op_delimiter_style...),
        JuliaCall            => JuliaCallToSyntaxNode(; delim_callee_style...),
        JuliaSplat           => JuliaSplatToSyntaxNode(; delim_only_style...),
        JuliaBroadcast       => JuliaBroadcastToSyntaxNode(; delim_callee_style...),
        JuliaStringInterpolation => JuliaStringInterpolationToSyntaxNode(; delim = get_style(:string_text)),
        JuliaStringChunk     => JuliaStringChunkToSyntaxLeaf(; string_style...),
        JuliaInterpolation   => JuliaInterpolationToSyntaxNode(; delim = get_style(:operator_text)),
        JuliaWhere           => JuliaWhereToSyntaxNode(; keyword_delim_style...),
        JuliaComprehension   => JuliaComprehensionToSyntaxNode(; keyword_delim_style...),
        JuliaDo              => JuliaDoToSyntaxNode(; keyword_only_style...),
        JuliaLet             => JuliaLetToSyntaxNode(; keyword_delim_style...),
        JuliaNamedTuple      => JuliaNamedTupleToSyntaxNode(; delim_only_style...),
        JuliaMacroCall       => JuliaMacroCallToSyntaxNode(; name_style = get_style(:callee_text),
                                                             sep_style = get_style(:punctuation_text)),
        JuliaConst           => JuliaConstToSyntaxNode(; keyword_style = get_style(:keyword_text)),
        JuliaDocstring       => JuliaDocstringToSyntaxNode(; doc_style = get_style(:string_text),
                                                             fence_style = get_style(:punctuation_text)),
        JuliaAbstractType    => JuliaAbstractTypeToSyntaxNode(; keyword_sep_style...),
        JuliaStruct          => JuliaStructToSyntaxNode(; keyword_sep_style...),
        JuliaSubtype         => JuliaSubtypeToSyntaxNode(; op_style = get_style(:operator_text)),
        JuliaCurly           => JuliaCurlyToSyntaxNode(; brace_style = get_style(:punctuation_text)),
        JuliaAnonymousTypeAnnotation => JuliaAnonymousTypeAnnotationToSyntaxNode(; op_only_style...),
        JuliaEmpty                   => JuliaEmptyToSyntaxLeaf(),
        JuliaTernary         => JuliaTernaryToSyntaxNode(; op_only_style...),
        JuliaIndex           => JuliaIndexToSyntaxNode(; delim_only_style...),
        JuliaFieldAccess     => JuliaFieldAccessToSyntaxNode(; dot = get_style(:operator_text)),
        JuliaTuple           => JuliaTupleToSyntaxNode(; delim_only_style...),
        JuliaArray           => JuliaArrayToSyntaxNode(; delim_only_style...),
        JuliaRange           => JuliaRangeToSyntaxNode(; op_only_style...),
        JuliaTypeAnnotation  => JuliaTypeAnnotationToSyntaxNode(; op_only_style...),
        JuliaAssignment      => JuliaAssignmentToSyntaxNode(; op_only_style...),
        JuliaForIterator     => JuliaForIteratorToSyntaxNode(; keyword_only_style...),
        JuliaFor             => JuliaForToSyntaxNode(; keyword_delim_style...),
        JuliaWhile           => JuliaWhileToSyntaxNode(; keyword_only_style...),
        JuliaReturn          => JuliaReturnToSyntaxNode(; keyword_only_style...),
        JuliaBreak           => JuliaBreakToSyntaxLeaf(; keyword_only_style...),
        JuliaContinue        => JuliaContinueToSyntaxLeaf(; keyword_only_style...),
        JuliaTry             => JuliaTryToSyntaxNode(; keyword_only_style...),
        JuliaBegin           => JuliaBeginToSyntaxNode(; keyword_only_style...),
        JuliaBlock           => JuliaBlockToSyntaxNode(),
        JuliaToplevel        => JuliaToplevelToSyntaxNode(; delim_only_style...),
        JuliaIf              => JuliaIfToSyntaxNode(; keyword_only_style...),
        JuliaFunction        => JuliaFunctionToSyntaxNode(; keyword_delim_style...),
        JuliaFunctionDeclaration => JuliaFunctionDeclarationToSyntaxNode(; keyword_only_style...),
        JuliaWhereParameters => JuliaWhereParametersToSyntaxNode(; keyword_delim_style...),
        JuliaUsing           => JuliaUsingToSyntaxNode(; keyword = get_style(:keyword_text),
                                                          path = get_style(:plain_text)),
        JuliaModuleDefinition       => JuliaModuleDefinitionToSyntaxNode(; keyword_style = get_style(:keyword_text),
                                                                           name_style = get_style(:name_text),
                                                                           sep_style = get_style(:punctuation_text)),
        JuliaLambda          => JuliaLambdaToSyntaxNode(; delim = get_style(:punctuation_text),
                                                           arrow = get_style(:operator_text)),
        # The types of a domain that embeds Julia code.
        entries...,
        # Last, because the first entry that matches is the one used: a node that
        # is not Julia is an object that stands in the code.
        Document             => JuliaObjectToSyntaxLeaf(; label = get_style(:identifier_text)),
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
