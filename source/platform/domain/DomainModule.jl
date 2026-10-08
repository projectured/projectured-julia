"""
    DomainModule

The core document domain. Models document-level identity and basic structural
documents: a base abstract type, a nothing-document, an insertion placeholder,
and a reference document.

The release of a document that leaves the window, `release_document!` and
`ReleaseDocumentOperation`, lives in `DocumentRelease.jl`.

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

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: has_document_duplicate
import ..GestureBindingModule: get_document_gesture_bindings_own
import ..OperationModule: evaluate_operation, make_inverse_operation, describe_operation

export DocumentBase
export compute_loaded_subtypes, var"@domain", var"@insertion",
       get_insertion_root, get_nothing_document, get_insertion_document, get_domain_prefix,
       get_domain_insertion, insertable, get_insertion_aliases, make_insertion_document,
       get_insertion_names, get_insertion_candidates, compute_concrete_subtypes,
       complete_insertion, name_completion, resolve_insertion,
       insert_document_operation, append_insertion_operation, move_to_field,
       replace_selected_document
export DocumentNothing, DocumentInsertion
export compute_context_menu
export release_document!, ReleaseDocumentOperation
export accepts_pasted_document, accepts_pasted_replacement, accepts_pasted_text,
       accepts_opened_file


include("DocumentCore.jl")
include("Domain.jl")
include("DocumentRelease.jl")


end # module
