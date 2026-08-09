"""
    GestureLogModule

A record of what the user did — a document that holds the last N gestures and
the operation that the projection pipeline made from each one.

The buffer has a fixed size. `record_gesture!` appends one entry and deletes the
oldest entry when the buffer is full. The entries live in a `CellVector`, so an
append invalidates every reader of the collection and the overlay redraws.

An entry holds **strings**, not the live gesture and the live operation. An
operation holds a reference into the document, and the document changes as soon
as the operation runs, so a live operation renders differently one second later.
A string is a record of the moment.

[`GestureLogToSyntax`](GestureLogToSyntax.jl) projects the log onto the
Syntax → Text → Graphics path. [`GestureLogRecordingProjection`](GestureLogRecorder.jl)
fills it and [`GestureLogOverlayProjection`](GestureLogOverlay.jl) shows it.
"""
module GestureLogModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference, strip_reference_types
import ..EventModule: Event, ModifierKeys, KeyDown, KeyUp, KeyPress,
                      MouseDown, MouseUp, MousePress, MouseMove, MouseScroll,
                      WindowInput, get_modifier_keys
import ..EventPatternModule: EventPattern, describe_event_pattern
import ..OperationModule: Operation, DoNothingOperation, QuitEditorOperation,
                          ReplaceSelectionOperation, ReplaceReferencedValueOperation,
                          CompoundOperation, ToggleCollapseOperation,
                          SelectNextInsertionOperation,
                          AdjustZoomOperation, AdjustFontZoomOperation,
                          operation_reference

export GestureLogEntry, GestureLog, record_gesture!, clear_gesture_log!,
       describe_gesture, describe_operation, default_gesture_log_filter

"""
    GestureLogEntry(index, gesture, operation, kind)

One line of the log. `index` counts every recorded entry of the session, so a
number that the user does not see marks a dropped entry. `gesture` and
`operation` are the rendered strings. `kind` is the operation's type name, which
the printer uses to choose a style.
"""
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

# ── Render an operation ────────────────────────────────────────────────────

"""
    describe_operation(operation) -> String

How the operation is written for a human: `"select entries[1].value"`,
`"set entries[2].key = \\"b\\""`, `"compound(2): … + …"`.

An operation type that this module does not name falls back to its type name
without the `Operation` suffix, followed by the reference that
`operation_reference` reports. A domain that adds an operation type therefore
needs no change here.
"""
describe_operation(::Nothing) = "no operation"
describe_operation(::DoNothingOperation) = "do nothing"
describe_operation(::QuitEditorOperation) = "quit"
describe_operation(::SelectNextInsertionOperation) = "select next insertion"
describe_operation(::ToggleCollapseOperation) = "toggle collapse"
describe_operation(operation::ReplaceSelectionOperation) = "select " * _short_reference(operation.path)
describe_operation(operation::AdjustZoomOperation) = "zoom " * _delta(operation.delta)
describe_operation(operation::AdjustFontZoomOperation) = "font zoom " * _delta(operation.delta)

describe_operation(operation::ReplaceReferencedValueOperation) =
    string("set ", _short_reference(operation.reference), " = ", _short_value(operation.value))

describe_operation(operation::CompoundOperation) =
    string("compound(", length(operation.operations), "): ",
           join((describe_operation(member) for member in operation.operations), " + "))

function describe_operation(operation)
    name = _operation_name(operation)
    reference = operation_reference(operation)
    reference === nothing ? name : string(name, " ", _short_reference(reference))
end

# The type name without the `Operation` suffix — `StringReplaceRangeOperation`
# reads as `StringReplaceRange`.
function _operation_name(operation)
    name = string(nameof(typeof(operation)))
    endswith(name, "Operation") ? name[1:end - length("Operation")] : name
end

_delta(delta::Integer) = delta > 0 ? "in" : delta < 0 ? "out" : "reset"

# The type checkpoints of a folded reference say nothing to a human and eat the
# whole width, so the skeleton is what the log shows: `entries[1].value`.
_short_reference(reference::Reference) = _truncate(string(strip_reference_types(reference)), 60)
_short_reference(reference) = _truncate(string(reference), 60)

# A value that a human can read: a literal keeps its text, a document shows its
# type. A whole document printed into one line is noise.
_short_value(value::Union{AbstractString,Char,Symbol}) = _truncate(repr(value), 24)
_short_value(value::Union{Number,Bool,Nothing}) = string(value)
_short_value(value) = string(nameof(typeof(value)))

_truncate(text::AbstractString, limit::Integer) =
    length(text) <= limit ? String(text) : String(text[1:nextind(text, 0, limit - 1)]) * "…"

end # module
