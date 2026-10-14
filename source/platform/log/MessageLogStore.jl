# Fragment of `MessageLogModule` — the producer side of the log: the store a
# logger writes from any task, without blocking and without touching a cell.

"""
    MessageLogStore(; capacity = 1000)

Where a captured message goes the moment the logger sees it. Any task may
write it: the write takes a lock for one push, touches no cell, and never
waits for the editor. The [`MessageLogFeed`](@ref) of each editor copies it into
the [`MessageLog`](@ref) of that editor once per frame, on the editor task — the
one task that may write that document.

The store keeps the last `capacity` lines, each with its number since the start
of the store, and a feed reads from the number that it reached
([`read_message_lines`](@ref)), so each editor gets every line. At the bound the
oldest line falls off; a feed that had not read it learns how many it missed, and
puts one warning line in its log, so a person knows lines are missing.
"""
mutable struct MessageLogStore
    lines::Vector{Tuple{String, String}}
    # How many lines left the store before `lines[1]`; the number of `lines[i]` is
    # `first_index + i`.
    first_index::Int
    lock::ReentrantLock
    capacity::Int
    dropped::Int
    # The wake of each reader, by the reader: `nothing` for a caller that names
    # none.
    wakes::IdDict{Any,Any}
end

MessageLogStore(; capacity::Integer = 1000) =
    MessageLogStore(Tuple{String, String}[], 0, ReentrantLock(), Int(capacity), 0, IdDict{Any,Any}())

"""
    record_message!(store::MessageLogStore, level, message) -> store

Append one line, drop the oldest beyond the capacity, and wake the editor.
Thread-safe, so it is safe wherever logging is safe.
"""
function record_message!(store::MessageLogStore, level, message)
    entry = (string(level), string(message))
    wakes = lock(store.lock) do
        push!(store.lines, entry)
        while length(store.lines) > store.capacity
            popfirst!(store.lines)
            store.first_index += 1
            store.dropped += 1
        end
        collect(values(store.wakes))
    end
    # Outside the lock, and it never throws through a logger: a wake is a
    # kick, not a promise.
    for wake in wakes
        try
            wake()
        catch
        end
    end
    store
end

"""
    read_message_lines(store, next) -> (lines, next, missed)

The `(level, message)` lines of `store` from the number `next` on, in arrival
order, without taking them, so each reader gets every line; the number to read
from the next time; and how many lines from `next` on fell off the bound before
this read. A reader starts at 1.
"""
function read_message_lines(store::MessageLogStore, next::Integer)
    lock(store.lock) do
        start = max(Int(next), store.first_index + 1)
        lines = store.lines[(start - store.first_index):end]
        (lines, store.first_index + length(store.lines) + 1, start - Int(next))
    end
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
        store.first_index += length(lines)
        dropped = store.dropped
        store.dropped = 0
        (lines, dropped)
    end
end

"""
    attach_message_log_wake!(store, [reader,] wake) -> store

Hand the store the wake function of the editor of `reader`, such as a
[`MessageLogFeed`](@ref). `record_message!` calls the wake of each reader after
every line, so a sleeping editor shows the line on its next frame. A second wake
of the same reader replaces the first; with no reader, the wake of no reader.
"""
attach_message_log_wake!(store::MessageLogStore, wake) = attach_message_log_wake!(store, nothing, wake)
attach_message_log_wake!(store::MessageLogStore, reader, wake) =
    (lock(() -> store.wakes[reader] = wake, store.lock); store)

"""
    detach_message_log_wake!(store, reader) -> store

Forget the wake of `reader`, whose editor ended, so the store holds that editor no
more.
"""
detach_message_log_wake!(store::MessageLogStore, reader) =
    (lock(() -> delete!(store.wakes, reader), store.lock); store)

# The store of the session, beside the log of the session: one program logs
# into one place.
const _SESSION_MESSAGE_LOG_STORE = MessageLogStore()

"""
    get_session_message_log_store() -> MessageLogStore

The one producer-side store of the session, paired with
[`get_session_message_log`](@ref).
"""
get_session_message_log_store() = _SESSION_MESSAGE_LOG_STORE
