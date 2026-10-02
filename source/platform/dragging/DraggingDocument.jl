# Fragment of `DraggingModule` — the dragging document types: the abstract
# `DraggingDocument` and the transparent wrapper that turns a press into a drag
# once it travels past a threshold.

abstract type DraggingDocument <: Document end

"""
Transparent wrapper around `content`; `threshold` is the pixel distance a
press must travel before it becomes a drag (below it, the press falls through
as a normal click). `press` is view state: the press that may become a drag, as
`(x, y, source, started)`, where `source` is the path in `content` of the element
under the pointer at the press, or `nothing` when no button is held.
"""
@document struct DraggingState <: DraggingDocument
    content::Document
    threshold::Int = 5
    press::Any = nothing
end
