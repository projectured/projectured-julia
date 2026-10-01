"""
    ProjecturedMcp

The Mcp adapter, a package of its own because it needs ModelContextProtocol.
`using ProjecturedMcp` gives `McpServer`, `start_mcp!`, `stop_mcp!`, `render_mcp_tools`, `render_mcp_resources`; the slice is `McpModule`, in `source/adapter/mcp/`.

The loop below binds every submodule of the packages below this one as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedMcp

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

include("../../../source/adapter/mcp/McpModule.jl")

# A person loads this package by name, so its names are exported here.
using .McpModule: McpServer, start_mcp!, stop_mcp!, render_mcp_tools, render_mcp_resources
export McpServer, start_mcp!, stop_mcp!, render_mcp_tools, render_mcp_resources

end # module ProjecturedMcp
