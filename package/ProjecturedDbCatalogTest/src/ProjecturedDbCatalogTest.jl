"""
    ProjecturedDbCatalogTest

The DbCatalog tier of the test-package DAG: the suites whose fixtures are dbcatalog
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_dbcatalog()`.
"""
module ProjecturedDbCatalogTest

using Test
import ProjecturedDbCatalog
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
using ProjecturedDbCatalogExample

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDbCatalog, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedSql, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

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

include("../../../test/dbcatalog/external/DbCatalogSqlTest.jl")

"""
    test_dbcatalog_layering()

Static layered-architecture guard for `ProjecturedDbCatalog`.
"""
function test_dbcatalog_layering()
    main = package_source_root(ProjecturedDbCatalog)
    check_layering(main, pathof(ProjecturedDbCatalog);
                   name = "dbcatalog",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedDbCatalog; all = true)
                         if isdefined(ProjecturedDbCatalog, n) &&
                            getfield(ProjecturedDbCatalog, n) isa Module &&
                            getfield(ProjecturedDbCatalog, n) !== ProjecturedDbCatalog &&
                            parentmodule(getfield(ProjecturedDbCatalog, n)) !== ProjecturedDbCatalog))
end

"""
    test_dbcatalog()

Run this package's whole suite: the layering guard and every dbcatalog test.
"""
function test_dbcatalog()
    @testset "ProjecturedDbCatalog" begin
        test_dbcatalog_layering()
        test_db_catalog_column_to_sql()
        test_db_catalog_table_to_sql()
        test_db_catalog_schema_to_sql()
        test_db_catalog_database_to_sql()
        test_db_catalog_rdbms_to_sql()
        test_db_catalog_marker_eligible()
        test_db_catalog_sql()
    end
end

export test_dbcatalog, test_dbcatalog_layering, test_db_catalog_column_to_sql
export test_db_catalog_table_to_sql, test_db_catalog_schema_to_sql, test_db_catalog_database_to_sql
export test_db_catalog_rdbms_to_sql, test_db_catalog_marker_eligible, test_db_catalog_sql

end # module ProjecturedDbCatalogTest
