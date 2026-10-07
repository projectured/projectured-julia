"""
    McpModule

Opt-in package providing the MCP (Model Context Protocol) server transport for
ProjecturEd. Depends on `ProjecturedKernel`; `using ProjecturedMCP` registers the
`:mcp` agent-server methods and exposes `McpServer`.

The editor tools themselves (`execute_julia_code`, the documentation/API search
tools, `register_default_tools!`) are not an MCP concept and live in the kernel's
`ToolModule`; each editor owns a `ToolSet` of them. Only the MCP *transport* — the
`McpServer`, the HTTP lifecycle, and the `ToolSet`→MCP wire-format bridges — needs
`ModelContextProtocol` and therefore lives here. Each call that the server answers
goes to the store of the MCP log of the platform (`McpLogModule`), which a tab of
the window shows.

The editor loop never names `McpServer`: it goes through the generic
`AgentModule` seam (`make_agent_server(:mcp, editor)` etc.), whose
`:mcp` methods this package registers.
"""
module McpModule

using ..KernelModule
# The protocol has a `Tool` and a `Resource` of its own, so this module names
# what it takes from the protocol, and `Tool` and `Resource` are the kernel's.
import ModelContextProtocol
using ModelContextProtocol: HttpTransport, MCPResource, MCPTool, Server, ServerConfig,
                            TextContent, TextResourceContents, ToolParameter, mcp_server,
                            register!, start!, stop!

# The store of the MCP log, which this module writes with each call it answers.
using ..McpLogModule

# Imported to extend: this module adds a method to each of these.
import ..AgentModule: make_agent_server, start_agent_server!, stop_agent_server!,
                      get_agent_server_access
import HTTP
using Random: RandomDevice
using Sockets: getaddrinfo, listenany

export McpServer, start_mcp!, stop_mcp!, render_mcp_tools, render_mcp_resources

include("McpServer.jl")

end # module McpModule
