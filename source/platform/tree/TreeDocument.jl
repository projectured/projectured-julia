# Fragment of `TreeModule` — the tree document: the document that a tree shows,
# the title of the tree, and its open nodes.

"""
    DocumentTree(root; title = format_tree_node_label(root))

A document that shows `root` and the documents under it as a tree, as a `Roster`
shows the items of a source as a table. The children of a node are the
documents of its collections ([`get_tree_children_steps`](@ref)), and its text
and its icon come from [`format_tree_node_label`](@ref) and
[`get_tree_node_icon`](@ref). `title` is the title of its tab.

`expanded` holds the open nodes: an `IdDict` whose keys are their documents, so
a node is open by the identity of its document and not by its index, and stays
open when another node comes before it. The root is open at the start. It is
view state: each write replaces the whole `IdDict` as view state, so an undo
records no open or closed node, and a file keeps the root and the title and no
open node.

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
    expanded::IdDict{Any,Nothing}
    shown::IdDict{Any,Nothing}
end

DocumentTree(root; title::AbstractString = format_tree_node_label(root)) =
    DocumentTree(Cell(root), Cell(String(title)),
                 Cell(IdDict{Any,Nothing}(root => nothing)),
                 Cell(IdDict{Any,Nothing}()), Cell(nothing))

get_document_title(tree::DocumentTree) = tree.title

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
_collect_tree_held_documents(tree::DocumentTree) =
    collect(keys(merge(IdDict{Any,Nothing}(), tree.expanded, tree.shown)))

const _FIRST_SHOWN_CHILD_COUNT = 50

# The first children of each lazy list of children of an open node whose nodes
# above are open, from the root, as the documents that a view of them would show.
function _collect_first_lazy_children(tree::DocumentTree)
    shown = IdDict{Any,Nothing}()
    function visit(document, above)
        (haskey(tree.expanded, document) && !any(d -> d === document, above)) || return
        push!(above, document)
        list = _find_lazy_tree_children(document)
        if list !== nothing
            link = list
            for _ in 1:_FIRST_SHOWN_CHILD_COUNT
                shown[link.value] = nothing
                visit(link.value, above)
                link = link.next
                link === nothing && break
            end
        else
            for (_, collection) in _collect_tree_collections(document)
                collection === nothing && continue
                foreach(child -> visit(child, above), collection)
            end
        end
        pop!(above)
    end
    visit(tree.root, Any[])
    shown
end

# A file keeps what a tree shows, its root and its title. The open nodes are view
# state, so a tree read from a file has its root open.
pred_arguments(tree::DocumentTree) = (tree.root,), Pair{Symbol,Any}[:title => tree.title]
make_pred_document(::Type{<:DocumentTree}, positional, keywords) = DocumentTree(positional...; keywords...)
