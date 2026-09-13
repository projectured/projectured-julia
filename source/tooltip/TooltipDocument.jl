"""
    TooltipDocumentModule

`TooltipSource` — a transparent wrapper marking a sub-tree as a tooltip
anchor. The `TooltipDecoratorProjection` reader watches events on it and emits
`Open/CloseWindowOperation`s carrying its `content`/`style`/`id`.
"""
module TooltipModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference

import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..IoMapModule: IoMap, var"@iomap"
import ..ReferenceModule: Reference, ConcreteReference, FieldReferenceStep, head, tail
import ..ScreenDocumentModule: OpenWindowOperation, CloseWindowOperation
import ..OperationModule: Operation
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
