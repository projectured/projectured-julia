# Fragment of `DomainModule` — the document types every domain builds on: the
# abstract `DocumentBase`, and the empty and insertion placeholders a domain
# inherits.

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
