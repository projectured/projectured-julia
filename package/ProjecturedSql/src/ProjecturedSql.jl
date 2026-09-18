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

using ProjecturedCollection
using ProjecturedDomain
using ProjecturedFileFormat
using ProjecturedKernel
using ProjecturedNatural
using ProjecturedProjection
using ProjecturedSerialization
using ProjecturedStyle
using ProjecturedSyntax
using ProjecturedText

for _src in (ProjecturedCollection, ProjecturedDomain, ProjecturedFileFormat, ProjecturedKernel, ProjecturedNatural, ProjecturedProjection, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/sql/SqlModule.jl")

end # module ProjecturedSql
