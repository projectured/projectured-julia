# Fragment of `McpModule` — `McpServer`, the transport of the Model Context Protocol for the tools of an editor.

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

# The address a server listens at when the caller names none: the loopback
# address, so only a program on this machine reaches it.
const DEFAULT_MCP_HOST = "127.0.0.1"
const DEFAULT_MCP_PORT = 9876

"""
    McpServer(editor; instructions = DEFAULT_MCP_INSTRUCTIONS,
              host = DEFAULT_MCP_HOST, port = DEFAULT_MCP_PORT)

An MCP server bound to an editor. It listens at `http://<host>:<port>/mcp`,
which is `http://127.0.0.1:9876/mcp` by default. Start/stop it through the
`AgentModule` generics (`start_agent_server!` / `stop_agent_server!`).
"""
mutable struct McpServer
    editor::Any
    server::Server
    task::Union{Task,Nothing}
    host::String
    port::Int
end

function McpServer(editor; instructions::AbstractString = DEFAULT_MCP_INSTRUCTIONS,
                   host::AbstractString = DEFAULT_MCP_HOST,
                   port::Integer = DEFAULT_MCP_PORT)
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
    # domain-free prompt so this module needs no Assistant dependency.
    srv.config = ServerConfig(
        name         = srv.config.name,
        version      = srv.config.version,
        description  = srv.config.description,
        capabilities = srv.config.capabilities,
        instructions = instructions,
        title        = srv.config.title,
        icons        = srv.config.icons,
    )
    McpServer(editor, srv, nothing, String(host), Int(port))
end

# Agent control-surface factory methods: the editor loop drives the MCP server
# through the generic AgentModule interface without naming `McpServer`.
make_agent_server(::Val{:mcp}, editor; kwargs...) = McpServer(editor; kwargs...)
start_agent_server!(mcp::McpServer) = start_mcp!(mcp)
stop_agent_server!(mcp::McpServer) = stop_mcp!(mcp)

"""
    start_mcp!(mcp::McpServer) -> McpServer

Launch the MCP server as an async task, with an HTTP transport at the host and
the port of `mcp`. The global logger after the start is the one before it, and
the task of the server logs to that logger.
"""
function start_mcp!(mcp::McpServer)
    for tool in _make_tools(mcp.editor)
        register!(mcp.server, tool)
    end
    transport = HttpTransport(
        host     = mcp.host,
        port     = mcp.port,
        endpoint = "/mcp",
    )
    mcp.server.transport = transport
    # `start!` of the library installs a logger of its own as the global logger,
    # with no option to keep the one that is there. That logger writes only to
    # stderr, so the capture of the message log would get no more records. So
    # the logger of the process is put back once the loop of the server runs.
    # The task of the server logs to the logger of the process from its start,
    # because a task logger comes before the global logger: the record that
    # `start!` writes as it starts reaches the message log and not stderr.
    previous = Base.CoreLogging.global_logger()
    try
        ModelContextProtocol.connect(transport)
        mcp.task = @async Base.CoreLogging.with_logger(previous) do
            start!(mcp.server)
        end
        timedwait(() -> mcp.server.active || istaskdone(mcp.task), 10.0; pollint = 0.001)
    catch e
        record_fault!(mcp.editor.faults, :tool; origin = :McpServer, exception = e,
                      traceback = catch_backtrace())
        @warn "MCP server failed to start" exception = e
    finally
        Base.CoreLogging.global_logger(previous)
    end
    mcp
end

"""
    stop_mcp!(mcp::McpServer) -> McpServer

Stop the MCP server: close its transport, so the port is free and the task of
the server ends.
"""
function stop_mcp!(mcp::McpServer)
    try
        stop!(mcp.server)
    catch e
        e isa ModelContextProtocol.ServerError || rethrow()
    end
    # `stop!` of the library only marks the server as stopped. Its loop ends when
    # the transport closes, and the port stays bound until then.
    transport = mcp.server.transport
    transport === nothing || ModelContextProtocol.close(transport)
    mcp
end

# ═══════════════════════════════════════════════════════════════════════
# Registry → MCP wire-format bridges
# ═══════════════════════════════════════════════════════════════════════

"""
    render_mcp_tools(editor, tools) -> Vector{MCPTool}

Render the given tools into the `MCPTool` shape the MCP server expects, binding
each handler to `editor`. This is the MCP half of the same job `ProjecturedAnthropic`
does for the Messages API: a `Tool` is provider-neutral, and each transport
renders it into its own wire format.

A handler runs its tool through `run_on_editor_task!`, so the tool runs on the
task of the editor's loop and the server task waits for its answer. Each call
goes to the store of the MCP log of the session, with its arguments, its answer,
the time it held the editor and whether it was a fault.
"""
function render_mcp_tools(editor, tools::AbstractVector{Tool})
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
                # The handler runs on the server task, and a tool may write what
                # the editor shows, so the call runs on the editor's task, in the
                # drain of its next frame, which then paints the change.
                held = Ref(0.0)
                fault = Ref(false)
                text = run_on_editor_task!(editor) do
                    started = time()
                    # Code that throws answers its message, so a new exception of
                    # an evaluation is what marks such a call as a fault. The count
                    # tells it, because two exceptions can be `===`.
                    before = get_evaluation_exception_count(editor.tools)
                    # The barrier is here and not only in the transport library.
                    # A tool that throws must answer the client an error text and
                    # must not stop the server task, except an exception that
                    # means stop, which goes on. This file is the only place
                    # that can promise both. The fault is recorded too, so a
                    # person reading the editor's log sees what a client ran
                    # into.
                    try
                        tool.handler(editor, args)
                    catch exception
                        is_passthrough_exception(exception) && rethrow()
                        fault[] = true
                        traceback = catch_backtrace()
                        record_fault!(editor.faults, :tool; origin = Symbol(tool.name),
                                      exception, traceback)
                        # A `showerror` method that throws gives the type name.
                        try
                            sprint(showerror, exception, traceback)
                        catch
                            string(nameof(typeof(exception)))
                        end
                    finally
                        held[] = time() - started
                        get_evaluation_exception_count(editor.tools) > before &&
                            (fault[] = true)
                    end
                end
                record_mcp_call!(get_session_mcp_log_store(); method = "tools/call",
                                 name = tool.name, arguments = _format_mcp_arguments(args),
                                 answer = string(text), duration = held[], fault = fault[])
                TextContent(text = text)
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

# The arguments of a call as the MCP log shows them: the code alone when the call
# runs code, else one `name = value` to a line.
function _format_mcp_arguments(args::AbstractDict)
    (length(args) == 1 && haskey(args, "code")) && return string(args["code"])
    join([string(name, " = ", repr(value)) for (name, value) in sort!(collect(args); by = first)], "\n")
end

"""
    render_mcp_resources(resources) -> Vector{MCPResource}

Render the given resources as `MCPResource` objects whose data providers return
`TextResourceContents` carrying the body. Each read goes to the store of the MCP
log of the session.
"""
function render_mcp_resources(resources::AbstractVector{Resource})
    out = MCPResource[]
    for r in resources
        let res = r
            push!(out, MCPResource(
                uri           = res.uri,
                name          = res.name,
                description   = res.description,
                mime_type     = res.mime_type,
                data_provider = () -> begin
                    started = time()
                    text = try
                        res.provider()
                    catch exception
                        record_mcp_call!(get_session_mcp_log_store(); method = "resources/read",
                                         name = res.uri, answer = sprint(showerror, exception),
                                         duration = time() - started, fault = true)
                        rethrow()
                    end
                    record_mcp_call!(get_session_mcp_log_store(); method = "resources/read",
                                     name = res.uri, answer = string(text),
                                     duration = time() - started)
                    TextResourceContents(uri = res.uri, mime_type = res.mime_type, text = text)
                end,
            ))
        end
    end
    out
end

# The editor's own ToolSet is what MCP publishes — one per editor, so an MCP
# server serves exactly the tools of the editor it is bound to.
function _make_tools(editor)
    register_default_tools!(editor.tools)
    render_mcp_tools(editor, list_tools(editor.tools))
end

function _make_resources(editor)
    register_default_tools!(editor.tools)
    render_mcp_resources(list_resources(editor.tools))
end
