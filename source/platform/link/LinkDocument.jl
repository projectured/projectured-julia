# Fragment of `LinkModule` — the general link: a document that any document can
# hold, with a target and a face.

"""
    Link(target; content = nothing)

A link that any document can hold: it refers to `target` and shows `content`.
`target` is a document, or a place in a document as a `DocumentLocator`. The link
holds it directly, as an edge of the graph of the documents, and a save writes it
as a node, or as a marker of the place where the file owns it. `content` is
`nothing` for the name and the icon of the target, a string such as an alias, or
a document to draw.

A search of a document that holds a link finds the content of the link, and does
not go through the link into its target.

Use it to put a link to a part into a note, a list or a dashboard.

# Example

    Link(page)                          # the name and the icon of `page`
    Link(page; content = "the list")    # an alias

See also `is_link`, `format_link_label` and `WidgetLink`.
"""
@document struct Link
    target::Any
    content::Any
end

Link(target; content = nothing) = Link(Cell(target), Cell(content))

is_link(::Link) = true
get_link_target(link::Link) = link.target
get_link_content(link::Link) = link.content

# A search finds the target where its own document holds it.
is_field_walked(::Link, name::Symbol) = name !== :target

# A tree names a link as its face, with the icon of its target.
format_tree_node_label(link::Link) = format_link_label(link)
get_document_decoration(link::Link) = DocumentDecoration(; icon = _get_target_icon(link.target))
