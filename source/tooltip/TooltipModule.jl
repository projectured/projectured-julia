"""
    TooltipModule

`TooltipSource` — a transparent wrapper marking a sub-tree as a tooltip
anchor. The `TooltipDecoratorProjection` reader watches events on it and emits
`Open/CloseWindowOperation`s carrying its `content`/`style`/`id`.
"""
module TooltipModule

using ..CellModule
using ..DocumentModule
using ..EventModule
using ..GestureModule
using ..SelectionModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..ScreenModule
using ..FeedModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..FeedModule: drain_changes!, compute_wake_deadline
using ..EditorModule

export TooltipSource
export TooltipDecoratorProjection, TooltipDecoratorIoMap
export TooltipProbeProjection, TooltipProbeIoMap
export PointerRest, TooltipRest, TooltipFeed, make_tooltip_feed


include("TooltipDocument.jl")
include("TooltipDecorator.jl")
include("TooltipRest.jl")
include("TooltipProbe.jl")

end # module
