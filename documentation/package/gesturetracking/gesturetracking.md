# Gesture tracking

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../kernel/devices-and-backends.md), [operation.md](../kernel/operation.md)

`ProjecturedGestureTracking` recognizes gestures from the events of the devices: a click with its count, a key chord and a mouse dwell. It is a projection with a wrapper document, and a host puts it around the document that the editor shows. The kernel has no recognizer, so an editor whose projection has no gesture tracker gets events and no gestures.

## How it works

`GestureTrackingState` wraps a `content` document and keeps the state of the recognition in its fields: the buttons that are down, the last click, the keys of a chord in progress, the inputs that wait for the content, and the last motion of the pointer. A view state operation writes each field, so a history does not record it, and no state is on the projection.

`GestureTrackingProjection` prints the content through its `inner` projection and returns its output, so the wrapper adds nothing to the view. The reader gives the content every event, and adds the `content` step to the operation that comes back. Then it adds its own writes:

- A `MouseDown` records the press of its button. A `MouseUp` inside the click window of that press adds a `MouseClick` with its count to the inputs that wait.
- A `KeyDown` of a sequence in the chord table is kept, and the key that completes the sequence goes to the content as a `KeyChord` in its place. A key that breaks the sequence gives out the kept keys and itself, in order. The table is empty by default, so a key writes no state and the answer of the content is the whole answer.
- A `MouseMove` with no button held records the motion and sets a timer at the end of `dwell_delay`. When the timer comes and no newer motion came, the content gets a `MouseDwell` at the position of the motion. A move with a button held, a down, a click, a scroll and the leave of the window stop the wait.

## Why a gesture waits for a timer

A reader must see the state after the operation of the event before it. The click of a `MouseUp` must see what the up changed, and the second of two kept keys must see where the first one put the caret. A reader answers one operation for each read, so the gesture can not go to the content in the same read as its event. The reader keeps the gesture in the state and answers a `SetTimerOperation` at the time of the event. The editor reads a due timer before new input, so the next read brings the gesture in, after the operation of the event is evaluated. No mechanism is added for this: the timer is the one that a reader uses for a deadline.

## How to use it

Apply the wrapper with `make_gesture_tracking_document(document)` and `make_gesture_tracking_projection(projection)`. The keywords of the second go to `GestureTrackingProjection`: `chords`, the click windows (`click_max_displacement`, `click_max_duration`, `multi_click_max_displacement`, `multi_click_max_interval`) and `dwell_delay`. The screen package applies it around the screen, so one tracker serves every window. `get_wrapped_document` of the state answers the content.

The times of the gestures are the times of the events, so a slow frame does not lengthen a click, and a replay gives the same gestures.
