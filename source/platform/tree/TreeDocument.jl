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
end

DocumentTree(root; title::AbstractString = format_tree_node_label(root)) =
    DocumentTree(Cell(root), Cell(String(title)), Cell(IdDict{Any,Nothing}(root => nothing)), Cell(nothing))

get_document_title(tree::DocumentTree) = tree.title

# A file keeps what a tree shows, its root and its title. The open nodes are view
# state, so a tree read from a file has its root open.
pred_arguments(tree::DocumentTree) = (tree.root,), Pair{Symbol,Any}[:title => tree.title]
make_pred_document(::Type{<:DocumentTree}, positional, keywords) = DocumentTree(positional...; keywords...)
