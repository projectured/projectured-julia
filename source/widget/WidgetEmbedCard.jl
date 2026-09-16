# Fragment of `WidgetModule`.
#
# The card an embedded document stands in on a page of another domain.
#
# A page — markdown, RST — is a stack of blocks, and a block that belongs to
# another domain is where the page stops and something else starts. The card
# says so: it is titled, and a person can fold it. It is not part of the page.
# A page's layout projection builds it, once for the block, and it lives only
# in the projected tree. It costs one reference step, the card's `content`,
# which the page's two maps add and drop with the two functions below.
#
# Which block stands in a card, and what its title says, is the page's to
# decide: this fragment knows a card and nothing about a file or a domain.

"""
    make_embed_card(document, title) -> WidgetCard

A foldable card whose body is `document` and whose header says `title`. The
card's selection is the document's own, under the card's `content` step, so a
key the page routes to the card reaches the document.
"""
function make_embed_card(document, title::AbstractString)
    card = WidgetCard(Point2D(0, 0); title = WidgetLabel(Point2D(0, 0), String(title)),
                      content = document, collapsible = true)
    set_cell_function!(getfield(card, :selection), () -> begin
        inner = hasproperty(document, :selection) ? getfield(document, :selection)[] : nothing
        inner === nothing ? nothing : ConcreteReference(FieldReferenceStep("content"), inner)
    end)
    card
end

"""
    make_embed_card_path(reference) -> Reference

A path into an embedded document, as a path into the card it stands in. The
whole document is the whole card, so an empty path stays empty.
"""
make_embed_card_path(reference::EmptyReference) = reference
make_embed_card_path(reference::Reference) =
    ConcreteReference(FieldReferenceStep("content"), reference)

"""
    find_embed_card_path_inside(reference) -> Reference or nothing

A path into a card, as a path into the document it holds. A path through the
card's body loses the `content` step, a path into the card's header names the
whole document, and the whole card is the whole document. Any other path
names nothing of the document.
"""
find_embed_card_path_inside(reference::EmptyReference) = reference
function find_embed_card_path_inside(reference::ConcreteReference)
    step = reference.head
    step isa FieldReferenceStep || return nothing
    step.name == "content" && return reference.tail
    step.name == "title" && return EmptyReference()
    nothing
end
find_embed_card_path_inside(::Any) = nothing
