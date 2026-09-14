# ── Binding layer — where a gesture acquires meaning ───────────────────────
# The ordered include list of the binding layer; a fragment of ProjecturedKernel.
# GestureBindingModule reifies the gesture → operation rules: the `GestureBinding`
# data type, the per-document-type registry, the `@gestures` DSL that authors it,
# and the `read_gesture` seam that fires it.
#
# This is the first layer that sees an event *and* a document: a binding maps an
# input pattern to an operation in a document's own reference vocabulary, so it
# imports the event, document, and operation layers.
include("GestureBindingModule.jl")
