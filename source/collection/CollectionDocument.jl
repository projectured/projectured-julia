# Fragment of `CollectionModule` — `CollectionDocument`, the union of the four
# collection shapes the sibling fragments declare.

const CollectionDocument = Union{CellVector, CellMatrix, CellTable, ListNode}

# A collection holds its elements, so its duplicate holds their duplicates.
has_document_duplicate(::CollectionDocument) = true
