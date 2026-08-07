"""
    PaneSurgeryModule

The pane-tree edits, and the paths they are expressed against.

**This module declares no operation type.** Each builder returns a generic
operation — `insert_elements`, `delete_elements`,
`ReplaceReferencedValueOperation`, `MoveRangeOperation`,
`ReplaceSelectionOperation`, or a `CompoundOperation` of two of them. Every write
leaves the operation's `document` field at `nothing`, so the reference re-roots as
the operation bubbles up and a pane tree keeps working nested inside another
document.

**The surgery reuses node objects; it never rebuilds a subtree.** A split puts
the *existing* group into the new split, and a collapse writes the *existing*
sibling at the parent's slot. Only the node that goes away is dropped — a rebuilt
subtree would drop the iomaps below it, and every tab would re-print.

**Paths carry their node types as they are built.** Each `(node, step)` pair
records the document the step descends *from*, which is what
`ConcreteReference`'s `type` field means. This is what lets a builder name a slot
the edit is *about to* create — a fresh tab, a collapsed sibling — which
`annotate_reference_types` can not do, because it resolves against the tree as it
stands now.
"""
module PaneSurgeryModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..DocumentApiModule: Document
import ..OperationModule: CompoundOperation, ReplaceReferencedValueOperation,
                          ReplaceSelectionOperation, insert_elements, delete_elements
import ..DraggingProjectionModule: MoveRangeOperation
import ..ReferenceModule: Reference, ConcreteReference, EmptyReference,
                          FieldReferenceStep, ElementReferenceStep, RangeReferenceStep,
                          get_reference_node_type
import ..SelectionModule: get_selection
import ..PaneModule: PaneDocument, PaneTree, PaneSplit, PaneGroup, PaneTab,
                     pane_weights, pane_normalized_weights, pane_groups, pane_parent

export pane_path, pane_collection_path,
       pane_focus, pane_focused_group, pane_focused_tab_index,
       pane_tab_reference, pane_focus_operation,
       pane_open_tab_operation, pane_close_tab_operation, pane_split_operation,
       pane_move_tab_operation, pane_drop_split_operation, pane_resize_operation

# ── Path construction ──────────────────────────────────────────────────────

# A reference from `(node, step)` pairs. Each pair's node is what its step
# descends from, which is the type `ConcreteReference` records; `final` is the
# document the path ends on.
function _reference_from(pairs, final)
    reference = EmptyReference(get_reference_node_type(final))
    for i in length(pairs):-1:1
        node, step = pairs[i]
        reference = ConcreteReference(get_reference_node_type(node), step, reference)
    end
    reference
end

# Append the pairs leading from `current` to `target`, and answer whether it was
# found. `from`/`to` substitute one node for another as the walk passes it, so a
# caller can name a slot in the tree the edit is about to produce (the sibling
# that replaces a collapsing split, the split that replaces a group).
function _trail_into!(current, target, pairs; from = nothing, to = nothing)
    if current === from
        # The substitution fires once. A replacement usually *contains* the node
        # it replaces — a split wraps the group it splits, a sibling sits inside
        # the split it collapses — so a second firing would walk in circles.
        current = to
        from = nothing
        to = nothing
    end
    current === target && return true
    if current isa PaneSplit
        elements = current.elements
        for i in 1:length(elements)
            push!(pairs, (current, FieldReferenceStep("elements")))
            push!(pairs, (elements, ElementReferenceStep(i)))
            _trail_into!(elements[i], target, pairs; from, to) && return true
            pop!(pairs)
            pop!(pairs)
        end
    elseif current isa PaneGroup
        tabs = current.tabs
        for i in 1:length(tabs)
            push!(pairs, (current, FieldReferenceStep("tabs")))
            push!(pairs, (tabs, ElementReferenceStep(i)))
            tabs[i] === target && return true
            pop!(pairs)
            pop!(pairs)
        end
    end
    false
end

# The pairs from `tree` down to `node`, or `nothing` when the node is not in it.
function _pairs_to(tree::PaneTree, node; from = nothing, to = nothing)
    node === tree && return Any[]
    pairs = Any[(tree, FieldReferenceStep("root"))]
    _trail_into!(tree.root, node, pairs; from, to) || return nothing
    pairs
end

"""
    pane_path(tree, node) -> Reference | Nothing

The typed path from `tree` to `node`, or `nothing` when the node is not in the
tree.
"""
function pane_path(tree::PaneTree, node)
    pairs = _pairs_to(tree, node)
    pairs === nothing ? nothing : _reference_from(pairs, node)
end

"""
    pane_collection_path(tree, owner, field) -> Reference | Nothing

The typed path to one of `owner`'s collection fields — `:tabs` of a group,
`:elements` or `:weights` of a split. This is the path
`insert_elements` / `delete_elements` splice against.
"""
function pane_collection_path(tree::PaneTree, owner, field::Symbol)
    pairs = _pairs_to(tree, owner)
    pairs === nothing && return nothing
    push!(pairs, (owner, FieldReferenceStep(String(field))))
    _reference_from(pairs, getproperty(owner, field))
end

# The path to element `index` of `owner`'s `field`, ending on `element`. The
# element need not be there yet — its type comes from the object, not from the
# tree — so this names the slot an insert or a collapse is about to fill.
function _element_path(tree::PaneTree, owner, field::Symbol, index::Integer, element;
                       from = nothing, to = nothing)
    pairs = _pairs_to(tree, owner; from, to)
    pairs === nothing && return nothing
    collection = getproperty(owner, field)
    push!(pairs, (owner, FieldReferenceStep(String(field))))
    push!(pairs, (collection, ElementReferenceStep(Int(index))))
    _reference_from(pairs, element)
end

# ── Tree walks ─────────────────────────────────────────────────────────────

# The tab that must take the focus inside `node`, with the pairs that lead to it
# appended. Answers the document the path ends on — the tab, or the node itself
# when it holds no tab.
function _focus_into!(node, pairs)
    if node isa PaneGroup
        isempty(node.tabs) && return node
        push!(pairs, (node, FieldReferenceStep("tabs")))
        push!(pairs, (node.tabs, ElementReferenceStep(1)))
        return node.tabs[1]
    elseif node isa PaneSplit
        isempty(node.elements) && return node
        push!(pairs, (node, FieldReferenceStep("elements")))
        push!(pairs, (node.elements, ElementReferenceStep(1)))
        return _focus_into!(node.elements[1], pairs)
    end
    node
end

# ── The focus ──────────────────────────────────────────────────────────────

"""
    pane_focus(tree) -> (group, index) | Nothing

The focused group and the 1-based index of the tab the selection names, or `0`
for that index when the selection names the group itself. `nothing` when the
selection is not inside the tree.
"""
function pane_focus(tree::PaneTree)
    selection = get_selection(tree)
    selection === nothing && return nothing
    rest = _after_field(selection, "root")
    rest === nothing && return nothing
    _focus_walk(tree.root, rest)
end

"""
    pane_focused_group(tree) -> PaneGroup | Nothing

The focused group, or `nothing` when the selection is not inside the tree.
"""
function pane_focused_group(tree::PaneTree)
    focus = pane_focus(tree)
    focus === nothing ? nothing : focus[1]
end

"""
    pane_focused_tab_index(tree) -> Int

The 1-based index of the focused tab, or `0` when no tab is focused.
"""
function pane_focused_tab_index(tree::PaneTree)
    focus = pane_focus(tree)
    focus === nothing ? 0 : focus[2]
end

function _focus_walk(node, path)
    if node isa PaneSplit
        rest = _after_field(path, "elements")
        rest === nothing && return nothing
        index, rest2 = _head_index(rest)
        index === nothing && return nothing
        (1 <= index <= length(node.elements)) || return nothing
        return _focus_walk(node.elements[index], rest2)
    elseif node isa PaneGroup
        rest = _after_field(path, "tabs")
        rest === nothing && return (node, 0)
        index, _ = _head_index(rest)
        index === nothing && return (node, 0)
        return (node, (1 <= index <= length(node.tabs)) ? index : 0)
    end
    nothing
end

_after_field(path::ConcreteReference, name::String) =
    (path.head isa FieldReferenceStep && path.head.name == name) ? path.tail : nothing
_after_field(::Any, ::String) = nothing

function _head_index(path)
    path isa ConcreteReference || return (nothing, path)
    step = path.head
    step isa RangeReferenceStep || return (nothing, path)
    (Int(step.start) + 1, path.tail)
end

"""
    pane_tab_reference(tree, group, index) -> Reference | Nothing

The selection reference naming tab `index` of `group`, or the group itself when
`index` is 0.
"""
function pane_tab_reference(tree::PaneTree, group::PaneGroup, index::Integer)
    index == 0 && return pane_path(tree, group)
    (1 <= index <= length(group.tabs)) || return nothing
    _element_path(tree, group, :tabs, index, group.tabs[index])
end

"""
    pane_focus_operation(tree, group, index) -> Operation | Nothing

Move the focus to tab `index` of `group` — the whole of what focusing is. An
`index` of 0 focuses the group itself, which is what an empty group takes.
"""
function pane_focus_operation(tree::PaneTree, group::PaneGroup, index::Integer)
    reference = pane_tab_reference(tree, group, index)
    reference === nothing ? nothing : ReplaceSelectionOperation(reference)
end

# ── Open a tab ─────────────────────────────────────────────────────────────

"""
    pane_open_tab_operation(tree, group, tab; index) -> Operation | Nothing

Insert `tab` into `group` at the 1-based `index` (the end by default) and focus
it. One `insert_elements` splice with its cursor move.
"""
function pane_open_tab_operation(tree::PaneTree, group::PaneGroup, tab::PaneTab;
                                 index = nothing)
    tabs_path = pane_collection_path(tree, group, :tabs)
    tabs_path === nothing && return nothing
    n = length(group.tabs)
    at = index === nothing ? n + 1 : clamp(Int(index), 1, n + 1)
    cursor = _element_path(tree, group, :tabs, at, tab)
    insert_elements(tabs_path, at - 1, Any[tab], cursor)
end

# ── Close a tab ────────────────────────────────────────────────────────────

"""
    pane_close_tab_operation(tree, group, index) -> Operation | Nothing

Remove tab `index` of `group`. When it is the group's last tab the group goes
too: it is dropped from its parent split, or — when that split is left with one
element — the split is replaced by its remaining sibling. An empty root group
stays, because a tree always has a root.
"""
function pane_close_tab_operation(tree::PaneTree, group::PaneGroup, index::Integer)
    n = length(group.tabs)
    (1 <= index <= n) || return nothing
    n > 1 && return _close_one_tab(tree, group, index, n)
    _close_group(tree, group)
end

function _close_one_tab(tree::PaneTree, group::PaneGroup, index::Integer, n::Integer)
    tabs_path = pane_collection_path(tree, group, :tabs)
    tabs_path === nothing && return nothing
    # The tab that takes the focus, named in the numbering that follows the
    # deletion: the next tab keeps this index, the last tab moves back one.
    survivor = index < n ? index + 1 : index - 1
    at = index < n ? index : index - 1
    cursor = _element_path(tree, group, :tabs, at, group.tabs[survivor])
    CompoundOperation(Any[delete_elements(tabs_path, index - 1),
                          ReplaceSelectionOperation(cursor)])
end

function _close_group(tree::PaneTree, group::PaneGroup)
    parent = pane_parent(tree, group)
    parent === nothing && return nothing
    owner, k = parent
    tabs_path = pane_collection_path(tree, group, :tabs)
    tabs_path === nothing && return nothing
    drop_tab = delete_elements(tabs_path, 0)

    # The root group stays, empty. The selection names the group itself.
    if owner === tree
        cursor = pane_path(tree, group)
        return CompoundOperation(Any[drop_tab, ReplaceSelectionOperation(cursor)])
    end

    split = owner::PaneSplit
    m = length(split.elements)
    if m > 2
        # Drop the group and its weight; the neighbour takes the focus.
        neighbour = split.elements[k < m ? k + 1 : k - 1]
        at = k < m ? k : k - 1
        pairs = _pairs_to(tree, split)
        push!(pairs, (split, FieldReferenceStep("elements")))
        push!(pairs, (split.elements, ElementReferenceStep(at)))
        leaf = _focus_into!(neighbour, pairs)
        cursor = _reference_from(pairs, leaf)
        elements_path = pane_collection_path(tree, split, :elements)
        weights = pane_weights(split)
        deleteat!(weights, k)
        writes = Any[drop_tab,
                     delete_elements(elements_path, k - 1),
                     _write_weights(tree, split, weights),
                     ReplaceSelectionOperation(cursor)]
        return CompoundOperation(filter(!isnothing, writes))
    end

    # Two elements left: the split is replaced by its sibling.
    sibling = split.elements[k == 1 ? 2 : 1]
    slot = _slot_write(tree, split, sibling)
    slot === nothing && return nothing
    pairs = _pairs_to(tree, sibling; from = split, to = sibling)
    pairs === nothing && return nothing
    leaf = _focus_into!(sibling, pairs)
    cursor = _reference_from(pairs, leaf)
    CompoundOperation(Any[drop_tab, slot, ReplaceSelectionOperation(cursor)])
end

# ── Split a group ──────────────────────────────────────────────────────────

"""
    pane_split_operation(tree, group, orientation, side, tab) -> Operation | Nothing

Split `group` and put `tab` in the new pane. `orientation` is `:vertical` (the
new pane sits beside) or `:horizontal` (it sits above or below); `side` is
`:left`, `:right`, `:above`, or `:below`.

The new split takes the weight the group had, and its two children take half
each, so the rest of the layout does not move. When the parent split already has
this orientation the group is not wrapped — the new group joins the parent as a
sibling, splitting the group's weight — which is what keeps a split from ever
holding a child split of its own orientation.
"""
function pane_split_operation(tree::PaneTree, group::PaneGroup, orientation::Symbol,
                              side::Symbol, tab::PaneTab)
    new_group = PaneGroup(PaneTab[tab])
    before = side === :left || side === :above
    parent = pane_parent(tree, group)
    parent === nothing && return nothing
    owner, k = parent

    # Flatten: join the parent instead of nesting a same-orientation split.
    if owner isa PaneSplit && owner.orientation === orientation
        at = before ? k : k + 1
        elements_path = pane_collection_path(tree, owner, :elements)
        weights = pane_weights(owner)
        half = weights[k] / 2
        weights[k] = half
        insert!(weights, at, half)
        # The new group is not in the tree yet, so its own path is built here:
        # the parent's element slot it lands in, then its first tab.
        pairs = _pairs_to(tree, owner)
        push!(pairs, (owner, FieldReferenceStep("elements")))
        push!(pairs, (owner.elements, ElementReferenceStep(at)))
        push!(pairs, (new_group, FieldReferenceStep("tabs")))
        push!(pairs, (new_group.tabs, ElementReferenceStep(1)))
        cursor = _reference_from(pairs, tab)
        return CompoundOperation(Any[
            insert_elements(elements_path, at - 1, Any[new_group]),
            _write_weights(tree, owner, weights),
            ReplaceSelectionOperation(cursor)])
    end

    elements = before ? Any[new_group, group] : Any[group, new_group]
    split = PaneSplit(orientation, elements; weights = [0.5, 0.5])
    write = _slot_write(tree, group, split)
    write === nothing && return nothing
    pairs = _pairs_to(tree, new_group; from = group, to = split)
    pairs === nothing && return nothing
    push!(pairs, (new_group, FieldReferenceStep("tabs")))
    push!(pairs, (new_group.tabs, ElementReferenceStep(1)))
    cursor = _reference_from(pairs, tab)
    CompoundOperation(Any[write, ReplaceSelectionOperation(cursor)])
end

# ── Move a tab ─────────────────────────────────────────────────────────────

"""
    pane_move_tab_operation(tree, source, source_index, target, target_index) -> Operation | Nothing

Move one tab from `source` to `target`. `target_index` names the slot the tab is
inserted **before**, in the target's numbering as it stands now — which is what a
drop between two tabs means, and `length(target.tabs) + 1` is a drop at the end.
Inside one group a forward move therefore lands one place earlier than
`target_index`, because the tab left its own slot first.

A move inside one group is a reorder. The tab's cell is relocated, so its content
keeps its iomap.

When the move empties the source group, the group is closed the same way
[`pane_close_tab_operation`](@ref) closes it.
"""
function pane_move_tab_operation(tree::PaneTree, source::PaneGroup, source_index::Integer,
                                 target::PaneGroup, target_index::Integer)
    n = length(source.tabs)
    (1 <= source_index <= n) || return nothing
    tab = source.tabs[source_index]
    same = source === target
    at = clamp(Int(target_index), 1, length(target.tabs) + 1)
    move = MoveRangeOperation(source.tabs, Int(source_index), Int(source_index),
                              target.tabs, at)
    # `MoveRangeOperation` compensates for the removal when both ends are the
    # same vector, so the landing index does too.
    landed = (same && at > source_index) ? at - 1 : at
    landed = clamp(landed, 1, same ? n : length(target.tabs) + 1)

    if same || n > 1
        cursor = _element_path(tree, target, :tabs, landed, tab)
        cursor === nothing && return move
        return CompoundOperation(Any[move, ReplaceSelectionOperation(cursor)])
    end

    # The source loses its last tab, so it goes away with it. The target's path
    # is named through the collapse, because the target can sit inside the very
    # sibling that replaces the source's parent.
    collapse = _collapse_writes(tree, source, target, landed, tab)
    collapse === nothing && return move
    CompoundOperation(vcat(Any[move], collapse))
end

# The writes that remove an emptied `group` from the tree, plus the cursor into
# `target`'s `index`-th tab named against the tree those writes leave behind.
function _collapse_writes(tree::PaneTree, group::PaneGroup, target::PaneGroup,
                          index::Integer, tab::PaneTab)
    parent = pane_parent(tree, group)
    parent === nothing && return nothing
    owner, k = parent
    owner === tree && return Any[]        # the root group stays, empty

    split = owner::PaneSplit
    m = length(split.elements)
    if m > 2
        elements_path = pane_collection_path(tree, split, :elements)
        weights = pane_weights(split)
        deleteat!(weights, k)
        # Every element after the dropped one moves back by one place.
        cursor = _shifted_tab_path(tree, split, k, target, index, tab)
        return filter(!isnothing, Any[delete_elements(elements_path, k - 1),
                                      _write_weights(tree, split, weights),
                                      cursor === nothing ? nothing :
                                          ReplaceSelectionOperation(cursor)])
    end

    sibling = split.elements[k == 1 ? 2 : 1]
    write = _slot_write(tree, split, sibling)
    write === nothing && return nothing
    pairs = _pairs_to(tree, target; from = split, to = sibling)
    pairs === nothing && return Any[write]
    push!(pairs, (target, FieldReferenceStep("tabs")))
    push!(pairs, (target.tabs, ElementReferenceStep(Int(index))))
    Any[write, ReplaceSelectionOperation(_reference_from(pairs, tab))]
end

# The path to `target`'s `index`-th tab after element `dropped` left `split`.
function _shifted_tab_path(tree::PaneTree, split::PaneSplit, dropped::Integer,
                           target::PaneGroup, index::Integer, tab::PaneTab)
    for i in 1:length(split.elements)
        i == dropped && continue
        inner = Any[]
        _trail_into!(split.elements[i], target, inner) || continue
        pairs = _pairs_to(tree, split)
        pairs === nothing && return nothing
        push!(pairs, (split, FieldReferenceStep("elements")))
        push!(pairs, (split.elements, ElementReferenceStep(i > dropped ? i - 1 : i)))
        append!(pairs, inner)
        push!(pairs, (target, FieldReferenceStep("tabs")))
        push!(pairs, (target.tabs, ElementReferenceStep(Int(index))))
        return _reference_from(pairs, tab)
    end
    nothing
end

# ── Drop a tab on a group's edge ───────────────────────────────────────────

"""
    pane_drop_split_operation(tree, source, source_index, target, orientation, side) -> Operation | Nothing

Split `target` and put `source`'s `source_index`-th tab in the new pane — what a
drop on a group's edge band means. The tab keeps its identity: it is moved, not
copied.

**The source must keep at least one tab.** A drop that would empty it is
declined, because the collapse of the emptied group and the split of the target
are two structural writes whose paths would each be named against the tree the
other leaves behind. Drop into the target's middle instead: that move handles the
collapse. See the plan's deferred list.
"""
function pane_drop_split_operation(tree::PaneTree, source::PaneGroup, source_index::Integer,
                                   target::PaneGroup, orientation::Symbol, side::Symbol)
    (1 <= source_index <= length(source.tabs)) || return nothing
    length(source.tabs) > 1 || return nothing
    tab = source.tabs[source_index]
    new_group = PaneGroup(PaneTab[])
    before = side === :left || side === :above
    elements = before ? Any[new_group, target] : Any[target, new_group]
    split = PaneSplit(orientation, elements; weights = [0.5, 0.5])
    write = _slot_write(tree, target, split)
    write === nothing && return nothing

    # The tab moves by identity, so this write carries the two vectors and no
    # path — it is the one member of the compound the split cannot invalidate.
    move = MoveRangeOperation(source.tabs, Int(source_index), Int(source_index),
                              new_group.tabs, 1)
    # The cursor is named against the tree the split leaves behind: the source
    # group can sit inside the very subtree that moved one level down.
    pairs = _pairs_to(tree, new_group; from = target, to = split)
    pairs === nothing && return nothing
    push!(pairs, (new_group, FieldReferenceStep("tabs")))
    push!(pairs, (new_group.tabs, ElementReferenceStep(1)))
    CompoundOperation(Any[write, move, ReplaceSelectionOperation(_reference_from(pairs, tab))])
end

# ── Resize a split ─────────────────────────────────────────────────────────

"""
    pane_resize_operation(tree, split, weights) -> Operation | Nothing

Give `split` new child weights. The weights are normalized, so a caller can pass
raw extents (the pixel sizes a splitter drag produced) and let this scale them.
"""
function pane_resize_operation(tree::PaneTree, split::PaneSplit, weights::AbstractVector)
    length(weights) == length(split.elements) || return nothing
    _write_weights(tree, split, weights)
end

# One write of the whole weights vector. The weights carry no identity anything
# depends on, so replacing the vector is simpler than splicing it, and it is the
# only form that also works when the field was empty (equal weights).
function _write_weights(tree::PaneTree, split::PaneSplit, weights::AbstractVector)
    path = pane_collection_path(tree, split, :weights)
    path === nothing && return nothing
    ReplaceReferencedValueOperation(nothing, path,
                                    CellVector(pane_normalized_weights(weights)))
end

# The write that puts `replacement` in the slot `node` occupies.
function _slot_write(tree::PaneTree, node, replacement)
    parent = pane_parent(tree, node)
    parent === nothing && return nothing
    owner, k = parent
    if owner === tree
        path = _reference_from(Any[(tree, FieldReferenceStep("root"))], replacement)
        return ReplaceReferencedValueOperation(nothing, path, replacement)
    end
    path = _element_path(tree, owner, :elements, k, replacement)
    path === nothing && return nothing
    ReplaceReferencedValueOperation(nothing, path, replacement)
end

end # module PaneSurgeryModule
