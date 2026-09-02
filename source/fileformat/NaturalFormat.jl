"""
    NaturalFormatModule

Reading and writing a document **as a file** — `import_document` /
`export_document` — and the two editor operations that do it.

What a natural notation *is* lives in `ProjecturedNatural`: a domain declares the
rung it starts at, the format it is written in, the extension that names that
format back, and how to read the text in again. This module is the file half
alone: it picks a parser by the extension of a path, and it writes what
`print_natural_text` produced.

Unlike the binary format ([`BinarySerializationModule`](@ref)), this is portable
and editable outside ProjecturEd, but lossy with respect to editor-only state:
selection and collapse are not represented, and a document carrying an *insertion
placeholder* has no valid natural-text form, so its export will not re-parse.
Round-trip on real data documents; not on editor scaffolding.
"""
module NaturalFormatModule

import ..DocumentModule: Document
import ..OperationModule: Operation, evaluate_operation
import ..NaturalNotationModule: get_natural_extension, get_natural_format,
                                has_natural_parser, parse_natural_text,
                                print_natural_text

export import_document, export_document,
       ImportDocumentOperation, ExportDocumentOperation

_ext_symbol(ext::AbstractString) = isempty(ext) ? Symbol("") : Symbol(SubString(ext, 2))

# ── Import / export file I/O ─────────────────────────────────────────────────

"""
    import_document(path) -> Document

Read and parse `path` into a document, choosing the parser by file extension.
Errors on an extension no domain registered.
"""
function import_document(path::AbstractString)
    ext    = lowercase(splitext(path)[2])
    text   = read(path, String)
    format = _ext_symbol(ext)
    has_natural_parser(format) ? parse_natural_text(format, text) :
        error("import_document: unsupported extension $(repr(ext)) for $(repr(path))")
end

"""
    export_document(document, path) -> path

Write `document`'s natural text (see [`print_natural_text`](@ref)) to `path`. The
projection is chosen by the document's type, so the content is always correct for
the document; the guard only rejects writing it under a *different* registered
format's extension (which would make a later `import_document` pick the wrong
parser).
"""
function export_document(document::Document, path::AbstractString)
    ext     = lowercase(splitext(path)[2])
    natural = get_natural_extension(document)
    (has_natural_parser(_ext_symbol(ext)) && ext != natural) &&
        error("export_document: $(typeof(document)) exports as $natural, not $ext")
    write(path, print_natural_text(document))
    path
end

# ── Editor operations ──────────────────────────────────────────────────────

"""
    ExportDocumentOperation(path)

Write `editor.document`'s natural text to `path` (see [`export_document`](@ref)).
A pure side effect; the document is not mutated.
"""
struct ExportDocumentOperation <: Operation
    path::String
end

ExportDocumentOperation(path::AbstractString) = ExportDocumentOperation(String(path))

evaluate_operation(editor, op::ExportDocumentOperation) =
    export_document(editor.document, op.path)

"""
    ImportDocumentOperation(path)

Replace `editor.document` with the document parsed from `path` (see
[`import_document`](@ref)). A whole-root swap: rebind `editor.document` and drop
the cached `editor.iomap` so the next print rebuilds on the new root.
"""
struct ImportDocumentOperation <: Operation
    path::String
end

ImportDocumentOperation(path::AbstractString) = ImportDocumentOperation(String(path))

function evaluate_operation(editor, op::ImportDocumentOperation)
    editor.document = import_document(op.path)
    editor.iomap = nothing
end

end # module
