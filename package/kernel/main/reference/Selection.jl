# Fragment of `ReferenceModule` — the selection generics that read, clear,
# set, and canonicalize a document's current selection reference. Their payload
# is a `Reference`/`ReferencePath` (introduced in this same module), which is
# why they live here rather than at the document layer where the `Document`
# type is defined (AR-47). The `get_selection` default reads the conventional
# `document.selection` field; `clear_selection!` and `set_selection!` are open
# generics whose default implementations that walk the reference path live
# with the concrete edit machinery in the operation layer.
#
# See [`documentation/concepts.md`](../../../../documentation/concepts.md) for
# the single-place narrative of the document editing model these generics are
# part of.

"""
    get_selection(document) -> reference or nothing

The document's current selection — a reference path or `nothing`. Every
document has one (the [`Document`](@ref) contract requires a `selection`
field); the default reads that conventional field, so a concrete document gets
it for free, and one that stores its selection differently overrides this
method.
"""
get_selection(document::Document) = document.selection

"""
    clear_selection!(document)

Clear the current selection of `document` and recursively clear the selections
of any child documents reached by the stored path.
"""
function clear_selection! end

"""
    set_selection!(document, path)

Propagate `path` down the document hierarchy starting at `document`. Each step
in the path navigates to a child document and sets that child's `selection` to
the remaining tail of the path.
"""
function set_selection! end

"""
    with_selection(document, path) -> document

Construct-and-select: set `path` on `document` and propagate it deeply into the
child documents it traverses (via [`set_selection!`](@ref)), returning
`document`. The one-expression form of
`d = SomeDocument(...); set_selection!(d, path); d` — for building a document
literal whose cursor is fully placed.
"""
function with_selection end
