"""
    ProjecturedAnthropic

The Anthropic adapter, a package of its own because it needs HTTP and JSON3.
`using ProjecturedAnthropic` gives `AnthropicLlm`, `get_newest_anthropic_model`, `find_adaptive_model`; the slice is `AnthropicModule`, in `source/adapter/anthropic/`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedAnthropic

using ProjecturedKernel

for _src in (ProjecturedKernel,)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/adapter/anthropic/AnthropicModule.jl")

# A person loads this package by name, so its names are exported here.
using .AnthropicModule: get_newest_anthropic_model, find_adaptive_model, AnthropicLlm
export get_newest_anthropic_model, find_adaptive_model, AnthropicLlm

end # module ProjecturedAnthropic
