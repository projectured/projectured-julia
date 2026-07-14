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
`AgentModule` control surface (`make_agent_server(:mcp, editor)` etc.), whose
`:mcp` methods this package registers.
"""
module ProjecturedMcp

using ModelContextProtocol
using ModelContextProtocol: HttpTransport, TextResourceContents, ServerConfig

import ProjecturedKernel.ToolModule: Tool, Resource, ToolSet,
                                     list_tools, list_resources, register_default_tools!
import ProjecturedKernel.AgentModule: make_agent_server, start_agent_server!, stop_agent_server!

export McpServer, mcp_start!, mcp_stop!, mcp_tools, mcp_resources

# Generic system prompt for MCP clients (domain-free). A richer, app-specific
# prompt can be supplied by the caller via `make_agent_server(:mcp, editor;
# instructions=…)`.
const DEFAULT_MCP_INSTRUCTIONS =
    "You are an assistant operating ProjecturEd, a projectional editor built in " *
    "Julia. Use the registered tools to inspect and manipulate the editor's " *
    "document, projection, and selection."

# ═══════════════════════════════════════════════════════════════════════
# MCP server
# ═══════════════════════════════════════════════════════════════════════

"""
    McpServer(editor; instructions = DEFAULT_MCP_INSTRUCTIONS)

An MCP server bound to an editor. Start/stop it through the `AgentModule`
generics (`start_agent_server!` / `stop_agent_server!`).
"""
mutable struct McpServer
    editor::Any
    server::Server
    task::Union{Task,Nothing}
end

function McpServer(editor; instructions::AbstractString = DEFAULT_MCP_INSTRUCTIONS)
    srv = mcp_server(
        name        = "projectured",
        version     = "0.1.0",
        description = "MCP server for ProjecturEd — a projectional editor built in Julia.",
        resources   = _make_resources(editor),
    )
    # `mcp_server` does not expose `instructions`, but `ServerConfig` does —
    # and that's the field the MCP `initialize` handler delivers to clients,
    # so the in-editor assistant and any external MCP client share the same
    # prompt. The caller supplies `instructions`; it defaults to a generic,
    # domain-free prompt so this module needs no Workbench dependency.
    srv.config = ServerConfig(
        name         = srv.config.name,
        version      = srv.config.version,
        description  = srv.config.description,
        capabilities = srv.config.capabilities,
        instructions = instructions,
        title        = srv.config.title,
        icons        = srv.config.icons,
    )
    McpServer(editor, srv, nothing)
end

# Agent control-surface factory methods: the editor loop drives the MCP server
# through the generic AgentModule interface without naming `McpServer`.
make_agent_server(::Val{:mcp}, editor; kwargs...) = McpServer(editor; kwargs...)
start_agent_server!(mcp::McpServer) = mcp_start!(mcp)
stop_agent_server!(mcp::McpServer) = mcp_stop!(mcp)

"""
    mcp_start!(mcp::McpServer) -> McpServer

Launch the MCP server as an async task (HTTP transport on port 9876).
"""
function mcp_start!(mcp::McpServer)
    for tool in _make_tools(mcp.editor)
        register!(mcp.server, tool)
    end
    transport = HttpTransport(
        host     = "127.0.0.1",
        port     = 9876,
        endpoint = "/mcp",
    )
    mcp.server.transport = transport
    try
        ModelContextProtocol.connect(transport)
        mcp.task = @async start!(mcp.server)
    catch e
        @warn "MCP server failed to start" exception = e
    end
    mcp
end

"""
    mcp_stop!(mcp::McpServer) -> McpServer

Stop the MCP server.
"""
function mcp_stop!(mcp::McpServer)
    try
        stop!(mcp.server)
    catch e
        e isa ModelContextProtocol.ServerError || rethrow()
    end
    mcp
end

# ═══════════════════════════════════════════════════════════════════════
# Registry → MCP wire-format bridges
# ═══════════════════════════════════════════════════════════════════════

"""
    mcp_tools(editor, tools) -> Vector{MCPTool}

Render the given tools into the `MCPTool` shape the MCP server expects, binding
each handler to `editor`. This is the MCP half of the same job `ProjecturedLlm`
does for the Messages API: a `Tool` is provider-neutral, and each transport
renders it into its own wire format.
"""
function mcp_tools(editor, tools::AbstractVector{Tool})
    out = MCPTool[]
    for t in tools
        params = ToolParameter[
            ToolParameter(
                name        = String(p.name),
                type        = String(p.type),
                description = String(p.description),
                required    = get(p, :required, false),
            ) for p in t.parameters
        ]
        # Capture t and editor in a closure
        let tool = t
            handler = params_dict -> begin
                args = Dict{String,Any}(string(k) => v for (k, v) in pairs(params_dict))
                TextContent(text = tool.handler(editor, args))
            end
            push!(out, MCPTool(
                name        = tool.name,
                description = tool.description,
                parameters  = params,
                handler     = handler,
            ))
        end
    end
    out
end

"""
    mcp_resources(resources) -> Vector{MCPResource}

Render the given resources as `MCPResource` objects whose data providers return
`TextResourceContents` carrying the body.
"""
function mcp_resources(resources::AbstractVector{Resource})
    out = MCPResource[]
    for r in resources
        let res = r
            push!(out, MCPResource(
                uri           = res.uri,
                name          = res.name,
                description   = res.description,
                mime_type     = res.mime_type,
                data_provider = () -> TextResourceContents(
                    uri       = res.uri,
                    mime_type = res.mime_type,
                    text      = res.provider(),
                ),
            ))
        end
    end
    out
end

# The editor's own ToolSet is what MCP publishes — one per editor, so an MCP
# server serves exactly the tools of the editor it is bound to.
function _make_tools(editor)
    register_default_tools!(editor.tools)
    mcp_tools(editor, list_tools(editor.tools))
end

function _make_resources(editor)
    register_default_tools!(editor.tools)
    mcp_resources(list_resources(editor.tools))
end

end # module Mcp
