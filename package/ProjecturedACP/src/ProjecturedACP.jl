"""
    ProjecturedACP

The Agent Client Protocol (ACP) client, a package of its own because it needs
`AgentClientProtocol` and starts an agent in another process.
`using ProjecturedACP` registers the `:acp` kind of `make_agent_connection`; the
slice is `AcpModule`, in `source/adapter/acp/`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedACP

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

include("../../../source/adapter/acp/AcpModule.jl")

# A person loads this package by name, so its names are exported here.
using .AcpModule: AcpConnection
using AgentClientProtocol: ProtocolException
export AcpConnection, ProtocolException

end # module ProjecturedACP
