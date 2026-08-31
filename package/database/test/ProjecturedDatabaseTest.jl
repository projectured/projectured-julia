"""
    ProjecturedDatabaseTest

The Database tier of the test-package DAG: the suites whose fixtures are database
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_database_domain()`.
"""
module ProjecturedDatabaseTest

using Test
import ProjecturedDatabase
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
using ProjecturedDatabaseExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDatabase, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

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


include("document/DatabaseTest.jl")

"""
    test_database_layering()

Static layered-architecture guard for `ProjecturedDatabase`.
"""
function test_database_layering()
    main = package_source_root(ProjecturedDatabase)
    check_layering(main, pathof(ProjecturedDatabase);
                   name = "database",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedDatabase; all = true)
                         if isdefined(ProjecturedDatabase, n) &&
                            getfield(ProjecturedDatabase, n) isa Module &&
                            getfield(ProjecturedDatabase, n) !== ProjecturedDatabase &&
                            parentmodule(getfield(ProjecturedDatabase, n)) !== ProjecturedDatabase))
end

"""
    test_database_domain()

Run this package's whole suite: the layering guard and every database test.
"""
function test_database_domain()
    @testset "ProjecturedDatabase" begin
        test_database_layering()
        test_database_documents()
    end
end

export test_database_domain, test_database_layering, test_database_documents

end # module ProjecturedDatabaseTest
