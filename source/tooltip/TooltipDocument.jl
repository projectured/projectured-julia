"""
    TooltipModule

`TooltipSource` — a transparent wrapper marking a sub-tree as a tooltip
anchor. The `TooltipDecoratorProjection` reader watches events on it and emits
`Open/CloseWindowOperation`s carrying its `content`/`style`/`id`.
"""
module TooltipModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule

using ..ProjectionApiModule
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..IntentModule
using ..IoMapModule
using ..ScreenModule
using ..OperationModule
export TooltipSource
export TooltipDecoratorProjection, TooltipDecoratorIoMap


"""
Transparent wrapper around `child` that carries a `content` document plus the
`style`/`id` of the future tooltip window.
"""
@document struct TooltipSource
    child::Document
    content::Document
    style::Symbol = :tooltip
    id::Symbol
end


include("TooltipDecorator.jl")

end # module
