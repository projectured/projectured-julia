"""
    DragTrackingModule

The drag tracking projection: it keeps the path of the part whose drag is on,
and gives that part the parts of its drag, `DragMove`, `DragEnd` and
`DragCancel`, by the path, wherever the pointer is. The part keeps its own state
of the drag, and starts the drag with a `StartDragOperation` in its answer.

The path is a field of a document, `DragTrackingState`, which wraps the document
that the projection shows, and operations write it. So no state is on the
projection.

- [`DragTrackingDocument.jl`](DragTrackingDocument.jl) — `DragTrackingState`.
- [`DragTracking.jl`](DragTracking.jl) — `DragTrackingProjection`: the printer,
  the reader and the mappings.
- [`DragTrackingWrapper.jl`](DragTrackingWrapper.jl) — the document and the
  projection of the wrapper, for a host to apply.
"""
module DragTrackingModule

using ..CellModule
using ..DocumentModule
using ..EventModule
using ..GestureModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule

import ..DocumentModule: get_wrapped_document
import ..ProjectionModule: print_document, read_intent, map_reference_forward,
                           map_reference_backward, get_child_iomaps

export DragTrackingState
export DragTrackingProjection, DragTrackingIoMap
export make_drag_tracking_document, make_drag_tracking_projection

include("DragTrackingDocument.jl")
include("DragTracking.jl")
include("DragTrackingWrapper.jl")

end # module
