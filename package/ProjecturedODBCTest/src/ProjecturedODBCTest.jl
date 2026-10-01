"""
    ProjecturedODBCTest

Test package for the opt-in `ProjecturedODBC` adapter. Hosts the live-database
suites moved down from the umbrella:

- `DatabaseTest` — the ODBC adapter, raw execute/insert, and DDL round-trips;
- `DbCatalogTest` — the catalog introspection + DbCatalog projections.

Most tests skip when no database is reachable (`skip_if_no_db`), so the suite is
inert without a live DB. Needs the ODBC driver, so it precompiles and runs only
where that is installed.
"""
module ProjecturedODBCTest

using Test
import ProjecturedConsole
import ProjecturedDatabase
import ProjecturedDBCatalog
import ProjecturedKernel
import ProjecturedODBC
import ProjecturedPDF
import ProjecturedPlatform
import ProjecturedSQL
using ProjecturedKernelTest

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedDatabase, ProjecturedDBCatalog,
                  ProjecturedKernel, ProjecturedODBC, ProjecturedPDF, ProjecturedSQL)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

# Live-DB fixture helpers shared by the two suites (moved down with them from the
# umbrella). `execute_db_raw` / `insert_into_db!` / `RawDatabaseResult` come from
# `using ProjecturedODBC`.
include("../../../test/adapter/odbc/OdbcSuite.jl")

end # module ProjecturedODBCTest
