"""
    ProjecturedTulip

The Tulip adapter, a package of its own because it needs Tulip and MathOptInterface.
`using ProjecturedTulip` gives `TulipConstraintSolver`; the slice is `TulipModule`, in `source/adapter/tulip/`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedTulip

using ProjecturedPlatform

for _src in (ProjecturedPlatform,)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/adapter/tulip/TulipModule.jl")

# A person loads this package by name, so its names are exported here.
using .TulipModule: TulipConstraintSolver
export TulipConstraintSolver

end # module ProjecturedTulip
