# Events, gestures and the pointer

> **Status (2026-09-26): design, no code.** The owner and Claude write this
> document over several sessions. It records the concepts, what is wrong today,
> the owner's decisions and the questions that are still open. The steps of the
> refactor come after the open questions have answers. The owner's model of
> three tracking projections (D8 to D33) came on the same day, after the first
> round of decisions.

The facts of the code are in the study
[pointer-hover-and-windows-today.md](pointer-hover-and-windows-today.md). This
document cites the study by section ("study §8") and does not repeat it. Step 3
of [every-window-tracks-the-pointer-and-says-when-it-leaves.md](every-window-tracks-the-pointer-and-says-when-it-leaves.md)
waits for this design.

## 1. The concepts

The owner's definitions, from the conversation of 2026-09-26:

- **Event.** A data structure that describes something that the hardware
  generated, as the platform reports it: a key goes down, a button goes up, the
  pointer moves, the pointer leaves a window, a character is typed (`KeyPress`,
  D18). An event has no meaning of its own.
- **Gesture.** A pattern that matches a sequence of events. The pattern can leave
  out events. A click is a down and an up of one button, near in place and in
  time. A chord is a sequence of keys. A dwell is no motion of the mouse for a
  short time. A projection recognizes gestures (D8), and it can hold any number
  of patterns. A tracking projection can also match a pattern over the events
  and its own state: the target tracker makes an enter from a motion and the
  target that the motion reaches.
- **Tracking projection.** A projection that recognizes gestures and keeps the
  state that the recognition needs, in a document (D10). There are three (D9):
  - the **gesture tracking projection**: the click and the key chord;
  - the **mouse target tracking projection**: its state is the most specific
    document part that the mouse points at; its gestures are the enter, the
    leave and the hover;
  - the **drag tracking projection**: its state is the dragged part; its gestures
    are the drag start, the drag end, the drag hover and the drag move.
- **Dwell and hover.** Two different gestures (D17). The mouse dwell: the mouse
  does not move for a short time. It does not depend on the view under the
  pointer, so a dwell alone is not a hover over a particular thing (D4). The
  mouse hover: the mouse moves over the same target.
- **The target.** The most specific document part under the pointer. It follows
  from two inputs: the position of the pointer, and the view (what is drawn
  where). `map_reference_backward` from the point finds it (D11). It changes when
  either input changes.
- **Meaning.** A reader takes a gesture and answers the edit that the gesture
  means. The meaning belongs to the thing that the gesture lands on.

The owner's first principle of hover was: "a pointer that rests on the same
thing for a while is a gesture". D4 and D17 make it exact: the gesture is the
dwell, and the thing is not a part of the gesture. The reader finds the thing at
the position of the dwell.

The naming rules already name this ladder: "Event → Gesture → Intent →
Operation → Document" ([naming-rules.md:192-200](../../documentation/rule/naming-rules.md)).
The code does not follow it (§3).

## 2. The owner's decisions

All of them are from 2026-09-26.

- **D1.** The pointer that leaves a window is an event, `WindowLeave`. Done on the
  branch `window-leave`.
- **D2.** The Tab wrap-around is unrelated to hover.
- **D3.** `SyntheticEvent` must not exist. A gesture is a gesture, with a type of
  its own, so that gestures and events do not mix.
- **D4.** A rest is a gesture: the event pattern of no mouse motion for a short
  time. It is independent of the view under it, so in itself it is not a hover
  over a particular thing. D17 names it the mouse dwell.
- **D5.** The recognition can hold any number of event patterns (gestures).
- **D6.** `MouseEnter` and `MouseLeave` are gestures, made by the mouse target
  tracking projection. The first decision of the day said "neither events nor
  gestures"; the owner changed it when the model of D9 came.
- **D7.** A reader must not answer a question that is not a gesture. In the
  owner's words: "how should a projection reader know what is the total set of
  possible questions?"
- **D8.** Gesture recognition leaves the kernel, and projections do it. The owner
  allows the unsealing of `gesture/GestureRecognizerModule.jl` and
  `gesture/GestureRecognizer.jl`.
- **D9.** Three tracking projections, as §1 lists them. The gesture tracking
  projection is the one that most hosts use, but a host does not have to.
- **D10.** The state of a tracking projection is a document, written by an
  operation. No state is on the projection itself.
- **D11.** The part at a point is found by `map_reference_backward` from a
  `PointReferenceStep`, and every projection supports it. In a domain projection
  this is usually trivial.
- **D12.** A gesture for a part reaches its reader by the reference of the part,
  never by a position. One generic mechanism reaches any reader of the composite
  projection by reference. It is the mechanism with which an AI agent imitates a
  person: an intent with no gesture, with a prepared operation, along the
  reference of the target. §3.10 shows what of it exists.
- **D13.** An enter and a leave go to every part on the path that changes: a
  leave to each part of the old path that is not on the new path, and an enter
  to each part of the new path that is not on the old path. So a button lights
  when the pointer is on its label, and a `JsonArray` can light when the pointer
  is on one of its elements.
- **D14.** While a drag is on, the drag tracking projection swallows the click
  gestures.
- **D15.** A utility function composes any combination of the tracking
  projections, so a host reuses a combination with one call.
- **D16.** The rules and the documents change with the design, for example
  `PAR-NO-NEW-SYNTHETIC-EVENT`.
- **D17.** The mouse hover (the mouse moves) and the mouse dwell (the mouse does
  not move) are two different gestures.
- **D18.** `KeyPress` stays what it is today: an event, the typed character. This
  avoids complications of decoding.
- **D19.** The dragged part is what the reader answers for the start of the drag,
  for example the target of a drag start operation.
- **D20.** A drag starts after a small move. Before that move, the press can
  still be a click.
- **D21.** The drag tracking projection gets its target from a reader: the reader
  reads a drag start gesture, and its answer is a drag start operation that
  names the target.
- **D22.** Time with no input comes as an event. At a deadline, the loop gives
  the projection an event that says that the time came, with its time. The
  tracker matches "no motion, then this event" as a dwell. The reader does not
  read a clock, so a replay gives the same answer. How a deadline is set is
  open (Q3).
- **D23.** A reader receives both events and gestures.
- **D24.** A reader sets a timer with an operation that it answers. The editor
  holds the deadline, because the loop owns the wait and already computes it from
  the clock and the feeds. The wrapper document of the tracker keeps only what
  the check of its pattern needs: the time and the position of the last motion.
  A new motion answers a new deadline, and a time event that comes after a newer
  motion matches nothing, so no cancel is needed.
- **D25.** The mouse dwell is a gesture of the gesture tracking projection.
- **D26.** The drag tracking projection is inside the gesture tracking
  projection. While a drag is on, it gets the click and drops it (D14).
- **D27.** The state documents of D10 are the wrapper documents of the tracking
  projections, as `DraggingState` wraps its content. The place of a wrapper
  decides its scope: around the screen, one target serves every window and a
  gesture can cross windows; around one window, neither holds. Claude proposes
  that the default composition of D15 puts the wrappers around the screen, and
  that the pointer position is the window id and the position in that window, as
  the events hold it.
- **D28.** At the end of a route, the last reader on the route reads the
  gesture, and the rest of the route names the part.
- **D29.** While a drag is on, the target tracker sends no enter, no leave and
  no hover: the drag gets the moves, and the drag hover takes the place of the
  hover. The order from the outside in is: gesture, drag, target, screen.
- **D30.** Each tracking projection has a package of its own.
- **D31.** The gesture type and the names, as Claude suggested them for Q1:
  - `abstract type Gesture end`, beside `Event` and not under it. A place that
    takes both takes `Union{Event,Gesture}`; there is no common root type.
  - `DeviceEvent` goes away.
  - The gesture types stay in the event layer of the kernel.
  - A gesture has the name form of an event, `<Source><Action>`, and the naming
    rules say so. The new gestures: `MouseHover`, `MouseDwell`, `DragStart`,
    `DragMove`, `DragHover`, `DragEnd`. `MouseEnter`, `MouseLeave` and
    `KeyChord` stay, and `MousePress` becomes `MouseClick`.
  - The timer: `SetTimerOperation`, and the event `TimerExpire`.
  - The projections `GestureTrackingProjection`,
    `MouseTargetTrackingProjection` and `DragTrackingProjection`, with the
    wrapper documents `GestureTrackingState`, `MouseTargetTrackingState` and
    `DragTrackingState`, in the packages `ProjecturedGestureTracking`,
    `ProjecturedMouseTargetTracking` and `ProjecturedDragTracking`.
- **D32.** The utility function of D15 lives in the screen package, next to
  `make_window_scene_projection`. The screen package depends on the three
  tracking packages, and they do not depend on it.
- **D33.** Keyboard navigation between parts is a projection step of its own,
  outside the hover tracker. Its purpose, in the owner's words: "to be able to
  reach any user interface component which can interact using the keyboard in a
  meaningful way". It does three things:
  - Tab and Shift+Tab move to the next and the previous such part, and start
    over at each end;
  - cursor keys, probably with modifiers, move in the plane to the part that is
    next in that direction, found with the mapping of references;
  - it works with any document that accepts it, not only with widgets.

## 3. What is wrong today

### 3.1 Events and gestures share one type tree

- `Event` has two subtypes, `DeviceEvent` and `SyntheticEvent`
  (`EventInterface.jl:19-38`). `SyntheticEvent` holds two kinds of thing:
  - gestures: `MousePress` (a click), `KeyChord` (a chord), and `PointerRest` of
    the tooltip package (`TooltipRest.jl:20`);
  - changes of the thing under the pointer: `MouseEnter` and `MouseLeave`.

  The kernel test adds one more, `EmTestRestEvent` (`EventModuleTest.jl:11`).
- The docstring of `SyntheticEvent` names "a crossing from the motion of the
  pointer" as an example. `devices-and-backends.md:457-462` says that the gesture
  layer "takes events and gives events".
- A gesture has the name form of an event, `<Source><Action>`. `MousePress` is a
  gesture (a click), and `KeyPress` is an event (a typed character), with the
  same verb.
- `EventPattern` selects one value in the table of a reader (`@event_case`,
  `read_bound_gesture`). It is not a pattern over a sequence of events. So the
  word "pattern" has two meanings: a pattern of the recognizer makes a gesture,
  and an `EventPattern` selects a gesture in a reader.

### 3.2 The recognizer is closed, and it passes the events through

- `GestureRecognizer` knows two gestures in its code: the click with its count,
  and the chord from a table (`GestureRecognizer.jl:47-118`). A new gesture needs
  a change of the kernel.
- It answers each event, and after it the gesture that the event completes. A
  reader gets `MouseDown`, `MouseUp` and then `MousePress`, so a reader reads
  events and gestures.
- It acts only when an event arrives, so it can not find a pattern of "no event
  for a time". For this reason the rest is outside it (§3.3).
- Only the editor uses it: every `Editor` makes one (`Editor.jl:89`), and `read!`
  sends every event through it before `read_intent` (`ReadEvaluatePrint.jl:28`).
  Two tests use it too. No layer below it and nothing in omnet-julia uses it.
- The chord table is empty in every running editor. Only the recognizer test
  fills it, and [key-chords-from-bindings.md](key-chords-from-bindings.md) is
  deferred (2026-09-25). So the chord exists only in tests.
- `KeyPress` comes from the input method of the platform (`SDL_TEXTINPUT` in
  SDL). Readers act on `KeyDown`, which holds the flag of the auto-repeat. No
  reader reads `KeyUp`.
- Readers in about 20 packages match `MousePress`, so the gesture types must stay
  low in the stack.

### 3.3 The rest lives in the tooltip package

- A feed of each window names a deadline, the loop sleeps until it, and the feed
  reads a `PointerRest` through the projection (study §7). Only the first window
  has a feed by default, and each host wires it by hand.
- The tooltip probe keeps the time of the last move itself. So the recognizer,
  the feed and the probe each keep a part of the state of the pointer.
- The kernel has the feed interface: `compute_wake_deadline(feed, editor)` names
  the time when the loop must wake (`FeedInterface.jl:38`), and the loop sleeps
  until the earliest deadline of all feeds.
- The editor has a clock (`Editor.jl:61`). The loop writes it once in each frame,
  and a printer reads it through the printer context to animate. A reader does
  not get it.
- The loop does not wake at a fixed rate. It wakes every `FRAME_INTERVAL` only
  while a cell reads the clock (an animation), at the nearest deadline of a feed,
  and else it sleeps until input (`compute_wait_timeout`, `Feeds.jl:35`). Only a
  backend with no wait of its own polls, in slices of 10 ms.

### 3.4 A widget projection makes the crossings

- `WidgetHoverTrackingProjection` makes every `MouseEnter` and `MouseLeave` from
  motion (study §6.1). Its faults:
  - it surrounds the content of the first window only;
  - its state is on the projection instance, and it changes that state inside
    `read_intent`;
  - it sends a leave at the last position, through the layout of now, so the
    leave can reach another thing, or nothing;
  - it holds the Tab wrap-around (D2).
- The thing under the pointer depends on the view too, but the tracker sees only
  motion. When the view changes under a pointer that does not move, the light
  stays on the old thing. Examples: a list that scrolls, a popup that opens, a
  content that changes.
- Eight readers answer a crossing, all of them widgets or charts. Each one writes
  view state on itself:

  | Reader | `MouseEnter` | `MouseLeave` |
  | --- | --- | --- |
  | `WidgetButton` (`WidgetToGraphics.jl:1914`) | `hovered = true` | `hovered = false`, `pressed = false` |
  | `WidgetMenuItem` (`:2406`) | `hovered = true` | `hovered = false` |
  | `WidgetToolbarItem` (`:2493`) | `hovered = true` | `hovered = false` |
  | `WidgetTable`, one reader for each of two IO maps (`:8320`, `WidgetTableList.jl:601`) | the row at the position | clears the row |
  | `WidgetTree` (`:8910`) | the row at the position | clears the row |
  | `WidgetList` (`:7388`) | nothing; it lights a row from `MouseMove` | `hovered = 0` |
  | `ChartPlot` (`ChartPlotToGraphics.jl:1382`) | nothing; it lights from `MouseMove` | stops a drag, clears the hover |
  | `SequenceChartPlot` (`SequenceChartPlotToGraphics.jl:1184`) | nothing; it lights from `MouseMove` | clears `hovered` and `cursor` |

  No domain projection answers a crossing: not JSON, text, syntax, layout,
  screen, shell or tooltip. No reader and no gesture table uses
  `MouseEnterPattern` or `MouseLeavePattern`.
- The list and the two charts answer the leave but not the enter. The tracker
  sends a leave only to a thing that answered its enter, so their leave branches
  are not reached through the tracker. A lit row of a list can stay lit when the
  pointer moves onto another widget. A reading of the code shows this; no run
  confirmed it yet.
- Every container translates a crossing into the frame of a child, next to the
  other positioned events (study §11, item 10).

### 3.5 Readers answer questions

- Five probes ask "what is under the pointer" through `read_intent`: the four of
  study §8, and the reorder drag, which finds its drop target with a fake
  `MousePress` (`Dragging.jl:222`). Each probe puts the question in the form of a
  fake gesture. Each reads the answer from the inner shape of an operation:
  `_target_of` takes the root of a hover write (`WidgetHoverTracking.jl:146`),
  and the four others take the path of a `ReplaceSelectionOperation`. No reader
  promises these shapes.
- A reader changes its answer for the sake of a probe: the table writes on every
  enter only so that the tracker finds it (`WidgetToGraphics.jl:8317`).
- The rule `PAR-NO-NEW-SYNTHETIC-EVENT` already forbids this use: "The reader
  chain reads what a person does. It is not a channel to carry an operation, a
  request or a question through the projection hierarchy"
  ([architecture-invariants.md:503-514](../../documentation/rule/architecture-invariants.md)).
  The five probes break it. The rule also says that a synthetic event that
  exists now is not a precedent for a new one.

### 3.6 The pointer position has no home

- The position exists only in the newest `MouseMove`, and in
  `get_pointer_position`, which answers screen coordinates while an event holds
  window coordinates (study §11, item 14).
- The web client sends no motion while no button is held, so the browser has no
  crossing and no rest (study §4).

### 3.7 Each drag works alone

| Drag | Where the state is | When the drag starts | The pointer leaves the window | Feedback over a target |
| --- | --- | --- | --- | --- |
| reorder (`ProjecturedDragging`) | on the projection instance (`Dragging.jl:37-44`) | after 5 px | not handled; the drag can stay on forever | none |
| splitter of `WidgetSplitPane` | document fields `active_splitter`, `drag_anchor` | at once, on `MouseDown` | not handled | none |
| tab of a pane | `PaneTree.drag`, view state | at once, on `MouseDown` | not handled | a drop indicator |
| slider | the field `dragging` | at once, on `MouseDown` | not handled | none |
| chart pan and zoom | document fields, view state | at once, on `MouseDown` | `MouseLeave` cancels it | a rubber band |

- Nothing prevents a click after a drag: any press and release within 5 px and
  0.3 s is a click. The tab strip and the slider read both `MouseDown` and
  `MousePress`.
- For the splitter and the chart pan, the dragged thing is not a part of the
  document: it is a divider, or the visible range of the data. D19 covers this:
  the dragged thing is what the reader answers for the start.
- The design of the drag package keeps the state on the projection because "no
  phase of a drag must survive a new print" (`dragging.md:21`). D10 changes this.

### 3.8 No projection that ends in graphics maps a point backward, except one

- `PointReferenceStep(x, y)` names a pixel (`PointReferenceStep.jl:4`, in the
  graphics package). The screen uses it for screen pixels
  (`ScreenToScreen.jl:113-147`).
- Only the math projection maps a point backward (`MathToGraphics.jl:1752`), and
  its click reader uses that mapping.
- These answer `nothing` for every reference: the graphics leaf
  (`GraphicsCaching.jl:43`), text to graphics (`TextToGraphics.jl:80`), the
  widgets (for example the button, `WidgetToGraphics.jl:1887`), both charts
  (`ChartPlotToGraphics.jl:1295`, `SequenceChartPlotToGraphics.jl:948`), and the
  anchored layout.
- These map a structural path backward, but not a point: the other layouts (a
  path into the drawn canvas becomes a path into `children`,
  `LayoutToGraphics.jl:600-635`), the syntax chain (text spans), and the screen
  (`ScreenToScreen.jl:116-159`).
- Every projection does its hit test by hand inside `read_intent`:
  `hit_element_at`, `_route_to_children`, `_wtl_row_at`, `_hit_segment` and
  others. No function answers "what is here" outside `read_intent`. The graphics
  leaf already turns a point into the path of a drawn element
  (`GraphicsCaching.jl:119-155`).
- About 90 projection types end in graphics in projectured-julia, 42 of them
  widgets, and about 17 in omnet-julia (counted by name).

### 3.9 The state of the trackers is on the projections

The hover tracker, the drag package and the tooltip probe keep their state on the
projection instance, and change it inside `read_intent`. The kernel already has
the operation for such state, `ReplaceViewStateOperation`: "what the pointer is
over, what it holds down, what a drag carries" (`Operations.jl:207-218`).

### 3.10 An intent can already follow a route to a place

- `Intent` has the field `route`: for an operation that code made, the path from
  the input of the reader to the place of the operation. The gesture is then
  `nothing` (`Intent.jl:24-31`).
- `read_rooted_operation(editor, place, operation)` starts such an intent at the
  root (`ReadEvaluatePrint.jl:73-99`). The plan
  [an-operation-enters-at-any-reference.md](../done/an-operation-enters-at-any-reference.md)
  (done 2026-09-23) made it for this goal: "a verb, the assistant, an MCP tool, a
  test, a replay … can do anything a person can do".
- Few readers follow a route: the chain (`Chaining.jl:137`), `ScreenToScreen`,
  the widget shell (`WidgetToGraphics.jl:2996`), the undo buffer, two clipboard
  projections and the file format projection. The default reader ignores the
  route. No other widget container and no domain projection follows it.
- At the place, the reader is not read: the prepared operation stands as its
  answer (`read_routed_intent`, `ProjectionDefaults.jl:226`). A gesture that goes
  to a target by reference (D12) needs the reader at the place to read the
  gesture.

## 4. What we want to change

The direction that follows from the decisions so far:

1. Remove `SyntheticEvent` (D3). The events stay under `Event`, and the gestures
   get a type tree of their own.
2. Remove the gesture layer from the kernel (D8). The editor gives events to the
   projection; the tracking projections make the gestures (D9).
3. Keep the state of each tracking projection in a document, written by view
   state operations (D10).
4. Make every projection that ends in graphics map a `PointReferenceStep`
   backward (D11). The hit tests move out of `read_intent`, and a click reader
   can use the same mapping, as the math projection does.
5. Extend the route of an intent so that a gesture can go to a reference, and
   make every composite projection follow a route (D12). Keys, crossings, a
   dwell on the target and an operation of an AI agent then take one path.
6. Send an enter and a leave to each part on the changed path (D13). The target
   tracker holds one target for the whole screen, so every window has hover
   (fault H1), and `WindowLeave` clears it.
7. Join the five drags in the drag tracking projection (D14, D19), and remove
   the five probes (D7).
8. The dwell moves from the tooltip package into a tracking projection (D4, D17).
   A tooltip is then one meaning of a dwell, which the target gives.
9. The Tab wrap-around leaves the hover tracker (D2) for the navigation step of
   D33, which reaches every part that takes the keyboard, in any document.
10. A utility function composes the tracking projections (D15), and the rules and
    documents change (D16).
11. Each tracking projection gets a package of its own (D30). The packages that
    hold the parts today change with it:
    - the widget package loses `WidgetHoverTrackingProjection`, and its widgets
      answer the gestures of the target tracker;
    - the tooltip package loses its feed, its probe and `PointerRest`; the
      tooltip becomes the meaning of a dwell, and `compute_tooltip` stays;
    - the dragging package keeps the reorder as a meaning of the drag gestures,
      and loses its own tracking and its probe;
    - the splitter, the tab of a pane, the slider and the chart read the drag
      gestures, and their own drag state goes away.

## 5. Open questions

- **Q13. The keyboard navigation of D33.** The facts of today:
  - The package `ProjecturedFocus` holds the open trait `is_focusable_document`,
    to which a domain adds a method; the widgets mark each enabled interactive
    leaf (`WidgetDocument.jl:2795`). It also holds the walks
    `get_first_focusable_path` and `get_last_focusable_path`, which name no
    widget type.
  - The widget and layout containers move Tab inside themselves
    (`WidgetToGraphics.jl:1225`, `LayoutToGraphics.jl:207`), and only the start
    over at the ends is in the hover tracker.
  - `SelectionWalkingProjection` of the same package is a precedent for the
    step: a transparent wrapper that answers the Alt + arrow keys that nothing
    inside answered, with a walk over the structure of any document.

  The questions, for the design of the step:
  - Does the step do the whole walk of Tab, so the code of Tab in the
    containers goes away? Claude recommends yes, so one place does it for every
    document.
  - Which keys move in the plane? Alt + arrow already walks the structure.
  - A part that uses a key itself (Tab in a text, arrows in a list) answers it
    first, and the step gets only what nothing answered. Which key always
    leaves such a part?
  - Is `is_focusable_document` the test of "can interact using the keyboard in
    a meaningful way"? Is a JSON editor one stop, or is each of its elements?
  - The move in the plane needs the drawn box of each stop: the forward mapping
    of a reference to the output. Claude did not check yet how far it reaches.

Answered and moved to §2: Q2 (D23), Q3 (D24), Q4 (D25), Q5 (D20), Q6 (D26), Q7
and Q8 (D27), Q9 (D28), Q10 (D29), Q11 (D30), Q1 (D31), Q12 (D32).

## 6. Next steps

1. Answer the open questions with the owner, one at a time, and record each
   answer in §2.
2. Collect the facts that an answer needs at the time it needs them.
3. Then write the steps of the refactor in this document, each with its test.

The refactor changes sealed files. The owner allows the unsealing of the two
files of `gesture/` (D8). These sealed files of `event/` change too, and each
needs the owner's word before a change ([SEALING.md](../../SEALING.md)):
- `EventInterface.jl`: `SyntheticEvent` and `DeviceEvent` go, `Gesture` comes;
- `MouseEvent.jl` and `KeyboardEvent.jl`: the supertypes of the gestures, and
  `MouseClick`;
- `EventPattern.jl`: a pattern takes a gesture, and `MouseClickPattern`;
- `EventDefaults.jl` and `WindowInput.jl`: they take `Union{Event,Gesture}`.

The rule `PAR-NO-NEW-SYNTHETIC-EVENT` changes too (D16).
