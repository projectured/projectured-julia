# Fragment of `NavigatorModule` — the navigator document: the content that it
# shows a part of, the address of that part, and the visits before and after it.

"""
    NavigatorVisit(content, address, selection)

One page that a person saw in a navigator: the `content`, the `address` of the
page in it, and the `selection` when the person left the page, as a path from
the content, or `nothing`. A visit is a value and not a document, as a
`DocumentLocator` is: Back and Forward replace one, and nothing edits it.
"""
struct NavigatorVisit
    content::Any
    address::Reference
    selection::Union{Reference, Nothing}
end

"""
    Navigator(content[, address])

A document that shows one part of `content`, its page, as a tab of a browser
shows one page of a site.

- `content` is the root that the pages are parts of: a document of any domain.
- `address` is the path of the page from `content`. The empty path shows the
  whole content.
- `back` holds the visits before the current one, the newest last, and
  `forward` the visits after it, the nearest last.

The address is state of the document, not of a projection, so it is saved with
the document and a program or the assistant reads it as any field. A move to
another page writes it as view state, so undo records none of it. See
[`make_navigator_open_operation`](@ref), [`make_navigator_back_operation`](@ref),
[`make_navigator_forward_operation`](@ref) and
[`make_navigator_parent_operation`](@ref).

# Example

    navigator = Navigator(frame_view, @reference(frame_view, rows[42]))
"""
@document struct Navigator <: Document
    content::Any
    address::Reference = EmptyReference()
    back::Vector{NavigatorVisit} = NavigatorVisit[]
    forward::Vector{NavigatorVisit} = NavigatorVisit[]
end

# A navigator shows a part of its content, so the document that a person edits in
# it is the content.
get_edited_field(::Navigator) = :content

# A navigator is called by its page, as a tab of a browser is called by the page
# that it shows.
function get_document_title(navigator::Navigator)
    title = get_document_title(get_navigator_page(navigator))
    title === nothing ? get_document_title(navigator.content) : title
end
