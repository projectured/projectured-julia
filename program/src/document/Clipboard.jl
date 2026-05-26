"""
    ClipboardModule

Clipboard document types. Two structural shapes: a slice (single content +
a slice reference) and a collection (single content + a sequence of elements).
Both carry a reactive selection Cell and inherit from the shared Document
contract.
"""
module ClipboardModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export ClipboardDocument, ClipboardInsertion, ClipboardForeign, ClipboardSlice, ClipboardCollection,
       IClipboardInsertion, IClipboardForeign, IClipboardSlice, IClipboardCollection

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type ClipboardDocument <: Document end

# ── ClipboardInsertion / ClipboardForeign ─────────────────────────────────

@document struct ClipboardInsertion <: ClipboardDocument
    value::Any
    selection::Reference
end
ClipboardInsertion() = ClipboardInsertion(Cell(nothing), Cell(nothing))

@document struct ClipboardForeign <: ClipboardDocument
    value::Any
    selection::Reference
end
ClipboardForeign(value) = ClipboardForeign(Cell(value), Cell(nothing))

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

# ── Display ───────────────────────────────────────────────────────────────────

Base.show(io::IO, c::ClipboardSlice) =
    print(io, "ClipboardSlice(", c.content, ")")

Base.show(io::IO, c::ClipboardCollection) =
    print(io, "ClipboardCollection(", length(c.elements), " elements)")

end # module
