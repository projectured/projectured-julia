# ── Device layer (layer 5 — input devices, events, gestures) ───────────────
# The ordered include list of the device layer; a fragment of ProjecturedKernel.
# The DeviceModule interface, the modifier/keyboard/mouse event types, and
# GestureModule (the @event_case macro + parser and the reified
# GestureBinding/@gestures DSL). GestureModule owns EventEnvelope, so the
# editor and gesture layers don't depend on a concrete document type.
# ScreenDevice (Screen + WindowQuit, both defined here) and GestureRecognizer
# (device event types + EventEnvelope only) close the layer.
include("Device.jl")
include("Modifiers.jl")
include("Keyboard.jl")
include("Mouse.jl")
include("GestureModule.jl")
include("ScreenDevice.jl")
include("GestureRecognizer.jl")
