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
dropped.
"""
@document struct GestureLog
    entries::CellVector = CellVector()
    capacity::Int = 20
    count::Int = 0
end

# The name the tab calls itself, and the name a person types into an empty tab
# to open one.
get_document_title(::GestureLog) = "Gestures"
get_insertion_aliases(::Type{GestureLog}) = ["gestures"]

# ── Record ─────────────────────────────────────────────────────────────────

"""
    record_gesture!(log, gesture, operation) -> GestureLog

Append one entry and drop the oldest entries that do not fit in the capacity.
The caller decides what to record; the filter lives on the recording projection.
"""
function record_gesture!(log::GestureLog, gesture, operation)
    index = log.count + 1
    log.count = index
    push!(log.entries, GestureLogEntry(index, describe_gesture(gesture),
                                       describe_operation(operation),
                                       _operation_kind(operation)))
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
