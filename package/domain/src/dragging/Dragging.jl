"""
    DraggingDocumentModule

`DraggingState` — a transparent wrapper Document that marks a sub-tree as a
region where drag-and-drop reordering is enabled. It carries the wrapped
`content` document and a `selection`; the actual gesture interpretation lives in
[`DraggingProjection`](../projection/higherorder/Dragging.jl), which dispatches
on `DraggingState` exactly the way `TooltipDecoratorProjection` dispatches on
`TooltipSource`.

`DraggingState` is intentionally minimal: it holds no transient gesture state.
The press → drag → drop state machine lives on the projection instance (a single
drag at a time), so a `DraggingState` is just a stable, serialisable marker in
the document tree.
"""
module DraggingDocumentModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference

export DraggingDocument

"""
    DraggingDocument

Abstract base for documents that participate in the dragging machinery.
"""
abstract type DraggingDocument <: Document end

"""
    DraggingState(content; threshold=5)

A transparent wrapper around `content`. The printer side of
`DraggingProjection` projects this as if the wrapper weren't there (output is
what `content` projects to). The reader side watches mouse gestures arriving at
this node and, on a completed press-drag-release, emits a `MoveRangeOperation`
that reorders elements inside `content`.

# Fields

- `content::Document` — the node where dragging applies. Projected like any
  other document.
- `threshold::Int` — pixel distance the cursor must travel while a button is
  held before a press turns into a drag (below it, the press falls through as a
  normal click). Default 5, matching the backend's click-synthesis tolerance.
- `selection::Reference` — the wrapper's own selection slot (the `content`'s
  selection is what the drag source is read from).
"""
@document struct DraggingState <: DraggingDocument
    content::Document
    threshold::Int
    selection::Reference
end

DraggingState(content::Document; threshold::Integer = 5) =
    DraggingState(Cell(content), Cell(Int(threshold)), Cell(nothing))

end # module
