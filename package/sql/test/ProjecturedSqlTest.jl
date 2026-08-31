"""
    ProjecturedSqlTest

The Sql tier of the test-package DAG: the suites whose fixtures are sql
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_sql()`.
"""
module ProjecturedSqlTest

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
import ProjecturedSql
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedKernelTest
using ProjecturedSubstrateTest
using ProjecturedSqlExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedSql, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

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

include("document/SqlDocumentTest.jl")
include("document/SqlParserTest.jl")
include("projection/SqlToSyntaxTest.jl")

"""
    test_sql_layering()

Static layered-architecture guard for `ProjecturedSql`.
"""
function test_sql_layering()
    main = normpath(dirname(pathof(ProjecturedSql)))
    check_layering(main, joinpath(main, "ProjecturedSql.jl");
                   name = "sql",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedSql; all = true)
                         if isdefined(ProjecturedSql, n) &&
                            getfield(ProjecturedSql, n) isa Module &&
                            getfield(ProjecturedSql, n) !== ProjecturedSql &&
                            parentmodule(getfield(ProjecturedSql, n)) !== ProjecturedSql))
end

"""
    test_sql()

Run this package's whole suite: the layering guard and every sql test.
"""
function test_sql()
    @testset "ProjecturedSql" begin
        test_sql_layering()
        test_sql_parser()
        test_sql_to_syntax()
        test_sql_insert_update_selection()
        test_sql_to_syntax_selection()
        test_sql_ddl()
        test_sql_ddl_selection()
    end
end

export test_sql, test_sql_layering, test_sql_parser
export test_sql_to_syntax, test_sql_insert_update_selection, test_sql_to_syntax_selection
export test_sql_ddl, test_sql_ddl_selection

end # module ProjecturedSqlTest
