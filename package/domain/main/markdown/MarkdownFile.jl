"""
    MarkdownFileModule

`MarkdownFile`: a `FileDocument` whose `content` is a
`MarkdownDocument` (the projectured Markdown AST). Parse uses
`markdownparse`; emit runs the standard `MarkdownToSyntax(style=:source)
→ SyntaxToText → TextToString` projection chain via `document_to_text`.
This module also registers `natural_syntax_projection` /
`natural_extension` / `parse_natural` for `MarkdownDocument` so
`document_to_text` works.

**Marker syntax in Markdown.** A cross-file reference reads as a
fenced code block with the info string `pred-ref`:

    ```pred-ref
    <<file("child.md")>>
    ```

Fenced blocks parse robustly (unlike inline link URLs, which the
markdown parser stops at the first `)`). Load walks the AST for
`MarkdownCodeBlock` with `language == "pred-ref"` and rewrites each
into a `ReferenceStub`. Emit is symmetric via a projection extension
(see `MarkdownToSyntax.jl`).
"""
module MarkdownFileModule

import ..CellModule: Cell, ComputedCell, AbstractCell
import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..CollectionModule: CellVector, ComputedCellVector
import ..MarkdownModule: MarkdownDocument, MarkdownRoot, MarkdownParagraph,
                         MarkdownHeading, MarkdownCodeBlock, MarkdownQuote,
                         MarkdownList, MarkdownListItem, MarkdownEmphasis,
                         MarkdownStrong, MarkdownLink
import ..MarkdownParserModule: markdownparse
import ..MarkdownToSyntaxModule: MarkdownToSyntax
import ..NaturalFormatModule: document_to_text, natural_syntax_projection,
                              natural_extension, parse_natural
import ..FileProjectModule: FileDocument, emit_text, populate_file!, content,
                            parse_marker_text, ReferenceStub, LoaderContext,
                            register_file_document_type!

export MarkdownFile, PRED_REF_LANGUAGE

"""
The info string that tags a fenced code block as a cross-file marker:

    ```pred-ref
    <<file("path")>>
    ```
"""
const PRED_REF_LANGUAGE = "pred-ref"

"""
    MarkdownFile(filename, content)

A file document whose `content` is a `MarkdownDocument`. See the
module docstring for the fenced-block marker convention.
"""
@document struct MarkdownFile <: FileDocument
    filename::String
    content::MarkdownDocument = MarkdownRoot()
end

emit_text(f::MarkdownFile) = document_to_text(content(f))

function populate_file!(f::MarkdownFile, filename::AbstractString, ctx::LoaderContext)
    text = read(joinpath(ctx.base_dir, filename), String)
    ast = markdownparse(text)
    ast = _substitute_markers(ast, ctx)
    getfield(f, :content)[] = ast
    f
end

# Unwrap a cell if we've grabbed one via getfield (a `CellVector`'s
# elements are `Cell`s already, so mid-walk we may hold either).
_unwrap(x) = x isa AbstractCell ? x[] : x

_is_marker_block(node::MarkdownCodeBlock) =
    _unwrap(getfield(node, :language)) == PRED_REF_LANGUAGE

function _marker_stub(node::MarkdownCodeBlock, ctx::LoaderContext)
    body = _unwrap(getfield(node, :code))
    src = parse_marker_text(strip(body))
    src === nothing ? node : ReferenceStub(src, ctx)
end

# Traversal: every container replaces its child-slot values in place
# with substituted values. Non-container nodes pass through.
_substitute_markers(node, ctx::LoaderContext) = node

function _substitute_markers(node::MarkdownCodeBlock, ctx::LoaderContext)
    _is_marker_block(node) ? _marker_stub(node, ctx) : node
end

# CellVector-backed containers: rewrite each element in place.
function _visit_vector!(node, field::Symbol, ctx::LoaderContext)
    v = getfield(node, field)[]
    for i in eachindex(v)
        v[i] = _substitute_markers(v[i], ctx)
    end
    node
end

_substitute_markers(n::MarkdownRoot,      ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::MarkdownParagraph, ctx::LoaderContext) = _visit_vector!(n, :content,  ctx)
_substitute_markers(n::MarkdownHeading,   ctx::LoaderContext) = _visit_vector!(n, :content,  ctx)
_substitute_markers(n::MarkdownQuote,     ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::MarkdownList,      ctx::LoaderContext) = _visit_vector!(n, :items,    ctx)
_substitute_markers(n::MarkdownListItem,  ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::MarkdownEmphasis,  ctx::LoaderContext) = _visit_vector!(n, :content,  ctx)
_substitute_markers(n::MarkdownStrong,    ctx::LoaderContext) = _visit_vector!(n, :content,  ctx)
_substitute_markers(n::MarkdownLink,      ctx::LoaderContext) = _visit_vector!(n, :content,  ctx)

# ── natural-format registration ────────────────────────────────────────────
# Markdown didn't previously register with NaturalFormatModule; we add
# the seams here so `document_to_text(::MarkdownDocument)` works
# uniformly with the other formats.

natural_syntax_projection(::MarkdownDocument) = MarkdownToSyntax()
natural_extension(::MarkdownDocument) = ".md"
parse_natural(::Val{:md}, text::AbstractString) = markdownparse(text)

function __init__()
    register_file_document_type!(".md",       MarkdownFile)
    register_file_document_type!(".markdown", MarkdownFile)
end

end # module
