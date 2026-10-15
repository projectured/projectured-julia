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

# A document shows no icon unless its slice gives one.
get_tree_node_icon(document) = nothing
