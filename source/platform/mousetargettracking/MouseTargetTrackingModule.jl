"""
    MouseTargetTrackingModule

The mouse target tracking projection: it keeps the part under the pointer, the
target, and gives each part of the target the crossings: a `MouseEnter` when
the pointer comes onto it, a `MouseLeave` when the pointer goes off it, and a
`MouseHover` to the deepest part on each move, whose route is the whole target.
A crossing goes to its part by route, never by a position.

The target is the part that a point maps to backward, through every projection
of the view. When the view changes under a still pointer, a `DisplayUpdate`
finds the target again at the last position, and when the pointer leaves the
window, `WindowLeave` clears it.

The state is a document, `MouseTargetTrackingState`, which wraps the document
that the projection shows, and operations write it. The crossings that one
input makes wait in the state and reach the content one in each read, after the
operation of the input.

- [`MouseTargetTrackingDocument.jl`](MouseTargetTrackingDocument.jl) — `MouseTargetTrackingState`.
- [`MouseTargetTracking.jl`](MouseTargetTracking.jl) — `MouseTargetTrackingProjection`:
  the printer, the reader and the mappings.
- [`MouseTargetTrackingWrapper.jl`](MouseTargetTrackingWrapper.jl) — the document
  and the projection of the wrapper, for a host to apply.
"""
module MouseTargetTrackingModule

using ..CellModule
using ..DocumentModule
using ..EventModule
using ..GestureModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule

import ..DocumentModule: get_wrapped_document
import ..ProjectionModule: print_document, read_intent, map_reference_forward,
                           map_reference_backward, get_child_iomaps

export MouseTargetTrackingState
export MouseTargetTrackingProjection, MouseTargetTrackingIoMap
export make_mouse_target_tracking_document, make_mouse_target_tracking_projection

include("MouseTargetTrackingDocument.jl")
include("MouseTargetTracking.jl")
include("MouseTargetTrackingWrapper.jl")

end # module
