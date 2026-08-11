"""
    ProjecturedMarkdownTest

The Markdown tier of the test-package DAG: the suites whose fixtures are markdown
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_markdown()`.
"""
module ProjecturedMarkdownTest

using Test
import ProjecturedBase
import ProjecturedKernel
import ProjecturedMarkdown
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedMarkdownExample

const _SOURCES = (ProjecturedBase, ProjecturedKernel, ProjecturedMarkdown, ProjecturedVisual)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("serializer/MarkdownEmbedTest.jl")

"""
    test_markdown_layering()

Static layered-architecture guard for `ProjecturedMarkdown`.
"""
function test_markdown_layering()
    main = normpath(dirname(pathof(ProjecturedMarkdown)))
    check_layering(main, joinpath(main, "ProjecturedMarkdown.jl");
                   name = "markdown",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedMarkdown; all = true)
                         if isdefined(ProjecturedMarkdown, n) &&
                            getfield(ProjecturedMarkdown, n) isa Module &&
                            getfield(ProjecturedMarkdown, n) !== ProjecturedMarkdown &&
                            parentmodule(getfield(ProjecturedMarkdown, n)) !== ProjecturedMarkdown))
end

"""
    test_markdown()

Run this package's whole suite: the layering guard and every markdown test.
"""
function test_markdown()
    @testset "ProjecturedMarkdown" begin
        test_markdown_layering()
        test_markdown_embed()
    end
end

export test_markdown, test_markdown_layering, test_markdown_embed

end # module ProjecturedMarkdownTest
