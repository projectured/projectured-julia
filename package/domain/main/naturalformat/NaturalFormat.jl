"""
    NaturalFormatModule

Natural (human-readable) document interchange — `import_document` /
`export_document` — for the domains that have a text **parser** and a text
**printer**.

- **Import** reads a file and parses it into a document, dispatched by file
  extension to the domain parser (`.json`→`jsonparse`, `.xml`→`xmlparse`,
  `.sql`→`sqlparse`, `.jl`→`juliaparse`).
- **Export** renders a document to text **through its projection** — the same
  `*ToSyntax → SyntaxToText` printer the editor displays, flattened to a `String`
  by `TextToString` — and writes it. There is no hand-written unparser; the
  printer *is* the natural-text producer.

Unlike the binary format ([`BinarySerializationModule`](@ref)), this is portable
and editable outside ProjecturEd, but lossy w.r.t. editor-only state: selection
and collapse are not represented, and a document carrying an *insertion
placeholder* (`JsonInsertion`, `XmlInsertion`, …) has no valid natural-text form,
so its export will not re-parse. Round-trip on real data documents; not on
editor scaffolding.
"""
module NaturalFormatModule

import ..ProjectionApiModule: print_document
import ..DocumentApiModule: Document
import ..OperationApiModule: Operation, evaluate_operation
import ..ChainingProjectionModule: ChainingProjection
import ..RecursiveProjectionModule: RecursiveProjection
import ..SyntaxToTextModule: SyntaxToText
import ..TextToStringModule: TextToString
import ..JsonToSyntaxModule: JsonToSyntax
import ..XmlToSyntaxModule: XmlToSyntax
import ..SqlToSyntaxModule: SqlToSyntax
import ..JuliaToSyntaxModule: JuliaToSyntax
import ..JsonModule: JsonDocument
import ..XmlModule: XmlDocument
import ..SqlDocumentModule: SqlDocument
import ..JuliaModule: JuliaDocument
import ..JsonParserModule: jsonparse
import ..XmlParserModule: xmlparse
import ..SqlParserModule: sqlparse
import ..JuliaParserModule: juliaparse

export document_to_text, import_document, export_document,
       ImportDocumentOperation, ExportDocumentOperation

# ── Per-domain text projection (export) ─────────────────────────────────────
# The first projection stage that turns the domain's own document into a syntax
# tree. The rest of the pipeline (`SyntaxToText` → `TextToString`) is shared.
# Dispatched on the document's abstract domain supertype, so any node kind of a
# domain (a whole SQL statement, an XML element, …) selects its domain printer.
_domain_to_syntax(::JsonDocument)  = JsonToSyntax()
_domain_to_syntax(::XmlDocument)   = XmlToSyntax()
_domain_to_syntax(::SqlDocument)   = SqlToSyntax()
_domain_to_syntax(::JuliaDocument) = JuliaToSyntax()
_domain_to_syntax(d) =
    error("document_to_text: no natural text projection for $(typeof(d))")

# The natural file extension a document exports as, mirroring `_domain_to_syntax`.
_natural_extension(::JsonDocument)  = ".json"
_natural_extension(::XmlDocument)   = ".xml"
_natural_extension(::SqlDocument)   = ".sql"
_natural_extension(::JuliaDocument) = ".jl"
_natural_extension(d) =
    error("export_document: no natural format for $(typeof(d))")

const _KNOWN_EXTENSIONS = (".json", ".xml", ".sql", ".jl")

"""
    document_to_text(document) -> String

Render `document` to its natural text by running the domain's
`*ToSyntax → SyntaxToText → TextToString` printer and flattening the result. The
text is the editor's rendered form (indented), which the domain parser re-reads.
"""
function document_to_text(document::Document)
    pipeline = ChainingProjection(
        RecursiveProjection(_domain_to_syntax(document)),
        RecursiveProjection(SyntaxToText()),
        RecursiveProjection(TextToString()),
    )
    String(print_document(pipeline, document).output[])
end

# ── Import / export ─────────────────────────────────────────────────────────

"""
    import_document(path) -> Document

Read and parse `path` into a document, choosing the parser by file extension.
Errors on an unknown extension.
"""
function import_document(path::AbstractString)
    ext = lowercase(splitext(path)[2])
    text = read(path, String)
    ext == ".json" ? jsonparse(text)  :
    ext == ".xml"  ? xmlparse(text)   :
    ext == ".sql"  ? sqlparse(text)   :
    ext == ".jl"   ? juliaparse(text) :
    error("import_document: unsupported extension $(repr(ext)) for $(repr(path))")
end

"""
    export_document(document, path) -> path

Write `document`'s natural text (see [`document_to_text`](@ref)) to `path`. The
projection is chosen by the document's type, so the content is always correct for
the document; the guard only rejects writing it under a *different* known
format's extension (which would make a later `import_document` pick the wrong
parser).
"""
function export_document(document::Document, path::AbstractString)
    ext = lowercase(splitext(path)[2])
    natural = _natural_extension(document)
    (ext in _KNOWN_EXTENSIONS && ext != natural) &&
        error("export_document: $(typeof(document)) exports as $natural, not $ext")
    write(path, document_to_text(document))
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
