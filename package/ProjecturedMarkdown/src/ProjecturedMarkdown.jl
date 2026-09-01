"""
    ProjecturedMarkdown

The Markdown source domain.

The block and inline documents, the text parser, the syntax projection, the
file wrapper, and the layout projection that renders a page as a stack of
blocks rather than as one syntax tree.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedMarkdown

using ProjecturedCollection
using ProjecturedFileFormat
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedLayout
using ProjecturedNatural
using ProjecturedPrimitive
using ProjecturedProjection
using ProjecturedSerialization
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText
using ProjecturedWidget

for _src in (ProjecturedCollection, ProjecturedFileFormat, ProjecturedGraphics, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPrimitive, ProjecturedProjection, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedWidget)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/markdown/MarkdownDocument.jl")
include("../../../source/markdown/MarkdownParser.jl")
include("../../../source/markdown/MarkdownToSyntax.jl")
include("../../../source/markdown/MarkdownFile.jl")
include("../../../source/markdown/MarkdownToLayout.jl")

end # module ProjecturedMarkdown
