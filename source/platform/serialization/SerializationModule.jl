"""
    SerializationModule

Exact, lossless binary persistence for documents — `save_document` /
`load_document` — independent of any domain's text format.

A document is written with Julia's `Serialization` stdlib. The only
customization is that a [`Cell`](@ref) serializes as **just its value**: a cell's
reactive wiring (`deps`/`dependents`) and its computing `thunk` are *runtime
state*, not data. That single rule prunes the reactive graph at every cell
boundary, so serializing a live document stays within the document's own data and
never traverses `dependents` out into the projection output graph (computed cells
and their closures). It also means documents, `CellVector`s, and the selection
`Reference` (whose steps are themselves `Cell`-backed) are all handled
uniformly — so the saved **selection is restored** on load. The mouse target
is not: a load gives none, because it was where the pointer was.

Targets *structural* documents. A document that holds a live external resource
(a database adapter, an open socket) is not serializable this way; for a
portable, human-readable format use the natural import/export
(`FileFormatModule`). The binary format is tied to the in-memory struct
layout, so it is a *same-version* persistence format, not an interchange format.
"""
module SerializationModule

using ..CellModule
using ..DocumentModule
using ..OperationModule
using ..ReferenceModule
using Serialization

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_edited_field
import ..OperationModule: evaluate_operation, make_inverse_operation

export save_document, load_document, SaveDocumentOperation, LoadDocumentOperation
export FileDocument, is_file_document,
       get_filename, get_file_content, emit_text,
       save_project!, load_project,
       register_file_document_type!, get_file_document_type, has_file_document_type,
       register_marker_function!, get_marker_function, evaluate_marker,
       get_pred_type, is_pred_constructible,
       parse_marker_text, get_document_section
export FileProject, FileCutException, save_file!, cut_file_text, load_file, parse_file_content,
       get_file_domain, is_file_domain_node, make_reference_leaf, find_reference_marker,
       make_marker_text, is_own_content, make_file, is_written_in_file
export TextFile
export parse_path_text, print_path_text
export PredFile, parse_pred_text, print_pred_text, pred_arguments, make_pred_document,
       is_pred_document


include("BinarySerialization.jl")
include("FileProject.jl")
include("FileCut.jl")
include("FileSplice.jl")
include("TextFile.jl")
include("PredFile.jl")

end # module
