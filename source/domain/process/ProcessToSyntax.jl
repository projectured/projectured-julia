# Fragment of `ProcessModule`.
#
# Process → Syntax projection: the **natural notation**, the primary edit
# surface of the process domain.
#
# ```
# process csma_transmit(frame)
#   step "prepare" / x = encode(frame)
#   while attempts < max_attempts
#     if carrier_free()
#       step / start_tx!(ctx, x)
#       return :sent
#     step "binary exponential backoff"
#     step / attempts += 1
#   return :failed
# ```
#
# The notation is **indentation-scoped and has no `end`**: a body is an indented
# run of lines, which is what makes the text view read like the flowchart it
# projects to. Line grammar, bracketed parts optional:
#
# ```
# process NAME(PARAM, …)
# step ["DESCRIPTION"] [/ ACTION]
# if CONDITION  /  else
# while CONDITION
# for VAR in ITERABLE
# break | continue | return [VALUE]
# ```
#
# The keywords `if`, `else`, `while`, `for`, `in`, `break`, `continue` and
# `return` carry their exact Julia meanings and their Julia colour, so an
# embedded expression and the structure around it read as one language; only
# `process` and `step` are minted.
#
# A step renders its description only when it has one, or when it has no action
# to render instead — so a code-only step is a clean `step / …` line and an
# unrefined step always offers a caret. An unrefined condition renders a muted
# `<condition>` marker: chrome, not content, and the flat-offset reader below is
# what keeps a caret there bounded.
#
# Composed with the Julia projection exactly as `FsmToSyntax` is: the embedded
# code (a step's action, a decision's or loop's condition, a `for`'s variable and
# iterable, the model's parameters) is a `JuliaDocument` subtree rendered through
# the same shared `recursion`, so `ProcessToSyntax()` merges the Julia
# type-dispatch table with the Process entries into one
# `TypeDispatchingProjection`.
#
# `ProcessToSyntax(; session)` hands every node rule a `ProcessDebugSession`, and
# a node the session names renders its leading keyword in the live colour (a
# breakpoint in another). It is a **style swap on a keyword that is printed
# anyway**: no glyph is added, so where a realized run happens to be cannot shift
# a caret offset out from under whoever is typing.
#
# The rules are `@projection_template` builders, so printing, reference mapping
# and the structural readers are generic. Every keyword is a part that a rule
# printed, and the rule names a caret on it by its own introduced step.
# ── Shared styles ────────────────────────────────────────────────────────────
#
# Control-flow keywords take the Julia projection's keyword colour: an embedded
# expression and the structure holding it are one language on the page. Each
# role comes from a style the builder gives the projection (`get_process_style`),
# so a projection that a builder gives no style renders the plain values of
# `ProcessTheme`.
#
# Where a realized run is, and where it is set to stop are both style swaps on
# a keyword that is printed anyway — nothing is added to the line, so a live
# position cannot shift a single caret offset out from under the reader.

# The style a node's leading keyword takes. Where a run *is* wins over where it
# is set to stop, and a node that is neither prints exactly as it always does —
# so a document with no session attached renders byte-for-byte the same.
#
# Both the position and the breakpoints are compared by identity against the
# node being printed, which is why neither needs the tree root a printer rule
# does not have. Read inside the printer's thunk, so a step arriving mid-run
# repaints the line without a reprint.
function _keyword_style(p, doc)
    session = p.session
    session === nothing && return p.keyword
    session.current === doc && return p.current
    has_breakpoint(session, doc) && return p.breakpoint
    p.keyword
end

# What an unrefined hole renders as. Muted, and bracketed so it cannot be
# mistaken for code that is actually there.
const _NO_CONDITION = "<condition>"
const _NO_VARIABLE  = "<variable>"
const _NO_ITERABLE  = "<iterable>"

# ── ProcessInsertion / ProcessNothing ────────────────────────────────────────

ProcessInsertionToSyntaxLeaf(; theme = nothing) = DomainInsertionToSyntaxLeaf(ProcessDocument; theme)

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

@projection UntrackedCell struct ProcessModelToSyntaxNode
    keyword::StyleText = get_process_style(nothing, :keyword_text)
    name::StyleText    = get_process_style(nothing, :name_text)
    chrome::StyleText  = get_process_style(nothing, :chrome_text)
end

@projection_template ProcessModelToSyntaxNode ProcessModel (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(bound(:name, String,
                                         make_hinted_text(() -> doc.name;
                                                          empty_thunk = () -> isempty(doc.name),
                                                          placeholder = "enter process name",
                                                          style = p.name));
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

@projection UntrackedCell struct ProcessStepToSyntaxNode
    keyword::StyleText    = get_process_style(nothing, :keyword_text)
    text::StyleText       = get_process_style(nothing, :action_text)
    chrome::StyleText     = get_process_style(nothing, :chrome_text)
    current::StyleText    = get_process_style(nothing, :current_text)
    breakpoint::StyleText = get_process_style(nothing, :breakpoint_text)
    session::Any = nothing
end

@projection_template ProcessStepToSyntaxNode ProcessStep (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[]
        if !isempty(doc.description) || doc.action === nothing
            push!(children, SyntaxLeaf(bound(:description, String,
                                             make_hinted_text(() -> doc.description;
                                                              empty_thunk = () -> isempty(doc.description),
                                                              placeholder = "describe this step",
                                                              style = p.text));
                                       open=TextString("step \"", _keyword_style(p, doc)),
                                       close=TextString("\"", _keyword_style(p, doc))))
        else
            push!(children, SyntaxLeaf(TextString("step", _keyword_style(p, doc))))
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

@projection UntrackedCell struct ProcessDecisionToSyntaxNode
    keyword::StyleText    = get_process_style(nothing, :keyword_text)
    chrome::StyleText     = get_process_style(nothing, :chrome_text)
    current::StyleText    = get_process_style(nothing, :current_text)
    breakpoint::StyleText = get_process_style(nothing, :breakpoint_text)
    session::Any = nothing
end

@projection_template ProcessDecisionToSyntaxNode ProcessDecision (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("if ", _keyword_style(p, doc))) ]
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

@projection UntrackedCell struct ProcessWhileToSyntaxNode
    keyword::StyleText    = get_process_style(nothing, :keyword_text)
    chrome::StyleText     = get_process_style(nothing, :chrome_text)
    current::StyleText    = get_process_style(nothing, :current_text)
    breakpoint::StyleText = get_process_style(nothing, :breakpoint_text)
    session::Any = nothing
end

@projection_template ProcessWhileToSyntaxNode ProcessWhile (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("while ", _keyword_style(p, doc))) ]
        push!(children, doc.condition === nothing ?
                        SyntaxLeaf(TextString(_NO_CONDITION, p.chrome)) : project(:condition))
        doc.body === nothing || push!(children, project(:body))
        children
    end)

# ── ProcessForeachToSyntaxNode ───────────────────────────────────────────────

@projection UntrackedCell struct ProcessForeachToSyntaxNode
    keyword::StyleText    = get_process_style(nothing, :keyword_text)
    chrome::StyleText     = get_process_style(nothing, :chrome_text)
    current::StyleText    = get_process_style(nothing, :current_text)
    breakpoint::StyleText = get_process_style(nothing, :breakpoint_text)
    session::Any = nothing
end

@projection_template ProcessForeachToSyntaxNode ProcessForeach (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("for ", _keyword_style(p, doc))) ]
        push!(children, doc.variable === nothing ?
                        SyntaxLeaf(TextString(_NO_VARIABLE, p.chrome)) : project(:variable))
        push!(children, SyntaxLeaf(TextString(" in ", p.keyword)))
        push!(children, doc.iterable === nothing ?
                        SyntaxLeaf(TextString(_NO_ITERABLE, p.chrome)) : project(:iterable))
        doc.body === nothing || push!(children, project(:body))
        children
    end)

# ── Jumps ────────────────────────────────────────────────────────────────────

@projection UntrackedCell struct ProcessBreakToSyntaxLeaf
    keyword::StyleText    = get_process_style(nothing, :keyword_text)
    current::StyleText    = get_process_style(nothing, :current_text)
    breakpoint::StyleText = get_process_style(nothing, :breakpoint_text)
    session::Any = nothing
end

@projection_template ProcessBreakToSyntaxLeaf ProcessBreak (p, doc) ->
    SyntaxLeaf(TextString(() -> "break", _keyword_style(p, doc)))

@projection UntrackedCell struct ProcessContinueToSyntaxLeaf
    keyword::StyleText    = get_process_style(nothing, :keyword_text)
    current::StyleText    = get_process_style(nothing, :current_text)
    breakpoint::StyleText = get_process_style(nothing, :breakpoint_text)
    session::Any = nothing
end

@projection_template ProcessContinueToSyntaxLeaf ProcessContinue (p, doc) ->
    SyntaxLeaf(TextString(() -> "continue", _keyword_style(p, doc)))

@projection UntrackedCell struct ProcessReturnToSyntaxNode
    keyword::StyleText    = get_process_style(nothing, :keyword_text)
    chrome::StyleText     = get_process_style(nothing, :chrome_text)
    current::StyleText    = get_process_style(nothing, :current_text)
    breakpoint::StyleText = get_process_style(nothing, :breakpoint_text)
    session::Any = nothing
end

@projection_template ProcessReturnToSyntaxNode ProcessReturn (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(TextString("return", _keyword_style(p, doc))) ]
        if doc.value !== nothing
            push!(children, SyntaxLeaf(TextString(" ", p.chrome)))
            push!(children, project(:value))
        end
        children
    end)

# ── Compound convenience constructor ─────────────────────────────────────────
#
# Merged with the Julia table so an embedded action/condition/iterable renders
# through the same recursion (the `FsmToSyntax` precedent). The builder gives
# each projection the style of its role with `get_process_style`, from
# `theme`, a `ProcessTheme` scaled or not, or the default styles for
# `nothing`; `julia_theme` and `syntax_theme` style the embedded Julia nodes,
# through `JuliaToSyntax`.

function ProcessToSyntax(; session = nothing, theme = nothing, julia_theme = nothing, syntax_theme = nothing)
    get_style(name) = get_process_style(theme, name)
    live_styles = (current = get_style(:current_text), breakpoint = get_style(:breakpoint_text))
    JuliaToSyntax(
        ProcessSequence  => ProcessSequenceToSyntaxNode(),
        ProcessModel     => ProcessModelToSyntaxNode(; keyword = get_style(:keyword_text),
                                                        name = get_style(:name_text),
                                                        chrome = get_style(:chrome_text)),
        ProcessStep      => ProcessStepToSyntaxNode(; keyword = get_style(:keyword_text),
                                                       text = get_style(:action_text),
                                                       chrome = get_style(:chrome_text),
                                                       live_styles..., session),
        ProcessDecision  => ProcessDecisionToSyntaxNode(; keyword = get_style(:keyword_text),
                                                           chrome = get_style(:chrome_text),
                                                           live_styles..., session),
        ProcessWhile     => ProcessWhileToSyntaxNode(; keyword = get_style(:keyword_text),
                                                        chrome = get_style(:chrome_text),
                                                        live_styles..., session),
        ProcessForeach   => ProcessForeachToSyntaxNode(; keyword = get_style(:keyword_text),
                                                          chrome = get_style(:chrome_text),
                                                          live_styles..., session),
        ProcessBreak     => ProcessBreakToSyntaxLeaf(; keyword = get_style(:keyword_text),
                                                        live_styles..., session),
        ProcessContinue  => ProcessContinueToSyntaxLeaf(; keyword = get_style(:keyword_text),
                                                           live_styles..., session),
        ProcessReturn    => ProcessReturnToSyntaxNode(; keyword = get_style(:keyword_text),
                                                         chrome = get_style(:chrome_text),
                                                         live_styles..., session),
        ProcessInsertion => ProcessInsertionToSyntaxLeaf(theme = syntax_theme),
        ProcessNothing   => InsertionNothingToSyntaxLeaf(theme = syntax_theme);
        theme = julia_theme, syntax_theme)
end
