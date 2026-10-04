# Fragment of `FsmModule`.
#
# Fsm → Syntax projection: the **natural notation**, the primary edit surface of
# the state machine domain.
#
# ```
# component EthernetCsmaMac
#   variable num_retries::Int = 0
#   timer tx_timer
#   event UPPER_PACKET
#   machine Mac initial IDLE
#     state IDLE
#       on UPPER_PACKET -> TRANSMITTING / set_current_tx!(m, payload)
#     state TRANSMITTING
#       entry / start_transmission!(ctx, m)
#       on COLLISION_START -> JAMMING / abort_tx!(ctx, m)
# ```
#
# Transition line grammar, each part optional except the ending:
#
# ```
# [on EVENT | on timeout(TIMER)] [when GUARD] (-> TARGET | stay | ignore) [/ ACTION]
# ```
#
# The action comes **last**, after the ending, because it is the only part that
# can be more than one statement: an action written as a `begin`-style block
# renders as an indented run of lines below its transition, and anything printed
# after it would be stranded at the bottom of that block, away from the line it
# belongs to.
#
# Composed with the Julia projection, exactly as `FormulaToSyntax` is: the
# embedded code (a transition's guard/action, a state's entry, a variable's
# type/default, the component's helpers and usings) is a `JuliaDocument` subtree
# rendered through the same shared `recursion`, so `FsmToSyntax()` merges the
# Julia type-dispatch table with the Fsm entries into one
# `TypeDispatchingProjection`.
#
# `trigger`, `target` and `initial` are held by identity and point at documents
# that live *elsewhere in the same component* (an event of the component, a state
# of the machine). They are rendered as **name leaves read reactively from the
# referent** — the `FormulaReferenceToSyntaxLeaf` pattern — never recursed into:
# projecting a transition's target would inline the whole target state, which for
# a self-loop does not terminate. A rename of the referent updates every mention.
#
# The rules are `@projection_template` builders, so printing, reference mapping
# and the structural readers are generic. Every keyword and every referent name is
# a part that a rule printed, and the rule names a caret on it by its own
# introduced step.
# ── Shared styles ────────────────────────────────────────────────────────────
#
# Each role is a style field of the projection, filled by the factory with
# `get_fsm_style`; a projection built with no styles holds the plain values of
# `FsmTheme`.

# The name of a referenced part, read reactively so a rename propagates. An
# unresolved reference renders `?` rather than erroring — a machine under
# construction is a legal document.
_referent_name(x) = x === nothing ? "?" : x.name

# ── FsmInsertion / FsmNothing ────────────────────────────────────────────────

FsmInsertionToSyntaxLeaf(; theme = nothing) = DomainInsertionToSyntaxLeaf(FsmDocument; theme)

# ── FsmTimerToSyntaxLeaf ─────────────────────────────────────────────────────

@projection UntrackedCell struct FsmTimerToSyntaxLeaf
    keyword::StyleText = get_fsm_style(nothing, :keyword_text)
    name::StyleText    = get_fsm_style(nothing, :name_text)
end

@projection_template FsmTimerToSyntaxLeaf FsmTimer (p, doc) ->
    SyntaxLeaf(bound(:name, String,
                     make_hinted_text(() -> doc.name; empty_thunk = () -> isempty(doc.name),
                                      placeholder = "enter timer name",
                                      style = p.name));
               open=TextString("timer ", p.keyword))

# ── FsmEventToSyntaxLeaf ─────────────────────────────────────────────────────

@projection UntrackedCell struct FsmEventToSyntaxLeaf
    keyword::StyleText = get_fsm_style(nothing, :keyword_text)
    name::StyleText    = get_fsm_style(nothing, :name_text)
end

@projection_template FsmEventToSyntaxLeaf FsmEvent (p, doc) ->
    SyntaxLeaf(bound(:name, String,
                     make_hinted_text(() -> doc.name; empty_thunk = () -> isempty(doc.name),
                                      placeholder = "enter event name",
                                      style = p.name));
               open=TextString("event ", p.keyword))

# ── FsmVariableToSyntaxNode ──────────────────────────────────────────────────
#
# `variable name`, `variable name::Type`, `variable name = default`, or both.
# The type and default are embedded Julia expressions, so they are `project`ed
# through the shared recursion; absent ones contribute no child at all.

@projection UntrackedCell struct FsmVariableToSyntaxNode
    keyword::StyleText = get_fsm_style(nothing, :keyword_text)
    name::StyleText    = get_fsm_style(nothing, :name_text)
    chrome::StyleText  = get_fsm_style(nothing, :chrome_text)
end

@projection_template FsmVariableToSyntaxNode FsmVariable (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(bound(:name, String,
                                         make_hinted_text(() -> doc.name;
                                                          empty_thunk = () -> isempty(doc.name),
                                                          placeholder = "enter variable name",
                                                          style = p.name));
                                   open=TextString("variable ", p.keyword),
                                   close=TextString(doc.type === nothing ? "" : "::", p.chrome)) ]
        doc.type === nothing || push!(children, project(:type))
        if doc.default !== nothing
            push!(children, SyntaxLeaf(TextString(" = ", p.chrome)))
            push!(children, project(:default))
        end
        children
    end)

# ── FsmTransitionToSyntaxNode ────────────────────────────────────────────────
#
# One line. Every part is optional except the ending, so the child list is
# built by a thunk (the `JuliaReturnToSyntaxNode` shape).
#
# The trigger and target leaves are projection-introduced: they render the
# *referent's* name, which is bound to the referenced document, not to a field
# of this transition.

@projection UntrackedCell struct FsmTransitionToSyntaxNode
    keyword::StyleText = get_fsm_style(nothing, :keyword_text)
    ref::StyleText     = get_fsm_style(nothing, :reference_text)
    chrome::StyleText  = get_fsm_style(nothing, :chrome_text)
end

# `on EVENT` / `on timeout(TIMER)`; a condition-only transition has no trigger
# part at all and opens with its guard.
_trigger_text(doc) = begin
    trigger = doc.trigger
    trigger === nothing ? "" :
        trigger isa FsmTimer ? "on timeout($(trigger.name))" : "on $(_referent_name(trigger))"
end

@projection_template FsmTransitionToSyntaxNode FsmTransition (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[]
        doc.trigger === nothing ||
            push!(children, SyntaxLeaf(TextString(() -> _trigger_text(doc), p.ref)))
        if doc.guard !== nothing
            push!(children, SyntaxLeaf(TextString(isempty(children) ? "when " : " when ", p.keyword)))
            push!(children, project(:guard))
        end
        ending = doc.target === nothing ?
            (doc.action === nothing ? "ignore" : "stay") :
            "-> " * _referent_name(doc.target)
        push!(children, SyntaxLeaf(TextString(isempty(children) ? ending : " " * ending, p.ref)))
        if doc.action !== nothing
            push!(children, SyntaxLeaf(TextString(" / ", p.chrome)))
            push!(children, project(:action))
        end
        children
    end)

# ── FsmStateToSyntaxNode ─────────────────────────────────────────────────────
#
# `state NAME`, then an indented body of the optional entry line and the
# transitions. The body is a nested sub-node keying off this same state (F1),
# so each transition lands on its own indented line.

@projection UntrackedCell struct FsmStateToSyntaxNode
    keyword::StyleText = get_fsm_style(nothing, :keyword_text)
    name::StyleText    = get_fsm_style(nothing, :name_text)
    chrome::StyleText  = get_fsm_style(nothing, :chrome_text)
end

@projection_template FsmStateToSyntaxNode FsmState (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(bound(:name, String,
                                         make_hinted_text(() -> doc.name;
                                                          empty_thunk = () -> isempty(doc.name),
                                                          placeholder = "enter state name",
                                                          style = p.name));
                                   open=TextString("state ", p.keyword)) ]
        # One indented line: the wrapper indents its single child, and that
        # child concatenates the keyword with the projected entry code, so a
        # one-expression entry stays on the line (a block still spills below,
        # which is what a multi-statement entry should look like).
        if doc.entry !== nothing
            push!(children, SyntaxNode([ SyntaxConcatenation(
                                             [ SyntaxLeaf(TextString("entry / ", p.keyword)),
                                               project(:entry) ]) ];
                                       indentation=1))
        end
        isempty(doc.transitions) ||
            push!(children, SyntaxNode(collection(:transitions); indentation=1))
        children
    end)

# ── FsmMachineToSyntaxNode ───────────────────────────────────────────────────

@projection UntrackedCell struct FsmMachineToSyntaxNode
    keyword::StyleText = get_fsm_style(nothing, :keyword_text)
    name::StyleText    = get_fsm_style(nothing, :name_text)
    ref::StyleText     = get_fsm_style(nothing, :reference_text)
end

@projection_template FsmMachineToSyntaxNode FsmMachine (p, doc) ->
    SyntaxConcatenation(() -> begin
        # `initial X` and, when the machine ignores unhandled events, the
        # policy — `:error` is the default and stays unwritten. (A newline
        # inside a bracketed literal separates elements, so this thunk is
        # bound here rather than written inline.)
        initial_text = () -> begin
            text = " initial " * _referent_name(doc.initial)
            doc.on_unhandled === :ignore ? text * " ignoring unhandled" : text
        end
        children = Any[ SyntaxLeaf(bound(:name, String,
                                         make_hinted_text(() -> doc.name;
                                                          empty_thunk = () -> isempty(doc.name),
                                                          placeholder = "enter machine name",
                                                          style = p.name));
                                   open=TextString("machine ", p.keyword)),
                        SyntaxLeaf(TextString(initial_text, p.ref)) ]
        isempty(doc.states) ||
            push!(children, SyntaxNode(collection(:states); indentation=1))
        children
    end)

# ── FsmComponentToSyntaxNode ─────────────────────────────────────────────────
#
# The component header plus one indented section per collection. An empty
# collection renders nothing, so the sections that a given component does not
# use simply do not appear.

@projection UntrackedCell struct FsmComponentToSyntaxNode
    keyword::StyleText = get_fsm_style(nothing, :keyword_text)
    name::StyleText    = get_fsm_style(nothing, :name_text)
end

@projection_template FsmComponentToSyntaxNode FsmComponent (p, doc) ->
    SyntaxConcatenation(() -> begin
        children = Any[ SyntaxLeaf(bound(:name, String,
                                         make_hinted_text(() -> doc.name;
                                                          empty_thunk = () -> isempty(doc.name),
                                                          placeholder = "enter component name",
                                                          style = p.name));
                                   open=TextString("component ", p.keyword)) ]
        # An empty section contributes no node at all: an empty indented node
        # still prints its line break, which would leave a blank line for every
        # section a component does not use.
        for field in (:usings, :variables, :timers, :events, :machines, :helpers)
            isempty(getproperty(doc, field)) ||
                push!(children, SyntaxNode(collection(field); indentation=1))
        end
        children
    end)

# ── Compound convenience constructor ─────────────────────────────────────────
#
# Merged with the Julia table so an embedded guard/action/entry/helper renders
# through the same recursion (the `FormulaToSyntax` precedent). The builder
# gives each projection the style of its role with `get_fsm_style`, from
# `theme`, a `FsmTheme` scaled or not, or the default styles for `nothing`;
# `julia_theme` and `syntax_theme` style the embedded Julia nodes, through
# `JuliaToSyntax`.

function FsmToSyntax(; theme = nothing, julia_theme = nothing, syntax_theme = nothing)
    get_style(name) = get_fsm_style(theme, name)
    keyword_name_style = (keyword = get_style(:keyword_text), name = get_style(:name_text))
    keyword_name_chrome_style = (keyword = get_style(:keyword_text), name = get_style(:name_text),
                                 chrome = get_style(:chrome_text))
    JuliaToSyntax(
        FsmVariable   => FsmVariableToSyntaxNode(; keyword_name_chrome_style...),
        FsmTimer      => FsmTimerToSyntaxLeaf(; keyword_name_style...),
        FsmEvent      => FsmEventToSyntaxLeaf(; keyword_name_style...),
        FsmTransition => FsmTransitionToSyntaxNode(; keyword = get_style(:keyword_text),
                                                     ref = get_style(:reference_text),
                                                     chrome = get_style(:chrome_text)),
        FsmState      => FsmStateToSyntaxNode(; keyword_name_chrome_style...),
        FsmMachine    => FsmMachineToSyntaxNode(; keyword = get_style(:keyword_text),
                                                  name = get_style(:name_text),
                                                  ref = get_style(:reference_text)),
        FsmComponent  => FsmComponentToSyntaxNode(; keyword_name_style...),
        FsmInsertion  => FsmInsertionToSyntaxLeaf(theme = syntax_theme),
        FsmNothing    => InsertionNothingToSyntaxLeaf(theme = syntax_theme);
        theme = julia_theme, syntax_theme)
end
