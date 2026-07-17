# ── Event layer — input events and the pattern language ────────────────────
# A fragment of ProjecturedKernel; the event layer's table of contents.
include("EventModule.jl")   # backend-agnostic input vocabulary: modifiers, key/mouse/window structs, WindowInput
include("EventPattern.jl")  # the pattern-matching language + the @event_case parser
