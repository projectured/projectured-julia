"""
    SelectionModule

**Selection**: a document's current-focus state, expressed as a reference path
stored on the document's `selection` field. The primitives read
(`get_selection`), clear (`clear_selection!`), set (`set_selection!`), and
replace (`replace_selection!`) that state. Setting a
selection propagates the path down the document hierarchy — each step navigates
to a child document and stores the remaining tail as that child's selection —
and canonicalizes the path against the live document, folding each node's type
in (see `annotate_reference_types`). A path that does not match the live
document is rejected with `SelectionMismatchException` *before any cell is
written*, so applying a selection either matches and takes effect or fails
atomically — it is never half-applied.

A selection that a document keeps when the focus leaves it is **dormant**.
`has_dormant_selection` says whether a document keeps one,
`get_stored_selection` and `is_live_selection` read the path and whether it is
live, and `map_selection_forward` carries that state through a projection.

A selection's payload is a `Reference` stored on a `Document`, which is why
these primitives live above references and the document contract.

A document extends `has_dormant_selection` when its children are alternatives.
No other generic of the layer has a method outside it: the defaults read and
write the conventional `document.selection` field.

The module lives in two fragments that share this namespace:
[`SelectionInterface.jl`](SelectionInterface.jl) declares the generics that
callers dispatch on, and [`SelectionDefaults.jl`](SelectionDefaults.jl) provides
their default implementations and the private path-walking helpers.
"""
module SelectionModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule

export get_selection, clear_selection!, set_selection!,
       var"@selected", replace_selection!, SelectionMismatchException,
       has_dormant_selection, get_stored_selection,
       is_live_selection, map_selection_forward

include("SelectionInterface.jl")
include("SelectionDefaults.jl")

end # module
