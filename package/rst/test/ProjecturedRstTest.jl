"""
    ProjecturedRstTest

The Rst tier of the test-package DAG: the suites whose fixtures are rst
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_rst()`.
"""
module ProjecturedRstTest

using Test
import ProjecturedBase
import ProjecturedKernel
import ProjecturedRst
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedRstExample

const _SOURCES = (ProjecturedBase, ProjecturedKernel, ProjecturedRst, ProjecturedVisual)

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

include("document/RstParserTest.jl")
include("serializer/RstEmbedTest.jl")

"""
    test_rst_layering()

Static layered-architecture guard for `ProjecturedRst`.
"""
function test_rst_layering()
    main = normpath(dirname(pathof(ProjecturedRst)))
    check_layering(main, joinpath(main, "ProjecturedRst.jl");
                   name = "rst",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedRst; all = true)
                         if isdefined(ProjecturedRst, n) &&
                            getfield(ProjecturedRst, n) isa Module &&
                            getfield(ProjecturedRst, n) !== ProjecturedRst &&
                            parentmodule(getfield(ProjecturedRst, n)) !== ProjecturedRst))
end

"""
    test_rst()

Run this package's whole suite: the layering guard and every rst test.
"""
function test_rst()
    @testset "ProjecturedRst" begin
        test_rst_layering()
        test_rst_parser()
        test_rst_round_trip()
        test_rst_embed()
    end
end

export test_rst, test_rst_layering, test_rst_parser
export test_rst_round_trip, test_rst_embed

end # module ProjecturedRstTest
