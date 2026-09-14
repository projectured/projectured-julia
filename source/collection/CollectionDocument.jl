# Fragment of `CollectionModule` — `CollectionDocument`, the union of the four
# collection shapes the sibling fragments declare.

const CollectionDocument = Union{CellVector, CellMatrix, CellTable, ListNode}
