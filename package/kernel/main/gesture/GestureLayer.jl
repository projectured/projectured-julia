# ── Gesture layer — recognising gestures in the event stream ───────────────
# The ordered include list of the gesture layer; a fragment of ProjecturedKernel.
# GestureRecognizerModule turns a stream of events into a stream of gestures: the
# combinations and sequences that only exist across several events (a click, a
# multi-click, a chord) become one synthesised event.
#
# Recognition is an endofunction on the event stream — events in, events out — so
# this layer names no document and no operation. What a gesture *means* is decided
# by whoever binds it, far above here.
include("GestureRecognizer.jl")
