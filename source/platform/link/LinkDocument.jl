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

# A tree, an address and a tab name a link as its face, with the icon of its target.
format_tree_node_label(link::Link) = format_link_label(link)
get_document_title(link::Link) = format_link_label(link)
get_document_decoration(link::Link) = DocumentDecoration(; icon = _get_target_icon(link.target))

"""
    Url(address)

An address as the web writes it, and a link to itself, so an address shows as a
link wherever it stands. An absolute address names a place outside the editor,
such as `https://julialang.org` or `mailto:someone@example.org`, and a click opens
it in the program of the system for it, such as the browser. A `file:` address
names a file, which opens in a tab. A relative address, such as `#install` or
`guide.md`, names a place that the page of the link resolves against itself, as
a browser resolves a relative link against its page.

The page of an address, for "Open as a page", shows the address and the command
that opens it.

Use it for a link to the web, to a mail address, or to a file by its address.

# Example

    Url("https://julialang.org")
    Link(Url("https://julialang.org"); content = "Julia")

See also `OpenUrlOperation` and `is_absolute_url`.
"""
@document struct Url
    address::String
end

is_link(::Url) = true
get_link_target(url::Url) = url

_format_target_label(url::Url) = String(url.address)
_describe_target(url::Url) = String(url.address)
format_tree_node_label(url::Url) = String(url.address)
get_document_title(url::Url) = String(url.address)
get_document_decoration(::Url) = DocumentDecoration(; icon = :external_link)

"""
    UrlView(url)

The page of an address: the view document that a navigator shows for a `Url`,
with the address and the command that opens it.
"""
@document struct UrlView
    url::Any
end

get_edited_field(::UrlView) = :url
make_document_view(url::Url) = UrlView(url)
