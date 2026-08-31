"""
    ProjecturedSequenceChartTest

The SequenceChart tier of the test-package DAG: the suites whose fixtures are sequencechart
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_sequencechart()`.
"""
module ProjecturedSequenceChartTest

using Test
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
import ProjecturedSequenceChart
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedKernelTest
using ProjecturedSubstrateTest
using ProjecturedSequenceChartExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSequenceChart, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

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

include("projection/SequenceChartGeometryTest.jl")
include("projection/SequenceChartTest.jl")

"""
    test_sequencechart_layering()

Static layered-architecture guard for `ProjecturedSequenceChart`.
"""
function test_sequencechart_layering()
    main = normpath(dirname(pathof(ProjecturedSequenceChart)))
    check_layering(main, joinpath(main, "ProjecturedSequenceChart.jl");
                   name = "sequencechart",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedSequenceChart; all = true)
                         if isdefined(ProjecturedSequenceChart, n) &&
                            getfield(ProjecturedSequenceChart, n) isa Module &&
                            getfield(ProjecturedSequenceChart, n) !== ProjecturedSequenceChart &&
                            parentmodule(getfield(ProjecturedSequenceChart, n)) !== ProjecturedSequenceChart))
end

"""
    test_sequencechart()

Run this package's whole suite: the layering guard and every sequencechart test.
"""
function test_sequencechart()
    @testset "ProjecturedSequenceChart" begin
        test_sequencechart_layering()
        test_sequencechart_geometry()
        test_sequencechart_projection()
        test_sequencechart_scale()
        test_sequencechart_selection()
    end
end

export test_sequencechart, test_sequencechart_layering, test_sequencechart_projection, test_sequencechart_geometry
export test_sequencechart_scale, test_sequencechart_selection

end # module ProjecturedSequenceChartTest
