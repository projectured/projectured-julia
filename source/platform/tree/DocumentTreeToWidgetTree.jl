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
then. Return on a node, or a double click on it, answers `OpenPageOperation` at
the path of its document.
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
# stays at one path.
struct _TreeEntry
    document::Any
    path::Vector{Int}
    entries::CellVector
    nodes::CellVector
end

# The entry of `document` at the index path `path`. The widget node of a child
# reads the text and the icon of its document, and takes its children from the
# entry of the child: so a change of the text of one document computes its own
# node again, and the nodes under it stay.
function _make_tree_entry(document, path::Vector{Int})
    entries = CellVector(@computation(1:_count_tree_children(document));
                         element = k -> _make_tree_entry(_get_tree_child(document, k), vcat(path, k)))
    nodes = CellVector(@computation(1:length(entries)); element = k -> _make_tree_node(entries[k]))
    _TreeEntry(document, path, entries, nodes)
end

_make_tree_node(entry::_TreeEntry) =
    WidgetTreeNode(get_tree_node_icon(entry.document), _format_node_line(entry.document),
                   entry.nodes; gestures = _make_open_page_bindings(entry.path),
                   has_children = () -> has_tree_children(entry.document) === true)

# The text of a node is one line: each line break of the label, with the blanks
# around it, is a space.
_format_node_line(document) =
    replace(format_tree_node_label(document), r"\s*\R\s*" => " ")

# Each collection of the children of `document`, with the steps that reach it, or
# `nothing` for a path that reaches nothing.
_collect_tree_collections(document) =
    Any[steps => try_evaluate_reference(document, extend_reference(EmptyReference(), steps...), nothing)
        for steps in get_tree_children_steps(document)]

_get_collection_length(collection) = collection === nothing ? 0 : length(collection)

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

# The entry at the index path `path` from the root entry, or `nothing`.
function _find_tree_entry(root::_TreeEntry, path)
    (isempty(path) || path[1] != 1) && return nothing
    entry = root
    for k in path[2:end]
        (1 <= k <= length(entry.entries)) || return nothing
        entry = entry.entries[k]
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
    for k in 1:length(entry.entries)
        _collect_open_paths!(paths, entry.entries[k], open, above)
    end
    pop!(above)
    nothing
end

# The write of the open nodes of the widget that a chevron makes, as a write of the
# open nodes of the tree document: the documents of the nodes at the paths that
# the write gives, so the tree holds no document that left it. The tree then holds
# the documents of the nodes that open and no longer those of the nodes that
# close, in the same write of view state, so an undo records neither. `nothing`
# for any other answer.
function _read_open_node_write(iomap::DocumentTreeToWidgetTreeIoMap, operation)
    operation isa ReplaceViewStateOperation || return nothing
    write = get_wrapped_operation(operation)
    (write isa ReplaceReferencedValueOperation && write.document === iomap.output) || return nothing
    steps = get_reference_steps(strip_reference_types(write.reference))
    (length(steps) == 1 && steps[1] == FieldReferenceStep("expanded")) || return nothing
    root = iomap.root_entry
    open = IdDict{Any,Nothing}()
    for path in write.value
        entry = _find_tree_entry(root, path)
        entry === nothing || (open[entry.document] = nothing)
    end
    tree = iomap.input
    before = tree.expanded
    opened = Any[document for document in keys(open) if !haskey(before, document)]
    closed = Any[document for document in keys(before) if !haskey(open, document)]
    open_write = ReplaceReferencedValueOperation(tree, "expanded", open)
    isempty(opened) && isempty(closed) && return ReplaceViewStateOperation(open_write)
    ReplaceViewStateOperation(CompoundOperation(Any[open_write, ChangeHeldDocumentsOperation(tree, closed, opened)]))
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
    # horizontal_scroll_bar, tooltip, anchor, selection, mouse target. The open nodes
    # follow the tree document. The tree scrolls itself in the slot that its
    # parent offers.
    widget = WidgetTree(Cell(Point2D(0, 0)), roots, Cell(true),
                        Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing),
                        Cell(@computation _compute_open_paths(root_entry[], tree.expanded)),
                        Cell(GestureBinding[]), Cell(Point2D(0, 0)), Cell(:auto), Cell(:auto),
                        Cell(nothing), Cell(nothing), paths.selection, paths.mouse_target)
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
    answer = _read_open_node_write(iomap, payload)
    answer === nothing && (answer = invoke(read_intent, Tuple{Projection,Any,Any}, p, iomap, payload))
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
        place = _find_tree_child_place(entry.document, k)
        place === nothing && return nothing
        (collection_steps, _, i) = place
        append!(steps, collection_steps)
        push!(steps, ElementReferenceStep(i))
        entry = entry.entries[k]
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
