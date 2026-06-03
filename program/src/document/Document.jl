"""
    DocumentCoreModule

The core document domain. Models document-level identity and basic structural
documents: a base abstract type, a nothing-document, an insertion placeholder,
and a reference document. Also defines the load/save/export document operations
and their evaluators.
"""
module DocumentCoreModule

import ..ReactiveModule: Cell
import ..DocumentModule: Document, @document
import ..ReferenceModule: Reference, ReferencePath
import ..OperationApiModule: Operation, evaluate_operation
export DocumentBase, DocumentNothing, DocumentInsertion, DocumentReference,
       LoadDocumentOperation, SaveDocumentOperation, ExportDocumentOperation,
       evaluate_operation,
       IDocumentNothing, IDocumentInsertion, IDocumentReference

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
    selection::Reference
end

DocumentNothing(; selection=nothing) = DocumentNothing(Cell(selection))

value(::DocumentNothing) = DOCUMENT_NOTHING_VALUE

function Base.show(io::IO, ::DocumentNothing)
    print(io, "DocumentNothing()")
end

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
    value::String
    font::Any
    selection::Reference
end

DocumentInsertion(value::AbstractString=""; font=nothing, selection=nothing) =
    DocumentInsertion(Cell(String(value)), Cell(font), Cell(selection))

prefix(::DocumentInsertion) = DOCUMENT_INSERTION_PREFIX
suffix(::DocumentInsertion) = DOCUMENT_INSERTION_SUFFIX

function Base.show(io::IO, d::DocumentInsertion)
    print(io, "DocumentInsertion(", repr(d.value), ")")
end

# ── DocumentReference ─────────────────────────────────────────────────────────

"""
    DocumentReference(path; selection=nothing)

A document that holds a reference path into another document tree.
"""
@document struct DocumentReference <: DocumentBase
    path::ReferencePath
    selection::Reference
end

DocumentReference(path::ReferencePath; selection=nothing) =
    DocumentReference(Cell(path), Cell(selection))

function Base.show(io::IO, d::DocumentReference)
    print(io, "DocumentReference(", d.path, ")")
end

# ── Operations ────────────────────────────────────────────────────────────────

"""
    LoadDocumentOperation(document, filename)

Operation that loads a document from `filename` and stores the result in
`document`'s content cell, updating its selection accordingly.
"""
struct LoadDocumentOperation <: Operation
    document::Document
    filename::String
end

"""
    SaveDocumentOperation(document, filename)

Operation that serialises the content of `document` to `filename`.
"""
struct SaveDocumentOperation <: Operation
    document::Document
    filename::String
end

"""
    ExportDocumentOperation(document, filename)

Operation that exports a human-readable rendering of `document`'s content
to `filename`.
"""
struct ExportDocumentOperation <: Operation
    document::Document
    filename::String
end

# ── Operation evaluation ──────────────────────────────────────────────────────

function evaluate_operation(editor, op::LoadDocumentOperation)
    doc = op.document
    content = call_loader(op.filename)
    doc.content = content
    doc.selection = nothing
end

function evaluate_operation(editor, op::SaveDocumentOperation)
    call_saver(op.filename, op.document.content)
end

function evaluate_operation(editor, op::ExportDocumentOperation)
    open(op.filename, "w") do output
        print_document(op.document.content, output)
    end
end

end # module
