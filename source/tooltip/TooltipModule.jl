"""
    TooltipModule

`TooltipSource` — a transparent wrapper marking a sub-tree as a tooltip
anchor. The `TooltipDecoratorProjection` reader watches events on it and emits
`Open/CloseWindowOperation`s carrying its `content`/`style`/`id`.
"""
module TooltipModule

using ..CellModule
using ..DocumentModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export TooltipSource
export TooltipDecoratorProjection, TooltipDecoratorIoMap


include("TooltipDocument.jl")
include("TooltipDecorator.jl")

end # module
