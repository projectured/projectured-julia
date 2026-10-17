"""
    DomainModule

The core document domain. Models document-level identity and basic structural
documents: a base abstract type, a nothing-document, an insertion placeholder,
and a reference document.

The acquire of a document that enters the window, `acquire_document!` and
`AcquireDocumentOperation`, the release of a document that leaves it,
`release_document!` and `ReleaseDocumentOperation`, and the count of the holders
of each document live in `DocumentRelease.jl`. The read of outside state for a
document on a task of its own, `start_document_read!`, lives in `DocumentRead.jl`.

The load/save/import/export document operations live with the serializers:
binary `Save`/`LoadDocumentOperation` in `SerializationModule`, natural
`Export`/`ImportDocumentOperation` in `FileFormatModule`.
"""
module DomainModule

using ..CellModule
using ..DocumentModule
using ..EventModule
using ..GestureBindingModule
using ..GestureModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..EditorModule
using ..FaultModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: has_document_duplicate
import ..GestureBindingModule: get_document_gesture_bindings_own
import ..OperationModule: evaluate_operation, make_inverse_operation, describe_operation,
                          is_self_contained_operation

export DocumentBase
export compute_loaded_subtypes, var"@domain", var"@insertion",
       get_insertion_root, get_nothing_document, get_insertion_document, get_domain_prefix,
       get_domain_insertion, insertable, get_insertion_aliases, make_insertion_document,
       get_insertion_names, get_insertion_candidates, compute_concrete_subtypes,
       complete_insertion, name_completion, resolve_insertion, find_declared_place_type,
       insert_document_operation, append_insertion_operation, move_to_field,
       replace_selected_document
export DocumentNothing, DocumentInsertion
export compute_context_menu
export acquire_document!, AcquireDocumentOperation, release_document!, ReleaseDocumentOperation,
       add_document_holder!, remove_document_holder!, is_document_held, hold_documents!,
       release_held_documents!, ChangeHeldDocumentsOperation, start_document_read!, DOCUMENT_READ_WAIT
export accepts_pasted_document, accepts_pasted_replacement, accepts_pasted_text,
       accepts_opened_file, make_pasted_document_operation


include("DocumentCore.jl")
include("Domain.jl")
include("DocumentRelease.jl")
include("DocumentRead.jl")


end # module
