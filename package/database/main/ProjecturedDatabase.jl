"""
    ProjecturedDatabase

The database connection domain.

The database and instance documents, and the `make_database_adapter` seam.
The seam is owned here because a database adapter is a database concept; the
ODBC driver that implements it lives in the opt-in `ProjecturedOdbc`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedDatabase

using ProjecturedKernel

for _src in (ProjecturedKernel)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("DatabaseInstance.jl")
include("Database.jl")
include("DatabaseAdapters.jl")

end # module ProjecturedDatabase
