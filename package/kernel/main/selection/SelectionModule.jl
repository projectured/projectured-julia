"""
    SelectionModule

Layer 4 of the kernel — **selection**: a document's current-focus state,
expressed as a reference path stored on the document's `selection` field. The
primitives read (`get_selection`), clear (`clear_selection!`), set
(`set_selection!` / `with_selection`), and replace (`replace_selection!` /
`update_selection!`) that state. Setting a selection propagates the path down the
document hierarchy — each step navigates to a child document and stores the
remaining tail as that child's selection — and canonicalizes the path against the
live document, folding each node's type in (see `annotate_reference_types`).

A selection's payload is a `ReferencePath` (layer 3) stored on a `Document`
(layer 2), which is why these primitives live one layer above references and the
document contract.

`clear_selection!` / `set_selection!` are open generics: a document that stores
its selection unconventionally overrides them; the defaults here read and write
the conventional `document.selection` field.

The module is one fragment, [`Selection.jl`](Selection.jl), sharing this namespace.
"""
module SelectionModule

import ..CellModule: AbstractCell
import ..DocumentModule: Document
import ..ReferenceModule: ConcreteReferencePath, ReferencePath, FieldReference,
                          RangeReference, annotate_reference_types,
                          strip_reference_types, is_reference_equal

export get_selection, clear_selection!, set_selection!, with_selection,
       replace_selection!, update_selection!

include("Selection.jl")

end # module
