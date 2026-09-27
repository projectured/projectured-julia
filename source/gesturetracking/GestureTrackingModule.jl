"""
    GestureTrackingModule

The gesture tracking projection: it runs the recognitions of the kernel gesture
layer over the inputs of the devices, and gives the content each input and the
gestures that the recognitions find, a click with its count, a key chord, a
mouse dwell, or a gesture that a package adds.

The states of the recognitions are a document, `GestureTrackingState`, which
wraps the document that the projection shows, and operations write it. So no
state is on the projection. An input that the recognitions give reaches the
content after the operation of the input before it: the state keeps the inputs
that wait, and a timer of the editor brings them in, one in each read.

- [`GestureTrackingDocument.jl`](GestureTrackingDocument.jl) — `GestureTrackingState`.
- [`GestureTracking.jl`](GestureTracking.jl) — `GestureTrackingProjection`: the
  printer, the reader and the mappings.
- [`GestureTrackingWrapper.jl`](GestureTrackingWrapper.jl) — the document and the
  projection of the wrapper, for a host to apply.
"""
module GestureTrackingModule

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

export GestureTrackingState
export GestureTrackingProjection, GestureTrackingIoMap
export make_gesture_tracking_document, make_gesture_tracking_projection

include("GestureTrackingDocument.jl")
include("GestureTracking.jl")
include("GestureTrackingWrapper.jl")

end # module
