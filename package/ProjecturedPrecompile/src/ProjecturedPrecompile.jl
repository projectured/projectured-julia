"""
    ProjecturedPrecompile

The one mechanism that compiles a package ahead of time. The slice is
`PrecompileModule`, in `source/tool/precompile/`; this package includes it and
exports every name it exports.
"""
module ProjecturedPrecompile

include("../../../source/tool/precompile/PrecompileModule.jl")

using .PrecompileModule
for _n in names(PrecompileModule)
    _n === :PrecompileModule || Core.eval(@__MODULE__, Expr(:export, _n))
end

end # module ProjecturedPrecompile
