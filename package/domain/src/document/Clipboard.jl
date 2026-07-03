"""
    ClipboardModule

Clipboard document types. Two structural shapes: a slice (single content +
a slice reference) and a collection (single content + a sequence of elements).
Both carry a reactive selection Cell and inherit from the shared Document
contract.
"""
module ClipboardModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export ClipboardDocument, ClipboardInsertion, ClipboardSlice, ClipboardCollection,
       IClipboardInsertion, IClipboardSlice, IClipboardCollection

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type ClipboardDocument <: Document end

# ── ClipboardInsertion ─────────────────────────────────────────────────────

@document struct ClipboardInsertion <: ClipboardDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── ClipboardSlice ────────────────────────────────────────────────────────────

"""
    ClipboardSlice(content; slice=nothing, selection=nothing)

A clipboard entry holding a single `content` document together with a
`slice` reference that identifies the portion of `content` that was
copied.
"""
@document struct ClipboardSlice <: ClipboardDocument
    content::Document
    slice::Any
    selection::Reference
end

ClipboardSlice(content; slice=nothing, selection=nothing) =
    ClipboardSlice(Cell(content), Cell(slice), Cell(selection))

# ── ClipboardCollection ───────────────────────────────────────────────────────

"""
    ClipboardCollection(content; elements=[], selection=nothing)

A clipboard entry holding a single `content` document together with a
sequence of `elements` extracted from it.
"""
@document struct ClipboardCollection <: ClipboardDocument
    content::Document
    elements::CellVector
    selection::Reference
end

ClipboardCollection(content; elements=[], selection=nothing) =
    ClipboardCollection(Cell(content), CellVector(Cell[Cell(x) for x in elements]), Cell(selection))

end # module
