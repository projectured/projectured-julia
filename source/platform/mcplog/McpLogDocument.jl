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

# A file keeps that it shows the log of the session, and not the calls of a
# session. A load gives the log of the session of its editor, and a load with no
# editor a new log.
pred_arguments(::McpLog) = (), Pair{Symbol,Any}[]

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

"""
    get_session_mcp_log(; editor = find_evaluation_editor()) -> McpLog

The MCP log of the session of `editor`: by default the editor of the evaluation,
or of the loop that runs the calling code. Each editor has its own, which its
[`McpLogFeed`](@ref) fills; with no editor, a new empty log, which nothing keeps
and nothing fills. Every MCP log that a person opens in a window of the editor is
this document.
"""
get_session_mcp_log(; editor = find_evaluation_editor()) =
    editor isa Editor ? get_session_document!(McpLog, editor, McpLog) : McpLog()

make_insertion_document(::Type{McpLog}) = get_session_mcp_log()
make_pred_document(::Type{<:McpLog}, positional, keywords) = get_session_mcp_log()

# The log of the calls of a client fails while one of its calls was a fault.
function get_document_decoration(log::McpLog)
    faults = log.faults
    tooltip = () -> _make_mcp_log_note(log)
    faults == 0 && return DocumentDecoration(; icon = :plug, tooltip)
    DocumentDecoration(; icon = :plug, conditions = [DocumentCondition(:failed)],
                       counts = [DocumentCount(string(faults, faults == 1 ? " fault" : " faults"); role = :error)],
                       tooltip)
end

# What a row of the log says when the pointer rests on it: what it holds, and how
# many calls it kept, recorded and how many failed.
_make_mcp_log_note(log::McpLog) =
    TooltipNote(; title = "MCP log", text = "The calls that a client made to this editor.",
                facts = ["Kept" => string(length(log.entries)), "Capacity" => string(log.capacity),
                         "Recorded" => string(log.count), "Faults" => string(log.faults)])

# The command of the log, with no key: a person runs it from the command palette
# or the menu of its row, and the count of the faults goes back to zero.
@gestures McpLog begin
    nothing => "Clear the MCP log" =>
        CompoundOperation(Any[ReplaceReferencedValueOperation(doc, "entries", CellVector()),
                              ReplaceReferencedValueOperation(doc, "faults", 0)])
end
