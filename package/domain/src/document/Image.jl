"""
    ImageModule

The image document domain. Provides file-backed and memory-backed image
documents. Both subtypes share the abstract `ImageDocument` base.
"""
module ImageModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference
export ImageDocument, ImageInsertion, ImageFile, ImageMemory, setfn!,
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

# ── setfn! delegation ──────────────────────────────────────────────────────

setfn!(img::ImageFile,   f::Function) = (setfn!(getfield(img, :raw), f); img)
setfn!(img::ImageMemory, f::Function) = (setfn!(getfield(img, :raw), f); img)

end # module
