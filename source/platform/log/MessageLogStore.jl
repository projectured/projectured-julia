# Fragment of `MessageLogModule` — the producer side of the log: the store a
# logger writes from any task, without blocking and without touching a cell.

"""
    MessageLogStore(; capacity = 1000)

Where a captured message goes the moment the logger sees it. Any task may
write it: the write takes a lock for one push, touches no cell, and never
waits for the editor. The [`MessageLogFeed`](@ref) drains it into the
[`MessageLog`](@ref) document once per frame, on the editor task — the one
task that may write a document.

`capacity` bounds the lines held between two frames. At the bound the oldest
line falls off and is counted in `dropped`; the drain then puts one warning
line in the log, so a person knows lines are missing.
"""
mutable struct MessageLogStore
    lines::Vector{Tuple{String, String}}
    lock::ReentrantLock
    capacity::Int
    dropped::Int
    wake::Any
end

MessageLogStore(; capacity::Integer = 1000) =
    MessageLogStore(Tuple{String, String}[], ReentrantLock(), Int(capacity), 0, nothing)

"""
    record_message!(store::MessageLogStore, level, message) -> store

Append one line, drop the oldest beyond the capacity, and wake the editor.
Thread-safe, so it is safe wherever logging is safe.
"""
function record_message!(store::MessageLogStore, level, message)
    entry = (string(level), string(message))
    lock(store.lock) do
        push!(store.lines, entry)
        while length(store.lines) > store.capacity
            popfirst!(store.lines)
            store.dropped += 1
        end
    end
    # Outside the lock, and it never throws through a logger: a wake is a
    # kick, not a promise.
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
    take_message_lines!(store) -> (lines, dropped)

Empty the store and answer what it held: the `(level, message)` lines in
arrival order, and how many lines fell off the bound since the last take.
"""
function take_message_lines!(store::MessageLogStore)
    lock(store.lock) do
        lines = store.lines
        store.lines = Tuple{String, String}[]
        dropped = store.dropped
        store.dropped = 0
        (lines, dropped)
    end
end

"""
    attach_message_log_wake!(store, wake) -> store

Hand the store the wake function of its editor. `record_message!` calls it
after every line, so a sleeping editor shows the line on its next frame.
"""
attach_message_log_wake!(store::MessageLogStore, wake) = (store.wake = wake; store)

# The store of the session, beside the log of the session: one program logs
# into one place.
const _SESSION_MESSAGE_LOG_STORE = MessageLogStore()

"""
    get_session_message_log_store() -> MessageLogStore

The one producer-side store of the session, paired with
[`get_session_message_log`](@ref).
"""
get_session_message_log_store() = _SESSION_MESSAGE_LOG_STORE
