# Fragment of `PaneModule`.
#
# The pane-tree edits, and the paths they are expressed against.
#
# **This module declares no operation type.** Each builder returns a generic
# operation — `make_insert_elements_operation`, `make_delete_elements_operation`,
# `ReplaceReferencedValueOperation`, `MoveRangeOperation`,
# `ReplaceSelectionOperation`, or a `CompoundOperation` of two of them. Every write
# leaves the operation's `document` field at `nothing`, so the reference re-roots as
# the operation bubbles up and a pane tree keeps working nested inside another
# document.
#
# **The surgery reuses node objects; it never rebuilds a subtree.** A split puts
# the *existing* group into the new split, and a collapse writes the *existing*
# sibling at the parent's slot. Only the node that goes away is dropped — a rebuilt
# subtree would drop the iomaps below it, and every tab would re-print.
#
# **Paths carry their node types as they are built.** Each `(node, step)` pair
# records the document the step descends *from*, which is what
# `ConcreteReference`'s `type` field means. This is what lets a builder name a slot
# the edit is *about to* create — a fresh tab, a collapsed sibling — which
# `annotate_reference_types` can not do, because it resolves against the tree as it
# stands now.
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
# found.
#
# `subs` is how a caller names a slot in the tree an edit is *about to* produce:
# each `old => new` swaps one node for another as the walk passes it. Several can
# be in flight at once — a drop that splits one group and collapses another needs
# both — and each fires **once**, because a replacement usually *contains* the node
# it replaces (a split wraps the group it splits, a sibling sits inside the split
# it collapses) and a second firing would walk in circles.
function _trail_into!(current, target, pairs; subs = _NO_SUBSTITUTIONS)
    subs = convert(Vector{Pair{Any,Any}}, subs)::Vector{Pair{Any,Any}}
    index = findfirst(pair -> pair.first === current, subs)
    if index !== nothing
        current = subs[index].second
        subs = [subs[j] for j in eachindex(subs) if j != index]
    end
    current === target && return true
    if current isa PaneSplit
        elements = current.elements
        for i in 1:length(elements)
            push!(pairs, (current, FieldReferenceStep("elements")))
            push!(pairs, (elements, ElementReferenceStep(i)))
            _trail_into!(elements[i], target, pairs; subs) && return true
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

const _NO_SUBSTITUTIONS = Pair{Any,Any}[]

# The pairs from `tree` down to `node`, or `nothing` when the node is not in it.
function _pairs_to(tree::PaneTree, node; from = nothing, to = nothing,
                   subs = from === nothing ? _NO_SUBSTITUTIONS : Pair{Any,Any}[from => to])
    node === tree && return Any[]
    pairs = Any[(tree, FieldReferenceStep("root"))]
    _trail_into!(tree.root, node, pairs; subs) || return nothing
    pairs
end

"""
    get_pane_path(tree, node) -> Reference | Nothing

The typed path from `tree` to `node`, or `nothing` when the node is not in the
tree.
"""
function get_pane_path(tree::PaneTree, node)
    pairs = _pairs_to(tree, node)
    pairs === nothing ? nothing : _reference_from(pairs, node)
end

"""
    get_pane_collection_path(tree, owner, field) -> Reference | Nothing

The typed path to one of `owner`'s collection fields — `:tabs` of a group,
`:elements` or `:weights` of a split. This is the path
`make_insert_elements_operation` / `make_delete_elements_operation` splice against.
"""
function get_pane_collection_path(tree::PaneTree, owner, field::Symbol)
    pairs = _pairs_to(tree, owner)
    pairs === nothing && return nothing
    push!(pairs, (owner, FieldReferenceStep(String(field))))
    _reference_from(pairs, getproperty(owner, field))
end

# The path to element `index` of `owner`'s `field`, ending on `element`. The
# element need not be there yet — its type comes from the object, not from the
# tree — so this names the slot an insert or a collapse is about to fill.
function _element_path(tree::PaneTree, owner, field::Symbol, index::Integer, element;
                       from = nothing, to = nothing,
                       subs = from === nothing ? _NO_SUBSTITUTIONS : Pair{Any,Any}[from => to])
    pairs = _pairs_to(tree, owner; subs)
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

# What a pane edit is evaluated against: the tree itself. `evaluate_operation`
# resolves a document-rooted reference against this `document` field, and a pane
# path only means anything inside the tree.
mutable struct PaneHost
    document::Any
end

"""
    apply_pane_operation!(tree, operation) -> tree

Apply a pane edit to the tree. A `nothing` operation is a no-op, which is what
`PaneSurgery` answers when the edit does not apply.
"""
function apply_pane_operation!(tree::PaneTree, operation)
    operation === nothing || evaluate_operation(PaneHost(tree), operation)
    tree
end

# ── The focus ──────────────────────────────────────────────────────────────

"""
    get_pane_focus(tree) -> (group, index) | Nothing

The focused group and the 1-based index of the tab the selection names, or `0`
for that index when the selection names the group itself. `nothing` when the
selection is not inside the tree.
"""
function get_pane_focus(tree::PaneTree)
    selection = get_selection(tree)
    selection === nothing && return nothing
    rest = _after_field(selection, "root")
    rest === nothing && return nothing
    found = _focus_walk(tree.root, rest)
    found === nothing ? nothing : (found[1], found[2])
end

"""
    get_pane_focus_title(tree) -> (group, index) | Nothing

The group and tab whose **title** the selection is inside, or `nothing` when it
is anywhere else. This is what tells a rename from ordinary editing.
"""
function get_pane_focus_title(tree::PaneTree)
    selection = get_selection(tree)
    selection === nothing && return nothing
    rest = _after_field(selection, "root")
    rest === nothing && return nothing
    found = _focus_walk(tree.root, rest)
    found === nothing && return nothing
    group, index, suffix = found
    index == 0 && return nothing
    _after_field(suffix, "title") === nothing && return nothing
    (group, index)
end

"""
    find_pane_content_selection(tree) -> Reference | Nothing

The part of the selection of `tree` inside the content of the focused tab: the
place in the document that the person works on, without the splits, the group
and the tab that lead to it. `nothing` when the selection is not inside the
content of a tab, such as on a tab title.
"""
function find_pane_content_selection(tree::PaneTree)
    selection = get_selection(tree)
    selection === nothing && return nothing
    rest = _after_field(selection, "root")
    rest === nothing && return nothing
    found = _focus_walk(tree.root, rest)
    (found === nothing || found[2] == 0) && return nothing
    _after_field(found[3], "content")
end

"""
    get_pane_focused_group(tree) -> PaneGroup | Nothing

The focused group, or `nothing` when the selection is not inside the tree.
"""
function get_pane_focused_group(tree::PaneTree)
    focus = get_pane_focus(tree)
    focus === nothing ? nothing : focus[1]
end

"""
    get_pane_focused_tab_index(tree) -> Int

The 1-based index of the focused tab, or `0` when no tab is focused.
"""
function get_pane_focused_tab_index(tree::PaneTree)
    focus = get_pane_focus(tree)
    focus === nothing ? 0 : focus[2]
end

# ── The tab title ──────────────────────────────────────────────────────────

"""
    get_pane_shown_tab_index(group) -> Int

The tab a group shows: the one its own selection names, or its first. A group
with no tab answers 0, which names the group itself.
"""
function get_pane_shown_tab_index(group::PaneGroup)
    isempty(group.tabs) && return 0
    # `get_stored_selection`, not `get_selection`: a group that lost the focus holds a
    # dormant selection, and the tab it shows is exactly what that selection names.
    index, _ = _head_index(_after_field(get_stored_selection(group), "tabs"))
    (index !== nothing && 1 <= index <= length(group.tabs)) ? index : 1
end

"""
    get_pane_tab_name_path(tree, group, index) -> Reference | Nothing

The typed path to the name in a tab's title: the text document that a rename
edits.
"""
function get_pane_tab_name_path(tree::PaneTree, group::PaneGroup, index::Integer)
    (1 <= index <= length(group.tabs)) || return nothing
    tab = group.tabs[index]
    pairs = _pairs_to(tree, group)
    pairs === nothing && return nothing
    push!(pairs, (group, FieldReferenceStep("tabs")))
    push!(pairs, (group.tabs, ElementReferenceStep(Int(index))))
    push!(pairs, (tab, FieldReferenceStep("title")))
    push!(pairs, (tab.title, FieldReferenceStep("name")))
    _reference_from(pairs, tab.title.name)
end

"""
    get_pane_content_path(tree, group, index) -> Reference | Nothing

The typed path to a tab's content document, which names the content as a whole.
"""
function get_pane_content_path(tree::PaneTree, group::PaneGroup, index::Integer)
    (1 <= index <= length(group.tabs)) || return nothing
    tab = group.tabs[index]
    pairs = _pairs_to(tree, group)
    pairs === nothing && return nothing
    push!(pairs, (group, FieldReferenceStep("tabs")))
    push!(pairs, (group.tabs, ElementReferenceStep(Int(index))))
    push!(pairs, (tab, FieldReferenceStep("content")))
    _reference_from(pairs, tab.content)
end

"""
    make_pane_title_caret_operation(tree, group, index[, position]) -> Operation | Nothing

Put the caret in a tab's title — which is the whole of what "rename" means here.
There is no rename mode and no rename operation: the title is a text document, so
the caret being in it *is* the editing state. `position` defaults to the end of
the name.
"""
function make_pane_title_caret_operation(tree::PaneTree, group::PaneGroup, index::Integer;
                                         position = nothing)
    path = get_pane_tab_name_path(tree, group, index)
    path === nothing && return nothing
    name = group.tabs[index].title.name
    at = position === nothing ? length(something(name.value, "")) : Int(position)
    ReplaceSelectionOperation(concat_references(path,
        @reference ::PrimitiveString.value::String{at}::Position))
end

"""
    make_pane_retarget_title_operation(tree, group, index; operation) -> Operation | Nothing

Re-root a title edit — an operation the title document built against its own
vocabulary — onto the tree. This is what lets the tab name be edited by the very
gestures that edit any other string, with no editing code of its own.
"""
function make_pane_retarget_title_operation(tree::PaneTree, group::PaneGroup, index::Integer;
                                            operation)
    operation isa ReplaceStringRangeOperation || return nothing
    path = get_pane_tab_name_path(tree, group, index)
    path === nothing && return nothing
    ReplaceStringRangeOperation(concat_references(path, operation.reference),
                                operation.replacement)
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
        rest === nothing && return (node, 0, path)
        index, suffix = _head_index(rest)
        index === nothing && return (node, 0, rest)
        return (node, (1 <= index <= length(node.tabs)) ? index : 0, suffix)
    end
    nothing
end

_after_field(path::ConcreteReference, name::String) =
    (path.head isa FieldReferenceStep && path.head.name == name) ? path.tail : nothing
_after_field(::Any, ::String) = nothing

_head_index(::Nothing) = (nothing, nothing)
function _head_index(path)
    path isa ConcreteReference || return (nothing, path)
    step = path.head
    step isa RangeReferenceStep || return (nothing, path)
    (Int(step.start) + 1, path.tail)
end

"""
    get_pane_tab_reference(tree, group, index) -> Reference | Nothing

The selection reference naming tab `index` of `group`, or the group itself when
`index` is 0.
"""
function get_pane_tab_reference(tree::PaneTree, group::PaneGroup, index::Integer)
    index == 0 && return get_pane_path(tree, group)
    (1 <= index <= length(group.tabs)) || return nothing
    _element_path(tree, group, :tabs, index, group.tabs[index])
end

"""
    make_pane_focus_operation(tree, group, index) -> Operation | Nothing

Move the focus to tab `index` of `group` — the whole of what focusing is. An
`index` of 0 focuses the group itself, which is what an empty group takes.
"""
function make_pane_focus_operation(tree::PaneTree, group::PaneGroup, index::Integer)
    reference = get_pane_tab_reference(tree, group, index)
    reference === nothing ? nothing : ReplaceSelectionOperation(reference)
end

# ── Open a tab ─────────────────────────────────────────────────────────────

"""
    make_pane_open_tab_operation(tree, group, tab; index) -> Operation | Nothing

Insert `tab` into `group` at the 1-based `index` (the end by default) and focus it. One
`make_insert_elements_operation` splice with its cursor move. A tab whose content is the
empty placeholder takes the selection on that content, as a whole, so a paste fills it. A
tab whose content holds a selection of its own, such as the caret of a new evaluator,
takes the focus along that selection, so the root holds the selection the document had.
"""
function make_pane_open_tab_operation(tree::PaneTree, group::PaneGroup, tab::PaneTab;
                                 index = nothing)
    tabs_path = get_pane_collection_path(tree, group, :tabs)
    tabs_path === nothing && return nothing
    n = length(group.tabs)
    at = index === nothing ? n + 1 : clamp(Int(index), 1, n + 1)
    pairs = _pairs_to(tree, group)
    pairs === nothing && return nothing
    push!(pairs, (group, FieldReferenceStep("tabs")))
    push!(pairs, (group.tabs, ElementReferenceStep(Int(at))))
    make_insert_elements_operation(tabs_path, at, Any[tab];
                                   selection = _make_new_tab_cursor(pairs, tab))
end

# Where the selection goes in a tab that is about to exist, given the pairs that
# lead to it: its content, when the content is the empty placeholder a paste
# fills; on along the content's own selection, when the content holds one; and
# the tab itself otherwise.
function _make_new_tab_cursor(pairs, tab::PaneTab)
    content = tab.content
    to_content = vcat(pairs, Any[(tab, FieldReferenceStep("content"))])
    content isa DocumentNothing && return _reference_from(to_content, content)
    own = content isa Document ? get_selection(content) : nothing
    own isa Reference || return _reference_from(pairs, tab)
    concat_references(_reference_from(to_content, content), copy_reference(own))
end

# A title no other tab carries. A person reads a title, so two panes reading the
# same is a window nobody can talk about.
function _unique_pane_title(tree::PaneTree, wanted::AbstractString)
    taken = Set(get_pane_tab_title_string(tab)
                for group in get_pane_groups(tree) for tab in group.tabs)
    String(wanted) in taken || return String(wanted)
    index = 2
    while String(wanted) * " (" * string(index) * ")" in taken
        index += 1
    end
    String(wanted) * " (" * string(index) * ")"
end

# ── Duplicate a tab ────────────────────────────────────────────────────────

# A new tab like `tab`: the duplicate of its content, its name with a number, and
# the icon that its title shows now, in its color. The badges and the tooltip say
# what the original content does, so the duplicate has none. Throws the
# `DocumentCopyException` of a content that has no duplicate.
function _make_pane_tab_duplicate(tree::PaneTree, tab::PaneTab)
    content = make_document_duplicate(tab.content)
    title = _unique_pane_title(tree, _get_pane_title_stem(get_pane_tab_title_string(tab)))
    PaneTab(PaneTabTitle(title; icon = tab.title.icon, icon_role = tab.title.icon_role), content)
end

# The title a duplicate is numbered from: the title without the number a
# duplicate got, so the duplicate of "Runner (2)" is "Runner (3)".
_get_pane_title_stem(title::AbstractString) = replace(String(title), r" \(\d+\)$" => "")

# Why a content has no duplicate, as a sentence that names what was refused:
# the content itself, or a value inside it.
_format_duplicate_refusal(content, e::DocumentCopyException) =
    e.value === content ? e.reason :
        "a $(_get_refused_word(e.value)) inside it is refused: $(e.reason)"

# A word for what was refused. A closure's type has no name a person can read.
_get_refused_word(value::Function) = "function"
_get_refused_word(value::AbstractCell) = "cell"
_get_refused_word(value) = String(nameof(typeof(value)))

"""
    make_pane_duplicate_tab_operation(tree, group, index) -> Operation | Nothing

Put a duplicate of tab `index` of `group` right after it, and focus it. The
content is copied by `make_document_duplicate`, so what the duplicate owns and
what it shares is for the kind of the content to say, and the title gets a
number.

`nothing` when there is no such tab, or when the content has no duplicate; the
refusal is logged with its reason.
"""
function make_pane_duplicate_tab_operation(tree::PaneTree, group::PaneGroup, index::Integer)
    (1 <= index <= length(group.tabs)) || return nothing
    tab = group.tabs[index]
    duplicate = try
        _make_pane_tab_duplicate(tree, tab)
    catch e
        e isa DocumentCopyException || rethrow()
        @warn "The pane has no duplicate" kind = nameof(typeof(tab.content)) reason = _format_duplicate_refusal(tab.content, e)
        return nothing
    end
    make_pane_open_tab_operation(tree, group, duplicate; index = index + 1)
end

# ── Close a tab ────────────────────────────────────────────────────────────

"""
    make_pane_close_tab_operation(tree, group, index) -> Operation | Nothing

Remove tab `index` of `group`. When it is the group's last tab the group goes
too: it is dropped from its parent split, or — when that split is left with one
element — the split is replaced by its remaining sibling. An empty root group
stays, because a tree always has a root. Then the document of the tab is
released with `ReleaseDocumentOperation`, so what it holds outside the tree,
such as the agent of an assistant, ends.
"""
function make_pane_close_tab_operation(tree::PaneTree, group::PaneGroup, index::Integer)
    n = length(group.tabs)
    (1 <= index <= n) || return nothing
    close = n > 1 ? _close_one_tab(tree, group, index, n) : _close_group(tree, group)
    close === nothing && return nothing
    CompoundOperation(Any[close, ReleaseDocumentOperation(group.tabs[index].content)])
end

function _close_one_tab(tree::PaneTree, group::PaneGroup, index::Integer, n::Integer)
    tabs_path = get_pane_collection_path(tree, group, :tabs)
    tabs_path === nothing && return nothing
    # The tab that takes the focus, named in the numbering that follows the
    # deletion: the next tab keeps this index, the last tab moves back one.
    survivor = index < n ? index + 1 : index - 1
    at = index < n ? index : index - 1
    cursor = _element_path(tree, group, :tabs, at, group.tabs[survivor])
    CompoundOperation(Any[make_delete_elements_operation(tabs_path, index),
                          ReplaceSelectionOperation(cursor)])
end

function _close_group(tree::PaneTree, group::PaneGroup)
    parent = get_pane_parent(tree, group)
    parent === nothing && return nothing
    owner, k = parent
    tabs_path = get_pane_collection_path(tree, group, :tabs)
    tabs_path === nothing && return nothing
    drop_tab = make_delete_elements_operation(tabs_path, 1)

    # The root group stays, empty. The selection names the group itself.
    if owner === tree
        cursor = get_pane_path(tree, group)
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
        elements_path = get_pane_collection_path(tree, split, :elements)
        weights = get_pane_weights(split)
        deleteat!(weights, k)
        writes = Any[drop_tab,
                     make_delete_elements_operation(elements_path, k),
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
    make_pane_split_operation(tree, group; orientation, side, tab) -> Operation | Nothing

Split `group` and put `tab` in the new pane. `orientation` is `:vertical` (the
new pane sits beside) or `:horizontal` (it sits above or below); `side` is
`:left`, `:right`, `:above`, or `:below`.

The new split takes the weight the group had, and its two children take half
each, so the rest of the layout does not move. When the parent split already has
this orientation the group is not wrapped — the new group joins the parent as a
sibling, splitting the group's weight — which is what keeps a split from ever
holding a child split of its own orientation.
"""
function make_pane_split_operation(tree::PaneTree, group::PaneGroup; orientation::Symbol,
                                   side::Symbol, tab::PaneTab)
    new_group = PaneGroup(PaneTab[tab])
    before = side === :left || side === :above
    parent = get_pane_parent(tree, group)
    parent === nothing && return nothing
    owner, k = parent

    # Flatten: join the parent instead of nesting a same-orientation split.
    if owner isa PaneSplit && owner.orientation === orientation
        at = before ? k : k + 1
        elements_path = get_pane_collection_path(tree, owner, :elements)
        weights = get_pane_weights(owner)
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
        cursor = _make_new_tab_cursor(pairs, tab)
        return CompoundOperation(Any[
            make_insert_elements_operation(elements_path, at, Any[new_group]),
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
    cursor = _make_new_tab_cursor(pairs, tab)
    CompoundOperation(Any[write, ReplaceSelectionOperation(cursor)])
end

# ── Move a tab ─────────────────────────────────────────────────────────────

"""
    make_pane_move_tab_operation(tree, source; source_index, target, target_index) -> Operation | Nothing

Move one tab from `source` to `target`. `target_index` names the slot the tab is
inserted **before**, in the target's numbering as it stands now — which is what a
drop between two tabs means, and `length(target.tabs) + 1` is a drop at the end.
Inside one group a forward move therefore lands one place earlier than
`target_index`, because the tab left its own slot first.

A move inside one group is a reorder. The tab's cell is relocated, so its content
keeps its iomap.

When the move empties the source group, the group is closed the same way
[`make_pane_close_tab_operation`](@ref) closes it.
"""
function make_pane_move_tab_operation(tree::PaneTree, source::PaneGroup;
                                      source_index::Integer, target::PaneGroup,
                                      target_index::Integer)
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
    parent = get_pane_parent(tree, group)
    parent === nothing && return nothing
    owner, k = parent
    owner === tree && return Any[]        # the root group stays, empty

    split = owner::PaneSplit
    m = length(split.elements)
    if m > 2
        elements_path = get_pane_collection_path(tree, split, :elements)
        weights = get_pane_weights(split)
        deleteat!(weights, k)
        # Every element after the dropped one moves back by one place.
        cursor = _shifted_tab_path(tree, split, k, target, index, tab)
        return filter(!isnothing, Any[make_delete_elements_operation(elements_path, k),
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
    make_pane_drop_split_operation(tree, source; source_index, target, orientation, side) -> Operation | Nothing

Split `target` and put `source`'s `source_index`-th tab in the new pane — what a
drop on a group's edge band means. The tab keeps its identity: it is moved, not
copied.

**The source may be emptied by it.** A group that loses its last tab goes away,
and its parent split goes with it when that leaves one element — so the drop is
two structural writes whose paths each have to be named against the tree the
other leaves behind. Four shapes, and each names its paths accordingly:

  * the source keeps a tab — the split is written at the target's own slot;
  * the source's parent holds it and the target and nothing else — the parent
    *is* what the new split replaces, so one write does the whole job;
  * the source's parent holds it and one other element — the split is written
    first (at a slot the collapse can not move, because a group holds nothing),
    then the sibling takes the parent's slot;
  * the source's parent holds three or more — the split is written first, then
    the source is spliced out with its weight.

`source` and `target` can be the same group, which is a tab that takes half of
its own pane. That is the first shape above, because a group that splits itself
must keep a tab behind; the drop answers `nothing` when the tab is its last.
"""
function make_pane_drop_split_operation(tree::PaneTree, source::PaneGroup;
                                        source_index::Integer, target::PaneGroup,
                                        orientation::Symbol, side::Symbol)
    (1 <= source_index <= length(source.tabs)) || return nothing
    # A group that drops its only tab on its own edge changes nothing: the tab
    # would take the new pane and leave the old half empty. With another tab
    # behind it the drop is real, and the surgery below needs no special case —
    # the new split takes the group's own slot, and the tab moves between two
    # different vectors.
    (source === target && length(source.tabs) == 1) && return nothing
    tab = source.tabs[source_index]
    new_group = PaneGroup(PaneTab[])
    before = side === :left || side === :above
    split = PaneSplit(orientation, before ? Any[new_group, target] : Any[target, new_group];
                      weights = [0.5, 0.5])
    # The tab moves by identity, so this write carries the two vectors and no
    # path — it is the one member of the compound no other write can invalidate.
    move = MoveRangeOperation(source.tabs, Int(source_index), Int(source_index),
                              new_group.tabs, 1)

    writes, subs = _drop_split_writes(tree, source, target, split)
    writes === nothing && return nothing

    pairs = _pairs_to(tree, new_group; subs)
    pairs === nothing && return CompoundOperation(vcat(writes, Any[move]))
    push!(pairs, (new_group, FieldReferenceStep("tabs")))
    push!(pairs, (new_group.tabs, ElementReferenceStep(1)))
    CompoundOperation(vcat(writes, Any[move, ReplaceSelectionOperation(_reference_from(pairs, tab))]))
end

# The structural writes a split-drop needs, and the substitutions that name the
# tree they leave behind. `nothing` when the drop can not be expressed.
function _drop_split_writes(tree::PaneTree, source::PaneGroup, target::PaneGroup,
                            split::PaneSplit)
    # The source keeps a tab: nothing goes away, so the split is all there is.
    if length(source.tabs) > 1
        write = _slot_write(tree, target, split)
        return write === nothing ? (nothing, _NO_SUBSTITUTIONS) :
               (Any[write], Pair{Any,Any}[target => split])
    end

    parent = get_pane_parent(tree, source)
    parent === nothing && return (nothing, _NO_SUBSTITUTIONS)
    owner, k = parent
    # The root group is the only group there is, so there is no target to drop on.
    owner === tree && return (nothing, _NO_SUBSTITUTIONS)

    split_parent = owner::PaneSplit
    n = length(split_parent.elements)
    if n == 2
        sibling = split_parent.elements[k == 1 ? 2 : 1]
        # The source and the target are the whole of that split: the new split
        # replaces it outright, and the source needs no write of its own.
        if sibling === target
            write = _slot_write(tree, split_parent, split)
            return write === nothing ? (nothing, _NO_SUBSTITUTIONS) :
                   (Any[write], Pair{Any,Any}[split_parent => split])
        end
        # Otherwise the sibling takes the parent's slot. The split is written
        # first: it lands in a *group's* slot, which nothing else can move.
        write = _slot_write(tree, target, split)
        collapse = _slot_write(tree, split_parent, sibling)
        (write === nothing || collapse === nothing) && return (nothing, _NO_SUBSTITUTIONS)
        return (Any[write, collapse],
                Pair{Any,Any}[target => split, split_parent => sibling])
    end

    # Three or more: the source is spliced out, and its weight with it.
    write = _slot_write(tree, target, split)
    write === nothing && return (nothing, _NO_SUBSTITUTIONS)
    elements_path = get_pane_collection_path(tree, split_parent, :elements)
    elements_path === nothing && return (nothing, _NO_SUBSTITUTIONS)
    weights = get_pane_weights(split_parent)
    deleteat!(weights, k)
    writes = filter(!isnothing, Any[write,
                                    make_delete_elements_operation(elements_path, k),
                                    _write_weights(tree, split_parent, weights)])
    # A split standing in for the parent as it will be — the same node type and
    # the surviving elements — so a path through it lands on the right index.
    survivors = Any[split_parent.elements[i] for i in 1:n if i != k]
    (writes, Pair{Any,Any}[target => split,
                           split_parent => PaneSplit(split_parent.orientation, survivors)])
end

# ── Resize a split ─────────────────────────────────────────────────────────

"""
    make_pane_resize_operation(tree, split, weights) -> Operation | Nothing

Give `split` new child weights. The weights are normalized, so a caller can pass
raw extents (the pixel sizes a splitter drag produced) and let this scale them.
"""
function make_pane_resize_operation(tree::PaneTree, split::PaneSplit, weights::AbstractVector)
    length(weights) == length(split.elements) || return nothing
    _write_weights(tree, split, weights)
end

# One write of the whole weights vector. The weights carry no identity anything
# depends on, so replacing the vector is simpler than splicing it, and it is the
# only form that also works when the field was empty (equal weights).
function _write_weights(tree::PaneTree, split::PaneSplit, weights::AbstractVector)
    path = get_pane_collection_path(tree, split, :weights)
    path === nothing && return nothing
    ReplaceReferencedValueOperation(nothing, path,
                                    CellVector(get_pane_normalized_weights(weights)))
end

# The write that puts `replacement` in the slot `node` occupies.
function _slot_write(tree::PaneTree, node, replacement; subs = _NO_SUBSTITUTIONS)
    parent = get_pane_parent(tree, node)
    parent === nothing && return nothing
    owner, k = parent
    if owner === tree
        path = _reference_from(Any[(tree, FieldReferenceStep("root"))], replacement)
        return ReplaceReferencedValueOperation(nothing, path, replacement)
    end
    path = _element_path(tree, owner, :elements, k, replacement; subs)
    path === nothing && return nothing
    ReplaceReferencedValueOperation(nothing, path, replacement)
end
