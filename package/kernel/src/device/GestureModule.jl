"""
    GestureModule

Layer 5 aggregator — the gesture machinery. Two fragments share this
namespace:

- [`EventCase.jl`](EventCase.jl) — the `@event_case` dispatch-table macro
  and its pattern parser (a first-match-wins `isa`/field test compiler over
  the Keyboard/Mouse event types).
- [`GestureBinding.jl`](GestureBinding.jl) — the reified `GestureBinding`
  data type, the `@gestures` DSL, and the catch-all `read_gesture(::Document, …)`
  interpreter that walks the reified table.

Merged in kernel plan P5 (R4): the two used to be separate modules, but
GestureBinding.jl imports EventCase.jl's private parser internals
(`_parse_rule`, `EvPat`, …) — a documented cross-module private edge that
becomes a plain same-namespace reference once both files are fragments.

Also owns the **rehomed `EventEnvelope`** (R5). Previously declared in
`ScreenDocumentModule`, `EventEnvelope` wraps every backend event with the
id of the window it came from — data the editor loop, the gesture
recognizer, and the envelope-unwrapping projection all interpret. Moving
its declaration here means those consumers stop importing a concrete
document type (`ScreenDocument`) just to name it, which was the last real
kernel→ScreenDocument edge. Window *events/ops* (WindowResize,
OpenWindowOperation, …) stay with ScreenDocument in base at P7.
"""
module GestureModule

import ..KeyboardModule
import ..MouseModule
import ..ModifiersModule
import ..KeyboardModule: KeyDown, KeyUp, KeyPress
import ..MouseModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
import ..ModifiersModule: Modifiers
import ..DocumentModule: Document, read_gesture
# R3 (kernel plan P8, completed 2026-07-06) — the upward
# `import ..ProjectionApiModule: Projection` is gone. The three
# Projection-typed seam methods moved up to
# projection/GestureBindings.jl (ProjectionGestureBindingsModule); this
# module no longer references the Projection type.

export var"@event_case",
       # from GestureBinding.jl
       GesturePattern, KeyPressPattern, KeyDownPattern, KeyUpPattern,
       MouseDownPattern, MouseUpPattern, MousePressPattern, MouseMovePattern,
       MouseScrollPattern,
       GestureBinding, matches, describe,
       get_document_gesture_bindings, get_document_gesture_bindings_own,
       get_instance_gesture_bindings,
       read_document_gesture, read_node_gesture,
       # get_projection_gesture_bindings, read_projection_gesture,
       # collect_gesture_bindings moved to ProjectionGestureBindingsModule (R3).
       get_applicable_gesture_bindings,
       is_help_gesture, var"@gestures", var"@gesture_set",
       # rehomed from ScreenDocumentModule (R5)
       EventEnvelope

# R5 — the rehomed `EventEnvelope`. Wraps an input event with the id of the
# window it came from; used by the editor loop, the gesture recognizer, and
# the envelope-unwrapping projection.
"""
    EventEnvelope(window_id::Symbol, event)

Wraps an input event with the id of the window it came from. This is the
protocol type that flows between the backend event source, the gesture
recognizer, and the projection pipeline — everything downstream of the raw
backend polling. Moved here from `ScreenDocumentModule` in kernel plan P5
(R5) so the editor and gesture layers don't depend on a concrete document
type just to name it.
"""
struct EventEnvelope
    window_id::Symbol
    event
end

include("EventCase.jl")        # the @event_case macro + its parser
include("GestureBinding.jl")   # gesture patterns, @gestures registry, read_gesture

end # module
