"""
    ProjecturedChartTest

The Chart tier of the test-package DAG: the suites whose fixtures are chart
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_chart()`.
"""
module ProjecturedChartTest

using Test
import ProjecturedChart
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedNatural
import ProjecturedFileFormat
import ProjecturedGestureLog
import ProjecturedGestureHelp
import ProjecturedInspector
import ProjecturedTooltip
import ProjecturedClipboard
import ProjecturedPane
import ProjecturedSyntax
import ProjecturedWidget
import ProjecturedText
import ProjecturedLayout
import ProjecturedScreen
import ProjecturedGraphics
import ProjecturedPlot
import ProjecturedVersioning
import ProjecturedFocus
import ProjecturedDragging
import ProjecturedReflection
import ProjecturedProjection
import ProjecturedComponent
import ProjecturedStyle
import ProjecturedSerialization
import ProjecturedDomain
import ProjecturedPrimitive
import ProjecturedCollection
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedKernelTest
using ProjecturedSubstrateTest
using ProjecturedChartExample

const _SOURCES = (ProjecturedChart, ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

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

include("projection/ChartTest.jl")

"""
    test_chart_layering()

Static layered-architecture guard for `ProjecturedChart`.
"""
function test_chart_layering()
    main = package_source_root(ProjecturedChart)
    check_layering(main, pathof(ProjecturedChart);
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
