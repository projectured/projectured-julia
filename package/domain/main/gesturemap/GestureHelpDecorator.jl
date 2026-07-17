"""
    GestureHelpDecoratorProjectionModule

A content-level decorator that opens the **gesture-help window** on the help
gesture (F1), modelled on [`TooltipDecoratorProjection`](TooltipDecorator.jl).

**Printer** — transparent: projects the wrapped `inner` and returns its output
unchanged, so the content window looks exactly as it did without the decorator.

**Reader** — the inner reader has priority (it is the real editor). When the
inner declines and the event is the help gesture, the decorator collects every
gesture reachable from *its own inner iomap* (the chain it just printed) via
`collect_gesture_bindings` — the projection-form collector, not anything reaching into the
editor — builds a snapshot `GestureMap`, and emits an `OpenWindowOperation` whose
`content` is that map. The op bubbles up to `WindowManagingProjection`, which opens
a real sibling window beside the content (the same rail tooltips ride). A second
help gesture emits `CloseWindowOperation`, so F1 toggles the window.

Open/closed state lives in a shared `GestureHelpState` (not on the projection
instance) because the example pipeline rebuilds the decorator per dispatch — the
caller threads one state object through every decorator so the toggle is stable.
"""
module GestureHelpDecoratorProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..IntentModule: Intent
import ..IoMapApiModule: IoMap
import ..ScreenDocumentModule: OpenWindowOperation, CloseWindowOperation
import ..OperationApiModule: Operation
import ..EventPatternModule: KeyDownPattern, matches_event_pattern
import ..ProjectionGestureBindingsModule: collect_gesture_bindings
import ..GestureMapModule: gesture_map

export GestureHelpProjection, GestureHelpState, GestureHelpProjectionIoMap,
       HELP_GESTURE, is_help_gesture

"""
    HELP_GESTURE

The gesture that summons the help window: F1, with any modifiers. It is an ordinary
reified pattern, owned here rather than by the input vocabulary — an event carries no
intent, so "F1 means help" is this projection's decision and no one else's.

Lisp binds help to Ctrl-H; F1 is unambiguous here, where Ctrl-? would need
`Ctrl+Shift+/` handling. A key chord would work too, once a chord table entry and a
chord pattern exist.
"""
const HELP_GESTURE = KeyDownPattern(:f1)

"""
    is_help_gesture(event) -> Bool

True when `event` is the gesture that summons the help window.
"""
is_help_gesture(event) = matches_event_pattern(HELP_GESTURE, event)

"""
    GestureHelpState(open=false)

Mutable open/closed flag for the gesture-help window, shared across the
(per-dispatch, transient) `GestureHelpProjection` instances that wrap each
content window, so F1 toggles the same window.
"""
mutable struct GestureHelpState
    open::Bool
end
GestureHelpState() = GestureHelpState(false)

"""
    GestureHelpProjection(; inner, state=GestureHelpState(), id=:gesture_help,
                            title="Gestures", x=100, y=100, width=1000, height=1400)

Decorator over `inner` (a content pipeline). On the help gesture it opens/closes a
window of id `id` carrying the collected `GestureMap`. Pass a shared `state` to
keep the toggle stable when the decorator is rebuilt each frame.
"""
struct GestureHelpProjection <: Projection
    inner::Any
    state::GestureHelpState
    id::Symbol
    title::String
    x::Int
    y::Int
    width::Int
    height::Int
end

GestureHelpProjection(; inner, state::GestureHelpState = GestureHelpState(),
                        id::Symbol = :gesture_help, title::AbstractString = "Gestures",
                        x::Integer = 100, y::Integer = 100,
                        width::Integer = 1000, height::Integer = 1400) =
    GestureHelpProjection(inner, state, id, String(title), Int(x), Int(y), Int(width), Int(height))

struct GestureHelpProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    inner_iomap::Any
end

# ── Printer (transparent) ──────────────────────────────────────────────────

function print_document(p::GestureHelpProjection, recursion, input, ctx)
    inner_iomap = print_document(p.inner, recursion, input, ctx)
    GestureHelpProjectionIoMap(p, input, inner_iomap.output, inner_iomap)
end

# ── Reader ─────────────────────────────────────────────────────────────────

function read_intent(p::GestureHelpProjection, recursion, change::Intent, iomap::GestureHelpProjectionIoMap)
    # The wrapped editor has priority: if it produced an operation, that wins and
    # the help gesture (if any) is reconsidered next event.
    child = read_intent(p.inner, recursion, change, iomap.inner_iomap)
    child.operation isa Operation && return child

    if is_help_gesture(change.gesture)
        if p.state.open
            p.state.open = false
            return Intent(change.gesture, CloseWindowOperation(p.id))
        end
        bindings = collect_gesture_bindings(p.inner, recursion, iomap.inner_iomap)
        gm = gesture_map(bindings, iomap.input)
        p.state.open = true
        return Intent(change.gesture, OpenWindowOperation(
            id = p.id, title = p.title,
            x = p.x, y = p.y, width = p.width, height = p.height,
            style = :normal, content = gm))
    end
    return child
end

read_intent(p::GestureHelpProjection, iomap::GestureHelpProjectionIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping (transparent — output is the inner's output) ──────────

map_reference_forward(p::GestureHelpProjection, iomap::GestureHelpProjectionIoMap, reference) =
    map_reference_forward(p.inner, iomap.inner_iomap, reference)

map_reference_backward(p::GestureHelpProjection, iomap::GestureHelpProjectionIoMap, reference) =
    map_reference_backward(p.inner, iomap.inner_iomap, reference)

end # module
