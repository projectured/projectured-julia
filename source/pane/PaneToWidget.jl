"""
    PaneToWidgetModule

PaneDocument → WidgetDocument. The layout tree becomes split panes and tabbed
panes:

    PaneTree  → the widget of its root (transparent)
    PaneSplit → WidgetSplitPane, one slot per element
    PaneGroup → WidgetTabbedPane, one tab per tab

**The two orientation vocabularies meet here.** A `:vertical` `PaneSplit` — one
with a vertical divider, so its children sit side by side — prints a
`WidgetSplitPane(:horizontal, …)`, because the widget's symbol names the axis its
children lay out along. `pane_split_axis` is the translation, and this module is
the only place that applies it.

**Weights become layout weights.** Each slot is wrapped in a `LayoutConstraint`
whose weight on the split axis is the element's share. Where the parent seeded an
available extent the slot also takes a preferred extent of 0, so the allocator
hands out the whole extent in proportion to the weights and nothing else. Where
it did not — an unconstrained print, which has no total to divide — the slots
fall back to their intrinsic sizes.

**The selection is forwarded** onto both widgets, so a tabbed pane shows the tab
the pane tree's selection names and a split pane routes a keystroke to the slot
it names. Only the *routing prefix* is forwarded, not the deep suffix: every
consumer reads the index alone, and forwarding less keeps a caret move inside a
tab from regenerating the strip.
"""
module PaneToWidgetModule

import ..ProjectionApiModule: print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..PaneModule: PaneDocument, PaneTree, PaneSplit, PaneGroup, PaneTab,
                     pane_split_axis, pane_weights, pane_normalized_weights,
                     pane_tab_title_string, default_new_pane_tab
import ..PaneSurgeryModule: pane_focus_operation, pane_open_tab_operation,
                            pane_close_tab_operation, pane_resize_operation,
                            pane_move_tab_operation, pane_drop_split_operation,
                            pane_focus, pane_shown_tab_index
import ..PaneGeometryModule: pane_drop_zone, pane_zone_orientation, pane_rectangle
import ..IntentModule: Intent
import ..EventModule: MouseMove, MouseUp, MousePress
import ..OperationModule: CompoundOperation, ReplaceReferencedValueOperation
import ..WidgetModule: SelectTabOperation, CloseTabRequestOperation,
                       NewTabRequestOperation, DragTabOperation,
                       StartSplitterDragOperation, ResizeSplitPaneOperation,
                       EndSplitterDragOperation
import ..WidgetModule: WidgetDocument, WidgetSplitPane, WidgetTabbedPane,
                       WidgetScrollPane, WidgetComposite, WidgetHighlight,
                       Inset, Point2D
import ..LayoutModule: LayoutConstraint
import ..IoMapModule: IoMap, SimpleIoMap, var"@iomap",
                      reconcile_child_iomap, reconcile_child_iomaps
import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..DocumentModule: SelectionDocument
import ..CollectionModule: CellVector
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ReferenceModule: Reference, ConcreteReference, EmptyReference,
                          FieldReferenceStep, RangeReferenceStep, ElementReferenceStep,
                          get_reference_node_type
import ..ReferenceBuilderModule: var"@reference", var"@reference_step"
import ..ReferenceCaseModule: var"@reference_case"
import ..PrinterContextModule: make_child_context

export PaneTreeToWidget, PaneTreeToWidgetIoMap,
       PaneSplitToWidgetSplitPane, PaneSplitToWidgetSplitPaneIoMap,
       PaneGroupToWidgetTabbedPane, PaneGroupToWidgetTabbedPaneIoMap,
       PaneToWidget

# ── Projection structs ─────────────────────────────────────────────────────

"""
    PaneTreeToWidget([new_tab])

The pane tree's own projection. `new_tab` is the thunk the new-tab button calls
to build a tab; pass one to decide what an empty tab holds in your application.
"""
struct PaneTreeToWidget <: Projection
    new_tab::Any
end

PaneTreeToWidget() = PaneTreeToWidget(default_new_pane_tab)
struct PaneSplitToWidgetSplitPane <: Projection end
struct PaneGroupToWidgetTabbedPane <: Projection end

# ── IoMap structs ──────────────────────────────────────────────────────────

@iomap struct PaneTreeToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    root_iomap::Any            # reconciling cell: the root node's IoMap
    available::Any             # (width, height) cells, or nothing — what a drag
                               # resolves the pointer against
end

@iomap struct PaneSplitToWidgetSplitPaneIoMap
    projection::Any
    input::Any
    output::Any
    element_iomaps::Any        # reconciling cell: one IoMap per element
end

@iomap struct PaneGroupToWidgetTabbedPaneIoMap
    projection::Any
    input::Any
    output::Any
    content_iomaps::Any        # reconciling cell: one IoMap per tab content
end

# ── Helpers ────────────────────────────────────────────────────────────────

const _PANE_BORDER = Inset(4, 4, 4, 4)
const _PANE_PADDING = Inset(4, 4, 4, 4)

# What a selection cell holds, past the live/dormant wrapper.
_get_stored_selection_value(value) = value
_get_stored_selection_value(value::SelectionDocument) = value.primary

# The junction type. A tab's content passes through this projection untouched, and
# the mapper that handed it back names the step but not the node it descends from
# — that node is the content document, which only this projection knows. Fill it
# in here, so the path is typed all the way down and `@reference` accepts it.
_typed_head(reference::ConcreteReference, document) =
    reference.type === nothing ?
        ConcreteReference(get_reference_node_type(document), reference.head, reference.tail) :
        reference
_typed_head(reference, ::Any) = reference

# The tail after a scroll pane's own `content` step, or `nothing`.
function _after_content_step(reference)
    reference isa ConcreteReference || return nothing
    head = reference.head
    (head isa FieldReferenceStep && head.name == "content") || return nothing
    reference.tail
end

# A tab's content belongs to a foreign domain, so it is not this projection's to
# print: it passes through unchanged and the renderer below reads it. Only pane
# nodes recurse. Mirrors the workbench's `_recurse`.
_recurse(recursion, document, ctx) =
    (recursion !== nothing && document isa PaneDocument) ?
        print_child(recursion, document, ctx) : SimpleIoMap(nothing, document, document)

# The forward image of a reference through a child IoMap, empty when the child
# says nothing. A pass-through IoMap (`projection === nothing`) carries a foreign
# document, whose own reference vocabulary the widget tree keeps unchanged.
function _child_forward(child_iomap, reference)
    child_iomap.projection === nothing && return reference
    image = map_reference_forward(child_iomap.projection, child_iomap, reference)
    # A typed terminal, because `@reference` refuses an under-typed path: the
    # child said nothing, so the image ends on the widget the child printed.
    image === nothing ? EmptyReference(WidgetDocument) : image
end

function _child_backward(child_iomap, reference)
    child_iomap.projection === nothing && return reference
    map_reference_backward(child_iomap.projection, child_iomap, reference)
end

# The routing prefix of a selection: the field step and the index step, with any
# deeper suffix dropped. Two nodes, not one — with the node types folded in,
# `elements` and `[i]` are separate path nodes, and truncating to the head alone
# would drop the index the routing needs.
function _index_prefix(selection)
    selection isa ConcreteReference || return selection
    tail = selection.tail
    if tail isa ConcreteReference && tail.head isa RangeReferenceStep
        return ConcreteReference(selection.type, selection.head,
                   ConcreteReference(tail.type, tail.head, EmptyReference(tail.tail.type)))
    end
    ConcreteReference(selection.type, selection.head, EmptyReference())
end

# Wire a widget's selection cell to the forward image of `source`'s selection.
function _forward_selection!(widget, source, projection, iomap)
    source_selection = getfield(source, :selection)
    set_cell_function!(getfield(widget, :selection), () -> begin
        # The stored path, live or dormant: a group that lost the focus still shows
        # the tab it was showing, so its widget image must name that tab.
        selection = _get_stored_selection_value(source_selection[])
        selection === nothing && return nothing
        map_reference_forward(projection, iomap, _index_prefix(selection))
    end)
end

# ── PaneTree ───────────────────────────────────────────────────────────────

# The tree is transparent: it prints as its root, and adds one field step to the
# paths that pass through it.
function print_document(p::PaneTreeToWidget, recursion, tree::PaneTree, ctx)
    root_iomap = reconcile_child_iomap(
        () -> tree.root,
        root -> _recurse(recursion, root,
                         make_child_context(ctx, tree, (@reference_step root))))
    available = (ctx.available_width === nothing || ctx.available_height === nothing) ?
                nothing : (ctx.available_width, ctx.available_height)

    # The layout, and one layer over it. A `WidgetComposite` is what can carry the
    # overlay: it hands each child the extent it was given itself, so the panes
    # still divide the whole window, and it places each child at its own position,
    # so the indicator can sit anywhere over them. (A `StackLayout` clears the
    # available size for its children, which would collapse the split panes to
    # their intrinsic sizes.)
    indicator = _drop_indicator(tree, available)
    composite = WidgetComposite(Point2D(0, 0), Any[])
    set_cell_function!(getfield(composite.elements, :elements),
                       () -> Cell[Cell(root_iomap[].output), Cell(indicator)])
    # The pane layer is slot 1, always. The indicator never takes a keystroke, so
    # a constant selection is the whole of what the composite's coordless routing
    # needs — the pane widget routes on from there by its own.
    getfield(composite, :selection)[] =
        @reference ::WidgetComposite.elements::CellVector[1]::WidgetDocument

    PaneTreeToWidgetIoMap(p, tree, composite, root_iomap, available)
end

# ── The drop indicator ─────────────────────────────────────────────────────
#
# While a tab is held, one muted rectangle shows where it would land: the whole
# of the target group for a drop that moves the tab into it, and the half a new
# pane would take for a drop on an edge band. It is a single widget whose cells
# read the drag, so showing and moving it costs no re-print — and it is always in
# the tree, just invisible, so the widget tree keeps its shape.
function _drop_indicator(tree::PaneTree, available)
    indicator = WidgetHighlight(Point2D(0, 0); visible = false)
    rectangle() = _drop_indicator_rectangle(tree, available)
    set_cell_function!(getfield(indicator, :position), () -> begin
        r = rectangle()
        r === nothing ? Point2D(0, 0) : Point2D(r[1], r[2])
    end)
    set_cell_function!(getfield(indicator, :width),
                       () -> (r = rectangle(); r === nothing ? 0 : r[3]))
    set_cell_function!(getfield(indicator, :height),
                       () -> (r = rectangle(); r === nothing ? 0 : r[4]))
    set_cell_function!(getfield(indicator, :visible), () -> rectangle() !== nothing)
    indicator
end

# The pixel rectangle the indicator marks, or `nothing` when no drag is over a
# group. An edge band shows the half the new pane would take; the strip and the
# middle show the whole group, because that is where the tab would go.
function _drop_indicator_rectangle(tree::PaneTree, available)
    available === nothing && return nothing
    state = getfield(tree, :drag)[]
    state === nothing && return nothing
    target = state.target
    target === nothing && return nothing
    r = pane_rectangle(tree, target)
    r === nothing && return nothing
    width, height = Int(available[1][]), Int(available[2][])
    (width <= 0 || height <= 0) && return nothing
    x, y, w, h = state.zone === :left  ? (r.x,             r.y,             r.w / 2, r.h) :
                 state.zone === :right ? (r.x + r.w / 2,   r.y,             r.w / 2, r.h) :
                 state.zone === :above ? (r.x,             r.y,             r.w,     r.h / 2) :
                 state.zone === :below ? (r.x,             r.y + r.h / 2,   r.w,     r.h / 2) :
                                         (r.x,             r.y,             r.w,     r.h)
    (round(Int, x * width), round(Int, y * height),
     round(Int, w * width), round(Int, h * height))
end

# The layout sits in slot 1 of the overlay composite, so every path through this
# projection gains that hop.
function map_reference_forward(::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap, reference)
    @reference_case reference begin
        ::PaneTree.root.rest... => begin
            inner = _child_forward(iomap.root_iomap, rest)
            @reference ::WidgetComposite.elements::CellVector[1].^(inner)
        end
    end
end

function map_reference_backward(::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap, reference)
    @reference_case reference begin
        ::WidgetComposite.elements{s:e}.rest... => begin
            s == 0 || return nothing        # slot 2 is the indicator: nothing to map
            inner = _child_backward(iomap.root_iomap, rest)
            inner === nothing && return nothing
            @reference ::PaneTree.root.^(inner)
        end
    end
end

# ── PaneSplit ──────────────────────────────────────────────────────────────

function print_document(p::PaneSplitToWidgetSplitPane, recursion, split::PaneSplit, ctx)
    element_iomaps = reconcile_child_iomaps(
        () -> split.elements,
        (i, element) -> _recurse(recursion, element,
            make_child_context(ctx, split, (@reference_step elements), (@reference_step [i]))))

    axis = pane_split_axis(split)
    # `axis` is what the widget calls its orientation: a vertical split lays its
    # children out horizontally.
    horizontal = axis === :horizontal
    available = horizontal ? ctx.available_width : ctx.available_height
    # With an allocation to divide, a slot prefers nothing of its own and takes
    # its weighted share of the whole. Without one there is no total to divide,
    # so the slots keep their intrinsic sizes.
    preferred = available === nothing ? nothing : 0

    pane = WidgetSplitPane(axis, Any[]; border = _PANE_BORDER)
    set_cell_function!(pane, () -> begin
        iomaps = element_iomaps[]
        weights = pane_normalized_weights(pane_weights(split))
        Any[_constrain(iomaps[i].output, horizontal,
                       i <= length(weights) ? weights[i] : 1.0, preferred)
            for i in eachindex(iomaps)]
    end)

    iomap = PaneSplitToWidgetSplitPaneIoMap(p, split, pane, element_iomaps)
    _forward_selection!(pane, split, p, iomap)
    iomap
end

_constrain(child, horizontal::Bool, weight::Float64, preferred) =
    horizontal ? LayoutConstraint(child; weight_width = weight, preferred_width = preferred) :
                 LayoutConstraint(child; weight_height = weight, preferred_height = preferred)

function map_reference_forward(::PaneSplitToWidgetSplitPane,
                               iomap::PaneSplitToWidgetSplitPaneIoMap, reference)
    @reference_case reference begin
        ::PaneSplit.elements[i].rest... => begin
            iomaps = iomap.element_iomaps
            (1 <= i <= length(iomaps)) || return nothing
            inner = _child_forward(iomaps[i], rest)
            @reference ::WidgetSplitPane.elements::CellVector[i]::LayoutConstraint.child.^(inner)
        end
    end
end

function map_reference_backward(::PaneSplitToWidgetSplitPane,
                                iomap::PaneSplitToWidgetSplitPaneIoMap, reference)
    # Each slot is wrapped in a `LayoutConstraint`, so the split pane's reader
    # prepends `elements[i].child` to whatever the slot answered.
    @reference_case reference begin
        ::WidgetSplitPane.elements{s:e}.child.rest... => begin
            i = s + 1
            iomaps = iomap.element_iomaps
            i <= length(iomaps) || return nothing
            inner = _child_backward(iomaps[i], rest)
            inner === nothing && return nothing
            @reference ::PaneSplit.elements::CellVector[i].^(inner)
        end
    end
end

# ── PaneGroup ──────────────────────────────────────────────────────────────

function print_document(p::PaneGroupToWidgetTabbedPane, recursion, group::PaneGroup, ctx)
    # One entry per tab: the content's IoMap, and the scroll pane that holds it.
    # **The scroll pane is what keeps a tab inside its own pane** — a content
    # document is drawn as wide as it is, so without a viewport to clip it the
    # text of one pane runs straight across the next. It is built here, beside the
    # IoMap, so it keeps its identity — and its scroll offset — for as long as the
    # tab lives.
    content_iomaps = reconcile_child_iomaps(
        () -> Any[tab.content for tab in group.tabs],
        (i, content) -> begin
            child = _recurse(recursion, content,
                make_child_context(ctx, group, (@reference_step tabs), (@reference_step [i]),
                                   (@reference_step content)))
            (iomap = child, pane = WidgetScrollPane(child.output; padding = _PANE_PADDING))
        end)

    # Every group offers the whole vocabulary: close a tab, open one, grab one.
    pane = WidgetTabbedPane(Any[]; closable = true, new_tab = true, draggable = true,
                            border = _PANE_BORDER)
    set_cell_function!(pane, () -> begin
        entries = content_iomaps[]
        tabs = group.tabs
        Any[(pane_tab_title_string(tabs[i]), entries[i].pane) for i in eachindex(entries)]
    end)

    iomap = PaneGroupToWidgetTabbedPaneIoMap(p, group, pane, content_iomaps)
    _forward_selection!(pane, group, p, iomap)
    iomap
end

function map_reference_forward(::PaneGroupToWidgetTabbedPane,
                               iomap::PaneGroupToWidgetTabbedPaneIoMap, reference)
    @reference_case reference begin
        ::PaneGroup.tabs[i].rest... => begin
            entries = iomap.content_iomaps
            (1 <= i <= length(entries)) || return nothing
            inner = _tab_forward(entries[i].iomap, rest)
            inner isa EmptyReference &&
                return @reference ::WidgetTabbedPane.selector_element_pairs::CellVector[i]::WidgetScrollPane
            @reference ::WidgetTabbedPane.selector_element_pairs::CellVector[i]::WidgetScrollPane.content.^(inner)
        end
    end
end

# The widget image of a selection inside a tab. Only the content has one: a
# selection that names the tab whole, or its title, has no image of its own — the
# strip draws the title as text, not as a widget.
function _tab_forward(content_iomap, rest)
    image = @reference_case rest begin
        ::PaneTab.content.inner... => _child_forward(content_iomap, inner)
    end
    image === nothing ? EmptyReference(WidgetDocument) : image
end

function map_reference_backward(::PaneGroupToWidgetTabbedPane,
                                iomap::PaneGroupToWidgetTabbedPaneIoMap, reference)
    @reference_case reference begin
        ::WidgetTabbedPane.selector_element_pairs{s:e}.rest... => begin
            i = s + 1
            entries = iomap.content_iomaps
            i <= length(entries) || return nothing
            # A bare `selector_element_pairs[i]` is a tab-strip click: it names
            # the tab, not anything inside it. Anything deeper comes through the
            # scroll pane that holds the tab's content.
            rest isa EmptyReference &&
                return @reference ::PaneGroup.tabs::CellVector[i]::PaneTab
            content = _after_content_step(rest)
            content === nothing && return @reference ::PaneGroup.tabs::CellVector[i]::PaneTab
            inner = _child_backward(entries[i].iomap, content)
            inner === nothing && return nothing
            @reference ::PaneGroup.tabs::CellVector[i]::PaneTab.content.^(_typed_head(inner, entries[i].iomap.input))
        end
    end
end

# ── The reader ─────────────────────────────────────────────────────────────
#
# Everything the strip and the splitter *report* is answered here, at the tree,
# for one reason: an edit needs the whole tree to name its target, and the tree
# projection is the only one that holds it. Each report carries the widget it came
# from, so the answer starts by finding the pane node that printed that widget.
#
# Every other payload — a reference-carrying operation, or a raw gesture — falls
# through to the generic reader, which re-targets references through
# `map_reference_backward` and hands a raw gesture to the tree's own
# `@gestures` table.
#
# **One method per report**, rather than one method that takes any payload and
# forwards the rest. Each names the operation it answers, so what this projection
# claims is the list below and nothing else — every other payload, a text edit or
# a raw gesture included, reaches the generic reader by ordinary dispatch.

# A tab click arrives as a ReplaceSelectionOperation now, which the generic
# reader re-targets through `map_reference_backward` — its bare
# `selector_element_pairs[i]` case answers `tabs[i]::PaneTab`, the same path
# `pane_focus_operation` used to build. No method of our own is needed.

function read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap,
                     operation::CloseTabRequestOperation)
    group = _pane_node_for(iomap, operation.widget)
    group isa PaneGroup || return nothing
    pane_close_tab_operation(iomap.input, group, operation.tab_index)
end

function read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap,
                     operation::NewTabRequestOperation)
    group = _pane_node_for(iomap, operation.widget)
    group isa PaneGroup || return nothing
    pane_open_tab_operation(iomap.input, group, p.new_tab())
end

function read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap,
                     operation::DragTabOperation)
    group = _pane_node_for(iomap, operation.widget)
    group isa PaneGroup || return nothing
    (1 <= operation.tab_index <= length(group.tabs)) || return nothing
    _drag_write(iomap.input, (group = group, index = operation.tab_index,
                              target = nothing, zone = :none))
end

read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap,
            operation::ResizeSplitPaneOperation) =
    _read_resize(iomap.input, iomap, operation)

# The two ends of a splitter drag are the widget's own transient state — which
# splitter is held, and where it was grabbed. They carry the split pane itself, so
# the pane layer has nothing to add, and dropping them would leave the drag unable
# to start at all.
#
# The grab does need one thing: **its measurements cleared first**. The widget
# anchors a drag on its `sizes`, and materializes them only when they are empty —
# but this projection answers every resize with a *weight* write and never lets
# `sizes` be written, so they still hold what was measured at the first grab. A
# second drag would anchor on those, and the splitter would jump back to where the
# first one started. Clearing them makes the widget re-measure what is on screen.
read_intent(::PaneTreeToWidget, ::PaneTreeToWidgetIoMap,
            operation::StartSplitterDragOperation) =
    CompoundOperation(Any[
        ReplaceReferencedValueOperation(operation.split, "sizes", CellVector()),
        operation])
read_intent(::PaneTreeToWidget, ::PaneTreeToWidgetIoMap,
            operation::EndSplitterDragOperation) = operation

# A drag is a *gesture* state machine, so it needs the raw gesture even when the
# layers below already turned it into an operation — a `MouseMove` over a button
# becomes a hover write, and the drag would never see the pointer. The four-arg
# reader is where both are in hand. Everything outside a drag reads exactly as
# the generic bridge does.
function read_intent(p::PaneTreeToWidget, recursion, change::Intent,
                     iomap::PaneTreeToWidgetIoMap)
    tree = iomap.input
    if getfield(tree, :drag)[] !== nothing
        answer = _drag_step(p, iomap, change.gesture)
        answer === nothing || return Intent(change.gesture, answer)
    end
    payload = change.operation === nothing ? change.gesture : change.operation
    answer = read_intent(p, iomap, payload)
    # A press that nothing claimed still says which pane the user pointed at. A
    # pane is mostly empty space — its content is a document that ends where its
    # text ends — so without this a click beside the text would focus nothing.
    answer === nothing && change.gesture isa MousePress &&
        (answer = _focus_from_press(iomap, change.gesture))
    Intent(change.gesture, answer)
end

function _focus_from_press(iomap::PaneTreeToWidgetIoMap, press)
    landing = _drop_target(iomap, press.x, press.y)
    landing === nothing && return nothing
    group = landing[1]
    tree = iomap.input
    focus = pane_focus(tree)
    (focus !== nothing && focus[1] === group) && return nothing
    pane_focus_operation(tree, group, pane_shown_tab_index(group))
end

# ── The drag ───────────────────────────────────────────────────────────────
#
# `PaneTree.drag` holds `(group, index, target, zone)` while a tab is held: where
# it came from, and where it would land. It is transient state on the tree, so
# each write carries the tree itself and re-roots nowhere.
#
# The pointer is resolved against the **layout tree**, not against the printed
# canvas: the groups divide the available extent in proportion to their weights,
# so the unit-square rectangle of a group *is* where it is drawn. The tab strip
# is the one part that has a fixed height rather than a share, so its band is
# converted from pixels here.

const _PANE_STRIP_PIXELS = 32

_drag_write(tree, state) = ReplaceReferencedValueOperation(tree, "drag", state)

function _drag_step(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap, gesture)
    tree = iomap.input
    state = getfield(tree, :drag)[]
    if gesture isa MouseMove
        landing = _drop_target(iomap, gesture.x, gesture.y)
        target, zone = landing === nothing ? (nothing, :none) : landing
        # Only write when the target moved, so a drag across a pane is not one
        # write per pixel.
        (state.target === target && state.zone === zone) && return nothing
        return _drag_write(tree, (group = state.group, index = state.index,
                                  target = target, zone = zone))
    elseif gesture isa MouseUp
        drop = _drop_operation(tree, state)
        clear = _drag_write(tree, nothing)
        return drop === nothing ? clear : CompoundOperation(Any[drop, clear])
    end
    nothing
end

function _drop_operation(tree::PaneTree, state)
    target = state.target
    target === nothing && return nothing
    source, index, zone = state.group, state.index, state.zone
    orientation = pane_zone_orientation(zone)
    if orientation === nothing
        # The strip or the middle: the tab moves into the group, at its end.
        source === target && return nothing
        return pane_move_tab_operation(tree, source, index, target,
                                       length(target.tabs) + 1)
    end
    # The zone names the side the new pane lands on.
    pane_drop_split_operation(tree, source, index, target, orientation, zone)
end

# The group and zone under a pointer, or `nothing` when the layout has no
# allocation to resolve against (an unconstrained print divides nothing).
function _drop_target(iomap::PaneTreeToWidgetIoMap, x::Integer, y::Integer)
    available = iomap.available
    available === nothing && return nothing
    width, height = available
    (width === nothing || height === nothing) && return nothing
    w, h = Int(width[]), Int(height[])
    (w <= 0 || h <= 0) && return nothing
    pane_drop_zone(iomap.input, x / w, y / h; strip = _PANE_STRIP_PIXELS / h)
end

# A splitter drag is a weight change. The widget computed two new pixel extents;
# they are put back among the other slots' extents and the lot is normalized, so
# the drag survives the next print and the next window resize — a pixel size
# would not.
function _read_resize(tree::PaneTree, iomap::PaneTreeToWidgetIoMap,
                      operation::ResizeSplitPaneOperation)
    split = _pane_node_for(iomap, operation.split)
    split isa PaneSplit || return nothing
    widget = operation.split
    k = operation.splitter_index
    n = length(split.elements)
    (1 <= k < n) || return nothing
    # The widget materializes `sizes` when the drag starts, so this is the extent
    # of every slot as drawn. Without it there is nothing to scale against and the
    # current weights stand.
    length(widget.sizes) == n || return nothing
    extents = Float64[Float64(widget.sizes[i]) for i in 1:n]
    extents[k] = Float64(operation.new_size_a)
    extents[k + 1] = Float64(operation.new_size_b)
    pane_resize_operation(tree, split, extents)
end

# The pane node whose widget is `widget`. Only pane nodes are searched — a tab's
# content is a foreign document and prints its own widgets, which are never the
# target of a report this projection answers.
function _pane_node_for(iomap, widget)
    iomap === nothing && return nothing
    # The children first, then this node. A tree prints *as* its root, so it
    # shares that widget — asking the tree first would answer every group's
    # report with the tree.
    if iomap isa PaneTreeToWidgetIoMap
        found = _pane_node_for(iomap.root_iomap, widget)
        found === nothing || return found
    elseif iomap isa PaneSplitToWidgetSplitPaneIoMap
        for child in iomap.element_iomaps
            found = _pane_node_for(child, widget)
            found === nothing || return found
        end
    end
    iomap.output === widget ? iomap.input : nothing
end

# ── The factory ────────────────────────────────────────────────────────────

"""
    PaneToWidget() -> TypeDispatchingProjection

The pane-tree stage: wrap it in a `RecursiveProjection` and chain a widget
renderer after it, exactly as the workbench does —

    ChainingProjection(RecursiveProjection(PaneToWidget()), renderer)

A tab's content passes through this stage unchanged, so `renderer` is what
decides how each content document is drawn.
"""
PaneToWidget(; new_tab = default_new_pane_tab) = TypeDispatchingProjection(
    PaneTree  => PaneTreeToWidget(new_tab),
    PaneSplit => PaneSplitToWidgetSplitPane(),
    PaneGroup => PaneGroupToWidgetTabbedPane(),
)

end # module PaneToWidgetModule
