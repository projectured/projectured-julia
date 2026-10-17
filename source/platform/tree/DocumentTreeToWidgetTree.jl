# Fragment of `TreeModule` — what a tree document shows: one `WidgetTree` whose
# nodes are the documents under the root, the maps between a path of the tree
# document and a node of the widget, the open nodes by identity, and the gestures
# that open a node as a page.
#
# The root document is the one root node, `roots[1]`. A node at
# `roots[1].children[k]…` is the document at `root.<steps of a collection>[i]…`,
# where `k` counts the children of all the collections of its parent, one
# collection after the other.

"""
    DocumentTreeToWidgetTree()

Prints a [`DocumentTree`](@ref) as one `WidgetTree`, which scrolls itself in the
slot that its parent offers. Each node computes from its own document: its text
([`format_tree_node_label`](@ref)), its icon ([`get_tree_node_icon`](@ref)), and
its children, the documents of its collections ([`get_tree_children_steps`](@ref)),
which a node reads only when the tree draws it or opens it. So a change of one
document draws its own node again, and no other.

The open nodes of the widget follow `expanded` of the tree document, and a press
on a chevron writes `expanded` with the documents of the nodes that are open
then. A scroll and a toggle of the widget write `shown` of the tree document with
the documents of the rows that its view shows, and the tree holds the open and
the shown documents.

Return on a node, or a double click on it, answers `OpenPageOperation` at the
path of its document.
"""
struct DocumentTreeToWidgetTree <: Projection end

@iomap struct DocumentTreeToWidgetTreeIoMap
    projection::Any
    input::Any          # DocumentTree
    output::Any         # WidgetTree
    root_entry::Any     # the entry of the root node
end

# ── The nodes ────────────────────────────────────────────────────────────────

# One node of a tree as its documents give it: the document, the index path of
# the node in the tree, the entries of its children, and the widget nodes of its
# children. Both lists compute one element at a time, at its first read. A change
# of the collections of a node makes new entries for its children, so an entry
# stays at one path. For a document whose children are a lazy list, `mirror` holds
# a `_TreeMirror` of that list (`_compute_tree_children_lists!`).
# The lazy list of the children of a document and the two lists that mirror it,
# with the count and the node of the entries of the last child that a lookup made,
# so the next lookup near it walks from there.
mutable struct _TreeMirror
    list::ListNode
    entries::ListNode
    nodes::ListNode
    cursor::Int
    cursor_link::ListNode
end

struct _TreeEntry
    document::Any
    path::Vector{Int}
    entries::CellVector
    nodes::CellVector
    mirror::Base.RefValue{Any}
end

# The entry of `document` at the index path `path`. The widget node of a child
# reads the text and the icon of its document, and takes its children from the
# entry of the child: so a change of the text of one document computes its own
# node again, and the nodes under it stay.
function _make_tree_entry(document, path::Vector{Int})
    entries = CellVector(@computation(1:_count_tree_children(document));
                         element = k -> _make_tree_entry(_get_tree_child(document, k), vcat(path, k)))
    nodes = CellVector(@computation(1:length(entries)); element = k -> _make_tree_node(entries[k]))
    _TreeEntry(document, path, entries, nodes, Ref{Any}(nothing))
end

function _make_tree_node(entry::_TreeEntry)
    (_, nodes) = _compute_tree_children_lists!(entry)
    label = _format_node_line(entry.document)
    WidgetTreeNode(get_tree_node_icon(entry.document), label, nodes;
                   gestures = _make_open_page_bindings(entry.path),
                   has_children = () -> has_tree_children(entry.document) === true)
end

# The lazy list of the children of `document`: its one collection of children,
# when that collection is a `ListNode`, or `nothing`. A lazy list has no count,
# so it is the only collection of its node; a lazy list beside another
# collection gives no children.
function _find_lazy_tree_children(document)
    collections = _collect_tree_collections(document)
    length(collections) == 1 || return nothing
    collection = last(only(collections))
    collection isa ListNode ? collection : nothing
end

# The entries and the nodes of the children of `entry`: its laid-out lists, or, for
# a document whose children are a lazy list, two lists that mirror that list node
# for node, made when a walk first reaches a node, and made again when the
# document gives a new list. The count of a child in a lazy list is its count
# from the head of the list.
function _compute_tree_children_lists!(entry::_TreeEntry)
    list = _find_lazy_tree_children(entry.document)
    list === nothing && return (entry.entries, entry.nodes)
    mirror = entry.mirror[]
    mirror !== nothing && mirror.list === list && return (mirror.entries, mirror.nodes)
    make_entry(link, k, _, _) = _make_tree_entry(link.value, vcat(entry.path, k))
    entries = make_mapped_list(make_entry, list; computed = true)
    make_node(link, _, _, _) = _make_tree_node(link.value)
    nodes = make_mapped_list(make_node, entries; computed = true)
    entry.mirror[] = _TreeMirror(list, entries, nodes, 1, entries)
    (entries, nodes)
end

# Each node of the list `source` of a document from its head on, as far as the
# walks of that list reached, with the node of `mirror` at the same count, until
# `f(document, mirror_link)` answers `false`. It reads no link of `source` that no
# walk read, so it makes no node of the document; the mirror makes the nodes of
# what `source` has, and a value of the mirror is made only when `f` reads it. The
# walks of a list of a document stay when the document prints again, so a second
# print finds what the first one reached.
function _foreach_made_mirror_link(f, source::ListNode, mirror::ListNode)
    (from, to) = (source, mirror)
    while true
        f(from.value, to) || return nothing
        cell = getfield(from, :next)
        is_cell_valid(cell) || return nothing
        from = cell[]
        from === nothing && return nothing
        to = to.next
    end
end

# The entry of the child `k` of `entry`, or `nothing`. A child of a lazy list counts
# from its head, and is found only when a walk of the list of the document reached
# it; with `make`, the walk to it makes it.
function _find_child_entry_at(entry::_TreeEntry, k::Int; make::Bool = false)
    (entries, _) = _compute_tree_children_lists!(entry)
    entries isa ListNode || return 1 <= k <= length(entries) ? entries[k] : nothing
    k >= 1 || return nothing
    if make
        # The rows of a view are near each other, so the walk starts at the child
        # that the last lookup made.
        mirror = entry.mirror[]
        (at, link) = (mirror.cursor, mirror.cursor_link)
        while at != k
            link = at < k ? link.next : link.prev
            link === nothing && return nothing
            at += at < k ? 1 : -1
        end
        (mirror.cursor, mirror.cursor_link) = (k, link)
        return link.value
    end
    found = Ref{Any}(nothing)
    count = Ref(0)
    source = _find_lazy_tree_children(entry.document)
    _foreach_made_mirror_link(source, entries) do _, link
        count[] += 1
        count[] == k && (found[] = link.value)
        count[] < k
    end
    found[]
end

# The text of a node is one line: each line break of the label, with the blanks
# around it, is a space.
_format_node_line(document) =
    replace(format_tree_node_label(document), r"\s*\R\s*" => " ")

# Each collection of the children of `document`, with the steps that reach it, or
# `nothing` for a path that reaches nothing.
_collect_tree_collections(document) =
    Any[steps => try_evaluate_reference(document, extend_reference(EmptyReference(), steps...), nothing)
        for steps in get_tree_children_steps(document)]

# A lazy list has no count, so it gives no laid-out child.
_get_collection_length(collection) =
    collection === nothing || collection isa ListNode ? 0 : length(collection)

_count_tree_children(document) =
    sum((_get_collection_length(last(entry)) for entry in _collect_tree_collections(document)); init = 0)

# The collection of the child `k` of `document`, the steps that reach it, and the
# index of the child in it, or `nothing` past the last child.
function _find_tree_child_place(document, k::Int)
    for (steps, collection) in _collect_tree_collections(document)
        count = _get_collection_length(collection)
        k <= count && return (steps, collection, k)
        k -= count
    end
    nothing
end

function _get_tree_child(document, k::Int)
    (_, collection, i) = _find_tree_child_place(document, k)
    collection[i]
end

"""
    collect_tree_children(document; limit) -> Vector{Pair{Reference,Any}}

The first `limit` children of `document` as a node of a tree, each with its path
from `document`: the elements of its collections, one collection after the other
([`get_tree_children_steps`](@ref)). A lazy list gives its first nodes from its
head, so a list with no end gives `limit` children and is read no further.

Use it to show the first children of a document beside it, as the page of a
section of an explorer does.

# Example

    collect_tree_children(get_session_task_group_list(); limit = 5)

See also `get_tree_children_steps` and `DocumentTree`.
"""
function collect_tree_children end

function collect_tree_children(document; limit::Integer)
    found = Pair{Reference,Any}[]
    for (steps, collection) in _collect_tree_collections(document)
        rest = limit - length(found)
        rest <= 0 && break
        collection === nothing && continue
        values = collection isa ListNode ? take_first(collection, rest) :
                 Any[collection[k] for k in 1:min(length(collection), rest)]
        for (k, value) in enumerate(values)
            push!(found, extend_reference(EmptyReference(), steps..., ElementReferenceStep(k)) => value)
        end
    end
    found
end

# The entry at the index path `path` from the root entry, or `nothing`.
function _find_tree_entry(root::_TreeEntry, path; make::Bool = false)
    (isempty(path) || path[1] != 1) && return nothing
    entry = root
    for k in path[2:end]
        entry = _find_child_entry_at(entry, k; make)
        entry === nothing && return nothing
    end
    entry
end

# The two gestures that open the document of a node as a page: Return while its
# row is selected, and a double click on its row. A first press still selects the
# row, because only a press with a count of two matches. A node answers in the
# frame of the widget, so the open names the node by its path there.
function _make_open_page_bindings(path::Vector{Int})
    make_operation = (node, event) -> OpenPageOperation(nothing, _make_node_reference(path))
    is_applicable = (node, selection) -> true
    GestureBinding[
        GestureBinding(KeyPressPattern('\n'), make_operation;
                       applicable = is_applicable, description = "Open as a page", domain = "tree"),
        GestureBinding(MouseClickPattern(:left; guard = event -> event.count == 2, label = "double click"),
                       make_operation; applicable = is_applicable, description = "Open as a page",
                       domain = "tree"),
    ]
end

# ── The open nodes ───────────────────────────────────────────────────────────

# The index paths of the open nodes: from the root, through the open nodes only,
# each node whose document is in `open`. A document that is on the path to its
# own node again stays closed there, so a cycle of documents ends.
function _compute_open_paths(root::_TreeEntry, open)
    paths = Set{Vector{Int}}()
    _collect_open_paths!(paths, root, open, Any[])
    paths
end

function _collect_open_paths!(paths, entry::_TreeEntry, open, above)
    (haskey(open, entry.document) && !any(document -> document === entry.document, above)) || return
    push!(paths, entry.path)
    push!(above, entry.document)
    (entries, _) = _compute_tree_children_lists!(entry)
    if entries isa ListNode
        # Only a child that a walk of the list of the document reached can be open:
        # an open child showed its row.
        source = _find_lazy_tree_children(entry.document)
        _foreach_made_mirror_link(source, entries) do document, link
            haskey(open, document) && _collect_open_paths!(paths, link.value, open, above)
            true
        end
    else
        for k in 1:length(entries)
            _collect_open_paths!(paths, entries[k], open, above)
        end
    end
    pop!(above)
    nothing
end

# The writes of the open nodes and of the shown rows of the widget, which a chevron
# and a scroll make, as writes of the tree document: the documents of the nodes
# at the paths that each write gives, so the tree holds no document that left it.
# The tree then holds the documents of its open nodes and of its shown rows
# together, and no longer those that left both, in the same write of view state,
# so an undo records none of it. The answer is that write and the other parts of
# the operation, such as a scroll, which the reader maps as it maps any answer;
# the write of the shown rows of the widget stays among them, so the widget keeps
# the rows that it wrote. `nothing` for an operation that writes neither.
function _read_open_node_write(iomap::DocumentTreeToWidgetTreeIoMap, operation)
    parts = operation isa CompoundOperation ? operation.operations : Any[operation]
    (open_paths, shown_paths, others) = (nothing, nothing, Any[])
    for part in parts
        (name, value) = _find_widget_view_write(iomap, part)
        name == "expanded" && (open_paths = value; continue)
        name == "shown" && (shown_paths = value)
        push!(others, part)
    end
    (open_paths === nothing && shown_paths === nothing) && return nothing
    tree = iomap.input
    root = iomap.root_entry
    open = open_paths === nothing ? tree.expanded :
           _collect_entry_documents(root, open_paths)
    shown = shown_paths === nothing ? tree.shown :
            _collect_entry_documents(root, shown_paths; make = true)
    writes = Any[]
    open_paths === nothing ||
        push!(writes, ReplaceReferencedValueOperation(tree, "expanded", open))
    shown_paths === nothing ||
        push!(writes, ReplaceReferencedValueOperation(tree, "shown", shown))
    before = merge(IdDict{Any,Nothing}(), tree.expanded, tree.shown)
    after = merge(IdDict{Any,Nothing}(), open, shown)
    acquired = Any[document for document in keys(after) if !haskey(before, document)]
    released = Any[document for document in keys(before) if !haskey(after, document)]
    (isempty(acquired) && isempty(released)) ||
        push!(writes, ChangeHeldDocumentsOperation(tree, released, acquired))
    held = ReplaceViewStateOperation(length(writes) == 1 ? only(writes) :
                                     CompoundOperation(writes))
    (held, others)
end

# The name and the value of a write of view state of one field of the widget,
# `("expanded", paths)` or `("shown", paths)`, else `(nothing, nothing)`.
function _find_widget_view_write(iomap::DocumentTreeToWidgetTreeIoMap, operation)
    operation isa ReplaceViewStateOperation || return (nothing, nothing)
    write = get_wrapped_operation(operation)
    (write isa ReplaceReferencedValueOperation && write.document === iomap.output) ||
        return (nothing, nothing)
    steps = get_reference_steps(strip_reference_types(write.reference))
    (length(steps) == 1 && steps[1] isa FieldReferenceStep) || return (nothing, nothing)
    name = steps[1].name
    name in ("expanded", "shown") ? (name, write.value) : (nothing, nothing)
end

# The documents of the nodes at the index paths `paths`, by identity. With `make`,
# a child of a lazy list that no walk reached yet is made, as for a row that comes
# into view.
function _collect_entry_documents(root::_TreeEntry, paths; make::Bool = false)
    documents = IdDict{Any,Nothing}()
    for path in paths
        entry = _find_tree_entry(root, path; make)
        entry === nothing || (documents[entry.document] = nothing)
    end
    documents
end

# ── Printer ──────────────────────────────────────────────────────────────────

function print_document(p::DocumentTreeToWidgetTree, recursion, tree::DocumentTree, ctx)
    root_entry = Cell(@computation _make_tree_entry(tree.root, [1]))
    # The paths of the widget, its selection and its mouse target, are the forward
    # images of those of the tree document: a node, or a part that the view drew.
    paths = make_output_path_cells(tree, path -> _map_tree_path_forward(p, root_entry[], path))
    roots = CellVector(Cell[Cell(@computation _make_tree_node(root_entry[]))])
    # Positional, so every declared field is named here in order and the paths
    # come last: position, roots, visible, margin, border, padding, style,
    # expanded, gestures, scroll_position, vertical_scroll_bar,
    # horizontal_scroll_bar, tooltip, anchor, shown, selection, mouse target.
    # The open nodes follow the tree document. The tree scrolls itself in the slot
    # that its parent offers.
    widget = WidgetTree(Cell(Point2D(0, 0)), roots, Cell(true),
                        Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                        Cell(@computation _compute_open_paths(root_entry[], tree.expanded)),
                        Cell(GestureBinding[]), Cell(Point2D(0, 0)), Cell(:auto), Cell(:auto),
                        Cell(nothing), Cell(nothing), Cell(Set{Vector{Int}}()),
                        paths.selection, paths.mouse_target)
    DocumentTreeToWidgetTreeIoMap(p, tree, widget, root_entry)
end

# ── Reader ───────────────────────────────────────────────────────────────────

# A chevron writes the open nodes of the tree document. Every other answer maps
# back as through any projection: the path of a node to the path of its document.
function read_intent(p::DocumentTreeToWidgetTree, recursion, change::Intent,
                     iomap::DocumentTreeToWidgetTreeIoMap)
    change.route === nothing ||
        return invoke(read_intent, Tuple{Projection,Any,Intent,Any}, p, recursion, change, iomap)
    payload = change.operation === nothing ? change.gesture : change.operation
    map_answer(answer) = invoke(read_intent, Tuple{Projection,Any,Any}, p, iomap, answer)
    read = _read_open_node_write(iomap, payload)
    answer = if read === nothing
        map_answer(payload)
    else
        (held, others) = read
        rest = length(others) == 1 ? only(others) : CompoundOperation(others)
        mapped = isempty(others) ? nothing : map_answer(rest)
        mapped === nothing ? held : CompoundOperation(Any[held, mapped])
    end
    Intent(change.gesture, answer, change.description, change.domain)
end

read_intent(p::DocumentTreeToWidgetTree, iomap::DocumentTreeToWidgetTreeIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping ────────────────────────────────────────────────────────

# `roots[1].children[k]…` of the index path `path`.
function _make_node_reference(path::Vector{Int})
    steps = Any[FieldReferenceStep("roots"), ElementReferenceStep(path[1])]
    for k in path[2:end]
        push!(steps, FieldReferenceStep("children"), ElementReferenceStep(k))
    end
    extend_reference(EmptyReference(), steps...)
end

# The index path of a node path `roots[1].children[k]…` of the widget, or `nothing`
# for any other path.
function _find_node_indices(reference)
    reference isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    (isempty(steps) || isodd(length(steps))) && return nothing
    indices = Int[]
    for (n, at) in enumerate(1:2:length(steps))
        field, index = steps[at], steps[at + 1]
        (field == FieldReferenceStep(n == 1 ? "roots" : "children") &&
         index isa RangeReferenceStep && is_element_reference_step(index)) || return nothing
        push!(indices, index.start + 1)
    end
    indices
end

# The entry of the child of `entry` that `steps` name from `at` on: the steps of a
# collection of its document and an index in it. The answer is the entry and the
# place after those steps, or `nothing`.
function _find_child_entry(entry::_TreeEntry, steps, at::Int)
    if _find_lazy_tree_children(entry.document) !== nothing
        (collection_steps, _) = only(_collect_tree_collections(entry.document))
        index_at = at + length(collection_steps)
        index_at <= length(steps) || return nothing
        is_step(j) = steps[at + j - 1] == collection_steps[j]
        all(is_step, eachindex(collection_steps)) || return nothing
        index = steps[index_at]
        index isa RangeReferenceStep || return nothing
        is_element_reference_step(index) || return nothing
        child = _find_child_entry_at(entry, index.start + 1)
        return child === nothing ? nothing : (child, index_at + 1)
    end
    offset = 0
    for (collection_steps, collection) in _collect_tree_collections(entry.document)
        count = _get_collection_length(collection)
        index_at = at + length(collection_steps)
        if index_at <= length(steps) &&
           all(steps[at + j - 1] == collection_steps[j] for j in eachindex(collection_steps))
            index = steps[index_at]
            if index isa RangeReferenceStep && is_element_reference_step(index) && 1 <= index.start + 1 <= count
                return (entry.entries[offset + index.start + 1], index_at + 1)
            end
        end
        offset += count
    end
    nothing
end

# The node of the path `reference` of the tree document: the node of each document
# on the path, and the row of its node for a path that goes on inside a document.
# A path outside the root has no image, and the tree document itself is the
# widget itself.
function _map_node_path_forward(root::_TreeEntry, reference)
    reference isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    isempty(steps) && return EmptyReference()
    steps[1] == FieldReferenceStep("root") || return nothing
    entry, at = root, 2
    while at <= length(steps)
        found = _find_child_entry(entry, steps, at)
        found === nothing && break
        entry, at = found
    end
    _make_node_reference(entry.path)
end

_map_tree_path_forward(p::DocumentTreeToWidgetTree, root::_TreeEntry, reference) =
    something(find_introduced_path(p, reference), Some(_map_node_path_forward(root, reference)))

map_reference_forward(p::DocumentTreeToWidgetTree, iomap::DocumentTreeToWidgetTreeIoMap, reference) =
    _map_tree_path_forward(p, iomap.root_entry, reference)

# A node path of the widget maps to the path of its document, `root.<steps of a
# collection>[i]…`; one that reaches no node has no image. Any other part of the
# widget, the widget itself as well, is a part that the view drew: an introduced
# reference names it.
function map_reference_backward(p::DocumentTreeToWidgetTree, iomap::DocumentTreeToWidgetTreeIoMap, reference)
    reference isa Reference || return nothing
    indices = _find_node_indices(reference)
    indices === nothing && return make_introduced_reference(p, iomap, strip_reference_types(reference))
    indices[1] == 1 || return nothing
    entry = iomap.root_entry
    steps = Any[FieldReferenceStep("root")]
    for k in indices[2:end]
        if _find_lazy_tree_children(entry.document) !== nothing
            # A child of a lazy list is its node `k` from the head of the list.
            (collection_steps, _) = only(_collect_tree_collections(entry.document))
            i = k
        else
            place = _find_tree_child_place(entry.document, k)
            place === nothing && return nothing
            (collection_steps, _, i) = place
        end
        append!(steps, collection_steps)
        push!(steps, ElementReferenceStep(i))
        child = _find_child_entry_at(entry, k)
        child === nothing && return nothing
        entry = child
    end
    extend_reference(EmptyReference(), steps...)
end

# ── Registration ─────────────────────────────────────────────────────────────

# A tree document draws as its widget, which a widget renderer of its own draws,
# as the tree of the files does, inside any document that a renderer draws.
make_graphics_projection(::Type{DocumentTree}; measure, appearance) =
    ChainingProjection(DocumentTreeToWidgetTree(), RecursiveProjection(FaultCatchingProjection(
        inner = WidgetToGraphics(; measure, theme = get_scaled_theme!(appearance, WidgetTheme),
                                 graphics_theme = get_scaled_theme!(appearance, GraphicsTheme)),
        substitute = FaultToGraphics())))
