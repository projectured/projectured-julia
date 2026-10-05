# Fragment of `McpLogModule` — the feed that moves the calls from the store into
# the document, the wrapper of `build_editor` that adds it, and the button of the
# toolbar that opens the log.

"""
    McpLogFeed(; store = get_session_mcp_log_store(), log = get_session_mcp_log())

Moves the calls of the store into the log once per frame, on the editor task.
The wrapper `mcp_log = true` adds it to an editor.
"""
struct McpLogFeed <: Feed
    store::McpLogStore
    log::McpLog
end

McpLogFeed(; store::McpLogStore = get_session_mcp_log_store(),
             log::McpLog = get_session_mcp_log()) = McpLogFeed(store, log)

function drain_changes!(feed::McpLogFeed, editor)
    calls, _ = take_mcp_calls!(feed.store)
    for call in calls
        record_mcp_call!(feed.log, McpCallEntry(call.time, call.method, call.name, call.arguments,
                                                call.answer, call.duration, call.fault))
    end
    length(calls)
end

attach_wake_callback!(feed::McpLogFeed, wake) = (feed.store.wake = wake; nothing)

"""
    mcp_log = true

The wrapper of `build_editor` that fills the MCP log of the session with the
calls that the MCP server of the editor answers: it adds a [`McpLogFeed`](@ref).
It is off by default. A window shows the log in a tab, which the button of
[`make_mcp_log_tool`](@ref) opens.
"""
function wrap_editor!(::Val{:mcp_log}, layer::Symbol, argument, parts::EditorParts)
    push!(parts.feeds, McpLogFeed())
    parts
end

get_wrapper_layers(::Val{:mcp_log}) = (:screen => 10,)

"""
    make_mcp_log_tool() -> WidgetToolbarItem

The button of the toolbar that opens the MCP log, or gives the focus to its tab.
A host passes it to the `tools` of the `shell` wrapper when its editor serves MCP.
"""
make_mcp_log_tool() =
    make_window_tool_command("MCP log", McpLog; icon = :bot,
                             tooltip = "MCP log: every call that a client made over MCP in this session")
