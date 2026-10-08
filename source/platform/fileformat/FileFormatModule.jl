"""
    FileFormatModule

Reading and writing a document **as a file** — `import_document` /
`export_document` — and the two editor operations that do it.

What a natural notation *is* lives in the natural slice (`NaturalModule`): a
domain declares the rung it starts at, the format it is written in, the
extension that names that format back, and how to read the text in again.
This module is the file half alone: it picks a parser by the extension of a
path, and it writes what `print_natural_text` produced.

Unlike the binary format ([`SerializationModule`](@ref)), this is portable
and editable outside ProjecturEd, but lossy with respect to editor-only state:
selection and collapse are not represented, and a document carrying an *insertion
placeholder* has no valid natural-text form, so its export will not re-parse.
Round-trip on real data documents; not on editor scaffolding.
"""
module FileFormatModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventModule
using ..GestureBindingModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule

# Imported to extend: this module adds a method to it.
import ..DocumentModule: get_document_title
using ..TextModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..OperationModule: evaluate_operation, make_inverse_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward,
                           map_reference_backward

export import_document, export_document,
       ImportDocumentOperation, ExportDocumentOperation
export write_document_file, read_document_file, make_document_for, make_document_seed,
       make_file_tab, make_file_tab_content
export export_document
export SaveFileOperation, ReloadFileOperation, compute_file_text
export FileToContent
export make_file_api


include("NaturalFormat.jl")
include("DocumentFile.jl")
include("FileToContent.jl")

end # module
