"""
    Mcp

Opt-in package providing the MCP (Model Context Protocol) server transport for
ProjecturEd. Depends on `ProjecturedKernel`; `using ProjecturedMcp` registers the
`:mcp` agent-server methods and exposes `McpServer`.

The editor tools themselves (`execute_julia_code`, the documentation/API search
tools, `register_default_tools!`) are not an MCP concept and live in the kernel's
`ToolModule`; each editor owns a `ToolSet` of them. Only the MCP *transport* — the
`McpServer`, the HTTP lifecycle, and the `ToolSet`→MCP wire-format bridges — needs
`ModelContextProtocol` and therefore lives here.

The editor loop never names `McpServer`: it goes through the generic
`AgentServerModule` seam (`make_agent_server(:mcp, editor)` etc.), whose
`:mcp` methods this package registers.
"""
module ProjecturedMcp

using ModelContextProtocol
using ModelContextProtocol: HttpTransport, TextResourceContents, ServerConfig

import ProjecturedKernel.EditorModule: wake_editor!
import ProjecturedKernel.FaultModule: record_fault!
import ProjecturedKernel.ToolModule: Tool, Resource, ToolSet,
                                     list_tools, list_resources, register_default_tools!
import ProjecturedKernel.AgentServerModule: make_agent_server, start_agent_server!, stop_agent_server!

include("../../../source/mcp/Mcp.jl")

end # module Mcp
