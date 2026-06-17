"""
    DocumentCopyModule

A deep-copy helper for document subtrees. Unlike `Base.deepcopy`, it
understands the `@document` Cell-wrapped field convention and the
`CellVector` sequence container, allocates **fresh** `Cell`s so the copy is
independent of the original's reactive graph, and **resets** the copy's
`selection` to `nothing` rather than duplicating the original's selection
path.

This is the Julia counterpart of Lisp's `deep-copy`, used by the clipboard
projection's copy / note / paste gestures (`ClipboardToAnyProjectionModule`).
"""
module DocumentCopyModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document
import ..CollectionModule: CellVector

export copy_document

"""
    copy_document(value)

Recursively clone `value`. For a `Document` every field is cloned into a fresh
`Cell`, except `selection`, which is reset to `nothing` (the copy starts with no
selection). For a `CellVector` each element is cloned into a fresh `Cell`. Plain
immutable leaves (strings, numbers, symbols, reference paths) are returned as-is.

The result shares **no** `Cell` with the original, so mutating the original's
reactive graph after copying leaves the copy untouched.
"""
copy_document(value) = value

function copy_document(doc::Document)
    T = typeof(doc)
    args = Any[]
    for nm in fieldnames(T)
        if nm === :selection
            push!(args, Cell(nothing))
        else
            raw = getfield(doc, nm)
            val = raw isa Cell ? raw[] : raw
            push!(args, Cell(copy_document(val)))
        end
    end
    T(args...)
end

function copy_document(cv::CellVector)
    CellVector(Cell[Cell(copy_document(cv[i])) for i in 1:length(cv)])
end

end # module
