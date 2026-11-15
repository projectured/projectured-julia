"""
    ProjecturedBuilder

The builder of native binaries, a tool of this repository: it loads in the
environment `environment/build`, and no package of the editor depends on it.
The slice is `BuilderModule`, in `source/tool/builder/`; this package includes
it and exports every name it exports.
"""
module ProjecturedBuilder

include("../../../source/tool/builder/BuilderModule.jl")

# A person loads this package by name, so its names are exported here.
using .BuilderModule
for _n in names(BuilderModule)
    _n === :BuilderModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

# The calls of the command that a reactive rebuild compiles, in
# `precompile/rebuild.txt`, so that a rebuild compiles none of them. There is no
# workload: a build can not run while the package precompiles.
using ProjecturedPrecompile: @compile_ahead
@compile_ahead

end # module ProjecturedBuilder
