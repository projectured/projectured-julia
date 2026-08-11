"""
    ProjecturedProcessTest

The Process tier of the test-package DAG: the suites whose fixtures are process
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_process()`.
"""
module ProjecturedProcessTest

using Test
import ProjecturedGraph
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedNaturalProjection
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
import ProjecturedProcess
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedKernelTest
using ProjecturedSubstrateTest
using ProjecturedProcessExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraph, ProjecturedGraphics, ProjecturedInspector, ProjecturedJulia, ProjecturedKernel, ProjecturedLayout, ProjecturedNaturalProjection, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProcess, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

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

include("document/ProcessTest.jl")
include("projection/ProcessDebugTest.jl")
include("projection/ProcessDiagramTest.jl")
include("projection/ProcessToJuliaCodeTest.jl")
include("projection/ProcessToSyntaxTest.jl")

"""
    test_process_layering()

Static layered-architecture guard for `ProjecturedProcess`.
"""
function test_process_layering()
    main = normpath(dirname(pathof(ProjecturedProcess)))
    check_layering(main, joinpath(main, "ProjecturedProcess.jl");
                   name = "process",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedProcess; all = true)
                         if isdefined(ProjecturedProcess, n) &&
                            getfield(ProjecturedProcess, n) isa Module &&
                            getfield(ProjecturedProcess, n) !== ProjecturedProcess &&
                            parentmodule(getfield(ProjecturedProcess, n)) !== ProjecturedProcess))
end

"""
    test_process()

Run this package's whole suite: the layering guard and every process test.
"""
function test_process()
    @testset "ProjecturedProcess" begin
        test_process_layering()
        test_process_document()
        test_process_debug()
        test_process_diagram()
        test_process_to_julia_code()
        test_process_to_syntax()
    end
end

export test_process, test_process_layering, test_process_document, test_process
export test_process_debug, test_process_diagram, test_process_to_julia_code
export test_process_to_syntax

end # module ProjecturedProcessTest
