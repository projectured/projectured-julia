"""
    ProjecturedFsmTest

The Fsm tier of the test-package DAG: the suites whose fixtures are fsm
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_fsm()`.
"""
module ProjecturedFsmTest

using Test
import ProjecturedFsm
import ProjecturedGraph
import ProjecturedJulia
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
using ProjecturedXmlExample
using ProjecturedGraphExample
using ProjecturedKernelExample
using ProjecturedSubstrateExample
import ProjecturedJson
import ProjecturedXml
using ProjecturedKernelTest
using ProjecturedSubstrateTest
using ProjecturedFsmExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedFsm, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraph, ProjecturedGraphics, ProjecturedInspector, ProjecturedJson, ProjecturedJulia, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget, ProjecturedXml)

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

include("document/FsmTest.jl")
include("projection/FsmDiagramTest.jl")
include("projection/FsmToJuliaCodeTest.jl")
include("projection/FsmToSyntaxTest.jl")

"""
    test_fsm_layering()

Static layered-architecture guard for `ProjecturedFsm`.
"""
function test_fsm_layering()
    main = normpath(dirname(pathof(ProjecturedFsm)))
    check_layering(main, joinpath(main, "ProjecturedFsm.jl");
                   name = "fsm",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedFsm; all = true)
                         if isdefined(ProjecturedFsm, n) &&
                            getfield(ProjecturedFsm, n) isa Module &&
                            getfield(ProjecturedFsm, n) !== ProjecturedFsm &&
                            parentmodule(getfield(ProjecturedFsm, n)) !== ProjecturedFsm))
end

"""
    test_fsm()

Run this package's whole suite: the layering guard and every fsm test.
"""
function test_fsm()
    @testset "ProjecturedFsm" begin
        test_fsm_layering()
        test_fsm_document()
        test_fsm_diagram()
        test_fsm_to_julia_code()
        test_fsm_to_syntax()
    end
end

export test_fsm, test_fsm_layering, test_fsm_document, test_fsm
export test_fsm_diagram, test_fsm_to_julia_code, test_fsm_to_syntax

end # module ProjecturedFsmTest
