# ──────────────────────────────────────────────────────────────────────────
# Folded in from AssistantToWidget.jl.
# ── Layout tokens ───────────────────────────────────────────────────────────
const _PAD5  = Inset(5, 5, 5, 5)
const _WHITE = StyleColor(255, 255, 255, 255)
# The composer's floor on the split axis, and the transcript's share of what is
# left over.
const _INPUT_MIN_HEIGHT = 200
const _MAIN_WEIGHT      = 1.0

struct AssistantToWidgetSplitPane <: Projection end

"""
    AssistantToWidgetCard(; title, width, transcript_height, cell_height)

The same assistant, as a card of a fixed size rather than a pane that fills a
window. It is what an assistant embedded in a DOCUMENT needs: a page of prose
carrying one grows every time a turn lands, and a card that grew with its
transcript would push the rest of the page down on every keystroke.

So each half scrolls inside the card, and the page stays the length it was.

The output is a `VerticalLayout`, so a renderer row can end in
`VerticalLayoutToGraphicsCanvas` and everything inside re-enters the renderer
that asked for the card — which is what lets a part's content draw in its own
domain without this projection naming any domain.
"""
struct AssistantToWidgetCard <: Projection
    title::String
    width::Int
    transcript_height::Int
    cell_height::Int
end

AssistantToWidgetCard(; title::AbstractString = ASSISTANT_TITLE,
                               width::Integer = 1040,
                               transcript_height::Integer = 460,
                               cell_height::Integer = 120) =
    AssistantToWidgetCard(String(title), Int(width),
                                   Int(transcript_height), Int(cell_height))

function print_document(projection::AssistantToWidgetSplitPane,
                           recursion, a::Assistant, ctx)
    # Both children are WidgetScrollPanes whose `content` is the underlying
    # document. `WidgetScrollPaneToGraphicsCanvas.print_document` calls
    # `print_child(recursion, content, …)` directly, so the outer
    # TypeDispatchingProjection routes `ConversationDocument` to
    # `ConversationToWidget` and `PrimitiveDocument` (the input) to the
    # Primitive→Syntax→Text→Graphics chain. This is also what makes the
    # `PrimitiveStringToSyntaxLeaf` reader receive `KeyPress` events.
    # Stick to the bottom: as streamed turns/parts are appended, the latest
    # message stays in view instead of scrolling below the fold (standard chat UX).
    conv_pane  = WidgetScrollPane(a.conversation;
                                  follow_end=true,
                                  padding=_PAD5, padding_color=_WHITE)
    # The input pane is the composer on `a.draft` (a `ConversationDraft`, so it
    # dispatches to the composer rather than the history presentation; it already
    # back-links the assistant for submit). The panel reader routes input keys to
    # `a.draft`.
    input_pane = WidgetScrollPane(a.draft;
                                  padding=_PAD5, padding_color=_WHITE)
    # Conversation takes the main weight; the input box stays at its minimum
    # (≈3 monospace rows) and does not grow with the window.
    column = WidgetSplitPane(:vertical, Any[
        LayoutConstraint(conv_pane;
                         min_height=0, preferred_height=0, weight_height=_MAIN_WEIGHT),
        LayoutConstraint(input_pane;
                         min_height=_INPUT_MIN_HEIGHT, preferred_height=_INPUT_MIN_HEIGHT),
    ])
    SimpleIoMap(projection, a, column)
end

"""
The same two panes as the split pane above, bounded and wrapped in a card. Both
children carry the DOCUMENT rather than a projection of it, exactly as there, so
the renderer around the card routes the conversation to the chat bubbles and the
draft to the composer.

The card takes the keyboard as a whole: the caret goes ON the assistant and not
inside it, and the reader hands every key to the draft. That is what the split
pane's own `KeyPress` / `KeyDown` fallbacks already do; it is written down here
too because a card sits inside a document, where nothing above it routes by tab.
"""
function print_document(p::AssistantToWidgetCard,
                        recursion, a::Assistant, ctx)
    inner = max(240, p.width - 40)
    # Stick to the bottom: an evaluated cell lands at the end of the transcript,
    # and the reader should be looking at it rather than at where they started.
    transcript = WidgetScrollPane(a.conversation; follow_end=true,
                                  size=Point2D(inner, p.transcript_height),
                                  padding=_PAD5, padding_color=_WHITE)
    cell = WidgetScrollPane(a.draft; size=Point2D(inner, p.cell_height),
                            padding=_PAD5, padding_color=_WHITE)
    card = WidgetCard(Point2D(0, 0); title=p.title, width=p.width,
                      content=VerticalLayout(Any[transcript, cell]; gap=6))
    column = VerticalLayout(Any[card]; gap=6)
    iomap = SimpleIoMap(p, a, column)
    # A keystroke is routed by SELECTION, and every container between the root
    # and the cell has to carry one or the key stops at the first that does not.
    # There are four here, and each sees the same path with its own prefix
    # already spent — the same suffix walk a catalog shell does for its panes.
    full() = map_reference_forward(p, iomap, getfield(a, :selection)[])
    suffix(n) = () -> begin
        r = full()
        r === nothing && return nothing
        steps = get_reference_steps(r)
        length(steps) > n ? _steps_to_reference(steps[(n + 1):end]) : nothing
    end
    set_cell_function!(getfield(column, :selection), full)
    set_cell_function!(getfield(card, :selection), suffix(2))
    set_cell_function!(getfield(card.content, :selection), suffix(3))
    # Only the pane the path names carries a selection. Both panes sit at the
    # same depth, so a bare suffix would tell each of them it held the caret.
    pane_suffix(i) = () -> begin
        r = full()
        r === nothing && return nothing
        steps = get_reference_steps(r)
        length(steps) > 5 || return nothing
        step = steps[5]
        (step isa RangeReferenceStep && step.start + 1 == i) || return nothing
        _steps_to_reference(steps[6:end])
    end
    set_cell_function!(getfield(transcript, :selection), pane_suffix(1))
    set_cell_function!(getfield(cell, :selection), pane_suffix(2))
    iomap
end

_steps_to_reference(steps) =
    foldr((step, tail) -> ConcreteReference(step, tail), steps; init = EmptyReference())

# Where the two panes sit in this card's output. The transcript is the first
# child of the card's interior and the cell is the second, so a path into either
# is that walk plus whatever the pane's own document said.
_CARD_PANE_PREFIX(i) = Any[FieldReferenceStep("children"), RangeReferenceStep(0, 1),
                           FieldReferenceStep("content"),
                           FieldReferenceStep("children"), RangeReferenceStep(i - 1, i),
                           FieldReferenceStep("content")]

# `conversation.<rest>` / `draft.<rest>` → the pane that holds it, plus `<rest>`.
function map_reference_forward(::AssistantToWidgetCard, iomap::SimpleIoMap, reference)
    reference isa ConcreteReference || return nothing
    head = reference.head
    head isa FieldReferenceStep || return nothing
    pane = head.name == "conversation" ? 1 : head.name == "draft" ? 2 : 0
    pane == 0 && return nothing
    _steps_to_reference(vcat(_CARD_PANE_PREFIX(pane),
                             get_reference_steps(reference.tail)))
end

# And back. A click in a pane is a click in the document that pane holds, so the
# caret lands where it was aimed rather than on the card as a whole — which is
# the difference between a card a reader can click into and one they can only
# click at.
function map_reference_backward(::AssistantToWidgetCard, iomap::SimpleIoMap, reference)
    reference isa Reference || return nothing
    steps = get_reference_steps(reference)
    for (pane, name) in ((1, "conversation"), (2, "draft"))
        prefix = _CARD_PANE_PREFIX(pane)
        length(steps) >= length(prefix) || continue
        matched = all(_same_step(steps[i], prefix[i]) for i in eachindex(prefix))
        matched || continue
        return _steps_to_reference(vcat(Any[FieldReferenceStep(name)],
                                        steps[(length(prefix) + 1):end]))
    end
    nothing
end

# A click that named no pane is still a click on the card, and the card takes it
# rather than letting it fall through to whatever the card is embedded in.
function read_intent(p::AssistantToWidgetCard, iomap::SimpleIoMap,
                     op::ReplaceSelectionOperation)
    inner = map_reference_backward(p, iomap, op.path)
    ReplaceSelectionOperation(inner === nothing ? EmptyReference() : inner)
end

# Assistant → vertical WidgetSplitPane(conversation | input), each a scroll pane.
function map_reference_forward(::AssistantToWidgetSplitPane, iomap, reference)
    @reference_case reference begin
        ::Assistant.conversation.rest... => @reference ::WidgetSplitPane.elements::CellVector[1]::LayoutConstraint.child::WidgetScrollPane.content.^(rest)
        ::Assistant.draft.rest...        => @reference ::WidgetSplitPane.elements::CellVector[2]::LayoutConstraint.child::WidgetScrollPane.content.^(rest)
    end
end

function map_reference_backward(::AssistantToWidgetSplitPane,
                                 iomap,
                                 reference)
    # The assistant projects to a vertical WidgetSplitPane with the
    # conversation pane at slot 0 and the composer at slot 1, each
    # wrapped in a LayoutConstraint and then a WidgetScrollPane.
    # So bubbled paths look like `elements[i].child.content.<rest>`.
    #
    # Slot 1 is the `draft` and not the `input`: the composer types into the
    # draft, as the printer above says. Naming `input` here spliced a path
    # through a `ConversationDraft` under a `PrimitiveString`, and the strict
    # check refused it — so a CLICK in the composer threw where a KEY worked,
    # because the reader routes keys by itself and only a click goes through
    # this mapper.
    #
    # The tail is typed against the document it descends from. What comes back
    # from a pane is a path in the widget domain with no node types on it, and a
    # spliced path must be typed all the way down or the strict check refuses it.
    assistant = iomap === nothing ? nothing : iomap.input
    typed(document, tail) = document === nothing ? tail : annotate_reference_types(document, tail)
    @reference_case reference begin
        ::WidgetSplitPane.elements{s:e}.child.content.rest... => begin
            i = s + 1
            if i == 1
                @reference ::Assistant.conversation.^(typed(assistant === nothing ? nothing : assistant.conversation, rest))
            elseif i == 2
                @reference ::Assistant.draft.^(typed(assistant === nothing ? nothing : assistant.draft, rest))
            else
                nothing
            end
        end
    end
end

function read_intent(p::AssistantToWidgetSplitPane,
                          iomap, op)
    # The specific KeyPress / KeyDown handlers live in
    # `AssistantModule` (loaded later in the include chain) and
    # take precedence via multiple dispatch. For everything else that
    # reaches us, translate path-bearing ops to the assistant's input
    # domain and let widget-target ops (an identity-rooted ReplaceReferencedValueOperation)
    # pass through; unhandled raw events return `nothing`.
    if op isa Operation
        return _retarget_panel_op(p, iomap, op)
    end
    nothing
end


# ── The two helpers this module keeps its own copy of ──────────────────────

_same_step(a::FieldReferenceStep, b::FieldReferenceStep) = a.name == b.name
_same_step(a::RangeReferenceStep, b::RangeReferenceStep) = a.start == b.start && a.stop == b.stop
_same_step(::Any, ::Any) = false

# Translate a path-bearing operation through `map_reference_backward` and pass
# every other one through unchanged. It is the kernel's default reader with one
# difference: an operation this projection cannot place travels rather than being
# dropped. `WorkbenchToWidgetModule` keeps the same helper for its own panels.
function _retarget_panel_op(p, iomap, op)
    op === nothing && return nothing
    if op isa ReplaceSelectionOperation
        new_path = map_reference_backward(p, iomap, op.path)
        return new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    elseif op isa ReplaceStringRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceStringRangeOperation(new_ref, op.replacement)
    elseif op isa ReplaceNumberRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceNumberRangeOperation(new_ref, op.replacement)
    elseif op isa ReplaceReferencedValueOperation
        op.document === nothing || return op
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceReferencedValueOperation(nothing, new_ref, op.value)
    elseif op isa CompoundOperation
        mapped = Any[_retarget_panel_op(p, iomap, o) for o in op.operations]
        return any(isnothing, mapped) ? nothing : CompoundOperation(mapped)
    else
        return op
    end
end
