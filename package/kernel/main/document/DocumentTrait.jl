# Fragment of `DocumentModule` — the two traits that steer `walk_document`.
# They exist so the walk never has to name a concrete collection type: a document
# opts into a shape, the walk reads the shape off the trait. That is what lets the
# walk sit below every collection it descends.

"""
    is_element_collection(document) -> Bool

`true` when a document's children are addressed **by position** (an
`ElementReference`, i.e. `[i]`) rather than by named field — a 1-D positional
sequence, not a record. A reflection walker keys off this to emit `[i]` element
paths for a collection instead of descending into its internal storage fields,
so it never has to name a concrete collection type. Default `false` (records,
leaves, and 2-D collections all answer `false`); a 1-D positional collection
opts in with its own method.
"""
is_element_collection(value) = false

"""
    is_opaque(document) -> Bool

`true` when a document is **opaque** to reflection walkers: its internals are
implementation detail, not addressable document content, so a walk over the
document treats it as a leaf and never descends into it. Default `false`; a
document type whose contents are configuration or an implementation detail
rather than navigable structure opts in with its own method.
"""
is_opaque(value) = false
