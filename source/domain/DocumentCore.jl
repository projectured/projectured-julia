"""
    DomainModule

The core document domain. Models document-level identity and basic structural
documents: a base abstract type, a nothing-document, an insertion placeholder,
and a reference document.

The load/save/import/export document operations live with the serializers:
binary `Save`/`LoadDocumentOperation` in `SerializationModule`, natural
`Export`/`ImportDocumentOperation` in `FileFormatModule`.
"""
module DomainModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule
export DocumentBase
using ..EventPatternModule
using ..GestureBindingModule
import ..GestureBindingModule: get_document_gesture_bindings_own
using ..SelectionModule
using ..ProjectionModule
using ..OperationModule
export var"@domain", var"@insertion",
       get_insertion_root, get_nothing_document, get_insertion_document, get_domain_prefix,
       get_domain_insertion, insertable, get_insertion_aliases, make_insertion_document,
       get_insertion_names, get_insertion_candidates, complete_insertion, name_completion,
       resolve_insertion,
       insert_document_operation, append_insertion_operation, move_to_field,
       replace_selected_document
export DocumentNothing, DocumentInsertion



# ── DocumentBase (abstract) ───────────────────────────────────────────────────

abstract type DocumentBase <: Document end

# ── DocumentNothing ───────────────────────────────────────────────────────────

const DOCUMENT_NOTHING_VALUE = "Empty document"

"""
    DocumentNothing(; selection=nothing)

A document that represents the absence of content. Its display value is the
class-level constant `"Empty document"`.
"""
@document struct DocumentNothing <: DocumentBase
end

value(::DocumentNothing) = DOCUMENT_NOTHING_VALUE

# ── DocumentInsertion ─────────────────────────────────────────────────────────

const DOCUMENT_INSERTION_PREFIX = "Insert a new "
const DOCUMENT_INSERTION_SUFFIX = " here"

"""
    DocumentInsertion(value; font=nothing, selection=nothing)

An insertion placeholder document.  `value` is the editable string being
inserted.  `font` is the optional display font (style/font, not yet ported).
The prefix `"Insert a new "` and suffix `" here"` are class-level constants.
"""
@document struct DocumentInsertion <: DocumentBase
    value::String = ""
    font::Any = nothing
end

DocumentInsertion(value::AbstractString; font=nothing, selection=nothing) =
    DocumentInsertion(Cell(String(value)), Cell(font), Cell(selection))

prefix(::DocumentInsertion) = DOCUMENT_INSERTION_PREFIX
suffix(::DocumentInsertion) = DOCUMENT_INSERTION_SUFFIX

# A DocumentInsertion's `value` (the editable insertion text) is a plain string,
# so text-replace edits are handled generically by `splice_value!` (see
# OperationModule). No per-type method is needed.

# ── DocumentReference ─────────────────────────────────────────────────────────

"""
    DocumentReference(path; selection=nothing)

A document that holds a reference path into another document tree.
"""
@document struct DocumentReference <: DocumentBase
    path::Reference
end

DocumentReference(path::Reference; selection=nothing) =
    DocumentReference(Cell(path), Cell(selection))

# The load/save/import/export document operations now live with the serializers
# (see the module docstring): binary in `SerializationModule`, natural in
# `FileFormatModule`.


include("Domain.jl")

end # module
