# Gesture tracking

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../../kernel/devices-and-backends.md), [operation.md](../../kernel/operation.md)

`ProjecturedGestureTracking` runs the recognitions of gestures over the inputs of the devices. It is a projection with a wrapper document, and a host puts it around the document that the editor shows. The recognitions themselves are in the gesture layer of the kernel, so a package can add one. The editor recognizes nothing, so an editor whose projection has no gesture tracker gets events and no gestures.

## The recognitions

A recognition is a pure rule of the kernel gesture layer, a subtype of `GestureRecognition`. `make_recognition_state(recognition)` gives its first state, an immutable value. `recognize(recognition, state, input, window)` reads one input, an event or a gesture, with its window, and answers a `RecognitionStep`:

- the next state;
- the inputs that follow the one it read: the gestures that the input completes, or inputs that it kept and gives back;
- a deadline, a time at which it wants to read again, or `nothing`;
- whether it holds the input from the recognitions after it and from the reader.

A time comes as an input: at the deadline, the recognition reads a `TimerExpire`. The kernel has three standard recognitions, and `make_standard_recognitions()` lists them in their order:

- `ChordRecognition(chords)` holds a key that continues a sequence of its chord table, and gives a `KeyChord` in place of the key that completes it. A key that breaks the sequence gives back the kept keys and itself, in order. The table is empty by default.
- `ClickRecognition()` gives a `MouseClick` with its count after a `MouseUp` inside the click window of the `MouseDown` of its button.
- `DwellRecognition(; delay = 0.5)` gives a `MouseDwell` when the pointer does not move for `delay` seconds after a motion with no button held. A motion with a button, a down, a click, a scroll and the leave of the window stop the wait. A key does not, because a dwell is no motion of the mouse. A move to the point of the last move, in the same window, is no motion either: it keeps the wait as it is and starts no new one. The SDL backend sends such a move after each frame that changed a window, so a view that changes on every frame still gets its dwell, and a pointer that rests gets one dwell, and none after a press, until it moves.

## How the projection works

`GestureTrackingState` wraps a `content` document and keeps two fields: `states`, the state of each recognition in the order of the list, and `waiting`, the inputs that wait for the content. A view state operation writes each field, so a history does not record it, and no state is on the projection.

`GestureTrackingProjection(; inner, recognitions)` prints the content through `inner` and returns its output, so the wrapper adds nothing to the view. For each input, it runs the recognitions in the order of the list. The inputs that a recognition gives are inputs of the recognitions after it, so a later recognition can read the gesture of an earlier one, or hold it. The content reads the input in the same read, unless a recognition holds it; then it reads the first input that the recognitions give. The projection adds the `content` step to the answer of the content, and then its own writes. It writes the states only when they change, so an input that changes no state leaves the answer of the content as it is: with an empty chord table, a key writes nothing, and the editor still sees Escape and the zoom keys.

A deadline becomes a timer of the editor with the name of its recognition, and the `TimerExpire` of that timer goes to that recognition alone.

## Why an input waits for a timer

A reader must see the state after the operation of the input before it. The click of a `MouseUp` must see what the up changed, and the second of two kept keys must see where the first one put the caret. A reader answers one operation for each read, so the other inputs wait in the state, and the projection answers a `SetTimerOperation` at the time of the input. The editor reads a due timer before new input, so the next read brings the next input in, after the operation of the one before. No mechanism is added for this: the timer is the one that a recognition uses for a deadline.

## How to add a gesture

A package defines a gesture type, a subtype of `Gesture` whose last field is `time`, and a recognition with its two methods. A host adds the recognition to the list, and a reader matches the gesture with `@gesture_case`. For example, a long press: `MouseDown` answers a deadline, `MouseUp` stops the wait, and the `TimerExpire` gives the gesture.

## How to use it

Apply the wrapper with `make_gesture_tracking_document(document)` and `make_gesture_tracking_projection(projection; recognitions)`. The screen package applies it around the screen in `make_tracking_screen`, outside the mouse target tracker, so one tracker serves every window and the target tracker reads the inputs that the recognitions pass. `get_wrapped_document` of the state answers the content. The times of the gestures are the times of the inputs, so a slow frame does not lengthen a click, and a replay gives the same gestures.
