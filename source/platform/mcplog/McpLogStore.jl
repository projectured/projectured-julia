# Fragment of `McpLogModule` — the producer side of the MCP log: the store that the
# server task writes, without blocking and without touching a cell.

"""
    McpLogStore(; capacity = 1000)

Where a call goes the moment the server has answered it. Any task may write it:
the write takes a lock for one push, touches no cell, and never waits for the
editor. The [`McpLogFeed`](@ref) of each editor copies it into the
[`McpLog`](@ref) of the session of that editor once per frame, on the editor
task.

The store keeps the last `capacity` calls, each with its number since the start
of the store, and a feed reads from the number that it reached
([`read_mcp_calls`](@ref)), so each editor gets every call. At the bound the
oldest call falls off and is counted in `dropped`.
"""
mutable struct McpLogStore
    calls::Vector{NamedTuple}
    # How many calls left the store before `calls[1]`.
    first_index::Int
    lock::ReentrantLock
    capacity::Int
    dropped::Int
    # The wake of each reader, by the reader.
    wakes::IdDict{Any,Any}
end

McpLogStore(; capacity::Integer = 1000) =
    McpLogStore(NamedTuple[], 0, ReentrantLock(), Int(capacity), 0, IdDict{Any,Any}())

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
    wakes = lock(store.lock) do
        push!(store.calls, call)
        while length(store.calls) > store.capacity
            popfirst!(store.calls)
            store.first_index += 1
            store.dropped += 1
        end
        collect(values(store.wakes))
    end
    # Outside the lock, and it never throws into the server: a wake is a kick.
    for wake in wakes
        try
            wake()
        catch
        end
    end
    store
end

"""
    read_mcp_calls(store, next) -> (calls, next)

The calls of `store` from the number `next` on, in the order of the answers,
without taking them, so each reader gets every call, and the number to read from
the next time. A reader starts at 1.
"""
function read_mcp_calls(store::McpLogStore, next::Integer)
    lock(store.lock) do
        start = max(Int(next), store.first_index + 1)
        (store.calls[(start - store.first_index):end], store.first_index + length(store.calls) + 1)
    end
end

"""
    attach_mcp_log_wake!(store, reader, wake) -> store

Hand the store the wake function of the editor of `reader`, such as a
[`McpLogFeed`](@ref); `record_mcp_call!` calls the wake of each reader.
[`detach_mcp_log_wake!`](@ref) forgets it when that editor ends.
"""
attach_mcp_log_wake!(store::McpLogStore, reader, wake) =
    (lock(() -> store.wakes[reader] = wake, store.lock); store)

"""
    detach_mcp_log_wake!(store, reader) -> store

Forget the wake of `reader`, whose editor ended, so the store holds that editor no
more.
"""
detach_mcp_log_wake!(store::McpLogStore, reader) =
    (lock(() -> delete!(store.wakes, reader), store.lock); store)

"""
    take_mcp_calls!(store) -> (calls, dropped)

Empty the store and answer what it held, in the order of the answers, and how
many calls fell off the bound since the last take.
"""
function take_mcp_calls!(store::McpLogStore)
    lock(store.lock) do
        calls = store.calls
        store.calls = NamedTuple[]
        store.first_index += length(calls)
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
