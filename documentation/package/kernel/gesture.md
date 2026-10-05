# Gesture

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

The gesture layer of the kernel turns a sequence of events into gestures: a
click with its count, a key chord and a pointer dwell, each a pattern that a
pure rule finds in events with no document and no operation involved. This
document describes the gesture types, the three recognitions, the pattern
language that a reader matches an input with, and the rule by which a dwell or
a right click that a part declines reaches the documents around it.

## How it works

### The event and the gesture

An event is a record of what a backend reports: a key that goes down, a button,
a motion. A gesture is a pattern that a recognition finds in a sequence of
events, and the pattern can leave out events: a `MouseClick` is a `MouseDown`
and a `MouseUp` of the same button, near in place and in time; a `MouseDwell` is
a motion followed by no motion for a while; a `KeyChord` is a sequence of
`KeyDown`s that a chord table names. `Gesture` is the supertype of six concrete
types, in `source/kernel/gesture/`, beside `Event` in the event layer below it:
these three, which a recognition finds, and `DragMove`, `DragEnd` and
`DragCancel`, which the platform's drag tracker makes from a drag in progress
(see [The drag gestures](#the-drag-gestures) below).

A gesture carries no intent, as an event does not: the code that reads it, a
document's own gesture table, gives it a meaning. Every concrete gesture holds
`time` as its last field, the time of the event that completes its pattern, and
answers the same two generics as an event, `get_event_time` and
`get_modifier_keys`, so a reader that takes `Union{Event,Gesture}` treats both
alike.

### The three recognitions

`GestureRecognition` is the supertype of a recognition: a pure rule that holds
its own settings and no state. `make_recognition_state(recognition)` gives its
first state, an immutable value, and `recognize(recognition, state, input,
window)` reads one event or gesture, with the id of its window, and answers a
`RecognitionStep`: the next state, the inputs that follow — the gesture the
input completes, or inputs the recognition kept and gives back — a deadline at
which the recognition reads again, and whether it holds the input from the
recognitions after it and from the reader.

`make_standard_recognitions()` lists the three recognitions a host runs by
default, in this order:

- `ChordRecognition(chords)` gives a `KeyChord` in place of a sequence of
  `KeyDown`s that matches an entry of its table, a `Vector{Vector{KeyDown}}`.
  It holds the keys of a sequence in progress, whatever their `repeat` flag, and
  gives them back, kept key first, when a key breaks every prefix. The table is
  empty by default, so every key passes through. This recognition runs first,
  so a key it keeps reaches no later recognition.
- `ClickRecognition(; click_max_displacement = 5, click_max_duration = 0.3,
  multi_click_max_displacement = 5, multi_click_max_interval = 0.3)` gives a
  `MouseClick` after a `MouseUp` close enough in place to the `MouseDown` of the
  same button. No check reads `click_max_duration`: SDL2 stamps an event when it
  takes it from the queue of the window system, so a slow frame between the down
  and the up makes the up late; the first press of a new process is such a frame.
  The comment on `_is_click` says when the check can come back. `count` goes
  to 2 and to 3 when the next click comes close enough in place and in time to
  the one before.
- `DwellRecognition(; delay = 0.5)` gives a `MouseDwell` when the pointer does
  not move for `delay` seconds after a motion with no button held. A motion
  with a button, a down, a click, a scroll and the leave of a window stop the
  wait; a key does not, because a dwell is no motion of the mouse. A move to the
  point of the last move, in the same window, keeps the wait as it is instead of
  starting a new one, so the move that a backend sends after a frame that
  changed a window gives no extra dwell.

A deadline that a recognition answers becomes a timer of the editor, under the
name of the recognition, and the `TimerExpire` of that timer goes back to that
recognition alone; see [editor.md](editor.md#the-timer-and-the-display-event).
The platform's gesturetracking slice runs the list of recognitions as a
projection wrapper around a document; see
[gesturetracking.md](../platform/gesturetracking/gesturetracking.md).

### The drag gestures

`DragMove(x, y, modifiers; time)`, `DragEnd(x, y, modifiers; time)` and
`DragCancel(; time)` are `Gesture` subtypes of this layer, beside `MouseClick`,
`MouseDwell` and `KeyChord`, but no recognition makes them. The platform's drag
tracking slice makes them instead: it keeps the path of the part whose drag is
on, and sends that part `DragMove` for each held move, `DragEnd` for the
release, and `DragCancel` for a bare Escape, the loss of the focus of the
window, or a move with no button held while the drag is on. `DragMove` and
`DragEnd` carry a position, in the frame of the part whose drag is on;
`DragCancel` carries only a time, because the part puts back what it kept at
the start of the drag and needs no position for that. See
[dragtracking.md](../platform/dragtracking/dragtracking.md).

### The gesture pattern and the table

A `GesturePattern{E}(fields, modifiers, guard, label)` is a pattern as data: the
event or gesture type `E`, the fields that must equal a value, the modifiers
that must match exactly, a guard function and a label for a person.
`matches_gesture_pattern(pattern, event)` tests one input, and
`describe_gesture_pattern(pattern)` renders the pattern for a person, such as
`"Ctrl+."` or `"Right click"`. `make_tooltip_binding` and
`make_context_menu_binding` of the platform tooltip and widget slices each
build a `GestureBinding` directly from a pattern:

```julia
GestureBinding(MouseDwellPattern(), (document, gesture) -> make_tooltip_operation(...);
              description = "Show the tooltip", domain = "tooltip")
GestureBinding(MouseClickPattern(:right), (document, gesture) -> make_context_menu_operation(...);
              description = "Show the context menu", domain = "context menu")
```

`GestureBinding` keeps the pattern beside the function it fires, so a listing of
the bindings of a document — the gesture help that F1 opens, and the command
palette that Ctrl+Shift+P opens — reads `describe_gesture_pattern` of the
pattern to say what runs each one, with no second table to keep in step.

`@gesture_case event begin pattern => result; … end` compiles a table of rules
into plain `isa` and field tests, for a reader that turns an event into an
operation in one expression, with no `GesturePattern` reified for any rule:

```julia
@gesture_case event begin
    KeyDown(:period; ctrl)  => on_toggle()
    MouseClick(:left, x, y) => select_at(x, y)
    _                       => nothing
end
```

The `@gestures` macro of the binding layer builds the reified `GesturePattern`
of each rule of its own table with the same parser
(`parse_gesture_pattern_rule`, `build_gesture_pattern_expr`,
`build_gesture_field_bindings`), so a table a document declares with
`@gestures` is both a compiled matcher and the listing the gesture help shows.

### The outward read of a dwell and a right click

`is_outward_gesture(gesture)` of the platform graphics slice is true for a
`MouseDwell` and for a right `MouseClick`: the two gestures that a document can
leave to the documents around it, when its own table answers nothing. A dwell
and a right click travel by position, the same hit test a move uses, not by the
mouse target.

`read_gesture_outward(answer, gesture, document; steps, with_part = false)` of
the projection layer is the rule behind it: `document` is the input of a
container, `steps` lead from it to the input of the child the gesture went to,
and `answer` is what the child answered. The documents on `steps`, from the
child's own input out to `document`, read the gesture with their own table
(`read_gesture`) in this order:

- **a document reads when nothing deeper answered**, or when the deeper answer
  collects (`is_collecting_operation`, of the operation layer);
- **a collected answer is joined** with the new one (`join_collected_operations`),
  so a tooltip or a context menu grows one layer per document that has
  something to add;
- **any other answer ends the walk**, and the nearest document that gave it
  wins.

With `with_part = true` the document at the end of `steps`, the part itself,
reads too. `read_child_part_gesture` of the graphics slice always passes
`true`, because nothing has read the part's own table yet. `read_container_gesture`
of the same slice passes `isempty(steps)`: `true` when no child took the
gesture, so the container's own input is the part, and `false` when a child did
take it, because the hand-off to that child already read the part's table.

A worked example: a `WidgetToolbarItem` shows the icon of its action alone,
with no tooltip of its own on the icon. A dwell on the icon answers nothing,
so the walk goes one step out to the toolbar item's own table, which answers
with the label of the action instead — so the dwell still opens a tooltip,
with no tooltip set on the icon itself.
[mouse-target.md](mouse-target.md#a-dwell-and-a-right-click-travel-by-position-too)
names the functions that route the gesture to the part before this read starts;
[tooltip.md](../platform/tooltip/tooltip.md) and
[context-menu.md](../platform/widget/context-menu.md) describe what the two
gestures mean once a table answers.

## How it fits

`Gesture`, the three recognitions and `GesturePattern` are the gesture layer of
the kernel, layer 8 of 23, above `device` and below `backend`; the layer depends
only on the `event` layer under it, and defines no document and no operation.
`GestureBinding`, `@gestures` and `read_gesture` are the binding layer, layer
15, which depends on the operation layer for the kind of value a binding
answers. `read_gesture_outward` is the projection layer, layer 17, built on
`is_collecting_operation` and `join_collected_operations` of the operation
layer, layer 13.

The platform graphics slice turns the projection layer's rule into the routing
every container shares: `is_outward_gesture`, `compute_part_at_point`,
`read_child_part_gesture` and `read_container_gesture`, described in
[graphics.md](../platform/graphics/graphics.md). The gesturetracking slice runs
the recognitions as a wrapper around the document a host shows; see
[gesturetracking.md](../platform/gesturetracking/gesturetracking.md), which also
describes why an input waits for a timer. The dragtracking slice makes the
three drag gestures from the path it keeps, and sends them to the part whose
drag is on; see
[dragtracking.md](../platform/dragtracking/dragtracking.md). The tooltip slice
and the widget slice's context menu are the two readers of an outward gesture
today; see [tooltip.md](../platform/tooltip/tooltip.md) and
[context-menu.md](../platform/widget/context-menu.md).

## Design decisions

- **A gesture carries no intent, and a recognition keeps no state of its own.**
  A recognition only finds the pattern; the document that reads the gesture
  with its own table gives it a meaning. The state is a plain value that the
  code that runs the recognition keeps, such as the state document of the
  gesture tracking projection, so the gesture layer defines no document type
  and a recognition is reusable without a registry or a singleton.
- **The pattern is reified, not only compiled.** `GesturePattern` is a value a
  binding keeps beside the function it fires, so the gesture help and the
  command palette read `describe_gesture_pattern` of the same pattern that
  fires the binding, with no second table written by hand.
- **The outward read is one rule, shared by every gesture that needs it.**
  `is_outward_gesture` names which gestures travel this way, and
  `read_gesture_outward` reads the documents around the part the same way for
  all of them, so a package that adds a new outward gesture writes no routing
  of its own.

## Usage

```julia
# A table of a document type, compiled and reified at once: each rule is a
# pattern, a description for the gesture help, and the answer.
@gestures DataFrameView begin
    KeyDown(:home; ctrl) => "Jump to the first row" => jump_to_row(doc, 1)
end

# The recognitions a host runs, and the wrapper that applies them:
document, projection = make_tracking_screen(screen_document, screen_projection;
                                            recognitions = make_standard_recognitions())
```

- Tests: `test_gesture_module()` and `test_gesture_recognition()`
  (`test/kernel/gesture/`) cover the gesture types and the three recognitions;
  `test_gesture_pattern()` covers the pattern syntax and `@gesture_case`;
  `test_gesture_tracking()` (`test/platform/projection/GestureTrackingTest.jl`)
  covers the wrapper that runs them.

## Limits

- **No package gives `ChordRecognition` a non-empty table yet.** Every caller of
  `make_standard_recognitions()` and of `GestureTrackingProjection` uses the
  default empty table, so every key passes through unrecognized as a chord.
- **An outward gesture travels by position only.** A dwell and a right click
  reach the part under the pointer by the same hit test a move uses; a part
  that is not drawn, such as the content of a closed tree node, answers
  neither.
