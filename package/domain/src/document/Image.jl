"""
    ImageModule

The image document domain. Provides file-backed and memory-backed image
documents. Both subtypes share the abstract `ImageDocument` base.
"""
module ImageModule

import ..CellModule: Cell, set_function!, set_value!
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference
export ImageDocument, ImageInsertion, ImageFile, ImageMemory, set_function!,
       IImageInsertion, IImageFile, IImageMemory

# ── Abstract base ──────────────────────────────────────────────────────────

"""
    ImageDocument

Abstract base type for all image documents.
"""
abstract type ImageDocument <: Document end

# ── ImageInsertion ───────────────────────────────────────────────────────

@document struct ImageInsertion <: ImageDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── ImageFile ──────────────────────────────────────────────────────────────

"""
    ImageFile(filename; selection)

A file-backed image document.  `filename` is a `Cell` holding a `String` path
and `raw` is a `Cell` holding the decoded image data (or `nothing` until loaded).
"""
@document struct ImageFile <: ImageDocument
    filename::String
    raw::Any
    selection::Reference
end

function ImageFile(filename::AbstractString; selection=nothing)
    ImageFile(Cell(filename), Cell(nothing), Cell(selection))
end

# ── ImageMemory ────────────────────────────────────────────────────────────

"""
    ImageMemory(raw; selection)

A memory-backed image document.  `raw` is a `Cell` holding the image data
directly (e.g. a decoded pixel buffer).
"""
@document struct ImageMemory <: ImageDocument
    raw::Any
    selection::Reference
end

function ImageMemory(raw; selection=nothing)
    ImageMemory(Cell(raw), Cell(selection))
end

# ── set_function! delegation ──────────────────────────────────────────────────────

set_function!(img::ImageFile,   f::Function) = (set_function!(getfield(img, :raw), f); img)
set_function!(img::ImageMemory, f::Function) = (set_function!(getfield(img, :raw), f); img)

end # module
