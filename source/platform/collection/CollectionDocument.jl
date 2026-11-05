# Fragment of `CollectionModule` — `CollectionDocument`, the union of the four
# collection shapes the sibling fragments declare.

"""
    CollectionDocument

The union of the four collection shapes: `CellVector`, `CellMatrix`, `CellTable` and
`ListNode`. A field declared `CollectionDocument` holds any of them, and a plain
vector given to such a field becomes a `CellVector`.

Use it to recognise a collection of parts in a document: a part is one when
`part isa CollectionDocument`.

# Example

    collections_1 = search_documents(get_edited_document(find_pane("data")), part -> part isa CollectionDocument)

See also `search_documents`, `find_pane` and `ListDocument`.

For the assistant.
"""
const CollectionDocument = Union{CellVector, CellMatrix, CellTable, ListNode}

# A plain vector converts to the list of its elements, so a field declared
# `CollectionDocument` takes it at a write, by rule 2 of the check of a declared type.
Base.convert(::Type{CollectionDocument}, items::AbstractVector) = CellVector(items)

# A list and a table hold their elements, so a duplicate holds the elements'
# duplicates. A matrix and a linked list declare none: the walk does not descend
# into a `Matrix{Cell}`, and a node's `prev` is a back-link.
has_document_duplicate(::Union{CellVector, CellTable}) = true
