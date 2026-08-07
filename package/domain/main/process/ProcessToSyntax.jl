"""
    ProcessToSyntaxModule

Process → Syntax projection: the **natural notation**, the primary edit
surface of the process domain.

```
process csma_transmit(frame)
  step "prepare" / x = encode(frame)
  while attempts < max_attempts
    if carrier_free()
      step / start_tx!(ctx, x)
      return :sent
    step "binary exponential backoff"
    step / attempts += 1
  return :failed
```

The notation is **indentation-scoped and has no `end`**: a body is an indented
run of lines, which is what makes the text view read like the flowchart it
projects to. Line grammar, bracketed parts optional:

```
process NAME(PARAM, …)
step ["DESCRIPTION"] [/ ACTION]
if CONDITION  /  else
while CONDITION
for VAR in ITERABLE
break | continue | return [VALUE]
```

The keywords `if`, `else`, `while`, `for`, `in`, `break`, `continue` and
`return` carry their exact Julia meanings and their Julia colour, so an
embedded expression and the structure around it read as one language; only
`process` and `step` are minted.

A step renders its description only when it has one, or when it has no action
to render instead — so a code-only step is a clean `step / …` line and an
unrefined step always offers a caret. An unrefined condition renders a muted
`<condition>` marker: chrome, not content, and the flat-offset reader below is
what keeps a caret there bounded.

Composed with the Julia projection exactly as `FsmToSyntax` is: the embedded
code (a step's action, a decision's or loop's condition, a `for`'s variable and
iterable, the model's parameters) is a `JuliaDocument` subtree rendered through
the same shared `recursion`, so `ProcessToSyntax()` merges the Julia
type-dispatch table with the Process entries into one
`TypeDispatchingProjection`.

The rules are `@projection_template` builders, so printing, reference mapping
and the structural readers are generic. Each compound rule additionally
collapses an unmapped caret to a bounded flat offset (`_syntax_to_flat`, the
`XmlElementToSyntaxNode` precedent) — every keyword in this notation is
projection-introduced text with no input pre-image, and without that collapse
the navigation walk grows its paths without bound.
"""
module ProcessToSyntaxModule

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..ProcessModule: ProcessDocument, ProcessNothing, ProcessInsertion,
                        ProcessModel, ProcessSequence, ProcessStep, ProcessDecision,
                        ProcessWhile, ProcessForeach, ProcessBreak, ProcessContinue,
                        ProcessReturn
import ..DocumentInsertionToSyntaxModule: DomainInsertionToSyntaxLeaf,
                                          InsertionNothingToSyntaxLeaf
import ..TextModule: TextString, hinted_text
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: StyleColor, color_default, color_solarized_gray, color_solarized_green,
                      color_solarized_magenta, color_solarized_cyan
import ..StyleTextModule: StyleText, DStyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode, SyntaxConcatenation
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ProjectionTemplateModule: var"@projection_template", RuleIoMap,
                                   bound, project, collection
import ..ReferenceModule: ConcreteReference, PositionReferenceStep
import ..ProjectionReferenceStepModule: introduced_reference
import ..OperationModule: ReplaceSelectionOperation
import ..SyntaxToTextModule: SyntaxCompoundToText, _syntax_to_flat
import ..JuliaToSyntaxModule: JuliaToSyntax

export ProcessSequenceToSyntaxNode, ProcessModelToSyntaxNode,
       ProcessStepToSyntaxNode, ProcessDecisionToSyntaxNode,
       ProcessWhileToSyntaxNode, ProcessForeachToSyntaxNode,
       ProcessBreakToSyntaxLeaf, ProcessContinueToSyntaxLeaf,
       ProcessReturnToSyntaxNode, ProcessInsertionToSyntaxLeaf, ProcessToSyntax

# ── Shared styles ────────────────────────────────────────────────────────────
#
# Control-flow keywords take the Julia projection's keyword colour: an embedded
# expression and the structure holding it are one language on the page.

const _KEYWORD = StyleText(font_ubuntu_monospace_bold_20, color_solarized_magenta)
const _NAME    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
const _TEXT    = StyleText(font_ubuntu_monospace_regular_20, color_solarized_cyan)
const _CHROME  = StyleText(font_ubuntu_monospace_regular_20, color_solarized_gray)

# What an unrefined hole renders as. Muted, and bracketed so it cannot be
# mistaken for code that is actually there.
const _NO_CONDITION = "<condition>"
const _NO_VARIABLE  = "<variable>"
const _NO_ITERABLE  = "<iterable>"

# ── ProcessInsertion / ProcessNothing ────────────────────────────────────────

ProcessInsertionToSyntaxLeaf() = DomainInsertionToSyntaxLeaf(ProcessDocument)

# ── ProcessSequenceToSyntaxNode ──────────────────────────────────────────────
#
# The domain's block: one line per node, indented one level. `JuliaBlock` has
# exactly this shape, and the surrounding line breaks it emits are what let the
# `else` keyword below sit on its own line without any newline chrome of its own.

@projection struct ProcessSequenceToSyntaxNode
    indentation::Int = 1
end

@projection_template ProcessSequenceToSyntaxNode ProcessSequence (p, doc) ->
    SyntaxNode(collection(:steps); indentation=p.indentation)

# ── ProcessModelToSyntaxNode ─────────────────────────────────────────────────

@projection struct ProcessModelToSyntaxNode
    keyword::ImmutableCell{DStyleText} = _KEYWORD
    name::ImmutableCell{DStyleText}    = _NAME
    chrome::ImmutableCell{DStyleText}  = _CHROME
end

@projection_template ProcessModelToSyntaxNode ProcessModel (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(bound(:name, String,
                                         hinted_text(() -> doc.name, () -> isempty(doc.name),
                                                     "enter process name", p.name));
                                   open=TextString("process ", p.keyword)),
                        SyntaxNode(collection(:parameters);
                                   open=TextString("(", p.chrome),
                                   close=TextString(")", p.chrome),
                                   sep=TextString(", ", p.chrome)) ]
        doc.body === nothing || push!(children, project(:body))
        children
    end)

# ── ProcessStepToSyntaxNode ──────────────────────────────────────────────────
#
# `step "description" / action`, both parts optional but never both absent: a
# step with code and no description is a clean `step / …` line, and a step with
# neither still renders its description leaf so there is somewhere to type.

@projection struct ProcessStepToSyntaxNode
    keyword::ImmutableCell{DStyleText} = _KEYWORD
    text::ImmutableCell{DStyleText}    = _TEXT
    chrome::ImmutableCell{DStyleText}  = _CHROME
end

@projection_template ProcessStepToSyntaxNode ProcessStep (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[]
        if !isempty(doc.description) || doc.action === nothing
            push!(children, SyntaxLeaf(bound(:description, String,
                                             hinted_text(() -> doc.description,
                                                         () -> isempty(doc.description),
                                                         "describe this step", p.text));
                                       open=TextString("step \"", p.keyword),
                                       close=TextString("\"", p.keyword)))
        else
            push!(children, SyntaxLeaf(TextString("step", p.keyword)))
        end
        if doc.action !== nothing
            push!(children, SyntaxLeaf(TextString(" / ", p.chrome)))
            push!(children, project(:action))
        end
        children
    end)

# ── ProcessDecisionToSyntaxNode ──────────────────────────────────────────────
#
# `if COND` / then body / `else` / else body. The `else` keyword needs no
# newline chrome of its own: the indented sequence on either side of it emits
# one (the `JuliaIf` precedent, for the same reason).

@projection struct ProcessDecisionToSyntaxNode
    keyword::ImmutableCell{DStyleText} = _KEYWORD
    chrome::ImmutableCell{DStyleText}  = _CHROME
end

@projection_template ProcessDecisionToSyntaxNode ProcessDecision (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("if ", p.keyword)) ]
        push!(children, doc.condition === nothing ?
                        SyntaxLeaf(TextString(_NO_CONDITION, p.chrome)) : project(:condition))
        doc.then_branch === nothing || push!(children, project(:then_branch))
        if doc.else_branch !== nothing
            push!(children, SyntaxLeaf(TextString("else", p.keyword)))
            push!(children, project(:else_branch))
        end
        children
    end)

# ── ProcessWhileToSyntaxNode ─────────────────────────────────────────────────

@projection struct ProcessWhileToSyntaxNode
    keyword::ImmutableCell{DStyleText} = _KEYWORD
    chrome::ImmutableCell{DStyleText}  = _CHROME
end

@projection_template ProcessWhileToSyntaxNode ProcessWhile (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("while ", p.keyword)) ]
        push!(children, doc.condition === nothing ?
                        SyntaxLeaf(TextString(_NO_CONDITION, p.chrome)) : project(:condition))
        doc.body === nothing || push!(children, project(:body))
        children
    end)

# ── ProcessForeachToSyntaxNode ───────────────────────────────────────────────

@projection struct ProcessForeachToSyntaxNode
    keyword::ImmutableCell{DStyleText} = _KEYWORD
    chrome::ImmutableCell{DStyleText}  = _CHROME
end

@projection_template ProcessForeachToSyntaxNode ProcessForeach (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("for ", p.keyword)) ]
        push!(children, doc.variable === nothing ?
                        SyntaxLeaf(TextString(_NO_VARIABLE, p.chrome)) : project(:variable))
        push!(children, SyntaxLeaf(TextString(" in ", p.keyword)))
        push!(children, doc.iterable === nothing ?
                        SyntaxLeaf(TextString(_NO_ITERABLE, p.chrome)) : project(:iterable))
        doc.body === nothing || push!(children, project(:body))
        children
    end)

# ── Jumps ────────────────────────────────────────────────────────────────────

@projection struct ProcessBreakToSyntaxLeaf
    keyword::ImmutableCell{DStyleText} = _KEYWORD
end

@projection_template ProcessBreakToSyntaxLeaf ProcessBreak (p, doc) ->
    SyntaxLeaf(TextString("break", p.keyword))

@projection struct ProcessContinueToSyntaxLeaf
    keyword::ImmutableCell{DStyleText} = _KEYWORD
end

@projection_template ProcessContinueToSyntaxLeaf ProcessContinue (p, doc) ->
    SyntaxLeaf(TextString("continue", p.keyword))

@projection struct ProcessReturnToSyntaxNode
    keyword::ImmutableCell{DStyleText} = _KEYWORD
    chrome::ImmutableCell{DStyleText}  = _CHROME
end

@projection_template ProcessReturnToSyntaxNode ProcessReturn (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("return", p.keyword)) ]
        if doc.value !== nothing
            push!(children, SyntaxLeaf(TextString(" ", p.chrome)))
            push!(children, project(:value))
        end
        children
    end)

# ── Structural-caret navigation ──────────────────────────────────────────────
#
# Every keyword and every unrefined-hole marker in this notation is
# projection-introduced text with no input pre-image, so a text caret there maps
# back to nothing through the wiring. The engine's domain-neutral fallback wraps
# the whole output path in a `ProjectionReferenceStep`, which
# `strip_reference_types` does not collapse — each round trip through such a
# caret grows the path and the navigation walk never terminates. Collapsing to a
# flat offset into the rendered node keeps the caret set bounded;
# `FsmToSyntax` needs it on every compound rule for the same reason.

for T in (:ProcessModelToSyntaxNode, :ProcessStepToSyntaxNode,
          :ProcessDecisionToSyntaxNode, :ProcessWhileToSyntaxNode,
          :ProcessForeachToSyntaxNode, :ProcessReturnToSyntaxNode)
    @eval function read_intent(p::$T, iomap::RuleIoMap, op::ReplaceSelectionOperation)
        result = map_reference_backward(p, iomap, op.path)
        result !== nothing && return ReplaceSelectionOperation(result)
        flat = _syntax_to_flat(iomap.output, op.path, SyntaxCompoundToText(), 0)
        flat < 0 && return nothing
        ReplaceSelectionOperation(
            introduced_reference(p, iomap.input, ConcreteReference(PositionReferenceStep(flat))))
    end
end

# ── Compound convenience constructor ─────────────────────────────────────────
#
# Merged with the Julia table so an embedded action/condition/iterable renders
# through the same recursion (the `FsmToSyntax` precedent).

function ProcessToSyntax()
    pairs = copy(JuliaToSyntax().dispatch)
    push!(pairs, ProcessSequence  => ProcessSequenceToSyntaxNode())
    push!(pairs, ProcessModel     => ProcessModelToSyntaxNode())
    push!(pairs, ProcessStep      => ProcessStepToSyntaxNode())
    push!(pairs, ProcessDecision  => ProcessDecisionToSyntaxNode())
    push!(pairs, ProcessWhile     => ProcessWhileToSyntaxNode())
    push!(pairs, ProcessForeach   => ProcessForeachToSyntaxNode())
    push!(pairs, ProcessBreak     => ProcessBreakToSyntaxLeaf())
    push!(pairs, ProcessContinue  => ProcessContinueToSyntaxLeaf())
    push!(pairs, ProcessReturn    => ProcessReturnToSyntaxNode())
    push!(pairs, ProcessInsertion => ProcessInsertionToSyntaxLeaf())
    push!(pairs, ProcessNothing   => InsertionNothingToSyntaxLeaf())
    TypeDispatchingProjection(pairs)
end

end # module
