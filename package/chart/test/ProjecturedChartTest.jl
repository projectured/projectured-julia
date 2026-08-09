"""
    ProjecturedChartTest

The Chart tier of the test-package DAG: the suites whose fixtures are chart
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_chart()`.
"""
module ProjecturedChartTest

using Test
import ProjecturedBase
import ProjecturedChart
import ProjecturedKernel
import ProjecturedVisual
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedChartExample

const _SOURCES = (ProjecturedBase, ProjecturedChart, ProjecturedKernel, ProjecturedVisual)

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

include("projection/ChartTest.jl")

"""
    test_chart_layering()

Static layered-architecture guard for `ProjecturedChart`.
"""
function test_chart_layering()
    main = normpath(dirname(pathof(ProjecturedChart)))
    check_layering(main, joinpath(main, "ProjecturedChart.jl");
                   name = "chart",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedChart; all = true)
                         if isdefined(ProjecturedChart, n) &&
                            getfield(ProjecturedChart, n) isa Module &&
                            getfield(ProjecturedChart, n) !== ProjecturedChart &&
                            parentmodule(getfield(ProjecturedChart, n)) !== ProjecturedChart))
end

"""
    test_chart()

Run this package's whole suite: the layering guard and every chart test.
"""
function test_chart()
    @testset "ProjecturedChart" begin
        test_chart_layering()
        test_chart_projection()
        test_chart_scale()
    end
end

export test_chart, test_chart_layering, test_chart_projection, test_chart
export test_chart_scale

end # module ProjecturedChartTest
