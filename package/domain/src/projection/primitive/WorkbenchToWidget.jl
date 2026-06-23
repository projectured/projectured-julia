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
    WorkbenchDescriptor → WidgetScrollPane wrapping a TextText that renders the content reference
    WorkbenchOperator   → empty WidgetScrollPane
    WorkbenchSearcher   → empty WidgetScrollPane
    WorkbenchEvaluator  → WidgetScrollPane wrapping projected content
    WorkbenchAssistant  → WidgetSplitPane (vertical) of conversation + input WidgetScrollPanes
    WorkbenchEditor     → WidgetScrollPane wrapping projected content

The printer also **forward-projects the workbench selection** onto the widget
tree: each `map_reference_forward` method is the structure-complete inverse of
the matching `map_reference_backward`, and `projection_print` wires the
`selection` cells of the shell, the structural split panes, and the tabbed
panes to it. That lets the widget readers route a keystroke to the child the
selection points at (split panes via `_selected_split_slot`, tabbed panes by
making the active tab follow the selection) instead of broadcasting to every
pane. See the "Forward-Projecting Selection" section of documentation/editor/selection.md.
"""
module WorkbenchToWidgetModule

import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                               map_reference_forward, map_reference_backward, Projection
import ..WorkbenchModule: WorkbenchDocument, WorkbenchWorkbench, WorkbenchPage,
                          WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
                          WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
                          WorkbenchAssistant,
                          WorkbenchEditor, title
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetShell, WidgetSplitPane, WidgetTabbedPane,
                       WidgetScrollPane, WidgetComposite, Point2D, Inset, inset_default,
                       SelectTabOperation
import ..LayoutModule: LayoutConstraint
import ..TextModule: TextText, TextString
import ..FontModule: font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default
import ..IoMapModule: SimpleIoMap, ContentIoMap, ChildrenIoMap
import ..ReactiveModule: Cell, setfn!
import ..IoMapApiModule: IoMap
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..OperationModule: ReplaceSelectionOperation
import ..OperationApiModule: Operation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..KeyboardModule: KeyDown
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, ElementReference, PositionReference, RangeReference, EmptyReferencePath, FieldReference, append_reference, skip_type_checkpoints
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"
import ..PrinterContextModule: child_context
export WorkbenchWorkbenchToWidgetShell,    WorkbenchWorkbenchToWidgetShellIoMap,
       WorkbenchPageToWidgetTabbedPane,    WorkbenchPageToWidgetTabbedPaneIoMap,
       WorkbenchNavigatorToWidgetScrollPane, WorkbenchNavigatorToWidgetScrollPaneIoMap,
       WorkbenchConsoleToWidgetScrollPane,
       WorkbenchDescriptorToWidgetScrollPane,
       WorkbenchOperatorToWidgetScrollPane,
       WorkbenchSearcherToWidgetScrollPane,
       WorkbenchEvaluatorToWidgetScrollPane,
       WorkbenchAssistantToWidgetSplitPane,
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
struct WorkbenchEditorToWidgetScrollPane    <: Projection end

# ── IoMap structs ─────────────────────────────────────────────────────────────

struct WorkbenchWorkbenchToWidgetShellIoMap <: IoMap
    projection::Any
    input::WorkbenchWorkbench
    output::WidgetShell
    navigation_page_iomap::Any   # IoMap for navigation_page
    editing_page_iomap::Any      # IoMap for editing_page
    information_page_iomap::Any  # IoMap for information_page
    control_page_iomap::Any      # IoMap for control_page
end

struct WorkbenchPageToWidgetTabbedPaneIoMap <: IoMap
    projection::Any
    input::WorkbenchPage
    output::WidgetTabbedPane
    element_iomaps::Vector       # one IoMap per page element
end

struct WorkbenchNavigatorToWidgetScrollPaneIoMap <: IoMap
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
    (recursion !== nothing && doc isa WorkbenchDocument) ? projection_printer_recurse(recursion, doc, ctx) : SimpleIoMap(nothing, doc, doc)

_title_widget(doc::WorkbenchDocument) = title(doc)

# Strip a leading `FieldReference(name)` step from a forward-projected path;
# `nothing` if it doesn't match. Used to re-root the shell's full widget-domain
# selection onto the structural split panes it builds.
function _strip_field(path, name::AbstractString)
    path = skip_type_checkpoints(path)
    path isa ConcreteReferencePath || return nothing
    (path.head isa FieldReference && path.head.name == name) || return nothing
    path.tail
end

# Strip a leading `elements[slot].child` (field, unit-range, field) from a
# split pane's selection; `nothing` if the selection doesn't enter that slot.
function _strip_split_child(path, slot::Int)
    rest = _strip_field(path, "elements")
    rest = skip_type_checkpoints(rest)
    rest isa ConcreteReferencePath || return nothing
    rest.head isa RangeReference || return nothing
    (rest.head.start + 1) == slot || return nothing
    _strip_field(rest.tail, "child")
end

# ── projection_print ──────────────────────────────────────────────────────────

function projection_print(::WorkbenchWorkbenchToWidgetShell,
                           recursion, w::WorkbenchWorkbench, ctx)
    nav_iomap  = _recurse(recursion, w.navigation_page,  child_context(ctx, @reference ^(ctx.reference).navigation_page))
    edit_iomap = _recurse(recursion, w.editing_page,     child_context(ctx, @reference ^(ctx.reference).editing_page))
    info_iomap = _recurse(recursion, w.information_page, child_context(ctx, @reference ^(ctx.reference).information_page))
    ctrl_iomap = _recurse(recursion, w.control_page,     child_context(ctx, @reference ^(ctx.reference).control_page))

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
    setfn!(getfield(main_split, :selection),
           () -> _strip_field(_shell_sel(), "content"))
    setfn!(getfield(center_split, :selection),
           () -> _strip_split_child(_strip_field(_shell_sel(), "content"), 2))

    # Track the window: the shell fills whatever extent the parent (the
    # WindowDocument's CopyingProjection) seeded on the context, falling
    # back to a sensible default when run outside a window.
    aw, ah = ctx.available_width, ctx.available_height
    shell_size = Point2D(
        Cell(() -> aw === nothing ? _SHELL_FALLBACK_WIDTH  : Int(aw[])),
        Cell(() -> ah === nothing ? _SHELL_FALLBACK_HEIGHT : Int(ah[])),
    )
    shell = WidgetShell(main_split;
                        size=shell_size)
    setfn!(getfield(shell, :selection), _shell_sel)

    iomap = WorkbenchWorkbenchToWidgetShellIoMap(nothing, w, shell,
                                                 nav_iomap, edit_iomap, info_iomap, ctrl_iomap)
    iomap_cell[] = iomap
    iomap
end

function projection_print(::WorkbenchPageToWidgetTabbedPane,
                           recursion, page::WorkbenchPage, ctx)
    element_iomaps = Any[_recurse(recursion, page.elements[i],
                             child_context(ctx, @reference ^(ctx.reference).elements[i]))
                         for i in eachindex(page.elements)]
    pairs = Any[(_title_widget(page.elements[i]), element_iomaps[i].output)
                for i in eachindex(page.elements)]
    tabbed = WidgetTabbedPane(pairs; border=_PAD5)
    iomap = WorkbenchPageToWidgetTabbedPaneIoMap(nothing, page, tabbed, element_iomaps)
    # Forward-project the page's selection onto the tabbed pane so the active
    # tab follows the document selection (and coordless events route to it).
    #
    # Forward only the *head* step (`elements[i]` → `selector_element_pairs[i]`),
    # not the deep suffix: every consumer of a tabbed pane's selection
    # (`_tab_index_from_selection`, `_route_active_tab`) reads only the tab index
    # `i`; the caret inside the active tab is carried by that tab content's own
    # forward-projected selection. Truncating to the head keeps this cell from
    # reading the deep cursor cells, so a caret move inside a tab — which (thanks
    # to the in-place `update_selection!`) mutates only the terminal cursor step,
    # leaving the page-level head step untouched — does not invalidate this cell
    # and therefore does not regenerate the tab strip or active-content wrapper
    # (incremental selection propagation).
    psel = getfield(page, :selection)
    setfn!(getfield(tabbed, :selection), () -> begin
        sel = psel[]
        sel === nothing && return nothing
        head_only = sel isa ConcreteReferencePath ?
            ConcreteReferencePath(sel.head, EmptyReferencePath()) : sel
        map_reference_forward(WorkbenchPageToWidgetTabbedPane(), iomap, head_only)
    end)
    iomap
end

function projection_print(::WorkbenchNavigatorToWidgetScrollPane,
                           recursion, nav::WorkbenchNavigator, ctx)
    scroll = WidgetScrollPane(nav.workspace;
                              padding=_PAD5, padding_color=_WHITE)
    WorkbenchNavigatorToWidgetScrollPaneIoMap(nothing, nav, scroll, Any[])
end

function projection_print(::WorkbenchConsoleToWidgetScrollPane,
                           recursion, c::WorkbenchConsole, ctx)
    content_iomap = _recurse(recursion, c.content, child_context(ctx, @reference ^(ctx.reference).content))
    scroll = WidgetScrollPane(content_iomap.output;
                              padding=_PAD5, padding_color=_WHITE)
    ContentIoMap(nothing, c, scroll, content_iomap)
end

function projection_print(::WorkbenchDescriptorToWidgetScrollPane,
                           recursion, d::WorkbenchDescriptor, ctx)
    text = TextText(
        TextString(() -> string(d.content),
                   font_ubuntu_monospace_regular_24, color_default),
    )
    scroll = WidgetScrollPane(text;
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, d, scroll)
end

function projection_print(::WorkbenchOperatorToWidgetScrollPane,
                           recursion, o::WorkbenchOperator, ctx)
    scroll = WidgetScrollPane(nothing;
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, o, scroll)
end

function projection_print(::WorkbenchSearcherToWidgetScrollPane,
                           recursion, s::WorkbenchSearcher, ctx)
    scroll = WidgetScrollPane(nothing;
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, s, scroll)
end

function projection_print(::WorkbenchEvaluatorToWidgetScrollPane,
                           recursion, e::WorkbenchEvaluator, ctx)
    content_iomap = _recurse(recursion, e.content, child_context(ctx, @reference ^(ctx.reference).content))
    scroll = WidgetScrollPane(content_iomap.output;
                              padding=_PAD5, padding_color=_WHITE)
    ContentIoMap(nothing, e, scroll, content_iomap)
end

function projection_print(::WorkbenchAssistantToWidgetSplitPane,
                           recursion, a::WorkbenchAssistant, ctx)
    # Both children are WidgetScrollPanes whose `content` is the underlying
    # document. `WidgetScrollPaneToGraphicsCanvas.projection_print` calls
    # `projection_printer_recurse(recursion, content, …)` directly, so the outer
    # TypeDispatchingProjection routes `ConversationDocument` to
    # `ConversationToWidget` and `PrimitiveDocument` (the input) to the
    # Primitive→Syntax→Text→Graphics chain. This is also what makes the
    # `PrimitiveStringToSyntaxLeaf` reader receive `KeyPress` events.
    conv_pane  = WidgetScrollPane(a.conversation;
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

function projection_print(::WorkbenchEditorToWidgetScrollPane,
                           recursion, e::WorkbenchEditor, ctx)
    content_iomap = _recurse(recursion, e.content, child_context(ctx, @reference ^(ctx.reference).content))
    scroll = WidgetScrollPane(content_iomap.output;
                              padding=_PAD5, padding_color=_WHITE)
    ContentIoMap(nothing, e, scroll, content_iomap)
end

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
# `[i]` is `RangeReference(i-1, i)`, the same shape the backward side
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
# nested `elements[1|2].child`. `something(_, EmptyReferencePath())` keeps a
# selection that points only at a page (no deeper suffix) routable.
function map_reference_forward(::WorkbenchWorkbenchToWidgetShell,
                                iomap::WorkbenchWorkbenchToWidgetShellIoMap,
                                reference)
    @reference_case reference begin
        navigation_page.rest... => begin
            inner = something(_page_forward(iomap.navigation_page_iomap, rest), EmptyReferencePath())
            @reference content.elements[1].child.^(inner)
        end
        editing_page.rest... => begin
            inner = something(_page_forward(iomap.editing_page_iomap, rest), EmptyReferencePath())
            @reference content.elements[2].child.elements[1].child.^(inner)
        end
        information_page.rest... => begin
            inner = something(_page_forward(iomap.information_page_iomap, rest), EmptyReferencePath())
            @reference content.elements[2].child.elements[2].child.^(inner)
        end
        control_page.rest... => begin
            inner = something(_page_forward(iomap.control_page_iomap, rest), EmptyReferencePath())
            @reference content.elements[3].child.^(inner)
        end
    end
end

# WorkbenchPage → WidgetTabbedPane: `elements[i]` ↔ `selector_element_pairs[i]`.
function map_reference_forward(::WorkbenchPageToWidgetTabbedPane,
                                iomap::WorkbenchPageToWidgetTabbedPaneIoMap,
                                reference)
    @reference_case reference begin
        elements[i].rest... => begin
            (1 <= i <= length(iomap.element_iomaps)) || return nothing
            inner = something(_panel_forward(iomap.element_iomaps[i], rest), EmptyReferencePath())
            @reference selector_element_pairs[i].^(inner)
        end
    end
end

# Each panel renames its workbench field to the widget scroll pane's `content`
# (the wrapped content document is opaque to this projection, so its own
# selection suffix passes straight through).
function map_reference_forward(::WorkbenchEditorToWidgetScrollPane, iomap::ContentIoMap, reference)
    @reference_case reference begin
        content.rest... => @reference content.^(rest)
    end
end

function map_reference_forward(::WorkbenchNavigatorToWidgetScrollPane,
                                iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap, reference)
    @reference_case reference begin
        workspace.rest... => @reference content.^(rest)
    end
end

function map_reference_forward(::WorkbenchConsoleToWidgetScrollPane, iomap::ContentIoMap, reference)
    @reference_case reference begin
        content.rest... => @reference content.^(rest)
    end
end

function map_reference_forward(::WorkbenchEvaluatorToWidgetScrollPane, iomap::ContentIoMap, reference)
    @reference_case reference begin
        content.rest... => @reference content.^(rest)
    end
end

# Assistant → vertical WidgetSplitPane(conversation | input), each a scroll pane.
function map_reference_forward(::WorkbenchAssistantToWidgetSplitPane, iomap, reference)
    @reference_case reference begin
        conversation.rest... => @reference elements[1].child.content.^(rest)
        input.rest...        => @reference elements[2].child.content.^(rest)
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
# workbench field name. The default `projection_read` consults these
# functions to translate `ReplaceSelectionOperation`, and custom
# `projection_read` overrides below extend the same translation to
# `StringReplaceRangeOperation` / `NumberReplaceRangeOperation`.

function map_reference_backward(::WorkbenchEditorToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    @reference_case reference begin
        content.rest... => @reference content.^(rest)
    end
end

function map_reference_backward(::WorkbenchNavigatorToWidgetScrollPane,
                                 iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap,
                                 reference)
    # WorkbenchNavigator stores the workspace in `.workspace`; the widget
    # scroll pane wraps it as `.content`. Rewrite the field name.
    @reference_case reference begin
        content.rest... => @reference workspace.^(rest)
    end
end

function map_reference_backward(::WorkbenchConsoleToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    @reference_case reference begin
        content.rest... => @reference content.^(rest)
    end
end

function map_reference_backward(::WorkbenchEvaluatorToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    @reference_case reference begin
        content.rest... => @reference content.^(rest)
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
        elements{s:e}.child.content.rest... => begin
            i = s + 1
            if i == 1
                @reference conversation.^(rest)
            elseif i == 2
                @reference input.^(rest)
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
        selector_element_pairs{s:e}.rest... => begin
            i = s + 1
            i <= length(iomap.element_iomaps) || return nothing
            elem_im = iomap.element_iomaps[i]
            inner = _panel_backward(elem_im, rest)
            inner === nothing && return nothing
            @reference elements[i].^(inner)
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
        content.elements{0:1}.child.rest... => begin
            inner = _page_backward(iomap.navigation_page_iomap, rest)
            inner === nothing && return nothing
            @reference navigation_page.^(inner)
        end
        content.elements{1:2}.child.elements{0:1}.child.rest... => begin
            inner = _page_backward(iomap.editing_page_iomap, rest)
            inner === nothing && return nothing
            @reference editing_page.^(inner)
        end
        content.elements{1:2}.child.elements{1:2}.child.rest... => begin
            inner = _page_backward(iomap.information_page_iomap, rest)
            inner === nothing && return nothing
            @reference information_page.^(inner)
        end
        content.elements{2:3}.child.rest... => begin
            inner = _page_backward(iomap.control_page_iomap, rest)
            inner === nothing && return nothing
            @reference control_page.^(inner)
        end
    end
end

_page_backward(page_iomap::WorkbenchPageToWidgetTabbedPaneIoMap, rest) =
    map_reference_backward(WorkbenchPageToWidgetTabbedPane(), page_iomap, rest)
_page_backward(_, _) = nothing

# ── projection_read ───────────────────────────────────────────────────────────

function projection_read(p::WorkbenchWorkbenchToWidgetShell,
                          iomap::WorkbenchWorkbenchToWidgetShellIoMap, op)
    # 1. Tab-strip click: a SelectTabOperation produced by the widget
    # tabbed pane. Find which page owns the tab strip (by matching
    # `op.widget` against each page's output) and convert via the page
    # reader, then re-root under that page's workbench field name.
    if op isa SelectTabOperation
        for (field_name, page_iomap) in (("navigation_page",  iomap.navigation_page_iomap),
                                          ("editing_page",     iomap.editing_page_iomap),
                                          ("information_page", iomap.information_page_iomap),
                                          ("control_page",     iomap.control_page_iomap))
            page_iomap isa WorkbenchPageToWidgetTabbedPaneIoMap || continue
            result = projection_read(WorkbenchPageToWidgetTabbedPane(), page_iomap, op)
            result isa ReplaceSelectionOperation || continue
            return ReplaceSelectionOperation(
                ConcreteReferencePath(FieldReference(field_name), result.path))
        end
        return nothing
    end
    # 2. Path-bearing op from a deeper reader: translate its widget-domain
    # reference into workbench-domain via `map_reference_backward`.
    if op isa ReplaceSelectionOperation
        new_path = map_reference_backward(p, iomap, op.path)
        return new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    end
    if op isa StringReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : StringReplaceRangeOperation(new_ref, op.replacement)
    end
    if op isa NumberReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : NumberReplaceRangeOperation(new_ref, op.replacement)
    end
    # 3. Other operation types (e.g. ScrollWidgetOperation) target widgets
    # directly, not paths — pass through.
    op isa Operation && return op
    # 4. Raw events (KeyPress / KeyDown). Route them through each panel's
    # reader so focus-sensitive handlers (currently only the assistant) can
    # pick them up. Path-bearing results get re-rooted via the panel's
    # location so `evaluate_operation` can walk the path against the
    # workbench root.
    wb2w = WorkbenchToWidget()
    for (field_name, page_iomap) in (("navigation_page",  iomap.navigation_page_iomap),
                                      ("editing_page",     iomap.editing_page_iomap),
                                      ("information_page", iomap.information_page_iomap),
                                      ("control_page",     iomap.control_page_iomap))
        page_iomap isa WorkbenchPageToWidgetTabbedPaneIoMap || continue
        for (elem_idx, elem_iomap) in enumerate(page_iomap.element_iomaps)
            result = projection_read(wb2w, elem_iomap, op)
            result isa Operation || continue
            prefix = (FieldReference(field_name),
                      FieldReference("elements"),
                      RangeReference(elem_idx - 1, elem_idx))
            return _prefix_operation(result, prefix)
        end
    end
    return nothing
end

# Prepend `prefix_steps` to the path inside `op`, if the op carries a path.
# Operations that target a captured Julia value (e.g. SubmitProseOperation
# holds its WorkbenchAssistant directly) need no prefixing.
function _prefix_operation(op, prefix_steps::Tuple)
    if op isa StringReplaceRangeOperation
        return StringReplaceRangeOperation(_prepend_path(prefix_steps, op.reference),
                                           op.replacement)
    elseif op isa NumberReplaceRangeOperation
        return NumberReplaceRangeOperation(_prepend_path(prefix_steps, op.reference),
                                           op.replacement)
    elseif op isa ReplaceSelectionOperation
        return ReplaceSelectionOperation(_prepend_path(prefix_steps, op.path))
    else
        return op
    end
end

function _prepend_path(steps::Tuple, path::ReferencePath)
    result = path
    for step in reverse(steps)
        result = ConcreteReferencePath(step, result)
    end
    result
end

function projection_read(p::WorkbenchPageToWidgetTabbedPane,
                          iomap::WorkbenchPageToWidgetTabbedPaneIoMap, op)
    # Convert a tab-strip click into a workbench-domain selection move.
    if op isa SelectTabOperation
        op.widget === iomap.output || return op
        idx = op.tab_index
        1 <= idx <= length(iomap.input.elements) || return op
        # The tabbed pane's active tab is a forward projection of the page
        # selection (see projection_print), so moving the document selection
        # to this element is enough — no imperative write to the widget cell.
        return ReplaceSelectionOperation(@reference elements[idx])
    end
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchNavigatorToWidgetScrollPane,
                          iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchConsoleToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchDescriptorToWidgetScrollPane, iomap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchOperatorToWidgetScrollPane, iomap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchSearcherToWidgetScrollPane, iomap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchEvaluatorToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchAssistantToWidgetSplitPane,
                          iomap, op)
    # The specific KeyPress / KeyDown handlers live in
    # `WorkbenchAssistantModule` (loaded later in the include chain) and
    # take precedence via multiple dispatch. For everything else that
    # reaches us, translate path-bearing ops to the assistant's input
    # domain and let widget-target ops (e.g. ScrollWidgetOperation) pass
    # through; unhandled raw events return `nothing`.
    if op isa Operation
        return _retarget_panel_op(p, iomap, op)
    end
    nothing
end

function projection_read(p::WorkbenchEditorToWidgetScrollPane,
                          iomap::ContentIoMap, op)
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
    elseif op isa StringReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : StringReplaceRangeOperation(new_ref, op.replacement)
    elseif op isa NumberReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : NumberReplaceRangeOperation(new_ref, op.replacement)
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
