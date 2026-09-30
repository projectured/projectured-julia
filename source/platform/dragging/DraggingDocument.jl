# Fragment of `DraggingModule` — the dragging document types: the abstract
# `DraggingDocument` and the transparent wrapper that turns a press into a drag
# once it travels past a threshold.

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
