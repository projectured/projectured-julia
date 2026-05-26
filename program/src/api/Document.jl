"""
    DocumentApiModule

Document selection API. Declares clear_selection! and set_selection! as
generic functions dispatched on by concrete document types and the default
implementation in common/Operation.jl. Keeping the interface here decouples
the declaration from the implementation and avoids circular dependencies.
"""
module DocumentApiModule

export Document, clear_selection!, set_selection!

"""
    Document

Abstract base type for all document types. Every concrete document
must have a `selection::Reference` field tracking the current selection state.
"""
abstract type Document end

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

end # module
