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
                            pane_close_tab_operation, pane_resize_operation
import ..WidgetModule: SelectTabOperation, CloseTabRequestOperation,
                       NewTabRequestOperation, DragTabOperation,
                       ResizeSplitPaneOperation
import ..WidgetModule: WidgetDocument, WidgetSplitPane, WidgetTabbedPane, Inset
import ..LayoutModule: LayoutConstraint
import ..IoMapModule: IoMap, SimpleIoMap, var"@iomap",
                      reconcile_child_iomap, reconcile_child_iomaps
import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..CollectionModule: CellVector
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..ReferenceModule: Reference, ConcreteReference, EmptyReference,
                          FieldReferenceStep, RangeReferenceStep, ElementReferenceStep
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
        selection = source_selection[]
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
        root -> _recurse(recursion, root, make_child_context(ctx, tree, (@reference_step root))))
    PaneTreeToWidgetIoMap(p, tree, ComputedCell(() -> root_iomap[].output), root_iomap)
end

function map_reference_forward(::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap, reference)
    @reference_case reference begin
        ::PaneTree.root.rest... => _child_forward(iomap.root_iomap, rest)
    end
end

function map_reference_backward(::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap, reference)
    inner = _child_backward(iomap.root_iomap, reference)
    inner === nothing && return nothing
    @reference ::PaneTree.root.^(inner)
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
    content_iomaps = reconcile_child_iomaps(
        () -> Any[tab.content for tab in group.tabs],
        (i, content) -> _recurse(recursion, content,
            make_child_context(ctx, group, (@reference_step tabs), (@reference_step [i]),
                               (@reference_step content))))

    # Every group offers the whole vocabulary: close a tab, open one, grab one.
    pane = WidgetTabbedPane(Any[]; closable = true, new_tab = true, draggable = true,
                            border = _PANE_BORDER)
    set_cell_function!(pane, () -> begin
        iomaps = content_iomaps[]
        tabs = group.tabs
        Any[(pane_tab_title_string(tabs[i]), iomaps[i].output) for i in eachindex(iomaps)]
    end)

    iomap = PaneGroupToWidgetTabbedPaneIoMap(p, group, pane, content_iomaps)
    _forward_selection!(pane, group, p, iomap)
    iomap
end

function map_reference_forward(::PaneGroupToWidgetTabbedPane,
                               iomap::PaneGroupToWidgetTabbedPaneIoMap, reference)
    @reference_case reference begin
        ::PaneGroup.tabs[i].rest... => begin
            iomaps = iomap.content_iomaps
            (1 <= i <= length(iomaps)) || return nothing
            inner = _tab_forward(iomaps[i], rest)
            @reference ::WidgetTabbedPane.selector_element_pairs::CellVector[i].^(inner)
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
            iomaps = iomap.content_iomaps
            i <= length(iomaps) || return nothing
            # A bare `selector_element_pairs[i]` is a tab-strip click: it names
            # the tab, not anything inside it.
            rest isa EmptyReference &&
                return @reference ::PaneGroup.tabs::CellVector[i]::PaneTab
            inner = _child_backward(iomaps[i], rest)
            inner === nothing && return nothing
            @reference ::PaneGroup.tabs::CellVector[i]::PaneTab.content.^(inner)
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

function read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap, payload)
    answer = _read_report(p, iomap, payload)
    answer === nothing || return answer
    # The generic reader. `invoke` reaches it past this more specific method.
    invoke(read_intent, Tuple{Projection, Any, Any}, p, iomap, payload)
end

function _read_report(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap, operation)
    tree = iomap.input
    if operation isa SelectTabOperation
        group = _pane_node_for(iomap, operation.widget)
        group isa PaneGroup || return nothing
        return pane_focus_operation(tree, group, operation.tab_index)
    elseif operation isa CloseTabRequestOperation
        group = _pane_node_for(iomap, operation.widget)
        group isa PaneGroup || return nothing
        return pane_close_tab_operation(tree, group, operation.tab_index)
    elseif operation isa NewTabRequestOperation
        group = _pane_node_for(iomap, operation.widget)
        group isa PaneGroup || return nothing
        return pane_open_tab_operation(tree, group, p.new_tab())
    elseif operation isa ResizeSplitPaneOperation
        return _read_resize(tree, iomap, operation)
    end
    nothing
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
