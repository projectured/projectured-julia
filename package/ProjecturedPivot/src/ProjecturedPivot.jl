"""
    ProjecturedPivot

The pivot domain.

The pivot table, its dimensions and its measures, the cross table that cuts the
rows of any table of the table interface into parts, and the view of the parts.
A cell can show a chart of its part, so this depends on `ProjecturedChart`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself. The `parentmodule` guard skips a package's re-exported aliases of a
lower package, so each module is bound once, under its own name.
"""
module ProjecturedPivot

using ProjecturedChart
using ProjecturedKernel
using ProjecturedPlatform

for _src in (ProjecturedChart, ProjecturedKernel, ProjecturedPlatform)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/domain/pivot/PivotModule.jl")

# The names of the domain at the level of the package, so that `using ProjecturedPivot`
# gives them, as `using ProjecturedPlatform` gives the names of the platform.
using .PivotModule
for _n in names(PivotModule)
    _n === :PivotModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

end # module ProjecturedPivot
