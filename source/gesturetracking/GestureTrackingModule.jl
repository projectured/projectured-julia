"""
    GestureTrackingModule

The gesture tracking projection: it reads the events of the devices and gives
the content the gestures that the events make, a click with its count, a key
chord and a mouse dwell, after the events themselves.

The state of the recognition is a document, `GestureTrackingState`, which wraps
the document that the projection shows, and operations write it. So no state is
on the projection. A gesture that an event completes reaches the content after
the operation of that event: the state keeps the gestures that wait, and a timer
of the editor at the time of the event brings them in, one in each read.

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
