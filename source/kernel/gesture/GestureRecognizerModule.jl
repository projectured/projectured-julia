"""
    GestureRecognizerModule

The recognition of gestures: the stage between the input events of a backend and
the readers, where a combination or a sequence of events becomes one synthetic
event. A reader receives the output of this stage, and each value of it is a
gesture.

Most events pass through unchanged: `KeyDown`, `KeyUp`, `KeyPress`, `MouseDown`,
`MouseUp`, `MouseMove`, `MouseScroll` and the window events. Two gestures exist
only across several events:

- a click, `MouseClick`, is a `MouseDown` and a `MouseUp` of the same button in
  the same window, near each other in place and in time. A click soon after a
  click at the same place is a double or a triple click, and `count` says which;
- a key chord, `KeyChord`, is a sequence of `KeyDown`s from the chord table of
  the recognizer, for example Ctrl+C Ctrl+K.

A drag is not a gesture of this stage: the readers that follow a drag read its
`MouseDown`, its `MouseMove`s and its `MouseUp` themselves.

The recognition needs state that spans several events, and a reactive pipeline
that the reader pulls cannot hold it. So the recognition happens here, once for
each input event. A gesture carries no intent: this stage never decides what a
click or a chord means. It needs no backend and no display, so a test drives it
with a scripted source.

The recognizer holds all of its state on its own instance, so one process can
run any number of them.

The module lives in one fragment:

- [`GestureRecognizer.jl`](GestureRecognizer.jl) — `GestureRecognizer`, its state
  for one editor, `recognize_gesture!` and `pop_gesture!`.
"""
module GestureRecognizerModule

using ..EventModule

export GestureRecognizer, recognize_gesture!, pop_gesture!

include("GestureRecognizer.jl")

end # module
