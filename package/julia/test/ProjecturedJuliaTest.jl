"""
    ProjecturedJuliaTest

The Julia tier of the test-package DAG: the suites whose fixtures are julia
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_julia()`.
"""
module ProjecturedJuliaTest

using Test
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
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedKernelTest
using ProjecturedSubstrateTest
using ProjecturedJuliaExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedJulia, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

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

include("document/JuliaParserTest.jl")
include("document/JuliaDefinitionTest.jl")
include("editor/JuliaTypeinTest.jl")

"""
    test_julia_layering()

Static layered-architecture guard for `ProjecturedJulia`.
"""
function test_julia_layering()
    main = package_source_root(ProjecturedJulia)
    check_layering(main, pathof(ProjecturedJulia);
                   name = "julia",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedJulia; all = true)
                         if isdefined(ProjecturedJulia, n) &&
                            getfield(ProjecturedJulia, n) isa Module &&
                            getfield(ProjecturedJulia, n) !== ProjecturedJulia &&
                            parentmodule(getfield(ProjecturedJulia, n)) !== ProjecturedJulia))
end

"""
    test_julia()

Run this package's whole suite: the layering guard and every julia test.
"""
function test_julia()
    @testset "ProjecturedJulia" begin
        test_julia_layering()
        test_julia_parser()
        test_julia_definition()
        test_julia_typein()
    end
end

export test_julia, test_julia_layering, test_julia_parser, test_julia_definition
export test_julia_typein

end # module ProjecturedJuliaTest
