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

# The duplicate of an empty tab is another empty tab.
has_document_duplicate(::DocumentNothing) = true

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

# ── What a paste may replace ──────────────────────────────────────────────────

"""
    accepts_pasted_document(document) -> Bool

Whether a pasted document may replace `document`, or a document inside it.
`true` by default. A domain answers `false` for a document that a paste must
leave alone: a record, such as the history of a conversation, or a tool, such as
an assistant pane or the form that starts a run. Such a document is not copied,
noted or pasted either.

It speaks only to a pasted document. An edit that a document's own reader
answers, such as typing into a form, does not ask.
"""
accepts_pasted_document(::Any) = true

"""
    accepts_pasted_replacement(document, value) -> Bool

Whether a pasted `value` may take the place of `document`. `true` by default. A
domain that keeps a structure answers `false` where a pasted value would break
it: a pane of a window is never replaced by a paste, and a pane is never pasted.
"""
accepts_pasted_replacement(::Any, ::Any) = true
