# Fragment of `TreeModule` — a tree as code and a language model use it: the verb
# that shows one in a tab.

"""
    show_document_tree!(root; title = format_tree_node_label(root), editor = get_evaluation_editor())
        -> ReferencedDocument

Show `root` and the documents under it as a tree in a tab of the window of
`editor`, and answer the tree in its window. A node is a document, and its
children are the documents of its collections; a double click on a node, or
Return, opens its document as a page. A `DocumentTree` in place of a root is
shown with its own title.

Use it to see the parts of a nested structure at a glance: the steps of a plan
with the steps under each, the processes under a process, the agents that an
agent started.

# Example

    show_document_tree!(plan; title = "Plan")

See also `show_roster!`, which shows the members of one kind as a table.
"""
function show_document_tree!(root; title::AbstractString = format_tree_node_label(root),
                             editor = get_evaluation_editor())
    tree = root isa DocumentTree ? root : DocumentTree(root; title)
    show_document!(tree; title = tree.title, editor)
    found = search_references(editor.document, node -> node === tree; maxdepth = 24)
    isempty(found) && throw(ArgumentError(string("The window shows no tree \"", tree.title, "\" after the show.")))
    ReferencedDocument(tree, strip_reference_types(found[1]))
end
