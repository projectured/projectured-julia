"""
    ReferenceInspectorDocumentModule

`ReferenceInspector` — pairs a `reference` (`Reference` or `nothing`) with
the `target` document it points into. `ReferenceInspectorToText` renders both
forms (compact + human narrative).
"""
module ReferenceInspectorDocumentModule

import ..CellModule: Cell, ComputedCell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference

"""
A display document pairing a `reference` (`Reference` or `nothing`) with
the `target` document it points into.
"""
@document struct ReferenceInspector
    reference::Union{Nothing, Reference} = nothing
    target::Any = nothing
end

end # module
