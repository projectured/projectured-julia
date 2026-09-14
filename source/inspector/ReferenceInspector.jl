"""
    InspectorModule

`ReferenceInspector` — pairs a `reference` (`Reference` or `nothing`) with
the `target` document it points into. `ReferenceInspectorToText` renders both
forms (compact + human narrative).
"""
module InspectorModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule
using ..ProjectionApiModule
import ..ProjectionApiModule: print_document, map_reference_forward, map_reference_backward, read_intent
using ..ProjectionModule
using ..TextModule
using ..TextModule
using ..StyleModule
using ..PrinterContextModule
using ..IoMapModule
export ReferenceInspectorToText
using ..IntentModule
using ..EventModule
using ..OperationModule
using ..ScreenModule
export HoverProbeProjection, HoverProbeIoMap
export ReferenceInspector



"""
A display document pairing a `reference` (`Reference` or `nothing`) with
the `target` document it points into.
"""
@document struct ReferenceInspector
    reference::Union{Nothing, Reference} = nothing
    target::Any = nothing
end


include("ReferenceInspectorToText.jl")
include("HoverProbe.jl")

end # module
