# Events, gestures and the pointer

> **Status (2026-09-26): design, no code.** The owner and Claude write this
> document over several sessions. It records the concepts, what is wrong today,
> the owner's decisions and the questions that are still open. The steps of the
> refactor come after the open questions have answers. The owner's model of
> three tracking projections (D8 to D45) and the steps came on the same day, after the first
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
  outside the hover tracker. Its design is the plan
  [tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md](tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md), split from this plan on 2026-09-26 with the decisions D35 to D39.
- **D34.** The owner allows the unsealing of every kernel file that the design
  needs, and the files stay unsealed after the work. Unsealed in `SEALING.md` on
  2026-09-26: `event/EventInterface.jl`, `event/KeyboardEvent.jl`,
  `event/MouseEvent.jl`, `event/WindowInput.jl`, `event/EventDefaults.jl`,
  `event/EventPattern.jl`, `gesture/GestureRecognizerModule.jl`,
  `gesture/GestureRecognizer.jl` and `backend/BackendInterface.jl` (its docstring
  names `DeviceEvent`). `event/WindowEvent.jl` and `event/EventModule.jl` were
  unsealed before, for `WindowLeave`, and stay unsealed too.
- **D35 to D39** moved to the plan of D33, as N2 to N6.
- **D40.** "Anything which can be done locally should be done locally because it
  combines better", in the owner's words. It must become a rule of the design
  documents, near `PAR-DELEGATE-ONE-LEVEL`. It holds for this plan too: a
  tracking projection does only what no part can do alone.
- **D41.** When the view changes, the target is found again, as if the pointer
  moved: the old part gets a leave and the new part an enter. The owner agreed to
  this principle for Q14.
- **D42.** After a frame that changed what the display shows, the loop gives the
  projection an event of the display, and the target tracker and the drag
  tracker find their part again at the last position. The owner chose this way
  for Q14. The principle, in the owner's words: the read-eval-print loop "can go
  to sleep when the view does not change anymore. If the view has changed the
  loop has to run again." So the loop sleeps only after a frame that changed
  nothing.
- **D43.** The backend sends the display event when it shows a frame that differs
  from the one before, because only the backend knows what the display shows. The
  event is `DisplayUpdate`. (Q15.)
- **D44.** A light never changes the layout: a hover draws a layer over the
  surface of the part, and no part changes its size or place for it. This stops
  the loop of D42 from a light that moves another part under the pointer, frame
  after frame. It becomes a rule of the design documents. (The risk of D42.)
- **D45.** A feed that writes because a frame happened writes at most once per
  time interval, so that a frame that a display event causes does not feed the
  next one (D42). The fix stays in each feed (D40). The owner chose this rule
  over a special frame and over a limit of display rounds (Q16).

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
9. The Tab wrap-around leaves the hover tracker (D2) for a small wrapping step
   of its own (§5 of the plan of D33). That step must exist before the hover
   tracker goes away, or come in the same change, so that Tab still starts over
   at the ends. The rest of that plan is deferred.
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

- **Q16 (answered by D45). Views that change on every frame (found in step 2).** With D42, a frame
  that changed the display is followed by one more read. A view that changes
  because a frame happened then keeps the loop awake for ever:
  - the frame statistics: `FrameStatisticsFeed` flushes on every frame whose
    count differs, and its own header says "a wake would make frames feed
    themselves";
  - `ReflectionFeed` syncs a live value on every frame, so a value that changes
    all the time would redraw at the full frame rate.

  Also, the SDL backend presents every window on every frame when partial
  rendering is off, which is the default; so "a frame that differs" must come
  from the dirty walk, which then runs in both modes.

The questions of keyboard navigation are in the plan of D33.

Answered and moved to §2: Q2 (D23), Q3 (D24), Q4 (D25), Q5 (D20), Q6 (D26), Q7
and Q8 (D27), Q9 (D28), Q10 (D29), Q11 (D30), Q1 (D31), Q12 (D32). Q13 moved to
the plan of D33. Q15 and the risk of D42 (D43, D44). Q14 is kept below, because
it holds the example.

- **Q14 (answered by D41 and D42). The view changes under a pointer that does
  not move.** An example: the
  pointer rests on row 5 of a list of files, and row 5 is lit. The person turns
  the wheel, and the list scrolls three rows. Row 8 is now under the pointer.
  - In principle, the target is a function of two inputs: the position of the
    pointer and the view. When either one changes, the target must be found
    again, and the old part gets a leave and the new part an enter, as if the
    pointer moved. A browser finds the hover again after a scroll or a change of
    the layout, and Qt sends an enter to a widget that appears under the cursor.
  - In the design, the tracker reads the wheel event before the scroll happens.
    It maps the point through the old view and finds row 5 again. Then the
    operation of the scroll is evaluated and the view is printed, but no event
    comes after that, so no reader runs. The tracker keeps row 5 as its target
    until the pointer moves, and row 5, now three rows higher, stays lit while
    row 8 is under the pointer. A fake move would find the target, but D3 does
    not allow it: a move is a record of the hardware.
  - Other examples of the same fault: a key scrolls the list; a dialog or a popup
    opens or closes under the pointer; a tab page changes by a key; a content
    changes by itself (a log that grows, a simulation that updates a table).
  - The principle is D41. What is open is how the tracker learns that the view
    changed. The loop knows it: a frame that evaluated an operation, or that
    drained a change from a feed, can change the view. Two ways:
    - **Claude's recommendation: an event of the display.** After a frame that
      changed the view, the loop gives the projection an event that says that the
      display shows a new frame (the name is open). The target tracker maps its
      last position through the new view, and when the target changed, it sends
      the leave and the enter. The drag tracker finds the drag hover again in the
      same way. The display is a device, and a new frame is a record of what it
      did, so D3 holds. The enter writes a light, which makes one more frame; its
      event finds the same target and answers nothing, so the chain stops. A
      frame that changes nothing sends no event, so an idle editor stays idle.
    - **A sample of the pointer.** After such a frame, the loop reads the
      position from the pointer device and gives it as an event of its own. It is
      a record of the hardware too, but it names the position, which the tracker
      has already, and not the cause, which is the change of the view.
  - Not a way: a light that each printer derives from the target. The owner's
    model gives the light to the reader of the part (the meaning belongs to the
    thing), and a target that depends on the view and a view that depends on the
    target can form a cycle of cells.


## 6. Steps

> **Proposed by Claude and approved by the owner on 2026-09-26, with their
> order.** Each step keeps every suite green, and each step ends with a commit. A
> step that changes a name or a signature also changes omnet-julia. The steps
> continue on the branch `window-leave`, whose plan this plan takes over.

- [x] 1. **The gesture type (D3, D31).** `abstract type Gesture end` beside
  `Event`. `MouseClick` (renamed from `MousePress` with `julia-rename.jl`),
  `KeyChord`, `MouseEnter`, `MouseLeave` and `PointerRest` subtype `Gesture`.
  `SyntheticEvent` and `DeviceEvent` go away. The places that take both take
  `Union{Event,Gesture}`. The naming rules get the line for a gesture. No
  behaviour changes. Tests: the event module, the patterns, the naming guard,
  the kernel layering, then the suites of the packages that match `MouseClick`.

  Done on the branch `gesture-type` (worktree
  `projectured-julia-gesture-type`, started from `window-leave` after its rebase
  onto `main`), with branches of the same name in omnet-julia and inet-julia.
  Facts found:
  - Four files bound a value to `Event`: `EventDefaults.jl`, `WindowInput.jl`,
    `EventPattern.jl` and the gesture log (`GestureLogDocument.jl:114,119`). The
    gesture log would have described a click with `string(gesture)`, because its
    method took `::Event`; it takes the union now.
  - `WindowInput` keeps the field name `event` for both kinds; its docstring says
    so.
  - The rename tool found 363 references in projectured-julia, 64 in omnet-julia
    and 6 in inet-julia. The text pass renamed the rest: comments, docstrings,
    Markdown and the precompile statements (a module-qualified name, which the
    tool skips). No data file names the type.
  - The test gesture `EmTestRestEvent` is `EmTestRestGesture`, and its
    description is "em test rest gesture".
  - The rule `PAR-NO-NEW-SYNTHETIC-EVENT` still names `SyntheticEvent`. Step 10
    writes it again (D16).
  - Checks, each compared with the same run on `main` (`a74de4ef`):
    - the naming guard passes; `Pkg.precompile` of `environment/all` compiles
      127 packages with no error and no import of a missing name;
    - `test_kernel` 2407 pass, 3 fail, 3 errors; `test_substrate` 85892 pass,
      3 fail, 2 errors, 1 broken; `test_shell` 230 pass: the same counts and the
      same failing tests as `main` (`DocumentMacroTest`, `ReferenceEvalTest`,
      `SplitPaneDragTest`);
    - 25 more test functions of the files that use `MouseClick` (JSON, chart,
      conversation, fault, file system, math, sequence chart, and the umbrella
      tests): the same summaries and the same failing tests as `main`
      (`test_application` 2 errors, `test_mouse_clicks` 13 fail,
      `test_table_selection` 9 fail and 1 error);
    - `test_input_coalescing` 25 pass (`main` 20: the branch has the tests of
      `WindowLeave`);
    - omnet-julia, in a scratch environment on the three worktrees: 82 packages
      precompile with no error; 27 test functions of the files that use
      `MouseClick` give the same summaries as `main`, where
      `test_inspector_disclosure`, `test_playback_mode` and `test_legacy_page`
      fail in the same way;
    - inet-julia: the three changed files parse.
- [x] 2. **The timer and the display event (D22, D24, D42, D43, D45).** The event
  `TimerExpire` and `SetTimerOperation`. The editor holds the deadlines,
  `compute_wait_timeout` counts them, and the loop reads a `TimerExpire` at each
  deadline. After a frame that changed what the display shows, the loop reads the
  event of the display, and it sleeps only after a frame that changed nothing.
  Tests: a reader that answers `SetTimerOperation` gets `TimerExpire` at that
  time; a new deadline replaces the old one; a frame that changes the display is
  followed by the display event, and a frame that changes nothing is not; an idle
  editor still sleeps.

  **The timer is done** on the branch `gesture-type`:
  - `TimerExpire(name, time)` is an event in its own fragment,
    `event/TimerEvent.jl`. `SetTimerOperation(name, time)` sets the timer `name`
    of the editor; the editor keeps the times in `editor.timers`, and
    `compute_wait_timeout` counts the earliest.
  - A timer has a name, so that a timer set again replaces only its own time:
    the gesture tracker, and later a chord or a drag, each set their own timer.
    The plan did not say this; Claude added it for "a new deadline replaces the
    old one" with more than one tracker.
  - `read!` reads a due timer before any device input, as a bare `TimerExpire`,
    because a timer belongs to no window; the earliest goes first and leaves the
    timers. The operation travels up every reader unchanged, inverts to nothing,
    and a history does not record it (`_is_no_edit` of the undo package).
  - Tests: `test_editor_timer`, 28 pass (the wait, the replace, the order of
    due timers, a loop that wakes at a timer, the traits of the operation); the
    undo filter drops a timer; a bare timer passes the whole window scene of a
    shell and answers nothing (`test_shell` 231 pass). `test_kernel` 2435 pass,
    with the same 3 failures and 3 errors as `main`; `test_undo` 111 pass.

  **The display event is done** too, after D45 (Q16):
  - `DisplayUpdate(time)` is an event in its own fragment,
    `event/DisplayEvent.jl`. The contract of `write_to_devices` says that a
    backend which shows windows reports each frame that differs from the one
    before as `WindowInput(window_id, DisplayUpdate)`, and does not block its
    wait while one waits.
  - The SDL backend runs the dirty walk in both modes; a full frame still
    repaints the whole window, because the full mode must not depend on the walk
    to draw right. `_render_window!` answers whether the frame changed, and
    `write_to_devices` queues one update for each window.
  - `FrameStatisticsFeed` flushes each document at most once per
    `flush_interval`; `ReflectionFeed` syncs at most once per `interval`
    (0.25 s), unless a chevron asks, and asks for a frame at the end of an
    interval in which it skipped a sync. Both take a clock `now` for tests.
  - Rebased onto `main` `7b667d83`, where the partial render branch landed; the
    walk helper answers its region of rectangles.
  - Tests, each compared with `main`: `test_kernel` +28, `test_substrate` +9
    (the reflection feed), `test_shell` +2 (a timer and a display update pass the
    window scene with no answer), the frame statistics feed +7, `test_sdl` 773
    pass (+17: a changed frame gives one update in both modes, a frame with no
    change gives none, and a waiting update ends a wait); the export collisions
    pass; the failing tests are the same as on `main`.
  - A count to know: the pass count of the substrate examples moves with what
    else the process holds (the printer walk follows weak links out of the
    document), so a new kernel test before it moves it; alone, the branch
    and `main` give the same count.
- [x] 3. **A gesture follows a route (D12, D28).** An intent with a route can
  carry a gesture. The last reader on the route reads the gesture, with the rest
  of the route as the part. Every widget container and every layout follows a
  route. A domain projection does not have to: its reader gets the gesture with
  the rest of the route and can ignore it. Tests: an enter with a route reaches
  a button inside a composite inside a split pane; a route that ends in a row of
  a list gives the list the rest of the route.

  Done on the branch `gesture-type`, rebased onto `main` `64fa21e2`:
  - The kernel: `read_routed_intent` lets the place read a gesture (an operation
    still stands as the answer). The default four-argument reader walks a route
    into the child that it names, when the IoMap holds children:
    `get_child_iomaps(iomap)` is a new open getter of the projection layer, and
    `read_routed_child` the walk. The kernel answers the getter for
    `ChildrenIoMap` and `ContentIoMap`; the widget package for the scroll pane,
    the transform pane, the context menu, the dialog, the menu item and the
    accordion; the layout package for the grid. So a container needs no code of
    its own for a route. The getter lives in the projection layer, not in the
    sealed IoMap interface, because it serves the readers.
  - The widget package's own walk (`_read_routed_child`, `_RoutingContainerProjection`,
    and the scroll pane reader that `main` added for the file tab) went away; the
    shell keeps its own reader, because its route names a band of the shell.
  - A gesture whose route ends at a container gets no answer, unless the
    container has a reader of its own for it. A routed gesture is not moved into
    the frame of a child: the route alone names the part, and a position that a
    part needs comes in the route as a point step (D11, step 4).
  - Tests: `test_routed_change` (kernel, 19 pass: the child that the route names
    reads the gesture, a leaf gets the rest of the route, an operation stands at
    its place, a gesture for the container itself or for nothing gets no answer,
    a wrapper passes the whole route, a change with no route is read as before);
    `test_routed_gesture` (substrate, 7 pass: a routed enter lights the button
    that it names inside a composite inside a split pane, and no other; a routed
    leave clears it wherever the pointer is; a route to nothing answers
    nothing). The list reads no route until step 7, so the kernel test covers a
    route deeper than a leaf with a probe leaf.
  - Compared with `main`: the kernel, substrate, shell, referenced document,
    application, mouse click and history sweep suites fail the same tests;
    omnet-julia's 27 test functions give the same summaries.
- [ ] 4. **The part at a point (D11).** `map_reference_backward` from a
  `PointReferenceStep` in each projection that ends in graphics. The hit test of
  each one moves into the mapping, and a reader of a click that has the same hit
  test uses the mapping, so each projection keeps one hit test. One commit for
  each package: 4a the graphics leaf and text to graphics; 4b the layouts; 4c the
  widgets; 4d the charts; 4e the screen and the window scene; 4f the projections
  of omnet-julia. Tests: for each projection, a point maps to the expected
  reference, and its click tests still pass.

  - [x] 4a. The graphics leaf and text to graphics. `find_reference_point`
    (graphics package) reads the point that a reference names: a bare
    `PointReferenceStep`, or a reference whose one step is one. The graphics leaf
    maps a point to the element at it and the point inside that element; text to
    graphics maps a point to the caret nearest to it, and the element path of
    the graphics leaf to the caret in that element. The readers of a click and
    of that path read the maps, so each projection keeps one hit test. Tests:
    the graphics leaf (a rect, a text, nothing), text to graphics (a point, a
    one-step reference, the click, the element path, a reference that names
    neither). The substrate, JSON, click, selection, clipboard, probe, dragging,
    gesture log, application, conversation and math suites fail the same tests
    as `main`.
  - [x] 4b. The layouts, and the higher-order projections above them. A layout
    maps a point to the child drawn at it with the hit test of a pointer event
    (`_find_child_point`), and on into the child with the point in its frame; a
    child that maps nothing at its point is itself the part. The stack and the
    constraint layout search from the topmost child, as their readers do; the
    anchored layout names its content and its children. A point could not pass
    four higher-order projections, which mapped nothing back since the first
    port: the chain now maps back through its stages in reverse, the recursive
    projection through its child, the predicate dispatcher through the
    projection that its predicate chooses, and the switcher through its active
    branch. Tests: a vertical layout and the whole chain above it, a point where
    nothing is drawn, a stack, an anchored layout (content and annotation), a
    predicate dispatcher and a switcher. The same suites as in 4a fail the same
    tests as `main`.
  - [x] 4c. The widgets. One hit test, `_find_widget_child_point`, serves the
    routing of a pointer event and the mapping of a point in every container
    that keeps `(x, y, child)` entries: the composite, the split pane, the menu,
    the toolbar, the title pane, the shell, the tooltip, the tabbed pane, the
    card, the menu item and the dialog. The steps from a container to the child
    are found by identity (`search_references`), as a route reaches a child, so a
    child behind a node without an IoMap is found too. The scroll pane and the
    transform pane map through the translation that their readers use (now named
    functions); the accordion maps a header to its item and the open body into
    `items[i].body`. The widgets with parts map to the reference that a click
    selects, through the hit test that the click uses: a list row to its item, a
    table (both forms) to a column header, a row header or a cell, a tree row to
    its node. A leaf widget maps nothing, so its container takes it as the part.
    A text body that the accordion draws itself is no child, so a point on it
    maps to nothing. Tests: `test_widget_point`, 17 pass. The same suites as in
    4a fail the same tests as `main`.
- [ ] 5. **The start over of Tab leaves the hover tracker (D2, §5 of the plan of
  D33).** A small wrapping step does only the start over at the ends, and the
  hover tracker loses its branch for Tab. Tests: the focus traversal tests; Tab
  at the last stop goes to the first, and Shift+Tab goes the other way.
- [ ] 6. **The gesture tracking package (D8, D9, D25, D30, D32).**
  `ProjecturedGestureTracking`, with `GestureTrackingState` and
  `GestureTrackingProjection`: the click with its count, the chord and the dwell
  (steps 2 and 1). The editor no longer owns a recognizer, and the gesture layer
  leaves the kernel. The composition function of the screen package wraps the
  screen, and every host uses it, also those of omnet-julia. The tests of the
  recognizer move to the package. Tests: the moved tests of the recognizer, the
  test of the input of SDL, the application.
- [ ] 7. **The mouse target tracking package (D6, D13, D17, D27, D29).**
  `ProjecturedMouseTargetTracking`, with `MouseTargetTrackingState` and
  `MouseTargetTrackingProjection`. On each move, it maps the point backward (step
  4). It sends a leave and an enter along the path that changes, by route (step
  3), and a `MouseHover` on a move over the same target. `WindowLeave` clears the
  target. The list, the table, the tree and the charts answer the gestures of
  their rows and points, so the two styles of hover become one.
  `WidgetHoverTrackingProjection` goes away. Tests: a row of a popup lights (H1);
  the light follows the pointer to the next row; the leave of the window turns
  it off (H3); a row of a list turns off when the pointer moves onto another
  widget (§3.4); a list that scrolls under a still pointer lights the row that is
  now under it (D41); a light changes the layout of no widget (D44); a live check on the display, with the owner's word for XTest.
- [ ] 8. **The probes go away (D7).** A tooltip is the meaning of a `MouseDwell`
  on the target, and `compute_tooltip` stays; the feed, the probe and
  `PointerRest` of the tooltip package go away. The inspector reads the target.
  The context menu is the meaning of a right click at the part. Tests: a tooltip
  opens after a dwell in any window, not only the first; the inspector shows the
  part under the pointer; the context menu opens for the part.
- [ ] 9. **The drag tracking package (D14, D19, D20, D21, D26, D29).**
  `ProjecturedDragTracking`, with `DragTrackingState` and
  `DragTrackingProjection`. A drag starts after a small move; the reader answers
  a drag start operation that names the target; then `DragMove`, `DragHover`
  (the part under the pointer, by step 4) and `DragEnd`. While a drag is on, the
  click is swallowed and the target tracker is quiet. The five drags move to it:
  the reorder of the dragging package (and its probe goes away), the splitter,
  the tab of a pane, the slider, the pan and the zoom of the chart. Their own
  drag state goes away. Tests: each drag; a short press on a tab still selects
  it; a drag over a button does not light it; a drag that leaves the window
  ends in one defined way.
- [ ] 10. **The rules and the documents (D16, D40).** `PAR-NO-NEW-SYNTHETIC-EVENT`
  is written again; the rules of D40 and D44 join the invariants; the concepts (event,
  gesture, tracking projection) go into the design documents; the documents of
  the kernel, the widgets, the screen, the tooltip, the dragging and the
  backends change. This step takes step 4 of the plan
  [every-window-tracks-the-pointer-and-says-when-it-leaves.md](every-window-tracks-the-pointer-and-says-when-it-leaves.md).
- [ ] 11. **The check against `main`, and the move of this plan and of the plan of
  `WindowLeave` to `plan/done/`.**

Not in the steps: the web client sends no motion while no button is held (study
§4), so the browser has no hover. That needs a decision of its own.

The files of the kernel that the refactor changes are unsealed, and they stay
unsealed after the work (D34).
