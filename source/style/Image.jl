"""
    ImageModule

The image document domain. Provides file-backed and memory-backed image
documents. Both subtypes share the abstract `ImageDocument` base.
"""
module ImageModule

import ..CellModule: Cell, ComputedCell, set_cell_function!, set_cell_value!
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference
export ImageDocument, set_cell_function!

# ── Abstract base ──────────────────────────────────────────────────────────

"""
    ImageDocument

Abstract base type for all image documents.
"""
abstract type ImageDocument <: Document end

# ── ImageInsertion ───────────────────────────────────────────────────────

@document struct ImageInsertion <: ImageDocument
    value::Any = nothing
end

# ── ImageFile ──────────────────────────────────────────────────────────────

"""
    ImageFile(filename)

A file-backed image document.  `filename` is a `Cell` holding a `String` path
and `raw` is a `Cell` holding the decoded image data (or `nothing` until loaded).
"""
@document struct ImageFile <: ImageDocument
    filename::String
    raw::Any
end

# Only `raw` needs filling; the trailing `selection` is filled by the macro.
ImageFile(filename::AbstractString) = ImageFile(Cell(filename), Cell(nothing))

# ── ImageMemory ────────────────────────────────────────────────────────────

"""
    ImageMemory(raw)

A memory-backed image document.  `raw` is a `Cell` holding the image data
directly (e.g. a decoded pixel buffer).
"""
@document struct ImageMemory <: ImageDocument
    raw::Any
end

# ── set_cell_function! delegation ──────────────────────────────────────────────────────

set_cell_function!(img::ImageFile,   f::Function) = (set_cell_function!(getfield(img, :raw), f); img)
set_cell_function!(img::ImageMemory, f::Function) = (set_cell_function!(getfield(img, :raw), f); img)

end # module
