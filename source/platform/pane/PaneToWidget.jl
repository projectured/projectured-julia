# Fragment of `PaneModule`.
#
# PaneDocument → WidgetDocument. The layout tree becomes split panes and tabbed
# panes:
#
#     PaneTree  → the widget of its root (transparent)
#     PaneSplit → WidgetSplitPane, one slot per element
#     PaneGroup → WidgetTabbedPane, one tab per tab
#
# **The two orientation vocabularies meet here.** A `:vertical` `PaneSplit` — one
# with a vertical divider, so its children sit side by side — prints a
# `WidgetSplitPane(:horizontal, …)`, because the widget's symbol names the axis its
# children lay out along. `get_pane_split_axis` is the translation, and this module is
# the only place that applies it.
#
# **Weights become layout weights.** Each slot is wrapped in a `LayoutConstraint`
# whose weight on the split axis is the element's share. Where the parent seeded an
# available extent the slot also takes a preferred extent of 0, so the allocator
# hands out the whole extent in proportion to the weights and nothing else. Where
# it did not — an unconstrained print, which has no total to divide — the slots
# fall back to their intrinsic sizes.
#
# **The selection is forwarded** onto both widgets, so a tabbed pane shows the tab
# the pane tree's selection names and a split pane routes a keystroke to the slot
# it names. Only the *routing prefix* is forwarded, not the deep suffix: every
# consumer reads the index alone, and forwarding less keeps a caret move inside a
# tab from regenerating the strip.
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

# The tail after a tab page's own `element` step, or the reference unchanged when
# it does not start with one.
#
# `selector_element_pairs[i]` names a `WidgetTabPage`, and the tab's content is
# that page's `element`. The tabbed pane adds the step only for a page whose
# element is a foreign document — a page holding a widget keeps its own path — so
# a reference that comes back from below carries it or does not, and both name the
# same place.
function _after_element_step(reference)
    reference isa ConcreteReference || return reference
    head = reference.head
    (head isa FieldReferenceStep && head.name == "element") || return reference
    reference.tail
end

# A tab's content belongs to a foreign domain, so it is not this projection's to
# print: it passes through unchanged and the renderer below reads it. Only pane
# nodes recurse.
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
# `get_routing` answers the part of the selection that the widget needs, which is
# the routing prefix unless the caller says more.
function _forward_selection!(widget, source, projection, iomap, get_routing = _index_prefix)
    source_selection = getfield(source, :selection)
    map_forward(path) = map_reference_forward(projection, iomap, get_routing(path))
    set_cell_computation!(getfield(widget, :selection), () -> begin
        # The stored path, live or dormant: a group that lost the focus still shows
        # the tab it was showing, so its widget image must name that tab.
        selection = _get_stored_selection_value(source_selection[])
        selection === nothing && return nothing
        map_forward(selection)
    end)
    hasfield(typeof(widget), :mouse_target) &&
        set_cell_computation!(getfield(widget, :mouse_target),
                              () -> map_mouse_target_forward(source, map_forward))
end

# ── PaneTree ───────────────────────────────────────────────────────────────

# The tree is transparent: it prints as its root, and adds one field step to the
# paths that pass through it.
function print_document(p::PaneTreeToWidget, recursion, tree::PaneTree, ctx)
    root_iomap = make_reconciled_child_iomap_cell(
        () -> tree.root,
        root -> _recurse(recursion, root,
                         make_child_context(ctx, tree, (@reference_step root))))
    available = (get_exact_width(ctx) === nothing || get_exact_height(ctx) === nothing) ?
                nothing : (get_exact_width(ctx), get_exact_height(ctx))

    # The layout, and one layer over it. A `WidgetComposite` is what can carry the
    # overlay: its children fill it (`Fill` on both axes), so the panes divide the
    # whole window, and it places each child at its own position, so the indicator
    # can sit anywhere over them; the indicator authors its size, which wins over
    # the fill. (A `StackLayout` clears the available size for its children, which
    # would collapse the split panes to their intrinsic sizes.)
    indicator = _drop_indicator(tree, available)
    composite = WidgetComposite(Any[]; child_width = Fill, child_height = Fill)
    set_cell_computation!(getfield(composite.elements, :elements),
                       () -> Cell[Cell(root_iomap[].output), Cell(indicator)])
    iomap = PaneTreeToWidgetIoMap(p, tree, composite, root_iomap, available)
    # The pane layer is slot 1, and the indicator never takes a keystroke. A key
    # reaches the pane layer whenever the focus is in the tree, and the pane
    # widgets route it on by their own selections. The composite names the layer
    # as a whole — and rings it — only when the tree's root is selected whole;
    # otherwise its selection is the image of the step the root takes, which is
    # all the routing reads and all the forward maps below take.
    map_forward(path) = begin
        path isa ConcreteReference || return nothing
        rest = _after_field(path, "root")
        rest === nothing && return nothing
        rest isa EmptyReference && return _PANE_LAYER
        map_reference_forward(p, iomap, ConcreteReference(path.type, path.head, _index_prefix(rest)))
    end
    set_cell_computation!(getfield(composite, :selection), () -> map_forward(get_selection(tree)))
    set_cell_computation!(getfield(composite, :mouse_target),
                          () -> map_mouse_target_forward(tree, map_forward))
    iomap
end

const _PANE_LAYER = @reference ::WidgetComposite.elements::CellVector[1]::WidgetDocument

# ── The drop indicator ─────────────────────────────────────────────────────
#
# While a tab is held, one muted rectangle shows where it would land: the whole
# of the target group for a drop that moves the tab into it, and the half a new
# pane would take for a drop on an edge band. It is a single widget whose cells
# read the drag, so showing and moving it costs no re-print — and it is always in
# the tree, just invisible, so the widget tree keeps its shape.
function _drop_indicator(tree::PaneTree, available)
    indicator = WidgetHighlight(; visible = false)
    rectangle() = _drop_indicator_rectangle(tree, available)
    set_cell_computation!(getfield(indicator, :position), () -> begin
        r = rectangle()
        r === nothing ? Point2D(0, 0) : Point2D(r[1], r[2])
    end)
    set_cell_computation!(getfield(indicator, :width),
                       () -> (r = rectangle(); r === nothing ? 0 : r[3]))
    set_cell_computation!(getfield(indicator, :height),
                       () -> (r = rectangle(); r === nothing ? 0 : r[4]))
    set_cell_computation!(getfield(indicator, :visible), () -> rectangle() !== nothing)
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
    r = get_pane_rectangle(tree, target)
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
    # The composite that holds the layout is the view of the tree, whole.
    reference isa EmptyReference && return EmptyReference(PaneTree)
    @reference_case reference begin
        ::WidgetComposite.elements{s:e}.rest... => begin
            s == 0 || return nothing        # slot 2 is the indicator: nothing to map
            inner = _child_backward(iomap.root_iomap, rest)
            inner === nothing && return nothing
            concat_references(
                ConcreteReference(PaneTree, FieldReferenceStep("root"), EmptyReference()),
                inner)
        end
    end
end

# ── PaneSplit ──────────────────────────────────────────────────────────────

function print_document(p::PaneSplitToWidgetSplitPane, recursion, split::PaneSplit, ctx)
    element_iomaps = make_reconciled_child_iomaps_cell(
        () -> split.elements,
        (i, element) -> _recurse(recursion, element,
            make_child_context(ctx, split, (@reference_step elements), (@reference_step [i]))))

    axis = get_pane_split_axis(split)
    # `axis` is what the widget calls its orientation: a vertical split lays its
    # children out horizontally.
    horizontal = axis === :horizontal
    available = horizontal ? get_exact_width(ctx) : get_exact_height(ctx)
    # With an allocation to divide, a slot prefers nothing of its own and takes
    # its weighted share of the whole. Without one there is no total to divide,
    # so the slots keep their intrinsic sizes.
    preferred = available === nothing ? nothing : 0

    pane = WidgetSplitPane(axis, Any[])
    set_cell_computation!(pane, () -> begin
        iomaps = element_iomaps[]
        weights = get_pane_normalized_weights(get_pane_weights(split))
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
    # The split pane is the view of the split, whole: a part that names the pane
    # itself, as a divider that starts a drag does, names the split.
    reference isa EmptyReference && return EmptyReference(PaneSplit)
    # Each slot is wrapped in a `LayoutConstraint`, so the split pane's reader
    # prepends `elements[i].child` to whatever the slot answered.
    @reference_case reference begin
        ::WidgetSplitPane.elements{s:e}.child.rest... => begin
            i = s + 1
            iomaps = iomap.element_iomaps
            i <= length(iomaps) || return nothing
            inner = _child_backward(iomaps[i], rest)
            inner === nothing && return nothing
            concat_references(
                ConcreteReference(PaneSplit, FieldReferenceStep("elements"),
                    ConcreteReference(CellVector, RangeReferenceStep(i - 1, i),
                                      EmptyReference())),
                inner)
        end
    end
end

# ── PaneGroup ──────────────────────────────────────────────────────────────

function print_document(p::PaneGroupToWidgetTabbedPane, recursion, group::PaneGroup, ctx)
    # One entry per tab: the content's IoMap, and the widget it draws as.
    #
    # Nothing is wrapped around it. Keeping a tab inside its own pane is the tabbed
    # pane's own work — it bounds the page, so it clips the page (see §3b of
    # layout-rules.md). A scroll pane here would clip too, but it would also take
    # the scroll: a content that manages its own panes, such as a transcript above
    # a composer, would scroll as one block.
    content_iomaps = make_reconciled_child_iomaps_cell(
        () -> Any[tab.content for tab in group.tabs],
        (i, content) -> begin
            child = _recurse(recursion, content,
                make_child_context(ctx, group, (@reference_step tabs), (@reference_step [i]),
                                   (@reference_step content)))
            (iomap = child, pane = child.output)
        end)

    # Every group offers the whole vocabulary: close a tab, open one, grab one, and
    # duplicate one whose content has a duplicate. That question is answered from
    # the type of the content, so the strip reads no cell of the content to ask it.
    pane = WidgetTabbedPane(Any[]; closable = true, new_tab = true, draggable = true,
                            duplicable = true)
    set_cell_computation!(pane, () -> begin
        entries = content_iomaps[]
        tabs = group.tabs
        Any[WidgetTabPage(_make_tab_label(tabs[i]), entries[i].pane, nothing,
                          has_document_duplicate(entries[i].iomap.input))
            for i in eachindex(entries)]
    end)

    iomap = PaneGroupToWidgetTabbedPaneIoMap(p, group, pane, content_iomaps)
    _forward_selection!(pane, group, p, iomap, selection -> _get_group_routing(group, selection))
    iomap
end

# The label of a tab in the strip: its name, and the icon, the role of the icon,
# the badges and the tooltip of its title. The four are cells of their own that
# read the title, so a title that follows a state redraws the strip and does not
# rebuild the pages.
function _make_tab_label(tab::PaneTab)
    title = tab.title
    WidgetTabLabel(get_pane_tab_title_string(tab);
                   icon = () -> title.icon, icon_role = () -> title.icon_role,
                   badges = () -> title.badges, tooltip = () -> title.tooltip)
end

# The part of a group's selection that its tabbed pane needs. A live caret in the
# name of a tab passes whole, because the tab bar draws it; everything else is the
# routing prefix. A group that lost the focus shows no caret in a name.
_get_group_routing(group::PaneGroup, selection) =
    (is_live_selection(group) && _is_title_caret(selection)) ? selection : _index_prefix(selection)

_is_title_caret(selection) = (@reference_case selection begin
    ::PaneGroup.tabs[i].rest... => _find_title_caret_position(rest) !== nothing
end) === true

# The caret position in the name of a tab, or `nothing` when the path below the
# tab is not a caret in its name.
_find_title_caret_position(rest) = @reference_case rest begin
    ::PaneTab.title.name.value{k} => k
end

# The caret position in the name that a tab page of the widget holds.
_find_selector_caret_position(rest) = @reference_case rest begin
    ::WidgetTabPage.selector.text{k} => k
end

function map_reference_forward(::PaneGroupToWidgetTabbedPane,
                               iomap::PaneGroupToWidgetTabbedPaneIoMap, reference)
    @reference_case reference begin
        ::PaneGroup.tabs[i].rest... => begin
            entries = iomap.content_iomaps
            (1 <= i <= length(entries)) || return nothing
            # A caret in the name is a caret in the name the tab page holds.
            k = _find_title_caret_position(rest)
            k === nothing ||
                return @reference ::WidgetTabbedPane.selector_element_pairs::CellVector[i]::WidgetTabPage.selector::WidgetTabLabel.text::String{k}::Position
            # The node at `[i]` is the tab page, and the content is its `element`. A
            # selection that names the tab whole, or its title whole, names the page.
            inside = _get_tab_content_path(rest)
            inside === nothing &&
                return @reference ::WidgetTabbedPane.selector_element_pairs::CellVector[i]::WidgetTabPage
            inner = _child_forward(entries[i].iomap, inside)
            # The content's type differs from tab to tab, so the checkpoint of the
            # element is read off the document the tab prints.
            image = inner isa EmptyReference ?
                    EmptyReference(get_reference_node_type(entries[i].pane)) :
                    _typed_head(inner, entries[i].pane)
            @reference ::WidgetTabbedPane.selector_element_pairs::CellVector[i]::WidgetTabPage.element.^(image)
        end
    end
end

# The path inside the content of a tab, or `nothing` when `rest` does not enter the
# content: a selection of the tab whole, or of its title.
function _get_tab_content_path(rest)
    @reference_case rest begin
        ::PaneTab.content.inner... => inner
    end
end

function map_reference_backward(::PaneGroupToWidgetTabbedPane,
                                iomap::PaneGroupToWidgetTabbedPaneIoMap, reference)
    # The tabbed pane is the view of the group, whole.
    reference isa EmptyReference && return EmptyReference(PaneGroup)
    @reference_case reference begin
        ::WidgetTabbedPane.selector_element_pairs{s:e}.rest... => begin
            i = s + 1
            entries = iomap.content_iomaps
            i <= length(entries) || return nothing
            # A bare `selector_element_pairs[i]` is a tab-strip click: it names the
            # tab and nothing in it.
            tab = @reference ::PaneGroup.tabs::CellVector[i]::PaneTab
            rest isa EmptyReference && return tab
            k = _find_selector_caret_position(rest)
            k === nothing ||
                return @reference ::PaneGroup.tabs::CellVector[i]::PaneTab.title::PaneTabTitle.name::PrimitiveString.value::String{k}::Position
            # `concat_references`, not the `^` splice of `@reference`: the splice
            # hoists the spliced path's leading type onto the node before it, so a
            # content path that starts at its own checkpoint would overwrite
            # `::PaneTab` and leave every node below untyped. A selection whose
            # checkpoints moved matches no document.
            content = concat_references(tab,
                ConcreteReference(FieldReferenceStep("content"), EmptyReference()))
            inside = _after_element_step(rest)
            # `.element` and nothing after it names the tab's CONTENT, whole — not
            # the tab. An Alt+click on a pane answers this, and so does a
            # document-replace that swaps the whole content, such as the one the
            # Insert key makes on an empty tab. Answering the tab there would write
            # the new document over the `PaneTab` itself and take the layout with
            # it.
            inside isa EmptyReference && return concat_references(content,
                EmptyReference(get_reference_node_type(entries[i].iomap.input)))
            # Anything deeper is a click INSIDE the tab, and it must reach the
            # document the tab holds. A caret is the case that shows it: a click in
            # a form field of a pane's content answers a path into that field, and
            # an answer truncated to the tab leaves the field with no caret and the
            # next key with nowhere to go.
            inner = _child_backward(entries[i].iomap, inside)
            # A content that claims nothing still says which pane was pointed at.
            inner === nothing && return tab
            concat_references(content, _typed_head(inner, entries[i].iomap.input))
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

# A tab click arrives as a ReplaceSelectionOperation, which the generic reader
# re-targets through `map_reference_backward`: its bare
# `selector_element_pairs[i]` case answers `tabs[i]::PaneTab`.
#
# An Alt+click inside a page names an object in the tab's document. When the
# content's projection maps it back to a whole document, the answer is that
# document. A caret, or a place the content's projection introduced, names the
# innermost document on its path: the one that holds the caret, or the one the
# projection printed the place for. Any other answer — the tab, because the
# content maps nothing back — names the tab's content, as a whole.
function _select_page_content(tree::PaneTree, widget_operation, answer)
    (widget_operation isa ReplaceSelectionOperation && _is_inside_page(widget_operation.path)) ||
        return answer
    answer isa ReplaceSelectionOperation || return answer
    target = try_evaluate_reference(tree, answer.path, nothing)
    (target isa Document && !(target isa PaneDocument)) && return answer
    innermost = _find_innermost_document_path(tree, answer.path)
    innermost === nothing || return ReplaceSelectionOperation(innermost)
    rest = _after_field(answer.path, "root")
    rest === nothing && return answer
    found = _focus_walk(tree.root, rest)
    found === nothing && return answer
    group, index = found[1], found[2]
    index == 0 && return answer
    content = get_pane_content_path(tree, group, index)
    content === nothing ? answer : ReplaceSelectionOperation(content)
end

# The longest prefix of `path` that names a document inside a tab, or `nothing`.
# The walk stops before a place a projection introduced, skips a collection, and
# gives up at a pane.
function _find_innermost_document_path(tree::PaneTree, path)
    steps = collect(get_reference_steps(strip_reference_types(path)))
    introduced = findfirst(step -> step isa ProjectionReferenceStep, steps)
    longest = introduced === nothing ? length(steps) - 1 : introduced - 1
    for n in longest:-1:1
        prefix = foldr(ConcreteReference, steps[1:n]; init = EmptyReference())
        node = try_evaluate_reference(tree, prefix, nothing)
        node isa PaneDocument && return nothing
        (node isa Document && !(node isa CollectionDocument)) &&
            return annotate_reference_types(tree, prefix)
    end
    nothing
end

# Whether a widget path goes into a tab's page: past `selector_element_pairs[i]`
# into its `element`.
function _is_inside_page(path)
    steps = get_reference_steps(strip_reference_types(path))
    for k in (length(steps) - 2):-1:1
        step = steps[k]
        (step isa FieldReferenceStep && step.name == "selector_element_pairs") || continue
        next = steps[k + 2]
        return next isa FieldReferenceStep && next.name == "element"
    end
    false
end

function read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap,
                     operation::CloseTabOperation)
    group = _pane_node_for(iomap, operation.widget)
    group isa PaneGroup || return nothing
    make_pane_close_tab_operation(iomap.input, group, operation.tab_index)
end

function read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap,
                     operation::OpenTabOperation)
    group = _pane_node_for(iomap, operation.widget)
    group isa PaneGroup || return nothing
    make_pane_open_tab_operation(iomap.input, group, p.new_tab())
end

function read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap,
                     operation::DuplicateTabOperation)
    group = _pane_node_for(iomap, operation.widget)
    group isa PaneGroup || return nothing
    make_pane_duplicate_tab_operation(iomap.input, group, operation.tab_index)
end

read_intent(p::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap, operation::DragTabOperation) =
    _press_tab(iomap, operation, nothing)

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
read_intent(::PaneTreeToWidget, iomap::PaneTreeToWidgetIoMap,
            operation::StartSplitterDragOperation) =
    _pane_node_for(iomap, operation.split) isa PaneSplit ?
        CompoundOperation(Any[
            ReplaceReferencedValueOperation(operation.split, "sizes", CellVector()),
            operation]) :
        operation      # a split a tab's content built: it keeps its own sizes
read_intent(::PaneTreeToWidget, ::PaneTreeToWidgetIoMap,
            operation::EndSplitterDragOperation) = operation

# The drag of a tab needs the raw gesture beside the operation that the layers
# below made of it: the press keeps its point, and a move with a button held
# starts the drag after the small move. The four-arg reader is where both are in
# hand. The parts of a drag that has started come by the path of the tree. Every
# other change reads exactly as the generic bridge does.
function read_intent(p::PaneTreeToWidget, recursion, change::Intent,
                     iomap::PaneTreeToWidgetIoMap)
    tree = iomap.input
    state = getfield(tree, :drag)[]
    gesture = change.gesture
    state !== nothing && gesture isa Union{DragMove, DragEnd, DragCancel} &&
        return Intent(gesture, _read_tab_drag(iomap, state, gesture))
    payload = change.operation === nothing ? gesture : change.operation
    answer = read_intent(p, iomap, payload)
    payload isa DragTabOperation && gesture isa MouseDown &&
        (answer = _press_tab(iomap, payload, (gesture.x, gesture.y)))
    (state === nothing || state.started) ||
        (answer = _join_tab_operations(_read_tab_press(iomap, state, gesture), answer))
    is_whole_selection_press(change.gesture) &&
        (answer = _select_page_content(tree, change.operation, answer))
    # A left press that nothing claimed still says which pane the user pointed at.
    # A pane is mostly empty space — its content is a document that ends where its
    # text ends — so without this a click beside the text would focus nothing.
    press = change.gesture
    answer === nothing && press isa MouseClick && press.button === :left &&
        (answer = _focus_from_press(iomap, press))
    Intent(change.gesture, answer)
end

function _focus_from_press(iomap::PaneTreeToWidgetIoMap, press)
    landing = _drop_target(iomap, press.x, press.y)
    landing === nothing && return nothing
    group = landing[1]
    tree = iomap.input
    focus = get_pane_focus(tree)
    (focus !== nothing && focus[1] === group) && return nothing
    make_pane_focus_operation(tree, group, get_pane_shown_tab_index(group))
end

# ── The drag ───────────────────────────────────────────────────────────────
#
# `PaneTree.drag` holds `(group, index, target, zone, origin, started)` while a
# tab is held: where it came from, where it would land, the point of the press,
# and whether the drag has started. It is transient state on the tree, so each
# write carries the tree itself and re-roots nowhere. The tree is the part whose
# drag is on: it starts the drag after the small move, so a press that does not
# move is still a click, and the drag wrapper then sends it `DragMove`, `DragEnd`
# and `DragCancel` by its path.
#
# The pointer is resolved against the **layout tree**, not against the printed
# canvas: the groups divide the available extent in proportion to their weights,
# so the unit-square rectangle of a group *is* where it is drawn. The tab strip
# is the one part that has a fixed height rather than a share, so its band is
# converted from pixels here.

const _PANE_STRIP_PIXELS = 32

# A drag in progress is the pointer's state and not the layout's, so the write is
# marked and no history records it; the drop is the edit.
_drag_write(tree, state) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(tree, "drag", state))

# The pixels that a press on a tab moves before it drags the tab.
const _TAB_DRAG_START = 5

# A press on a tab of a pane that can be dragged: the tree keeps the tab and the
# point of the press, and no drag is on yet.
function _press_tab(iomap::PaneTreeToWidgetIoMap, operation::DragTabOperation, origin)
    group = _pane_node_for(iomap, operation.widget)
    group isa PaneGroup || return nothing
    (1 <= operation.tab_index <= length(group.tabs)) || return nothing
    _drag_write(iomap.input, (group = group, index = operation.tab_index, target = nothing,
                              zone = :none, origin = origin, started = false))
end

# Before the drag of a tab starts: a move with a button held past the small move
# starts it, and the tree is the part whose drag is on; a release ends the press,
# which was a click, so the click selects the tab. A grab with no point of a
# press, which code makes, starts at the first move with a button held.
function _read_tab_press(iomap::PaneTreeToWidgetIoMap, state, gesture)
    tree = iomap.input
    gesture isa MouseUp && return _drag_write(tree, nothing)
    (gesture isa MouseMove && !is_move_without_button(gesture)) || return nothing
    if state.origin !== nothing
        ox, oy = state.origin
        hypot(gesture.x - ox, gesture.y - oy) >= _TAB_DRAG_START || return nothing
    end
    target, zone = _find_tab_landing(iomap, state, gesture.x, gesture.y)
    CompoundOperation(Any[
        _drag_write(tree, merge(state, (target = target, zone = zone, started = true))),
        StartDragOperation(EmptyReference(), (group = state.group, index = state.index)),
        make_screen_pointer_shape_operation(_get_tab_drop_shape(target))])
end

# The shape of the pointer during the drag of a tab: the closed hand where a group
# takes the tab, the crossed circle where none does.
_get_tab_drop_shape(target) = target === nothing ? :crossed_circle : :closed_hand

# The parts of the drag of a tab, which come by the path of the tree: a move sets
# where the tab would land, the release drops it there, and a cancel drops it
# nowhere.
function _read_tab_drag(iomap::PaneTreeToWidgetIoMap, state, gesture)
    tree = iomap.input
    if gesture isa DragMove
        target, zone = _find_tab_landing(iomap, state, gesture.x, gesture.y)
        # Only write when the target moved, so a drag across a pane is not one
        # write per pixel.
        (state.target === target && state.zone === zone) && return nothing
        write = _drag_write(tree, merge(state, (target = target, zone = zone)))
        shape = _get_tab_drop_shape(target)
        shape === _get_tab_drop_shape(state.target) && return write
        return CompoundOperation(Any[write, make_screen_pointer_shape_operation(shape)])
    elseif gesture isa DragEnd
        drop = _drop_operation(tree, state)
        clear = CompoundOperation(Any[_drag_write(tree, nothing),
                                      make_screen_pointer_shape_operation(nothing)])
        return drop === nothing ? clear : CompoundOperation(Any[drop, clear.operations...])
    end
    CompoundOperation(Any[_drag_write(tree, nothing), make_screen_pointer_shape_operation(nothing)])
end

# Where the tab of `state` dragged to `(x, y)` of the view would land: the group and
# the zone, or `(nothing, :none)`.
function _find_tab_landing(iomap::PaneTreeToWidgetIoMap, state, x::Integer, y::Integer)
    point = _get_view_point(iomap, x, y)
    landing = point === nothing ? nothing :
              find_drop_zone(iomap.input, (group = state.group, index = state.index), point)
    landing === nothing ? (nothing, :none) : landing
end

_join_tab_operations(first, second) =
    first === nothing ? second : second === nothing ? first :
    CompoundOperation(Any[first, second])

function _drop_operation(tree::PaneTree, state)
    target = state.target
    target === nothing && return nothing
    source, index, zone = state.group, state.index, state.zone
    orientation = get_pane_zone_orientation(zone)
    if orientation === nothing
        # The strip or the middle: the tab moves into the group, at its end.
        source === target && return nothing
        return make_pane_move_tab_operation(tree, source; source_index = index, target,
                                            target_index = length(target.tabs) + 1)
    end
    # The zone names the side the new pane lands on.
    make_pane_drop_split_operation(tree, source; source_index = index, target,
                                   orientation, side = zone)
end

# The point `(x, y)` of the view with the size of the view, or `nothing` when the
# layout has no allocation to resolve against (an unconstrained print divides
# nothing).
function _get_view_point(iomap::PaneTreeToWidgetIoMap, x::Integer, y::Integer)
    available = iomap.available
    available === nothing && return nothing
    width, height = available
    (width === nothing || height === nothing) && return nothing
    w, h = Int(width[]), Int(height[])
    (w <= 0 || h <= 0) && return nothing
    (x = x, y = y, width = w, height = h)
end

# The group and zone under a pointer, or `nothing`.
function _drop_target(iomap::PaneTreeToWidgetIoMap, x::Integer, y::Integer)
    point = _get_view_point(iomap, x, y)
    point === nothing ? nothing : _find_pane_landing(iomap.input, point)
end

_find_pane_landing(tree::PaneTree, point) =
    get_pane_drop_zone(tree, point.x / point.width, point.y / point.height;
                       strip = _PANE_STRIP_PIXELS / point.height)

# A tree takes a tab of its own at the group and the zone under the point, which
# holds the point and the size of the view of the tree in pixels.
find_drop_zone(tree::PaneTree, dragged, point) = _find_pane_landing(tree, point)

# A splitter drag is a weight change. The widget computed two new pixel extents;
# they are put back among the other slots' extents and the lot is normalized, so
# the drag survives the next print and the next window resize — a pixel size
# would not.
function _read_resize(tree::PaneTree, iomap::PaneTreeToWidgetIoMap,
                      operation::ResizeSplitPaneOperation)
    split = _pane_node_for(iomap, operation.split)
    # Not one of the tree's own splits: it is a split a tab's content built, and
    # the widget layer answers it itself. Pass it on unchanged. Dropping it here
    # killed every drag of a splitter inside a pane — the grab started and the
    # first motion went nowhere.
    split isa PaneSplit || return operation
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
    # The weights that the split holds are not written again: a move to the point
    # of the last move writes no cell.
    get_pane_normalized_weights(extents) == get_pane_weights(split) && return nothing
    make_pane_resize_operation(tree, split, extents)
end

# The pane node whose widget is `widget`. Only pane nodes are searched — a tab's
# content is a foreign document and prints its own widgets, which are never the
# target of a report this projection answers.
function _pane_node_for(iomap, widget)
    iomap === nothing && return nothing
    iomap = get_content_iomap(iomap)
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
renderer after it —

    ChainingProjection(RecursiveProjection(PaneToWidget()), renderer)

A tab's content passes through this stage unchanged, so `renderer` is what
decides how each content document is drawn. A tab's content is read through
`print_child`, not through a fresh top-level `print_document`, so a document
whose own natural row produces a widget (rather than final graphics) is not
reduced to a fixpoint the way a top-level print reduces one: give such a
document its own `extra` entry that chains its widget-producing projection
into a fresh `renderer` instance, rather than relying on the row alone.
"""
PaneToWidget(; new_tab = default_new_pane_tab) = TypeDispatchingProjection(
    PaneTree  => PaneTreeToWidget(new_tab),
    PaneSplit => PaneSplitToWidgetSplitPane(),
    PaneGroup => PaneGroupToWidgetTabbedPane(),
)
