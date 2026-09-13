"""
    InspectorModule

`ReferenceInspector` — pairs a `reference` (`Reference` or `nothing`) with
the `target` document it points into. `ReferenceInspectorToText` renders both
forms (compact + human narrative).
"""
module InspectorModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..ProjectionApiModule: print_document, map_reference_forward,
                              map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..ReferenceModule: ConcreteReference, annotate_reference_types
import ..ReferenceToTextModule: ReferenceToText, ReferenceToHumanReadableText
import ..TextModule: TextDocument, TextBlock, TextString, TextNewline
import ..StyleModule: StyleFont, font_ubuntu_monospace_regular_20, font_liberation_sans_bold_30
import ..StyleModule: StyleColor, color_solarized_blue
import ..PrinterContextModule: PrinterContext
import ..IoMapModule: SimpleIoMap
export ReferenceInspectorToText
import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward,
                              Projection
import ..IntentModule: Intent
import ..IoMapModule: IoMap, var"@iomap"
import ..EventModule: MouseMove, MousePress
import ..OperationModule: ReplaceSelectionOperation
import ..ScreenModule: OpenWindowOperation, CloseWindowOperation
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
