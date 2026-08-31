"""
    NaturalFormatModule

Natural (human-readable) document interchange — `import_document` /
`export_document` — for the domains that register a text **parser** and a text
**printer** through this module's seams.

- **Import** reads a file and parses it into a document, dispatched by file
  extension to the domain parser registered on `parse_natural`.
- **Export** renders a document to text **through its projection** — the
  domain's `natural_syntax_projection` followed by the shared
  `SyntaxToText → TextToString` printers — and writes it. There is no
  hand-written unparser; the printer *is* the natural-text producer.

Each source domain registers three one-line methods (in a file it already has):
`natural_syntax_projection(::JsonDocument)` returns its `*ToSyntax` projection,
`natural_extension(::JsonDocument)` its file extension, and
`parse_natural(::Val{:json}, text)` its parser. The shared
`SyntaxToText → TextToString` tail lives here, so a domain never repeats it —
which is why this module sits in `visual` (it names the visual text printers),
not `base`.

Unlike the binary format ([`BinarySerializationModule`](@ref)), this is portable
and editable outside ProjecturEd, but lossy w.r.t. editor-only state: selection
and collapse are not represented, and a document carrying an *insertion
placeholder* has no valid natural-text form, so its export will not re-parse.
Round-trip on real data documents; not on editor scaffolding.
"""
module NaturalFormatModule

import ..ProjectionApiModule: print_document
import ..DocumentModule: Document
import ..OperationModule: Operation, evaluate_operation
import ..ChainingProjectionModule: ChainingProjection
import ..RecursiveProjectionModule: RecursiveProjection
import ..SyntaxToTextModule: SyntaxToText
import ..TextToStringModule: TextToString

export natural_syntax_projection, natural_extension, natural_format, parse_natural,
       document_to_text, import_document, export_document,
       ImportDocumentOperation, ExportDocumentOperation

# ── Per-domain seams ────────────────────────────────────────────────────────
# Each source domain registers these in a file it already has, dispatching on
# its abstract document supertype for the forward direction (export) and on
# `Val{:ext}` for the reverse (import). The shared SyntaxToText → TextToString
# tail stays here, so a domain registers only its own ToSyntax stage.

"""
    natural_syntax_projection(document) -> Projection

The first projection stage that turns `document`'s domain into a syntax tree
(its `*ToSyntax`). Registered per domain; errors for a domain with no printer.
"""
natural_syntax_projection(d) =
    error("document_to_text: no natural text projection for $(typeof(d))")

"""
    natural_extension(document) -> String

The natural file extension `document` exports as (e.g. `".json"`). Registered
per domain; errors for a domain with no natural format.
"""
natural_extension(d) =
    error("export_document: no natural format for $(typeof(d))")

"""
    parse_natural(::Val{ext}, text) -> Document

Parse `text` of the format named by the extension symbol `ext` (e.g. `:json`).
Registered per domain; an unregistered extension has no method — `import_document`
checks `applicable` and errors cleanly rather than throwing a `MethodError`.
"""
function parse_natural end

"""
    natural_format(::Type{<:Document}) -> Symbol | Nothing

The format key a domain's documents are written in — `JsonDocument` → `:json`.
It is the type-level inverse of [`natural_extension`](@ref), and it is what turns
a **type** into the key [`parse_natural`](@ref) takes.

`natural_extension` answers for an instance, which a caller that holds a document
already has. A caller that holds only a type — the insertion a person is typing
into, before there is anything to parse — has no instance to ask, and this is the
seam it asks instead.

Registered per domain, in the same file as `parse_natural`, on the domain's
abstract root. `nothing` for every type no domain claimed.
"""
natural_format(::Type) = nothing

_ext_symbol(ext::AbstractString) = isempty(ext) ? Symbol("") : Symbol(SubString(ext, 2))

# ── Export ──────────────────────────────────────────────────────────────────

"""
    document_to_text(document) -> String

Render `document` to its natural text by running the domain's
`natural_syntax_projection → SyntaxToText → TextToString` printer and flattening
the result. The text is the editor's rendered form (indented), which the domain
parser re-reads.
"""
function document_to_text(document::Document)
    pipeline = ChainingProjection(
        RecursiveProjection(natural_syntax_projection(document)),
        RecursiveProjection(SyntaxToText()),
        RecursiveProjection(TextToString()),
    )
    String(print_document(pipeline, document).output)
end

# ── Import / export file I/O ─────────────────────────────────────────────────

"""
    import_document(path) -> Document

Read and parse `path` into a document, choosing the parser by file extension.
Errors on an extension no domain registered.
"""
function import_document(path::AbstractString)
    ext  = lowercase(splitext(path)[2])
    text = read(path, String)
    v    = Val(_ext_symbol(ext))
    applicable(parse_natural, v, text) ? parse_natural(v, text) :
        error("import_document: unsupported extension $(repr(ext)) for $(repr(path))")
end

"""
    export_document(document, path) -> path

Write `document`'s natural text (see [`document_to_text`](@ref)) to `path`. The
projection is chosen by the document's type, so the content is always correct for
the document; the guard only rejects writing it under a *different* registered
format's extension (which would make a later `import_document` pick the wrong
parser).
"""
function export_document(document::Document, path::AbstractString)
    ext     = lowercase(splitext(path)[2])
    natural = natural_extension(document)
    v       = Val(_ext_symbol(ext))
    (applicable(parse_natural, v, "") && ext != natural) &&
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
