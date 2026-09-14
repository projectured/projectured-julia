"""
    InspectorModule

`ReferenceInspector` — pairs a `reference` (`Reference` or `nothing`) with
the `target` document it points into. `ReferenceInspectorToText` renders both
forms (compact + human narrative).
"""
module InspectorModule

using ..CellModule
using ..DocumentModule
using ..EventModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule
using ..StyleModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward, read_intent

export ReferenceInspectorToText
export HoverProbeProjection, HoverProbeIoMap
export ReferenceInspector


include("ReferenceInspector.jl")
include("ReferenceInspectorToText.jl")
include("HoverProbe.jl")

end # module
