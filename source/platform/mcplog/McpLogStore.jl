# Fragment of `McpLogModule` — the producer side of the MCP log: the store that the
# server task writes, without blocking and without touching a cell.

"""
    McpLogStore(; capacity = 1000)

Where a call goes the moment the server has answered it. Any task may write it:
the write takes a lock for one push, touches no cell, and never waits for the
editor. The [`McpLogFeed`](@ref) drains it into the [`McpLog`](@ref) of the
session once per frame, on the editor task.

`capacity` bounds the calls held between two drains. At the bound the oldest
call falls off and is counted in `dropped`.
"""
mutable struct McpLogStore
    calls::Vector{NamedTuple}
    lock::ReentrantLock
    capacity::Int
    dropped::Int
    wake::Any
end

McpLogStore(; capacity::Integer = 1000) =
    McpLogStore(NamedTuple[], ReentrantLock(), Int(capacity), 0, nothing)

"""
    record_mcp_call!(store::McpLogStore; method, name, arguments, answer, duration, fault)
        -> store

Keep one call that the server answered, drop the oldest beyond the capacity, and
wake the editor. Thread-safe: the server task calls it.
"""
function record_mcp_call!(store::McpLogStore; method::AbstractString, name::AbstractString,
                          arguments::AbstractString = "", answer::AbstractString = "",
                          duration::Real = 0.0, fault::Bool = false, time::Real = Base.time())
    call = (time = Float64(time), method = String(method), name = String(name),
            arguments = String(arguments), answer = String(answer), duration = Float64(duration),
            fault = fault)
    lock(store.lock) do
        push!(store.calls, call)
        while length(store.calls) > store.capacity
            popfirst!(store.calls)
            store.dropped += 1
        end
    end
    # Outside the lock, and it never throws into the server: a wake is a kick.
    wake = store.wake
    if wake !== nothing
        try
            wake()
        catch
        end
    end
    store
end

"""
    take_mcp_calls!(store) -> (calls, dropped)

Empty the store and answer what it held, in the order of the answers, and how
many calls fell off the bound since the last take.
"""
function take_mcp_calls!(store::McpLogStore)
    lock(store.lock) do
        calls = store.calls
        store.calls = NamedTuple[]
        dropped = store.dropped
        store.dropped = 0
        (calls, dropped)
    end
end

const _SESSION_MCP_LOG_STORE = McpLogStore()

"""
    get_session_mcp_log_store() -> McpLogStore

The one store of the session, paired with [`get_session_mcp_log`](@ref). The MCP
adapter writes every call it answers here.
"""
get_session_mcp_log_store() = _SESSION_MCP_LOG_STORE
