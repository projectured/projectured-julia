"""
    ProjecturedMarkdownExample

The Markdown tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedMarkdownExample

import ProjecturedBase
import ProjecturedKernel
import ProjecturedMarkdown
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedBase, ProjecturedKernel, ProjecturedMarkdown, ProjecturedVisual)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("document/Markdown.jl")
include("projection/Markdown.jl")

export make_markdown_text_document_example, make_markdown_code_document_example, make_markdown_thematic_break_document_example
export make_markdown_insertion_document_example, make_markdown_heading_document_example, make_markdown_paragraph_document_example
export make_markdown_list_document_example, make_markdown_emphasis_document_example, make_markdown_link_document_example
export make_markdown_strong_document_example, make_markdown_code_block_document_example, make_markdown_image_document_example
export make_markdown_list_item_document_example, make_markdown_quote_document_example, make_markdown_root_document_example
export make_markdown_document_example, make_markdown_projection_example, make_markdown_rendered_projection_example

end # module ProjecturedMarkdownExample
