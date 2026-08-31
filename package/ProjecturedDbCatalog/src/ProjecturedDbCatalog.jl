"""
    ProjecturedDbCatalog

The database catalog domain.

The schema, table and column documents, the projection that turns a catalog
query into SQL, and the syntax projection. It depends on `ProjecturedSql`
because its output is a SQL statement.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedDbCatalog

using ProjecturedCollection
using ProjecturedKernel
using ProjecturedProjection
using ProjecturedSql
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText
using ProjecturedSql

for _src in (ProjecturedCollection, ProjecturedKernel, ProjecturedProjection, ProjecturedSql, ProjecturedStyle, ProjecturedSyntax, ProjecturedText)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/dbcatalog/DbCatalog.jl")
include("../../../source/dbcatalog/DbCatalogToSql.jl")
include("../../../source/dbcatalog/DbCatalogToSyntax.jl")

end # module ProjecturedDbCatalog
