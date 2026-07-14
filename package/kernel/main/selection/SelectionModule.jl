"""
    SelectionModule

**Selection**: a document's current-focus state,
expressed as a reference path stored on the document's `selection` field. The
primitives read (`get_selection`), clear (`clear_selection!`), set
(`set_selection!` / `with_selection`), and replace (`replace_selection!`) that
state. Setting a selection propagates the path down the
document hierarchy — each step navigates to a child document and stores the
remaining tail as that child's selection — and canonicalizes the path against the
live document, folding each node's type in (see `annotate_reference_types`). A
path that no longer matches the live document is rejected with `SelectionMismatch`
*before any cell is written*, so applying a selection either matches and takes
effect or fails atomically — it is never half-applied.

A selection's payload is a `ReferencePath` stored on a `Document`, which is why
these primitives live above references and the
document contract.

`clear_selection!` / `set_selection!` are open generics: a document that stores
its selection unconventionally overrides them; the defaults here read and write
the conventional `document.selection` field.

The module lives in two fragments that share this namespace:
[`Interface.jl`](Interface.jl) declares the generics (the contract documents
override / callers dispatch on) and [`Selection.jl`](Selection.jl) provides their
default implementations and the private path-walking helpers.
"""
module SelectionModule

using ..CellModule
using ..DocumentModule
# This also binds the module itself, so `@with_selection` can expand to a qualified
# `ReferenceModule.@reference` call and its callers need only import the macro.
using ..ReferenceModule

export get_selection, clear_selection!, set_selection!, with_selection,
       var"@with_selection", replace_selection!, SelectionMismatch

include("Interface.jl")   # the selection generics (declaration-only)
include("Selection.jl")   # their default methods + private helpers

end # module
