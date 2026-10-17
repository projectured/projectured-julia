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

# A file keeps that it shows the log of the session, and not what the log held:
# the entries of one session say nothing about the next, and only the log of the
# session fills. A load gives the log of the session of its editor, and a load with
# no editor a new log.
pred_arguments(::MessageLog) = (), Pair{Symbol,Any}[]

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

"""
    get_session_message_log(; editor = find_evaluation_editor()) -> MessageLog

The message log of the session of `editor`: by default the editor of the
evaluation, or of the loop that runs the calling code. Each editor has its own,
which its [`MessageLogFeed`](@ref) fills, so no log is shared by two editors.
With no editor, a new empty log, which nothing keeps and nothing fills.

Every message log that a person opens in a window of the editor is this
document, so two of them show the same messages rather than two halves of them.
A view that shows only part of the history is a filter over this log, not a log
of its own.

Use it to read the messages of the window, such as a warning of a file that
could not be read: `print_natural_text` prints one line for each message, with
its level.

# Example

    println(print_natural_text(get_session_message_log()))

See also `get_session_fault_log`, `get_session_gesture_log`.
"""
function get_session_message_log end

get_session_message_log(; editor = find_evaluation_editor()) =
    editor isa Editor ? get_session_document!(MessageLog, editor, MessageLog) : MessageLog()

# A person who types `log` into an empty tab gets the log of the editor, not a
# fresh empty one. A fresh one would never fill: the feed of the editor fills
# the log of its session.
make_insertion_document(::Type{MessageLog}) = get_session_message_log()
make_pred_document(::Type{<:MessageLog}, positional, keywords) = get_session_message_log()

# A log counts the warnings and the errors that it holds.
function get_document_decoration(log::MessageLog)
    levels = [lowercase(entry.level) for entry in log.entries]
    errors = count(level -> startswith(level, "error"), levels)
    warnings = count(level -> startswith(level, "warn"), levels)
    counts = DocumentCount[]
    errors > 0 && push!(counts, DocumentCount(string(errors, errors == 1 ? " error" : " errors"); role = :error))
    warnings > 0 && push!(counts, DocumentCount(string(warnings, warnings == 1 ? " warning" : " warnings"); role = :warning))
    DocumentDecoration(; icon = :scroll_text, counts)
end
