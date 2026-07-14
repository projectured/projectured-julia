# ── Event layer — input events and the pattern language ────────────────────
# The ordered include list of the event layer; a fragment of ProjecturedKernel.
# EventModule is the backend-agnostic input vocabulary (modifiers, the keyboard/
# mouse/window event structs, and the EventEnvelope that carries an event with
# the window it came from). EventPatternModule is the language for *matching*
# those events: the reified patterns, and the `@event_case` dispatch table with
# the parser both it and the gesture-binding DSL are built on.
#
# The layer depends on nothing — an event is data, and knows neither the device
# that produced it nor the document it will end up changing.
include("EventModule.jl")
include("EventPattern.jl")
