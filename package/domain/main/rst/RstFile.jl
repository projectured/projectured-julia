"""
    RstFileModule

`RstFile`: a `FileDocument` whose `content` is an `RstDocument` (the
projectured reStructuredText tree). Parse uses `rstparse`; emit runs the
standard `RstToSyntax(style=:source) → SyntaxToText → TextToString`
projection chain through `document_to_text`.

This module also registers `natural_syntax_projection` / `natural_extension`
/ `parse_natural` for `RstDocument`, and `.rst` as a file document type, so
`import_document` and `export_document` reach the slice by extension.

**No marker vocabulary yet.** The markdown slice carries a cross-file
reference convention (a fenced `pred-ref` block). The INET documentation the
slice was built for uses `.. literalinclude::` and `:doc:` instead, and
neither resolves here — see the module docstring of `RstToSyntaxModule`. When
a marker is wanted, the natural place is an `RstComment` whose body opens
with `pred-ref`, which is the RST analogue of the fenced block.
"""
module RstFileModule

import ..CellModule: Cell, AbstractCell
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
import ..RstModule: RstDocument, RstRoot, RstSection, RstText, RstLiteral, RstRole,
                    RstStrong, RstEmphasis
import ..RstParserModule: rstparse
import ..RstToSyntaxModule: RstToSyntax
import ..NaturalFormatModule: document_to_text, natural_syntax_projection,
                              natural_extension, parse_natural
import ..FileProjectModule: FileDocument, emit_text, populate_file!, content,
                            LoaderContext, register_file_document_type!

export RstFile, rst_section, rst_title_text

"""
    RstFile(filename, content)

A file document whose `content` is an `RstDocument`.
"""
@document struct RstFile <: FileDocument
    filename::String
    content::RstDocument = RstRoot()
end

emit_text(f::RstFile) = document_to_text(content(f))

function populate_file!(f::RstFile, filename::AbstractString, ctx::LoaderContext)
    text = read(joinpath(ctx.base_dir, filename), String)
    getfield(f, :content)[] = rstparse(text)
    f
end

# ── natural-format registration ───────────────────────────────────────────────

natural_syntax_projection(::RstDocument) = RstToSyntax()
natural_extension(::RstDocument) = ".rst"
parse_natural(::Val{:rst}, text::AbstractString) = rstparse(text)

# ── Addressing a section by its title ─────────────────────────────────────────

"""
    rst_title_text(section) -> String

The plain text of a section's title, with every inline marker dropped. This is
what addresses a section by name, so `:ned:`Foo`` in a title reads as `Foo`.
"""
function rst_title_text(section::RstSection)
    buffer = IOBuffer()
    _collect_run_text!(buffer, section.title)
    String(take!(buffer))
end

_collect_run_text!(buffer::IO, nodes) = (foreach(n -> _collect_title_text!(buffer, n), nodes); nothing)

_collect_title_text!(buffer::IO, node::RstText)     = (print(buffer, node.content); nothing)
_collect_title_text!(buffer::IO, node::RstLiteral)  = (print(buffer, node.content); nothing)
_collect_title_text!(buffer::IO, node::RstRole)     = (print(buffer, node.content); nothing)
_collect_title_text!(buffer::IO, node::RstStrong)   = _collect_run_text!(buffer, node.content)
_collect_title_text!(buffer::IO, node::RstEmphasis) = _collect_run_text!(buffer, node.content)
_collect_title_text!(::IO, ::Any) = nothing

"""
    rst_section(document, title) -> RstSection or nothing

The section of `document` whose title reads `title`, searched depth first.

The section tree already owns its blocks, so this returns the node itself —
unlike the markdown counterpart, which has to gather the blocks that follow a
heading because markdown headings do not nest.
"""
function rst_section(document, title::AbstractString)
    for element in _elements_of(document)
        element isa RstSection || continue
        rst_title_text(element) == title && return element
        found = rst_section(element, title)
        found === nothing || return found
    end
    nothing
end

_elements_of(document::RstRoot)    = document.elements
_elements_of(document::RstSection) = document.elements
_elements_of(::Any)                = ()

function __init__()
    register_file_document_type!(".rst", RstFile)
end

end # module
