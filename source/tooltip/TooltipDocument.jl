"""
    TooltipDocumentModule

`TooltipSource` — a transparent wrapper marking a sub-tree as a tooltip
anchor. The `TooltipDecoratorProjection` reader watches events on it and emits
`Open/CloseWindowOperation`s carrying its `content`/`style`/`id`.
"""
module TooltipDocumentModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference

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

end # module
