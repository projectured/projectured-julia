"""
    ProjecturedGraphTest

The Graph tier of the test-package DAG: the suites whose fixtures are graph
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_graph()`.
"""
module ProjecturedGraphTest

using Test
import ProjecturedBase
import ProjecturedGraph
import ProjecturedKernel
import ProjecturedVisual
using ProjecturedXmlExample
using ProjecturedKernelExample
using ProjecturedVisualExample
import ProjecturedJson
import ProjecturedXml
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedGraphExample

const _SOURCES = (ProjecturedXml, ProjecturedJson, ProjecturedBase, ProjecturedGraph, ProjecturedKernel, ProjecturedVisual)

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

include("projection/GraphTest.jl")

"""
    test_graph_layering()

Static layered-architecture guard for `ProjecturedGraph`.
"""
function test_graph_layering()
    main = normpath(dirname(pathof(ProjecturedGraph)))
    check_layering(main, joinpath(main, "ProjecturedGraph.jl");
                   name = "graph",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedGraph; all = true)
                         if isdefined(ProjecturedGraph, n) &&
                            getfield(ProjecturedGraph, n) isa Module &&
                            getfield(ProjecturedGraph, n) !== ProjecturedGraph &&
                            parentmodule(getfield(ProjecturedGraph, n)) !== ProjecturedGraph))
end

"""
    test_graph()

Run this package's whole suite: the layering guard and every graph test.
"""
function test_graph()
    @testset "ProjecturedGraph" begin
        test_graph_layering()
        test_graph_projection()
    end
end

export test_graph, test_graph_layering, test_graph_projection, test_graph

end # module ProjecturedGraphTest
