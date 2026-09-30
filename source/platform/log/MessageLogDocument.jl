# Fragment of `MessageLogModule` — the message log document types:
# `MessageLogEntry`, one captured log record, and the bounded buffer that keeps
# the most recent ones.

@document struct MessageLogEntry
    level::String
    message::String
end

"""
    MessageLog(; capacity = 200)

The buffer. `entries` holds at most `capacity` entries, oldest first. `count` is
the number of entries that were recorded, including the entries that the buffer
dropped.
"""
@document struct MessageLog
    entries::CellVector = CellVector()
    capacity::Int = 200
    count::Int = 0
end

# The name the tab calls itself, and the name a person types into an empty tab
# to open one.
get_document_title(::MessageLog) = "Log"
get_insertion_aliases(::Type{MessageLog}) = ["log"]

# Last session's log is not this one's: `entries` and `count` are what a
# session captured, not a setting of the log, and `entries` holds
# `MessageLogEntry` values the notation cannot write in any case. Only
# `capacity` describes the log itself, so a load starts empty at the same size.
pred_arguments(log::MessageLog) = (), Pair{Symbol,Any}[:capacity => log.capacity]

# ── Record ─────────────────────────────────────────────────────────────────

"""
    record_message!(log, level, message) -> MessageLog

Append one entry and drop the oldest entries that do not fit in the capacity.
Every call records; the logger that calls this is what decides what reaches it.
"""
function record_message!(log::MessageLog, level, message)
    log.count = log.count + 1
    push!(log.entries, MessageLogEntry(string(level), string(message)))
    capacity = log.capacity
    while length(log.entries) > capacity
        deleteat!(log.entries, 1)
    end
    log
end

"""
    clear_message_log!(log) -> MessageLog

Delete every entry. The `count` keeps its value, so the index of the next entry
still tells the user how many messages came before it.
"""
function clear_message_log!(log::MessageLog)
    while length(log.entries) > 0
        deleteat!(log.entries, 1)
    end
    log
end

# ── The session's log ────────────────────────────────────────────────────────

# One log for the session, because there is one editor and one program logging
# into it. `MessageLog()` still builds an empty one, which a test wants.
const _SESSION_MESSAGE_LOG = MessageLog()

"""
    get_session_message_log() -> MessageLog

The one log of the session.

Every message log a person opens is this document, so two of them show the
same messages rather than two halves of them. A view that shows only part of
the history is a filter over this log, not a log of its own.
"""
get_session_message_log() = _SESSION_MESSAGE_LOG

# A person who types `log` into an empty tab gets the session's log, not a
# fresh empty one. A fresh one would never fill: what captures is a logger
# installed for the session, and it writes into the log it holds.
make_insertion_document(::Type{MessageLog}) = get_session_message_log()
