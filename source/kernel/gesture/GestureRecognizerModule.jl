"""
    GestureRecognizerModule

The **event → gesture** transformation stage. It sits between the raw device-event
stream and whoever consumes it, and is the place where *combinations and sequences
of raw events* are recognised as a single gesture.

## Why a separate stage

An event source emits low-level, backend-agnostic input events (`KeyDown`,
`KeyPress`, `MouseDown`, `MouseUp`, `MouseMove`, `MouseScroll`). Most of these are
already meaningful on their own and pass straight through — they *are* the
normalized gesture vocabulary. But some gestures only exist as a *combination* of
several events:

- a **click** (`MousePress`) is a `MouseDown` followed by a `MouseUp` at
  approximately the same place within a short time window;
- a **double/triple-click** is several clicks in quick succession — the recognised
  `MousePress` carries a `count`;
- a **key chord** (`KeyChord`) is a recognised *sequence* of `KeyDown`s, e.g.
  `Ctrl-C Ctrl-K`;
- (future) a **drag** (down → move… → up).

Recognising these requires state that spans several events, which a pull-based
reactive pipeline cannot hold. So recognition lives here, in a small stateful
component driven once per input event.

A gesture is *only* a combination of events — it carries no intent. The recogniser
never decides what a click or a chord *means*. Recognising here rather than inside
a backend makes it backend-agnostic and unit-testable without a display, and gives
composite gestures a single home.

The recogniser holds all of its state on its own instance, so one process can run
any number of them independently.
"""
module GestureRecognizerModule

using ..EventModule

export GestureRecognizer, recognize_gesture!, pop_gesture!

include("GestureRecognizer.jl")

end # module
