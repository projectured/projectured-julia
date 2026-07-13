"""
    ReferenceInspectorDocumentModule

`ReferenceInspector` — pairs a `reference` (`ReferencePath` or `nothing`) with
the `target` document it points into. `ReferenceInspectorToText` renders both
forms (compact + human narrative).
"""
module ReferenceInspectorDocumentModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference

"""
A display document pairing a `reference` (`ReferencePath` or `nothing`) with
the `target` document it points into.
"""
@document struct ReferenceInspector
    reference::Reference = nothing
    target::Any = nothing
end

end # module
