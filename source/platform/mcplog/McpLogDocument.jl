# Fragment of `McpLogModule` — the document of the MCP log: `McpCallEntry`, one
# call that the server answered, and the bounded list of the most recent ones.

"""
    McpCallEntry

One call that the server answered: `time` it came (seconds since the epoch), the
`method` (`tools/call` or `resources/read`), the `name` of the tool or the URI,
the `arguments` as text (the code itself for `execute_julia_code`), the
`answer`, the `duration` in seconds that the call held the editor, and whether
it was a `fault`.
"""
@document struct McpCallEntry
    time::Float64
    method::String
    name::String
    arguments::String
    answer::String
    duration::Float64
    fault::Bool
end

"""
    McpLog(; capacity = 500)

The calls of the session, oldest first, at most `capacity` of them. `count`,
`faults` and `held` count every call, the faults, and the seconds that the calls
held the editor, also the calls that the log dropped. `shown` is what the pane
lists: `"all"`, `"tools"` or `"faults"`.
"""
@document struct McpLog
    entries::CellVector = CellVector()
    capacity::Int = 500
    count::Int = 0
    faults::Int = 0
    held::Float64 = 0.0
    shown::Any = PrimitiveString("all")
end

# The name the tab calls itself, and the name a person types into an empty tab to
# open one.
get_document_title(::McpLog) = "MCP log"
get_insertion_aliases(::Type{McpLog}) = ["mcp log"]

# A file keeps the size of the log and not the calls of a session.
pred_arguments(log::McpLog) = (), Pair{Symbol,Any}[:capacity => log.capacity]

"""
    record_mcp_call!(log, entry) -> McpLog

Append one call, count it, and drop the oldest calls that do not fit in the
capacity. Only the editor task writes the log; the server task writes the store.
"""
function record_mcp_call!(log::McpLog, entry::McpCallEntry)
    log.count = log.count + 1
    entry.fault && (log.faults = log.faults + 1)
    log.held = log.held + entry.duration
    push!(log.entries, entry)
    while length(log.entries) > log.capacity
        deleteat!(log.entries, 1)
    end
    log
end

# One log for the session, as there is one server for the editor.
const _SESSION_MCP_LOG = McpLog()

"""
    get_session_mcp_log() -> McpLog

The one MCP log of the session. Every MCP log a person opens is this document.
"""
get_session_mcp_log() = _SESSION_MCP_LOG

make_insertion_document(::Type{McpLog}) = get_session_mcp_log()
