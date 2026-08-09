"""
    ProjecturedSql

The SQL source domain.

The statement documents (select, insert, update, create), the text parser, and
the syntax projection. `ProjecturedOdbc` runs these statements against a live
database; nothing here needs a driver.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedSql

using ProjecturedKernel
using ProjecturedBase
using ProjecturedVisual

for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("Sql.jl")
include("SqlParser.jl")
include("SqlToSyntax.jl")

end # module ProjecturedSql
