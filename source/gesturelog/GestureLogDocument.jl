# Fragment of `GestureLogModule` — the gesture log document types:
# `GestureLogEntry`, one recorded gesture with the operation it produced, and
# the bounded buffer that keeps the most recent ones.

struct GestureLogEntry
    index::Int
    gesture::String
    operation::String
    kind::Symbol
end

"""
    GestureLog(; capacity = 20)

The buffer. `entries` holds at most `capacity` entries, oldest first. `count` is
the number of entries that were recorded, including the entries that the buffer
dropped. `typing` is the text of the run of typed characters that the newest
entry folds, and is empty when the newest entry is not such a run.
"""
@document struct GestureLog
    entries::CellVector = CellVector()
    capacity::Int = 20
    count::Int = 0
    typing::String = ""
end

# The name the tab calls itself, and the name a person types into an empty tab
# to open one.
get_document_title(::GestureLog) = "Gestures"
get_insertion_aliases(::Type{GestureLog}) = ["gestures"]

# Last session's log is not this one's: `entries` and `count` are what a
# session recorded, not a setting of the log, and `entries` holds
# `GestureLogEntry` values the notation cannot write in any case. Only
# `capacity` describes the log itself, so a load starts empty at the same size.
pred_arguments(log::GestureLog) = (), Pair{Symbol,Any}[:capacity => log.capacity]

# ── Record ─────────────────────────────────────────────────────────────────

"""
    record_gesture!(log, gesture, operation; root = nothing, fold_typing = false) -> GestureLog

Append one entry and drop the oldest entries that do not fit in the capacity.
The caller decides what to record; the filter lives on the recording projection.

With `root`, the document the references of `operation` start at, the entry
writes each reference as `describe_reference` writes it, from the deepest
document on it that has a title. With `fold_typing`, a typed character joins the
newest entry when that entry is a run of typed characters, so a typed sentence
is one entry, `typed "…"`, with the operation of its last character.
"""
function record_gesture!(log::GestureLog, gesture, operation; root = nothing,
                         fold_typing::Bool = false)
    text = root === nothing ? describe_operation(operation) : describe_operation(operation, root)
    event = gesture isa WindowInput ? gesture.event : gesture
    if fold_typing && event isa KeyPress
        typing = log.typing * event.text
        log.typing = typing
        entry = GestureLogEntry(0, _describe_typing(typing), text, _operation_kind(operation))
        if length(typing) > length(event.text) && !isempty(log.entries)
            newest = log.entries[end]
            log.entries[end] = GestureLogEntry(newest.index, entry.gesture, text, entry.kind)
            return log
        end
        return _push_entry!(log, entry)
    end
    log.typing = ""
    _push_entry!(log, GestureLogEntry(0, describe_gesture(gesture), text, _operation_kind(operation)))
end

# A run of typed characters as its line: the end of the text, which is what the
# person typed last.
_describe_typing(text::AbstractString) =
    string("typed \"", length(text) <= 20 ? text : "…" * last(text, 19), "\"")

function _push_entry!(log::GestureLog, entry::GestureLogEntry)
    index = log.count + 1
    log.count = index
    push!(log.entries, GestureLogEntry(index, entry.gesture, entry.operation, entry.kind))
    capacity = log.capacity
    while length(log.entries) > capacity
        deleteat!(log.entries, 1)
    end
    log
end

"""
    clear_gesture_log!(log) -> GestureLog

Delete every entry. The `count` keeps its value, so the index of the next entry
still tells the user how many gestures came before it.
"""
function clear_gesture_log!(log::GestureLog)
    while length(log.entries) > 0
        deleteat!(log.entries, 1)
    end
    log
end

"""
    default_gesture_log_filter(gesture, operation) -> Bool

The filter that the overlay uses when the caller names no other one. It drops a
selection operation, because a selection follows almost every click and almost
every arrow key and would fill the whole buffer. It also drops the operations
that change nothing.
"""
default_gesture_log_filter(gesture, operation) =
    !(operation === nothing ||
      operation isa DoNothingOperation ||
      operation isa ReplaceSelectionOperation)

_operation_kind(::Nothing) = :Nothing
_operation_kind(operation) = nameof(typeof(operation))

# ── Render a gesture ───────────────────────────────────────────────────────

"""
    describe_gesture(gesture) -> String

How the gesture is written for a human: `"Ctrl+C"`, `"←"`, `"a"`,
`"Left click (412,88)"`.

The phrasing comes from [`describe_event_pattern`](@ref): the event is turned
into the pattern that matches exactly it, so one table of key names and button
names serves both the gesture help and this log.
"""
describe_gesture(input::WindowInput) = describe_gesture(input.event)
describe_gesture(gesture) = _describe_event(gesture)
# The words of code that acted with no gesture, such as "Focus the pane Files".
describe_gesture(text::AbstractString) = String(text)

describe_gesture(event::MouseMove) = string(_describe_event(event), " (", event.x, ",", event.y, ")")
describe_gesture(event::MouseScroll) = string(_describe_event(event), " (", event.dx, ",", event.dy, ")")

function describe_gesture(event::Union{MouseDown,MouseUp,MousePress})
    count = event isa MousePress ? event.count : 1
    suffix = count > 1 ? string(" x", count) : ""
    string(_describe_event(event), suffix, " (", event.x, ",", event.y, ")")
end

const _MODIFIER_FLAGS = (:ctrl, :shift, :alt, :meta)

_describe_event(event::Event) = describe_event_pattern(_gesture_pattern(event))
_describe_event(gesture) = string(gesture)

# The pattern that matches exactly this event: the field that names the gesture
# is constrained, and every modifier that the user holds is listed.
function _gesture_pattern(event::Event)
    type = typeof(event)
    fields = hasfield(type, :key)    ? (; key = event.key) :
             hasfield(type, :char)   ? (; char = event.char) :
             hasfield(type, :button) ? (; button = event.button) :
             NamedTuple()
    held = hasfield(type, :modifiers) ? get_modifier_keys(event) : ModifierKeys()
    modifiers = Symbol[flag for flag in _MODIFIER_FLAGS if getfield(held, flag)]
    EventPattern{type}(fields, modifiers, nothing, nothing)
end

# ── The session's log ────────────────────────────────────────────────────────

# One log for the session, because there is one editor and one history of what a
# person did to it. `GestureLog()` still builds an empty one, which a test wants.
const _SESSION_GESTURE_LOG = GestureLog()

"""
    get_session_gesture_log() -> GestureLog

The one log of the session.

Every gesture log a person opens is this document, so two of them show the same
history rather than two halves of it. A view that shows only part of the history
is a filter over this log, not a log of its own.
"""
get_session_gesture_log() = _SESSION_GESTURE_LOG

# A person who types `gestures` into an empty tab gets the session's log, not a
# fresh empty one. A fresh one would never fill: what records is a decorator at
# the root of the projection, and it records into the log it holds.
make_insertion_document(::Type{GestureLog}) = get_session_gesture_log()
