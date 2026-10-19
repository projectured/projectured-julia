# Fragment of `TreeModule` — the tree document: the document that a tree shows,
# the title of the tree, and its open nodes.

"""
    DocumentTree(root; title = format_tree_node_label(root), current = nothing)

A document that shows `root` and the documents under it as a tree, as a `Roster`
shows the items of a source as a table. The children of a node are the
documents of its collections ([`get_tree_children_steps`](@ref)), and its text
and its icon come from [`format_tree_node_label`](@ref) and
[`get_document_decoration`](@ref). `title` is the title of its tab.

`expanded` holds the open places: an `IdDict` whose keys are the documents of the
open nodes below one place, each with the `IdDict` of the open places below it.
The root is its one key. So a place is open by the identity of the documents on
its path and not by its indices: it stays open when another node comes before it,
and one document at two places opens at each place on its own. The root is open
at the start. It is view state: each write replaces the whole `IdDict` as view
state, so an undo records no open or closed node, and a file keeps the root and
the title and no open node.

`current` is the path from `root` of the node whose row has the mark of the
current page, or `nothing`: a value, a `Cell`, or a function of no argument,
whose answer the tree follows. An explorer gives the address of the page of its
navigator.

`shown` holds the documents of the rows that the view of the tree shows, which
the view writes beside each scroll and each toggle. It is view state as well. The
tree holds the documents of its open nodes and of its shown rows while it is
held, so a document that comes into view starts what it needs, such as the read
of its details, and one that leaves the view is released.

Use it to show a document and the documents under it as a tree.

# Example

    tree_1 = DocumentTree(get_edited_document(find_pane("people.json")))
    open_pane!(tree_1; title = "People tree")

See also `Roster` and `open_pane!`.
"""
@document struct DocumentTree <: Document
    root::Any
    title::String
    expanded::IdDict{Any,Any}
    shown::IdDict{Any,Nothing}
    current::Any
end

DocumentTree(root; title::AbstractString = format_tree_node_label(root), current = nothing) =
    DocumentTree(Cell(root), Cell(String(title)), Cell(IdDict{Any,Any}(root => IdDict{Any,Any}())),
                 Cell(IdDict{Any,Nothing}()), _make_current_cell(current), Cell(nothing))

_make_current_cell(current::Cell) = current
_make_current_cell(current::Function) = Cell(@computation current())
_make_current_cell(current) = Cell(current)

"""
    collect_open_tree_documents(tree) -> Vector{Any}

The documents of the open nodes of `tree`, each once, also a document that is open
at two places.

Use it to know which documents a tree holds open, as its acquire does.

# Example

    collect_open_tree_documents(DocumentTree(get_session_task_group_list()))

See also `DocumentTree`.
"""
function collect_open_tree_documents end

function collect_open_tree_documents(tree::DocumentTree)
    found = IdDict{Any,Nothing}()
    _collect_open_documents!(found, tree.expanded)
    collect(keys(found))
end

function _collect_open_documents!(found::IdDict{Any,Nothing}, places::IdDict{Any,Any})
    for (document, below) in places
        found[document] = nothing
        _collect_open_documents!(found, below)
    end
    found
end

get_document_title(tree::DocumentTree) = tree.title

"""
    make_tree_reveal_operation(tree, reference) -> Operation or nothing

The operation that opens the nodes above the node at `reference`, a path from the
root of `tree`, so its row shows: a write of the open places as view state, as a
chevron makes, and the hold of the documents of the nodes that open. A path that
goes on inside the document of a node opens the nodes above that node. `nothing`
when those nodes are open, or when `reference` names no node below the root.

Use it to show the row of a node that a person reached another way, such as by a
link on a page.

# Example

    operation_1 = make_tree_reveal_operation(tree_1, @reference(section_1, entries[1].directory.elements[2]))

See also `DocumentTree`.
"""
function make_tree_reveal_operation end

function make_tree_reveal_operation(tree::DocumentTree, reference::Reference)
    nodes = _collect_path_node_documents(tree.root, get_reference_steps(strip_reference_types(reference)))
    places = copy(tree.expanded)
    (level, is_changed) = (places, false)
    for document in nodes[1:(end - 1)]
        below = get(level, document, nothing)
        below === nothing && (is_changed = true)
        below = below === nothing ? IdDict{Any,Any}() : copy(below)
        level[document] = below
        level = below
    end
    is_changed || return nothing
    before = merge!(_collect_open_documents!(IdDict{Any,Nothing}(), tree.expanded), tree.shown)
    after = merge!(_collect_open_documents!(IdDict{Any,Nothing}(), places), tree.shown)
    acquired = Any[document for document in keys(after) if !haskey(before, document)]
    ReplaceViewStateOperation(CompoundOperation(Any[ReplaceReferencedValueOperation(tree, "expanded", places),
                                                    ChangeHeldDocumentsOperation(tree, Any[], acquired)]))
end

# The documents of the nodes on the path `steps` from `root`, the root first: at
# each node, the steps of one of its collections and the step of an element. The
# path ends at a step that names no child.
function _collect_path_node_documents(root, steps)
    nodes = Any[root]
    (document, at) = (root, 1)
    while at <= length(steps)
        found = nothing
        for (collection_steps, _) in _collect_tree_collections(document)
            index_at = at + length(collection_steps)
            index_at <= length(steps) || continue
            all(steps[at + j - 1] == collection_steps[j] for j in eachindex(collection_steps)) || continue
            index = steps[index_at]
            (index isa RangeReferenceStep && is_element_reference_step(index)) || continue
            child = try_evaluate_reference(document, extend_reference(EmptyReference(), steps[at:index_at]...),
                                           _NO_PATH_NODE)
            child === _NO_PATH_NODE || (found = (child, index_at + 1); break)
        end
        found === nothing && break
        (document, at) = found
        push!(nodes, document)
    end
    nodes
end

struct _NoPathNode end
const _NO_PATH_NODE = _NoPathNode()

# A tree holds the documents of its open nodes and of its shown rows, so a
# document whose node is open, or whose row is in view, starts what it needs, such
# as the read of a folder, while the tree is shown. A chevron and a scroll change
# what the tree holds (`ChangeHeldDocumentsOperation`). A tree whose view showed
# no row yet holds the first children of each open lazy list of children, as many
# as `_FIRST_SHOWN_CHILD_COUNT`, because no view told it which rows it shows.
function acquire_document!(editor, tree::DocumentTree)
    isempty(tree.shown) &&
        set_cell_value!(getfield(tree, :shown), _collect_first_lazy_children(tree))
    hold_documents!(editor, tree, _collect_tree_held_documents(tree))
end

release_document!(editor, tree::DocumentTree) =
    release_held_documents!(editor, tree, _collect_tree_held_documents(tree))

# The documents that `tree` holds: those of its open nodes and of its shown rows.
function _collect_tree_held_documents(tree::DocumentTree)
    found = _collect_open_documents!(IdDict{Any,Nothing}(), tree.expanded)
    collect(keys(merge!(found, tree.shown)))
end

const _FIRST_SHOWN_CHILD_COUNT = 50

# The first children of each lazy list of children of an open place whose places
# above are open, from the root, as the documents that a view of them would show.
function _collect_first_lazy_children(tree::DocumentTree)
    shown = IdDict{Any,Nothing}()
    function visit(document, places, above)
        below = get(places, document, nothing)
        (below !== nothing && !any(d -> d === document, above)) || return
        push!(above, document)
        list = _find_lazy_tree_children(document)
        if list !== nothing
            (link, count) = (list, 1)
            while true
                shown[link.value] = nothing
                visit(link.value, below, above)
                count == _FIRST_SHOWN_CHILD_COUNT && break
                link = link.next
                link === nothing && break
                count += 1
            end
        else
            # A lazy list beside another collection gives no children, so it is
            # not walked.
            for (_, collection) in _collect_tree_collections(document)
                (collection === nothing || collection isa ListNode) && continue
                foreach(child -> visit(child, below, above), collection)
            end
        end
        pop!(above)
    end
    visit(tree.root, tree.expanded, Any[])
    shown
end

# A file keeps what a tree shows, its root and its title. The open nodes are view
# state, so a tree read from a file has its root open.
pred_arguments(tree::DocumentTree) = (tree.root,), Pair{Symbol,Any}[:title => tree.title]
make_pred_document(::Type{<:DocumentTree}, positional, keywords) = DocumentTree(positional...; keywords...)
