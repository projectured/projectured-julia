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

end # module ProjecturedBuilder
