"""
    WorkbenchToWidgetModule

WorkbenchDocument → WidgetDocument projection. Maps the workbench document
hierarchy to a widget tree.

    WorkbenchWorkbench  → WidgetShell containing a horizontal WidgetSplitPane
                          (navigation | center | control), where the center
                          is itself a vertical split of editing / information
    WorkbenchPage       → WidgetTabbedPane with one tab per panel
    WorkbenchNavigator  → WidgetScrollPane wrapping a WidgetComposite of folders
    WorkbenchConsole    → WidgetScrollPane wrapping projected content
    WorkbenchDescriptor → WidgetScrollPane wrapping a TextBlock that renders the content reference
    WorkbenchOperator   → empty WidgetScrollPane
    WorkbenchSearcher   → empty WidgetScrollPane
    WorkbenchEvaluator  → WidgetScrollPane wrapping projected content
    WorkbenchAssistant  → WidgetSplitPane (vertical) of conversation + input WidgetScrollPanes
    WorkbenchEditor     → WidgetScrollPane wrapping projected content

The printer also **forward-projects the workbench selection** onto the widget
tree: each `map_reference_forward` method is the structure-complete inverse of
the matching `map_reference_backward`, and `print_document` wires the
`selection` cells of the shell, the structural split panes, and the tabbed
panes to it. That lets the widget readers route a keystroke to the child the
selection points at (split panes via `_selected_split_slot`, tabbed panes by
making the active tab follow the selection) instead of broadcasting to every
pane. See the "Forward-Projecting Selection" section of package/kernel/doc/selection.md.
"""
module WorkbenchToWidgetModule

import ..ProjectionApiModule: print_document, print_child, read_intent,
                               map_reference_forward, map_reference_backward, Projection
import ..WorkbenchModule: WorkbenchDocument, WorkbenchWorkbench, WorkbenchPage,
                          WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
                          WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
                          WorkbenchAssistant, WORKBENCH_ASSISTANT_TITLE,
                          WorkbenchEditor, title
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetShell, WidgetSplitPane, WidgetTabbedPane,
                       WidgetScrollPane, WidgetComposite, WidgetCard, Point2D, Inset, inset_default,
                       SelectTabOperation
import ..LayoutModule: VerticalLayout
import ..ReferenceModule: Reference, EmptyReference, ConcreteReference,
                          FieldReferenceStep, RangeReferenceStep, get_reference_steps
import ..LayoutModule: LayoutConstraint
import ..TextModule: TextBlock, TextString
import ..FontModule: font_ubuntu_monospace_regular_20
import ..ColorModule: StyleColor, color_default
import ..IoMapModule: SimpleIoMap, ContentIoMap, ChildrenIoMap,
                      reconcile_child_iomap, reconcile_child_iomaps, var"@iomap"
import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..IoMapModule: IoMap
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..OperationModule: ReplaceSelectionOperation, ReplaceReferencedValueOperation, CompoundOperation
import ..OperationModule: Operation
import ..OperationModule: reroot_operation
import ..PrimitiveModule: ReplaceStringRangeOperation, ReplaceNumberRangeOperation
import ..EventModule: KeyDown, KeyPress
import ..GestureBindingModule: read_gesture
import ..ReferenceModule: Reference, ConcreteReference, ElementReferenceStep, PositionReferenceStep, RangeReferenceStep, EmptyReference, FieldReferenceStep, extend_reference, try_evaluate_reference
import ..CollectionModule: CellVector, ComputedCellVector
import ..ReferenceModule: var"@reference", var"@reference_step"
import ..ReferenceModule: var"@reference_case"
import ..PrinterContextModule: make_child_context
export WorkbenchWorkbenchToWidgetShell,    WorkbenchWorkbenchToWidgetShellIoMap,
       WorkbenchPageToWidgetTabbedPane,    WorkbenchPageToWidgetTabbedPaneIoMap,
       WorkbenchNavigatorToWidgetScrollPane, WorkbenchNavigatorToWidgetScrollPaneIoMap,
       WorkbenchConsoleToWidgetScrollPane,
       WorkbenchDescriptorToWidgetScrollPane,
       WorkbenchOperatorToWidgetScrollPane,
       WorkbenchSearcherToWidgetScrollPane,
       WorkbenchEvaluatorToWidgetScrollPane,
       WorkbenchAssistantToWidgetSplitPane,
       WorkbenchAssistantToWidgetCard,
       WorkbenchEditorToWidgetScrollPane,
       WorkbenchToWidget

# ── Projection structs ────────────────────────────────────────────────────────

struct WorkbenchWorkbenchToWidgetShell    <: Projection end
struct WorkbenchPageToWidgetTabbedPane    <: Projection end
struct WorkbenchNavigatorToWidgetScrollPane <: Projection end
struct WorkbenchConsoleToWidgetScrollPane   <: Projection end
struct WorkbenchDescriptorToWidgetScrollPane <: Projection end
struct WorkbenchOperatorToWidgetScrollPane  <: Projection end
struct WorkbenchSearcherToWidgetScrollPane  <: Projection end
struct WorkbenchEvaluatorToWidgetScrollPane <: Projection end
struct WorkbenchAssistantToWidgetSplitPane <: Projection end

"""
    WorkbenchAssistantToWidgetCard(; title, width, transcript_height, cell_height)

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
struct WorkbenchAssistantToWidgetCard <: Projection
    title::String
    width::Int
    transcript_height::Int
    cell_height::Int
end

WorkbenchAssistantToWidgetCard(; title::AbstractString = WORKBENCH_ASSISTANT_TITLE,
                               width::Integer = 1040,
                               transcript_height::Integer = 460,
                               cell_height::Integer = 120) =
    WorkbenchAssistantToWidgetCard(String(title), Int(width),
                                   Int(transcript_height), Int(cell_height))
struct WorkbenchEditorToWidgetScrollPane    <: Projection end

# ── IoMap structs ─────────────────────────────────────────────────────────────

@iomap struct WorkbenchWorkbenchToWidgetShellIoMap
    projection::Any
    input::WorkbenchWorkbench
    output::WidgetShell
    navigation_page_iomap::Any   # IoMap for navigation_page
    editing_page_iomap::Any      # IoMap for editing_page
    information_page_iomap::Any  # IoMap for information_page
    control_page_iomap::Any      # IoMap for control_page
end

# @iomap so the mappers/readers keep reading `iomap.element_iomaps` as the value
# while it is now a reconciling cell (a page tab add/remove reflows through it,
# AR-STABLE-IOMAP-IDENTITY).
@iomap struct WorkbenchPageToWidgetTabbedPaneIoMap
    projection::Any
    input::Any
    output::Any
    element_iomaps::Any          # reconciling cell: one IoMap per page element
end

@iomap struct WorkbenchNavigatorToWidgetScrollPaneIoMap
    projection::Any
    input::WorkbenchNavigator
    output::WidgetScrollPane
    folder_iomaps::Vector        # one IoMap per folder
end


# ── Helpers ───────────────────────────────────────────────────────────────────

const _PAD5  = Inset(5, 5, 5, 5)
const _WHITE = StyleColor(255, 255, 255, 255)

# ── Workbench layout tokens ───────────────────────────────────────────────
# The IDE chrome is laid out purely by the split panes' `LayoutConstraint`s —
# no pane carries a fixed `size`. Each split child states only:
#
#   - a **minimum** extent on the split axis (its floor), and
#   - a **weight**: its share of the leftover space once every child is at its
#     minimum. Main areas (editor, conversation, the center column) take the
#     large weight; the surrounding side panels take a small one, so they grow
#     *a bit* with the window but always less than the main area.
#
# A child sits at its minimum and grows only by weight, so its `preferred`
# extent is set equal to its `min` (otherwise the child's intrinsic content
# size would leak in as the base). Children with no minimum (the main areas)
# start from 0 and are sized entirely by their weight share.
const _NAV_MIN_WIDTH      = 200   # navigation column (left)
const _CONTROL_MIN_WIDTH  = 400   # control column (right; assistant chat)
const _INFO_MIN_HEIGHT    = 200   # information row in the center column
const _INPUT_MIN_HEIGHT   = 200   # assistant input: the composer chat-bubble draft
const _MAIN_WEIGHT        = 1.0   # editor / conversation / center column
const _SIDE_WEIGHT        = 0.2   # nav / control / info — grow, but less
const _SHELL_FALLBACK_WIDTH  = 1280  # window width when run outside a window
const _SHELL_FALLBACK_HEIGHT = 720   # window height when run outside a window

_recurse(recursion, doc, ctx) =
    (recursion !== nothing && doc isa WorkbenchDocument) ? print_child(recursion, doc, ctx) : SimpleIoMap(nothing, doc, doc)

_title_widget(doc::WorkbenchDocument) = title(doc)

# Strip a leading `FieldReferenceStep(name)` step from a forward-projected path;
# `nothing` if it doesn't match. Used to re-root the shell's full widget-domain
# selection onto the structural split panes it builds.
function _strip_field(path, name::AbstractString)
    path = path
    path isa ConcreteReference || return nothing
    (path.head isa FieldReferenceStep && path.head.name == name) || return nothing
    path.tail
end

# Strip a leading `elements[slot].child` (field, unit-range, field) from a
# split pane's selection; `nothing` if the selection doesn't enter that slot.
function _strip_split_child(path, slot::Int)
    rest = _strip_field(path, "elements")
    rest = rest
    rest isa ConcreteReference || return nothing
    rest.head isa RangeReferenceStep || return nothing
    (rest.head.start + 1) == slot || return nothing
    _strip_field(rest.tail, "child")
end

# ── print_document ──────────────────────────────────────────────────────────

function print_document(::WorkbenchWorkbenchToWidgetShell,
                           recursion, w::WorkbenchWorkbench, ctx)
    nav_iomap  = _recurse(recursion, w.navigation_page,  make_child_context(ctx, w, @reference_step navigation_page))
    edit_iomap = _recurse(recursion, w.editing_page,     make_child_context(ctx, w, @reference_step editing_page))
    info_iomap = _recurse(recursion, w.information_page, make_child_context(ctx, w, @reference_step information_page))
    ctrl_iomap = _recurse(recursion, w.control_page,     make_child_context(ctx, w, @reference_step control_page))

    # Placeholder filled once the IoMap is built below, so the
    # forward-projected selection cells can reference it.
    iomap_cell = Cell(nothing)
    wsel = getfield(w, :selection)
    _shell_sel() = begin
        im = iomap_cell[]
        im === nothing && return nothing
        sel = wsel[]
        sel === nothing && return nothing
        map_reference_forward(WorkbenchWorkbenchToWidgetShell(), im, sel)
    end

    # Center column: editor takes the main weight, info row grows a little from
    # its minimum.
    center_split = WidgetSplitPane(:vertical, Any[
        LayoutConstraint(edit_iomap.output;
                         min_height=0, preferred_height=0, weight_height=_MAIN_WEIGHT),
        LayoutConstraint(info_iomap.output;
                         min_height=_INFO_MIN_HEIGHT, preferred_height=_INFO_MIN_HEIGHT,
                         weight_height=_SIDE_WEIGHT),
    ])
    # Top level: navigator on the left and control on the right grow a little
    # from their minimums; the center column takes the main weight.
    main_split = WidgetSplitPane(:horizontal, Any[
        LayoutConstraint(nav_iomap.output;
                         min_width=_NAV_MIN_WIDTH, preferred_width=_NAV_MIN_WIDTH,
                         weight_width=_SIDE_WEIGHT),
        LayoutConstraint(center_split;
                         min_width=0, preferred_width=0, weight_width=_MAIN_WEIGHT),
        LayoutConstraint(ctrl_iomap.output;
                         min_width=_CONTROL_MIN_WIDTH, preferred_width=_CONTROL_MIN_WIDTH,
                         weight_width=_SIDE_WEIGHT),
    ])
    # Forward-project the workbench selection onto the structural split panes
    # so their coordless readers route the event to the focused child: the
    # main split's selection is the shell selection without its leading
    # `content` step; the center column's is the main split's without its
    # `elements[2].child` (slot 2) step.
    set_cell_function!(getfield(main_split, :selection),
           () -> _strip_field(_shell_sel(), "content"))
    set_cell_function!(getfield(center_split, :selection),
           () -> _strip_split_child(_strip_field(_shell_sel(), "content"), 2))

    # Track the window: the shell fills whatever extent the parent (the
    # WindowDocument's CopyingProjection) seeded on the context, falling
    # back to a sensible default when run outside a window.
    aw, ah = ctx.available_width, ctx.available_height
    shell_size = Point2D(
        ComputedCell(() -> aw === nothing ? _SHELL_FALLBACK_WIDTH  : Int(aw[])),
        ComputedCell(() -> ah === nothing ? _SHELL_FALLBACK_HEIGHT : Int(ah[])),
    )
    shell = WidgetShell(main_split;
                        size=shell_size)
    set_cell_function!(getfield(shell, :selection), _shell_sel)

    iomap = WorkbenchWorkbenchToWidgetShellIoMap(nothing, w, shell,
                                                 nav_iomap, edit_iomap, info_iomap, ctrl_iomap)
    iomap_cell[] = iomap
    iomap
end

function print_document(::WorkbenchPageToWidgetTabbedPane,
                           recursion, page::WorkbenchPage, ctx)
    # Reconcile the page elements by identity so a tab add/remove reuses the
    # survivors' iomaps, and wire the tab strip reactively so it reflows on a
    # structural edit (each tab page is `(title, content-output)` per element).
    element_iomaps = reconcile_child_iomaps(
        () -> page.elements,
        (i, elem) -> _recurse(recursion, elem,
            make_child_context(ctx, page, (@reference_step elements), (@reference_step [i]))))
    tabbed = WidgetTabbedPane(Any[]; border=_PAD5)
    set_cell_function!(tabbed, () -> begin
        ims = element_iomaps[]
        Any[(_title_widget(page.elements[i]), ims[i].output) for i in eachindex(ims)]
    end)
    iomap = WorkbenchPageToWidgetTabbedPaneIoMap(nothing, page, tabbed, element_iomaps)
    # Forward-project the page's selection onto the tabbed pane so the active
    # tab follows the document selection (and coordless events route to it).
    #
    # Forward only the tab-identifying prefix `elements[i]` →
    # `selector_element_pairs[i]`, not the deep suffix: every consumer of a tabbed
    # pane's selection (`_tab_index_from_selection`, `_route_active_tab`) reads only
    # the tab index `i`; the caret inside the active tab is carried by that tab
    # content's own forward-projected selection. Keeping just `elements[i]` stops
    # this cell from reading the deep cursor cells, so a caret move inside a tab —
    # which (thanks to the in-place `replace_selection!`) mutates only the terminal
    # cursor step, leaving the `elements[i]` prefix untouched — does not invalidate
    # this cell and therefore does not regenerate the tab strip or active-content
    # wrapper (incremental selection propagation).
    #
    # The prefix is two nodes: the `elements` field step *and* the `[i]` index step.
    # With type checkpoints folded into nodes, `elements` and `[i]` are separate
    # path nodes, so truncating to `sel.head` alone drops the index and the tab
    # routing can no longer tell which tab is selected (clicking a tab would not
    # switch the active page).
    psel = getfield(page, :selection)
    set_cell_function!(getfield(tabbed, :selection), () -> begin
        sel = psel[]
        sel === nothing && return nothing
        map_reference_forward(WorkbenchPageToWidgetTabbedPane(), iomap, _tab_index_prefix(sel))
    end)
    iomap
end

# The tab-identifying prefix of a page selection: `elements[i]` — the field step
# and the index step — with any deeper cursor suffix dropped. Type checkpoints fold
# into the nodes, so `elements` and `[i]` are two distinct `ConcreteReference`
# nodes; keep both and re-terminate after the index, carrying the index node's
# result type onto the new `EmptyReference` terminal. Returns `sel` unchanged
# when it is not the `elements[i]…` shape (e.g. a whole-page `∅` selection), which
# forwards to no tab and the printer falls back to tab 1.
function _tab_index_prefix(sel)
    sel isa ConcreteReference || return sel
    tail = sel.tail
    if tail isa ConcreteReference && tail.head isa RangeReferenceStep
        return ConcreteReference(sel.type, sel.head,
                   ConcreteReference(tail.type, tail.head,
                       EmptyReference(tail.tail.type)))
    end
    ConcreteReference(sel.type, sel.head, EmptyReference())
end

function print_document(::WorkbenchNavigatorToWidgetScrollPane,
                           recursion, nav::WorkbenchNavigator, ctx)
    scroll = WidgetScrollPane(nav.workspace;
                              padding=_PAD5, padding_color=_WHITE)
    WorkbenchNavigatorToWidgetScrollPaneIoMap(nothing, nav, scroll, Any[])
end


# A panel whose CONTENT can be replaced — an editor reloaded from disk, a console
# handed a new block, an evaluator given a new expression.
#
# The obvious printing (`_recurse` once, hand the result to `WidgetScrollPane`)
# freezes it: the constructor wraps whatever it is given in `Cell(content)`, a
# CONSTANT, so a later write to `panel.content` has no reactive edge and the pane
# keeps rendering the document it was born with. It does not error; it silently
# stops updating (AR-REACTIVE-OUTPUT-STRUCTURE).
#
# So the child IoMap is reconciled by identity and the pane's content is a THUNK
# over it. Replacing the content re-projects exactly once and the pane follows;
# leaving it alone reuses the same child IoMap, so nothing downstream is rebuilt.
function _content_pane(recursion, node, step, ctx; kwargs...)
    field = Symbol(step.name)     # the step addresses it; reading it needs the name
    child = reconcile_child_iomap(() -> getproperty(node, field),
                                  v -> _recurse(recursion, v, make_child_context(ctx, node, step)))
    scroll = WidgetScrollPane(child[].output; kwargs...)
    set_cell_function!(getfield(scroll, :content), () -> child[].output)
    iomap = ContentIoMap(nothing, node, scroll, child[])
    set_cell_function!(getfield(iomap, :inner_iomap), () -> child[])
    iomap
end

print_document(::WorkbenchConsoleToWidgetScrollPane, recursion, c::WorkbenchConsole, ctx) =
    _content_pane(recursion, c, @reference_step(content), ctx;
                  padding=_PAD5, padding_color=_WHITE)

function print_document(::WorkbenchDescriptorToWidgetScrollPane,
                           recursion, d::WorkbenchDescriptor, ctx)
    text = TextBlock(
        TextString(() -> string(d.content),
                   font_ubuntu_monospace_regular_20, color_default),
    )
    scroll = WidgetScrollPane(text;
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, d, scroll)
end

function print_document(::WorkbenchOperatorToWidgetScrollPane,
                           recursion, o::WorkbenchOperator, ctx)
    scroll = WidgetScrollPane(nothing;
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, o, scroll)
end

function print_document(::WorkbenchSearcherToWidgetScrollPane,
                           recursion, s::WorkbenchSearcher, ctx)
    scroll = WidgetScrollPane(nothing;
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, s, scroll)
end

print_document(::WorkbenchEvaluatorToWidgetScrollPane, recursion, e::WorkbenchEvaluator, ctx) =
    _content_pane(recursion, e, @reference_step(content), ctx;
                  padding=_PAD5, padding_color=_WHITE)

function print_document(::WorkbenchAssistantToWidgetSplitPane,
                           recursion, a::WorkbenchAssistant, ctx)
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
    SimpleIoMap(nothing, a, column)
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
function print_document(p::WorkbenchAssistantToWidgetCard,
                        recursion, a::WorkbenchAssistant, ctx)
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
function map_reference_forward(::WorkbenchAssistantToWidgetCard, iomap::SimpleIoMap, reference)
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
function map_reference_backward(::WorkbenchAssistantToWidgetCard, iomap::SimpleIoMap, reference)
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

_same_step(a::FieldReferenceStep, b::FieldReferenceStep) = a.name == b.name
_same_step(a::RangeReferenceStep, b::RangeReferenceStep) = a.start == b.start && a.stop == b.stop
_same_step(::Any, ::Any) = false

# A click that named no pane is still a click on the card, and the card takes it
# rather than letting it fall through to whatever the card is embedded in.
function read_intent(p::WorkbenchAssistantToWidgetCard, iomap::SimpleIoMap,
                     op::ReplaceSelectionOperation)
    inner = map_reference_backward(p, iomap, op.path)
    ReplaceSelectionOperation(inner === nothing ? EmptyReference() : inner)
end

print_document(::WorkbenchEditorToWidgetScrollPane, recursion, e::WorkbenchEditor, ctx) =
    _content_pane(recursion, e, @reference_step(content), ctx;
                  follow_end=e.follow_end === true, padding=_PAD5, padding_color=_WHITE)

# ── map_reference_forward ──────────────────────────────────────────────
#
# Inverse of `map_reference_backward`: translate a workbench-domain
# reference rooted at a node into the widget-domain reference that node's
# projection produced. The printer wires each output widget node's
# `selection` cell to `map_reference_forward(...)` of the corresponding
# input node's selection (which `set_selection!` stores as a suffix at
# every level), so the generated widget tree carries the forward-projected
# selection at every level and each reader can forward an event to the
# child the selection points to (see `_selected_split_slot` /
# `_route_active_tab` in WidgetToGraphics). These are the precise inverses
# of the structural steps the backward mappings strip; recall that the DSL
# `[i]` is `RangeReferenceStep(i-1, i)`, the same shape the backward side
# matches with `{i-1:i}`.

# Forward an already-stripped tail through a page / panel iomap, dispatching
# the way the backward side does — the per-node IoMaps store
# `projection = nothing`, so recover the projection from the iomap / input
# type rather than from the stored projection.
_page_forward(page_iomap::WorkbenchPageToWidgetTabbedPaneIoMap, rest) =
    map_reference_forward(WorkbenchPageToWidgetTabbedPane(), page_iomap, rest)
_page_forward(_, _) = nothing

_panel_forward(elem_im, rest) = _panel_forward(elem_im.input, elem_im, rest)
_panel_forward(::WorkbenchEditor,    im, ref) = map_reference_forward(WorkbenchEditorToWidgetScrollPane(),    im, ref)
_panel_forward(::WorkbenchNavigator, im, ref) = map_reference_forward(WorkbenchNavigatorToWidgetScrollPane(), im, ref)
_panel_forward(::WorkbenchConsole,   im, ref) = map_reference_forward(WorkbenchConsoleToWidgetScrollPane(),   im, ref)
_panel_forward(::WorkbenchEvaluator, im, ref) = map_reference_forward(WorkbenchEvaluatorToWidgetScrollPane(), im, ref)
_panel_forward(::WorkbenchAssistant, im, ref) = map_reference_forward(WorkbenchAssistantToWidgetSplitPane(),  im, ref)
_panel_forward(_, _, _)                       = nothing

# WorkbenchWorkbench → WidgetShell(WidgetSplitPane(nav | center(edit|info) | ctrl)).
# Mirror the structural steps stripped by `map_reference_backward` above:
# the horizontal split's `elements[1|2|3].child`, and the center column's
# nested `elements[1|2].child`. `something(_, EmptyReference())` keeps a
# selection that points only at a page (no deeper suffix) routable.
function map_reference_forward(::WorkbenchWorkbenchToWidgetShell,
                                iomap::WorkbenchWorkbenchToWidgetShellIoMap,
                                reference)
    @reference_case reference begin
        ::WorkbenchWorkbench.navigation_page.rest... => begin
            inner = something(_page_forward(iomap.navigation_page_iomap, rest), EmptyReference(WidgetTabbedPane))
            @reference ::WidgetShell.content::WidgetSplitPane.elements::CellVector[1]::LayoutConstraint.child.^(inner)
        end
        ::WorkbenchWorkbench.editing_page.rest... => begin
            inner = something(_page_forward(iomap.editing_page_iomap, rest), EmptyReference(WidgetTabbedPane))
            @reference ::WidgetShell.content::WidgetSplitPane.elements::CellVector[2]::LayoutConstraint.child::WidgetSplitPane.elements::CellVector[1]::LayoutConstraint.child.^(inner)
        end
        ::WorkbenchWorkbench.information_page.rest... => begin
            inner = something(_page_forward(iomap.information_page_iomap, rest), EmptyReference(WidgetTabbedPane))
            @reference ::WidgetShell.content::WidgetSplitPane.elements::CellVector[2]::LayoutConstraint.child::WidgetSplitPane.elements::CellVector[2]::LayoutConstraint.child.^(inner)
        end
        ::WorkbenchWorkbench.control_page.rest... => begin
            inner = something(_page_forward(iomap.control_page_iomap, rest), EmptyReference(WidgetTabbedPane))
            @reference ::WidgetShell.content::WidgetSplitPane.elements::CellVector[3]::LayoutConstraint.child.^(inner)
        end
    end
end

# WorkbenchPage → WidgetTabbedPane: `elements[i]` ↔ `selector_element_pairs[i]`.
function map_reference_forward(::WorkbenchPageToWidgetTabbedPane,
                                iomap::WorkbenchPageToWidgetTabbedPaneIoMap,
                                reference)
    @reference_case reference begin
        ::WorkbenchPage.elements[i].rest... => begin
            (1 <= i <= length(iomap.element_iomaps)) || return nothing
            inner = something(_panel_forward(iomap.element_iomaps[i], rest), EmptyReference(WidgetDocument))
            @reference ::WidgetTabbedPane.selector_element_pairs::CellVector[i].^(inner)
        end
    end
end

# Each panel renames its workbench field to the widget scroll pane's `content`
# (the wrapped content document is opaque to this projection, so its own
# selection suffix passes straight through).
function map_reference_forward(::WorkbenchEditorToWidgetScrollPane, iomap::ContentIoMap, reference)
    @reference_case reference begin
        ::WorkbenchEditor.content.rest... => @reference ::WidgetScrollPane.content.^(rest)
    end
end

function map_reference_forward(::WorkbenchNavigatorToWidgetScrollPane,
                                iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap, reference)
    @reference_case reference begin
        ::WorkbenchNavigator.workspace.rest... => @reference ::WidgetScrollPane.content.^(rest)
    end
end

function map_reference_forward(::WorkbenchConsoleToWidgetScrollPane, iomap::ContentIoMap, reference)
    @reference_case reference begin
        ::WorkbenchConsole.content.rest... => @reference ::WidgetScrollPane.content.^(rest)
    end
end

function map_reference_forward(::WorkbenchEvaluatorToWidgetScrollPane, iomap::ContentIoMap, reference)
    @reference_case reference begin
        ::WorkbenchEvaluator.content.rest... => @reference ::WidgetScrollPane.content.^(rest)
    end
end

# Assistant → vertical WidgetSplitPane(conversation | input), each a scroll pane.
function map_reference_forward(::WorkbenchAssistantToWidgetSplitPane, iomap, reference)
    @reference_case reference begin
        ::WorkbenchAssistant.conversation.rest... => @reference ::WidgetSplitPane.elements::CellVector[1]::LayoutConstraint.child::WidgetScrollPane.content.^(rest)
        ::WorkbenchAssistant.input.rest...        => @reference ::WidgetSplitPane.elements::CellVector[2]::LayoutConstraint.child::WidgetScrollPane.content.^(rest)
    end
end

# Descriptor / Operator / Searcher render non-document content — nothing to project.
map_reference_forward(::WorkbenchDescriptorToWidgetScrollPane, iomap, reference) = nothing
map_reference_forward(::WorkbenchOperatorToWidgetScrollPane, iomap, reference) = nothing
map_reference_forward(::WorkbenchSearcherToWidgetScrollPane, iomap, reference) = nothing

# ── map_reference_backward ────────────────────────────────────────────────────

# ── map_reference_backward ──────────────────────────────────────────────
#
# Each panel projection translates a widget-domain reference (what the
# combined widget→graphics chain produced) into a workbench-domain
# reference rooted at this panel's input document. Widget-side readers
# have already prepended their structural steps (`content` for a scroll
# pane, `selector_element_pairs[i]` for a tabbed pane, `elements[i].child`
# for a split pane slot wrapped in a LayoutConstraint); the panel
# projections strip the widget naming and re-root with the panel's own
# workbench field name. The default `read_intent` consults these
# functions to translate `ReplaceSelectionOperation`, and custom
# `read_intent` overrides below extend the same translation to
# `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation`.

function map_reference_backward(::WorkbenchEditorToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    @reference_case reference begin
        ::WidgetScrollPane.content.rest... => @reference ::WorkbenchEditor.content.^(rest)
    end
end

function map_reference_backward(::WorkbenchNavigatorToWidgetScrollPane,
                                 iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap,
                                 reference)
    # WorkbenchNavigator stores the workspace in `.workspace`; the widget
    # scroll pane wraps it as `.content`. Rewrite the field name.
    @reference_case reference begin
        ::WidgetScrollPane.content.rest... => @reference ::WorkbenchNavigator.workspace.^(rest)
    end
end

function map_reference_backward(::WorkbenchConsoleToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    @reference_case reference begin
        ::WidgetScrollPane.content.rest... => @reference ::WorkbenchConsole.content.^(rest)
    end
end

function map_reference_backward(::WorkbenchEvaluatorToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    @reference_case reference begin
        ::WidgetScrollPane.content.rest... => @reference ::WorkbenchEvaluator.content.^(rest)
    end
end

# Descriptor/Operator/Searcher render empty or non-document content — no
# referenceable structure to translate into.
function map_reference_backward(::WorkbenchDescriptorToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkbenchOperatorToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkbenchSearcherToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkbenchAssistantToWidgetSplitPane,
                                 iomap,
                                 reference)
    # The assistant projects to a vertical WidgetSplitPane with the
    # conversation pane at slot 0 and the input pane at slot 1, each
    # wrapped in a LayoutConstraint and then a WidgetScrollPane.
    # So bubbled paths look like `elements[i].child.content.<rest>`.
    @reference_case reference begin
        ::WidgetSplitPane.elements{s:e}.child.content.rest... => begin
            i = s + 1
            if i == 1
                @reference ::WorkbenchAssistant.conversation.^(rest)
            elseif i == 2
                @reference ::WorkbenchAssistant.input.^(rest)
            else
                nothing
            end
        end
    end
end

function map_reference_backward(::WorkbenchPageToWidgetTabbedPane,
                                 iomap::WorkbenchPageToWidgetTabbedPaneIoMap,
                                 reference)
    # A WorkbenchPage projects to a WidgetTabbedPane whose
    # `selector_element_pairs[i]` corresponds 1:1 with `elements[i]` of
    # the page. Recurse via the matching element iomap so the panel's
    # own backward map can re-root its slice of the path.
    @reference_case reference begin
        ::WidgetTabbedPane.selector_element_pairs{s:e}.rest... => begin
            i = s + 1
            i <= length(iomap.element_iomaps) || return nothing
            elem_im = iomap.element_iomaps[i]
            inner = _panel_backward(elem_im, rest)
            inner === nothing && return nothing
            @reference ::WorkbenchPage.elements::CellVector[i].^(inner)
        end
    end
end

# Dispatch the panel iomap's backward map by the panel input document's
# type. The panel iomaps were built by the WorkbenchToWidget factory which
# stores `projection = nothing` on the per-panel IoMap structs, so we
# can't dispatch on the stored projection — we dispatch on `input` type
# instead.
_panel_backward(elem_im, rest) = _panel_backward(elem_im.input, elem_im, rest)
_panel_backward(::WorkbenchEditor,     im, ref) = map_reference_backward(WorkbenchEditorToWidgetScrollPane(),     im, ref)
_panel_backward(::WorkbenchNavigator,  im, ref) = map_reference_backward(WorkbenchNavigatorToWidgetScrollPane(),  im, ref)
_panel_backward(::WorkbenchConsole,    im, ref) = map_reference_backward(WorkbenchConsoleToWidgetScrollPane(),    im, ref)
_panel_backward(::WorkbenchEvaluator,  im, ref) = map_reference_backward(WorkbenchEvaluatorToWidgetScrollPane(),  im, ref)
_panel_backward(::WorkbenchDescriptor, im, ref) = map_reference_backward(WorkbenchDescriptorToWidgetScrollPane(), im, ref)
_panel_backward(::WorkbenchOperator,   im, ref) = map_reference_backward(WorkbenchOperatorToWidgetScrollPane(),   im, ref)
_panel_backward(::WorkbenchSearcher,   im, ref) = map_reference_backward(WorkbenchSearcherToWidgetScrollPane(),   im, ref)
_panel_backward(::WorkbenchAssistant,  im, ref) = map_reference_backward(WorkbenchAssistantToWidgetSplitPane(),   im, ref)
_panel_backward(_, _, _)                        = nothing

function map_reference_backward(::WorkbenchWorkbenchToWidgetShell,
                                 iomap::WorkbenchWorkbenchToWidgetShellIoMap,
                                 reference)
    # The workbench shell's widget tree is:
    #   WidgetShell.content (horizontal WidgetSplitPane)
    #     elements[0].child = nav page widget   ← navigation_page
    #     elements[1].child = center (vertical WidgetSplitPane)
    #       elements[0].child = edit page widget   ← editing_page
    #       elements[1].child = info page widget   ← information_page
    #     elements[2].child = ctrl page widget  ← control_page
    @reference_case reference begin
        ::WidgetShell.content.elements{0:1}.child.rest... => begin
            inner = _page_backward(iomap.navigation_page_iomap, rest)
            inner === nothing && return nothing
            @reference ::WorkbenchWorkbench.navigation_page.^(inner)
        end
        ::WidgetShell.content.elements{1:2}.child.elements{0:1}.child.rest... => begin
            inner = _page_backward(iomap.editing_page_iomap, rest)
            inner === nothing && return nothing
            @reference ::WorkbenchWorkbench.editing_page.^(inner)
        end
        ::WidgetShell.content.elements{1:2}.child.elements{1:2}.child.rest... => begin
            inner = _page_backward(iomap.information_page_iomap, rest)
            inner === nothing && return nothing
            @reference ::WorkbenchWorkbench.information_page.^(inner)
        end
        ::WidgetShell.content.elements{2:3}.child.rest... => begin
            inner = _page_backward(iomap.control_page_iomap, rest)
            inner === nothing && return nothing
            @reference ::WorkbenchWorkbench.control_page.^(inner)
        end
    end
end

_page_backward(page_iomap::WorkbenchPageToWidgetTabbedPaneIoMap, rest) =
    map_reference_backward(WorkbenchPageToWidgetTabbedPane(), page_iomap, rest)
_page_backward(_, _) = nothing

# ── read_intent ───────────────────────────────────────────────────────────

function read_intent(p::WorkbenchWorkbenchToWidgetShell,
                          iomap::WorkbenchWorkbenchToWidgetShellIoMap, op)
    # 1. Tab-strip click: a selection replacement whose path ends in a pane's own
    # `selector_element_pairs[i]`, prefixed by the widget route from this shell's
    # output down to that pane. Resolve the prefix to find which pane was clicked,
    # match it against each page's output, convert through that page's reader, and
    # re-root the answer under the page's workbench field name.
    #
    # It has to be claimed here, before the path-bearing branch below: that one maps
    # the whole path with the shell's own mapper, which does not resolve a strip step
    # and answers `nothing`, dropping the click.
    tab_click = op isa ReplaceSelectionOperation ? _split_tab_click(op.path) : nothing
    if tab_click !== nothing
        (prefix, index) = tab_click
        pane = try_evaluate_reference(iomap.output, prefix)
        local_op = ReplaceSelectionOperation(
            ConcreteReference(FieldReferenceStep("selector_element_pairs"),
                              ConcreteReference(ElementReferenceStep(index), EmptyReference())))
        for (field_name, page_iomap) in (("navigation_page",  iomap.navigation_page_iomap),
                                          ("editing_page",     iomap.editing_page_iomap),
                                          ("information_page", iomap.information_page_iomap),
                                          ("control_page",     iomap.control_page_iomap))
            page_iomap isa WorkbenchPageToWidgetTabbedPaneIoMap || continue
            # Identity, not an index range: two pages can both have a third tab, and
            # only the one the click landed in may answer.
            page_iomap.output === pane || continue
            result = read_intent(WorkbenchPageToWidgetTabbedPane(), page_iomap, local_op)
            result isa ReplaceSelectionOperation || continue
            return ReplaceSelectionOperation(
                ConcreteReference(FieldReferenceStep(field_name), result.path))
        end
        # No page owns that pane, so this is not a page's tab strip — a nested pane
        # inside a tab names its tabs the same way. Fall through and let the ordinary
        # mapper below answer, rather than swallow the operation here.
    end
    # 2. Path-bearing op from a deeper reader: translate its widget-domain
    # reference into workbench-domain via `map_reference_backward`.
    if op isa ReplaceSelectionOperation
        new_path = map_reference_backward(p, iomap, op.path)
        return new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    end
    if op isa ReplaceStringRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceStringRangeOperation(new_ref, op.replacement)
    end
    if op isa ReplaceNumberRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceNumberRangeOperation(new_ref, op.replacement)
    end
    # A document-rooted ReplaceReferencedValueOperation (e.g. a folded document-replace /
    # sequence-splice from a doc edited in a panel) must be rerooted too; a compound
    # of such ops maps over its members.
    if op isa ReplaceReferencedValueOperation && op.document === nothing
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : ReplaceReferencedValueOperation(nothing, new_ref, op.value)
    end
    if op isa CompoundOperation
        mapped = Any[read_intent(p, iomap, o) for o in op.operations]
        return any(isnothing, mapped) ? nothing : CompoundOperation(mapped)
    end
    # 3. Other operation types (an identity-rooted ReplaceReferencedValueOperation that
    # targets a widget directly, not a path) — pass through.
    op isa Operation && return op
    # 4. Raw events (KeyPress / KeyDown). Focus follows the workbench selection:
    # offer the key ONLY to the panel the selection currently points at, so
    # clicking the JSON editor moves typing there instead of the assistant
    # composer. The composer grabs every printable key (its `insert` binding
    # matches any KeyPress) and forward-projects no selection of its own, so a
    # blind broadcast to every panel here let it swallow the keystroke no matter
    # where the selection was — clicking the JSON document could never take focus
    # away from the draft. A panel that declines (its reader hands the raw key
    # back rather than an Operation — e.g. an editor tab passing a plain character
    # down to its own text cursor) yields `nothing`, so the normal output→input
    # threading then routes the key through the forward-projected selection to the
    # focused descendant.
    sel_panel = _selected_panel(iomap)
    if sel_panel !== nothing
        field_name, elem_idx, elem_iomap = sel_panel
        return _panel_raw_key(field_name, elem_idx, elem_iomap, op)
    end
    # No panel is selected (a fresh workbench, nothing clicked yet): the assistant
    # composer keeps the default focus, so offer the key to each panel — only the
    # assistant claims a raw key. Guards the "ENTER through the nested workbench"
    # path (ConversationPanelTest); once anything is clicked, the selection-gated
    # branch above takes over.
    for (field_name, page_iomap) in (("navigation_page",  iomap.navigation_page_iomap),
                                      ("editing_page",     iomap.editing_page_iomap),
                                      ("information_page", iomap.information_page_iomap),
                                      ("control_page",     iomap.control_page_iomap))
        page_iomap isa WorkbenchPageToWidgetTabbedPaneIoMap || continue
        for (elem_idx, elem_iomap) in enumerate(page_iomap.element_iomaps)
            handled = _panel_raw_key(field_name, elem_idx, elem_iomap, op)
            handled === nothing || return handled
        end
    end
    return nothing
end

# The panel `(page_field_name, 1-based index, element iomap)` the workbench
# selection currently points at, or `nothing` when the selection is empty or
# does not name a panel. A selection is `page.elements[i].<rest>`: match the
# leading page field, then the `elements` field and its index step (type
# checkpoints fold into the nodes, so `elements` and `[i]` are two nodes).
function _selected_panel(iomap::WorkbenchWorkbenchToWidgetShellIoMap)
    sel = getfield(iomap.input, :selection)[]
    sel isa ConcreteReference || return nothing
    sel.head isa FieldReferenceStep || return nothing
    page_iomap = sel.head.name == "navigation_page"  ? iomap.navigation_page_iomap  :
                 sel.head.name == "editing_page"     ? iomap.editing_page_iomap      :
                 sel.head.name == "information_page" ? iomap.information_page_iomap  :
                 sel.head.name == "control_page"     ? iomap.control_page_iomap      : nothing
    page_iomap isa WorkbenchPageToWidgetTabbedPaneIoMap || return nothing
    rest = sel.tail
    (rest isa ConcreteReference && rest.head isa FieldReferenceStep &&
        rest.head.name == "elements") || return nothing
    rest = rest.tail
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) || return nothing
    idx = rest.head.start + 1
    (1 <= idx <= length(page_iomap.element_iomaps)) || return nothing
    (sel.head.name, idx, page_iomap.element_iomaps[idx])
end

# Offer a raw event to a single panel's reader, re-rooting a produced Operation
# under `page.elements[idx]`. Returns `nothing` when the panel declines (its
# reader returns a non-Operation, e.g. the raw key passed straight through so it
# can be threaded to the panel's own text cursor instead).
function _panel_raw_key(field_name, elem_idx, elem_iomap, op)
    result = read_intent(WorkbenchToWidget(), elem_iomap, op)
    result isa Operation || return nothing
    _prefix_operation(result, (FieldReferenceStep(field_name),
                               FieldReferenceStep("elements"),
                               RangeReferenceStep(elem_idx - 1, elem_idx)))
end

# Prepend `prefix_steps` to the path inside `op`, if the op carries a path.
# Operations that target a captured Julia value (e.g. SubmitProseOperation
# holds its WorkbenchAssistant directly) need no prefixing.
# Prepend a panel's location steps to a path-bearing op routed up from that panel.
# Delegates to the shared `reroot_operation`, so ReplaceReferencedValueOperation (the
# folded document-replace / sequence-splice ops) and CompoundOperation reroot too.
_prefix_operation(op, prefix_steps::Tuple) = reroot_operation(op, prefix_steps)

# The 1-based tab a bare `selector_element_pairs[i]` names, or `nothing`.
function _strip_tab_index(path)
    path isa ConcreteReference || return nothing
    (path.head isa FieldReferenceStep && path.head.name == "selector_element_pairs") || return nothing
    t = path.tail
    (t isa ConcreteReference && t.head isa RangeReferenceStep && t.tail isa EmptyReference) || return nothing
    Int(t.head.start) + 1
end

# A tab-strip click arrives re-rooted: the widget tree between the shell's output
# and the tabbed pane is already prefixed onto the path, so the strip's own
# `selector_element_pairs[i]` sits at the **end**. Split it into that prefix (which
# names the pane that was clicked) and the 1-based tab index. `nothing` when the
# path does not end that way.
function _split_tab_click(path)
    prefix_steps = Any[]
    node = path
    while node isa ConcreteReference
        idx = _strip_tab_index(node)
        idx === nothing || return (foldr(ConcreteReference, prefix_steps; init = EmptyReference()), idx)
        push!(prefix_steps, node.head)
        node = node.tail
    end
    nothing
end

function read_intent(p::WorkbenchPageToWidgetTabbedPane,
                          iomap::WorkbenchPageToWidgetTabbedPaneIoMap, op)
    # Convert a tab-strip click into a workbench-domain selection move. The strip
    # reports one as a selection replacement naming its own `selector_element_pairs[i]`,
    # so this recognises that shape rather than a bespoke operation.
    idx = op isa ReplaceSelectionOperation ? _strip_tab_index(op.path) : nothing
    if idx !== nothing
        1 <= idx <= length(iomap.input.elements) || return op
        # The tabbed pane's active tab is a forward projection of the page
        # selection (see print_document), so moving the document selection
        # to this element is enough — no imperative write to the widget cell.
        return ReplaceSelectionOperation(@reference ::WorkbenchPage.elements::CellVector[idx]::WorkbenchDocument)
    end
    _retarget_panel_op(p, iomap, op)
end

function read_intent(p::WorkbenchNavigatorToWidgetScrollPane,
                          iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

function read_intent(p::WorkbenchConsoleToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

function read_intent(p::WorkbenchDescriptorToWidgetScrollPane, iomap, op)
    _retarget_panel_op(p, iomap, op)
end

function read_intent(p::WorkbenchOperatorToWidgetScrollPane, iomap, op)
    _retarget_panel_op(p, iomap, op)
end

function read_intent(p::WorkbenchSearcherToWidgetScrollPane, iomap, op)
    _retarget_panel_op(p, iomap, op)
end

function read_intent(p::WorkbenchEvaluatorToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

function read_intent(p::WorkbenchAssistantToWidgetSplitPane,
                          iomap, op)
    # The specific KeyPress / KeyDown handlers live in
    # `WorkbenchAssistantModule` (loaded later in the include chain) and
    # take precedence via multiple dispatch. For everything else that
    # reaches us, translate path-bearing ops to the assistant's input
    # domain and let widget-target ops (an identity-rooted ReplaceReferencedValueOperation)
    # pass through; unhandled raw events return `nothing`.
    if op isa Operation
        return _retarget_panel_op(p, iomap, op)
    end
    nothing
end

function read_intent(p::WorkbenchEditorToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    # Give the WorkbenchEditor tab first crack at a raw input gesture — its
    # `@gestures` table (Ctrl+S save, Ctrl+O reload, in `WorkbenchFileModule`) —
    # before the event descends into the tab's content. `iomap.input` is the
    # `WorkbenchEditor`. This mirrors the generic leaf delegation to
    # `read_gesture` in `Projection.jl`, which this projection's own reader
    # override would otherwise shadow. A handled gesture yields a self-contained
    # operation (it carries the tab), so it bubbles up unchanged.
    if op isa Union{KeyDown, KeyPress}
        tab_op = read_gesture(iomap.input, op)
        tab_op === nothing || return tab_op
    end
    _retarget_panel_op(p, iomap, op)
end

# Translate a path-bearing op via `map_reference_backward`; pass other ops
# through unchanged. Used by each workbench panel projection so the path
# walks up into the workbench-domain reference space one layer at a time.
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

# ── Factory ───────────────────────────────────────────────────────────────────

"""
    WorkbenchToWidget()

Build a type-dispatching projection that maps any `WorkbenchDocument`
subtree to the corresponding `WidgetDocument` tree.

The compound projections (`WorkbenchWorkbench`, `WorkbenchPage`,
`WorkbenchNavigator`) recurse back through this same projection for their
child documents. Wrap the result in `RecursiveProjection` at the call site
to enable that recursion.
"""
function WorkbenchToWidget()
    TypeDispatchingProjection(
        WorkbenchWorkbench  => WorkbenchWorkbenchToWidgetShell(),
        WorkbenchPage       => WorkbenchPageToWidgetTabbedPane(),
        WorkbenchNavigator  => WorkbenchNavigatorToWidgetScrollPane(),
        WorkbenchConsole    => WorkbenchConsoleToWidgetScrollPane(),
        WorkbenchDescriptor => WorkbenchDescriptorToWidgetScrollPane(),
        WorkbenchOperator   => WorkbenchOperatorToWidgetScrollPane(),
        WorkbenchSearcher   => WorkbenchSearcherToWidgetScrollPane(),
        WorkbenchEvaluator  => WorkbenchEvaluatorToWidgetScrollPane(),
        WorkbenchAssistant  => WorkbenchAssistantToWidgetSplitPane(),
        WorkbenchEditor     => WorkbenchEditorToWidgetScrollPane(),
    )
end

end # module
