# Fragment of `McpLogModule` — the feed that moves the calls from the store into
# the document, the wrapper of `build_editor` that adds it, and the button of the
# toolbar that opens the log.

"""
    McpLogFeed(; store = get_session_mcp_log_store(), log = nothing)

Copies the calls of the store into `log` once per frame, on the editor task, or
with no `log` into the MCP log of the session of its editor
([`get_session_mcp_log`](@ref)), so each editor has its own log, and two editors
that read one store each get every call. The wrapper `mcp_log = true` adds it to
an editor, and detaches its wake when the loop of the editor ends.
"""
mutable struct McpLogFeed <: Feed
    store::McpLogStore
    log::Union{Nothing,McpLog}
    # The number of the next call of the store to copy.
    next::Int
end

McpLogFeed(; store::McpLogStore = get_session_mcp_log_store(),
             log::Union{Nothing,McpLog} = nothing) = McpLogFeed(store, log, 1)

function drain_changes!(feed::McpLogFeed, editor)
    calls, next = read_mcp_calls(feed.store, feed.next)
    feed.next = next
    isempty(calls) && return 0
    log = something(feed.log, get_session_mcp_log(; editor))
    for call in calls
        record_mcp_call!(log, McpCallEntry(call.time, call.method, call.name, call.arguments,
                                           call.answer, call.duration, call.fault))
    end
    length(calls)
end

attach_wake_callback!(feed::McpLogFeed, wake) = (attach_mcp_log_wake!(feed.store, feed, wake); nothing)

"""
    mcp_log = true

The wrapper of `build_editor` that fills the MCP log of the session of the editor
with the calls that MCP servers answer: it adds a [`McpLogFeed`](@ref).
It is off by default. A window shows the log in a tab, which the button of
[`make_mcp_log_tool`](@ref) opens.
"""
function wrap_editor!(::Val{:mcp_log}, layer::Symbol, argument, parts::EditorParts)
    feed = McpLogFeed()
    push!(parts.feeds, feed)
    push!(parts.stop_steps, _ -> (detach_mcp_log_wake!(feed.store, feed); nothing))
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
