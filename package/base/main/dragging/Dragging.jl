"""
    DraggingDocumentModule

`DraggingState` — a transparent wrapper marking a sub-tree as a drag-and-drop
reorder region. Actual gesture interpretation lives in `DraggingProjection`.
"""
module DraggingDocumentModule

import ..CellModule: Cell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference

export DraggingDocument

abstract type DraggingDocument <: Document end

"""
Transparent wrapper around `content`; `threshold` is the pixel distance a
press must travel before it becomes a drag (below it, the press falls through
as a normal click).
"""
@document struct DraggingState <: DraggingDocument
    content::Document
    threshold::Int = 5
end

end # module
