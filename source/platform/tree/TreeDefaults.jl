# Fragment of `TreeModule` — the fallback behaviours of the generics of
# `TreeInterface.jl`, so any document is a leaf with a label.

# A document has no children unless its slice says so.
get_tree_children_steps(document) = ()

# The title of a document, or the name of its type, as a column `type` of a roster
# names it.
function format_tree_node_label(document)
    title = get_document_title(document)
    title === nothing || return string(title)
    document isa Document ? compute_item_facet(document, Val(:type)) : string(nameof(typeof(document)))
end

# A part that a verb answered has the label of its document.
format_tree_node_label(part::ReferencedDocument) = format_tree_node_label(get_document(part))

# A node has children when a collection of its children has an element, or when
# its children are a lazy list, which has a node at its head.
has_tree_children(document) =
    _count_tree_children(document) > 0 || _find_lazy_tree_children(document) !== nothing

# A kind whose children are in memory asks for nothing.
demand_tree_children(document) = nothing

# No kind is in the list of `+` of an explorer unless its slice puts it there.
is_explorer_entry_type(::Type) = false
