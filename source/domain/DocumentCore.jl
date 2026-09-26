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
an assistant pane or the form that starts a run. Such a document can still be
pasted somewhere else: a copy of it is the duplicate that its kind declares.

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

"""
    accepts_pasted_text(document) -> Bool

Whether a paste may put text into a string of `document`, or of a document
inside it. `true` by default. A domain answers `false` for a document whose text
a paste must leave alone, such as a record.

It is not `accepts_pasted_document`. A tool refuses a pasted document, and still
takes text in its fields, because a person types there.
"""
accepts_pasted_text(::Any) = true

# ── What a new tab may share a pane group with ────────────────────────────────

"""
    accepts_opened_file(document) -> Bool

Whether the pane group `document` sits in may also take a newly opened file, or
a new pane that no caller placed, as a sibling tab. `true` by default. A domain
answers `false` for a document a new tab must not crowd: an explorer a person
opened the file from, or a running conversation.
"""
accepts_opened_file(::Any) = true

# ── What a document says about itself in one glance ───────────────────────────

"""
    compute_tooltip(document) -> Document | Nothing

What to show about `document` when a person rests the pointer on it, or
`nothing` when it has nothing to say. `nothing` by default.

**A widget stores its answer; every other document computes one.** That is the
whole of the difference. A widget carries a `tooltip` field, which whoever built
it set from outside, because a button knows nothing about why it is there. A
Julia function definition computes its signature and the prose of its docstring;
a JSON node computes what is worth saying about that node. Hence `compute_`, and
not `find_`: most answers are built, and only the widget's is looked up.

A method answers a `Document`. Where a one-line tooltip is what a caller wants
to write, the slice that offers the field wraps the string, because this slice
names no document type of its own.

See also `compute_context_menu`, which asks the same question of the same
document and is answered the same two ways.
"""
compute_tooltip(::Any) = nothing

"""
    compute_context_menu(document) -> Document | Nothing

The menu to open when a person presses the right button on `document`, or
`nothing` when it offers none. `nothing` by default.

The two kinds of answer are the two of `compute_tooltip`. A widget reads a
`context_menu` field that whoever built it set. Every other document computes its
menu, which is what makes the menu worth having: a JSON array offers to add an
element, and no field set from outside could have said that.
"""
compute_context_menu(::Any) = nothing
