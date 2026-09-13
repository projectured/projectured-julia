"""
    FileSystemModule

The file-system document domain — `FileSystemFile` (leaf) and
`FileSystemDirectory` (node holding `elements` in a `CellVector`). Both carry
their `pathname` as identity.
"""
module FileSystemModule

import ..CellModule: Cell, ComputedCell
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector, ComputedCellVector
import ..ReferenceModule: Reference
export FileSystemDocument, make_filesystem_pathname
import ..ProjectionApiModule: print_document, print_child, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..TextModule: TextString
import ..StyleModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..StyleModule: StyleColor, color_black, color_default, color_solarized_blue, color_solarized_red
import ..StyleModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep, RangeReferenceStep, FieldReferenceStep, extend_reference
import ..ProjectionReferenceStepModule: make_introduced_reference, is_introduced_reference
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..PrinterContextModule: make_child_context
export FileSystemFileToSyntaxLeaf, FileSystemDirectoryToSyntaxNode, FileSystemToSyntax,
       is_filesystem_marker_eligible
import ..NaturalModule: register_natural_syntax!
import ..ProjectionApiModule: print_document, map_reference_forward, map_reference_backward, Projection
import ..WidgetModule: WidgetTree, WidgetTreeNode, Point2D
import ..GestureBindingModule: GestureBinding
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep, EmptyReference,
                          is_element_reference_step
export FileSystemToWidgetTree, FileSystemToWidget
export FileSystemFile, FileSystemDirectory



abstract type FileSystemDocument <: Document end

# ── FileSystemInsertion ─────────────────────────────────────────────────

@document struct FileSystemInsertion <: FileSystemDocument
    value::Any = nothing
end

# ── File ──────────────────────────────────────────────────────────────────────

@document struct FileSystemFile <: FileSystemDocument
    pathname::String
end


# ── Directory ─────────────────────────────────────────────────────────────────

@document struct FileSystemDirectory <: FileSystemDocument
    pathname::String
    elements::CellVector
end



# ── API ───────────────────────────────────────────────────────────────────────

function make_filesystem_pathname(pathname::AbstractString)
    p = String(pathname)
    if isdir(p)
        children = FileSystemDocument[]
        for entry in readdir(p; join=true)
            push!(children, make_filesystem_pathname(entry))
        end
        FileSystemDirectory(p, children)
    else
        FileSystemFile(p)
    end
end


include("FileSystemToSyntax.jl")
include("FileSystemToWidget.jl")

end # module
