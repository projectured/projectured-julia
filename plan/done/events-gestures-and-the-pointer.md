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
  `gesture/GestureRecognizer.jl`. (Refined by D51: the mechanism of the
  recognition is in the kernel gesture layer, and a projection uses it.)
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
  - The gesture types stay in the event layer of the kernel. (Changed by D49:
    they are in the gesture layer.)
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
  [tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md](../pending/tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md), split from this plan on 2026-09-26 with the decisions D35 to D39.
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
- **D46.** A gesture that an event completes reaches the content after the
  operation of that event, as it does today. The tracker keeps the waiting
  gestures in its state document and answers a `SetTimerOperation` at the time
  of the event (step 2). The editor reads a due timer before new input, and the
  tracker then gives the next waiting gesture to the content. A chord that
  breaks gives out its kept keys the same way, one in each read. (Q18, owner
  2026-09-27.)
- **D47.** The state document of the gesture tracker wraps the screen, as D27
  says: the document of the editor is `GestureTrackingState(screen)`. Code that
  needs the screen finds it with `get_wrapped_document`, and the screen package
  has the path from the root to the screen, so every reference from the root
  gets the steps of the wrappers. (Q19, owner 2026-09-27.)
- **D48.** The names: `make_gesture_tracking_document(document)` and
  `make_gesture_tracking_projection(projection)` in the tracking package, the
  pattern of the dragging wrappers, and `make_tracking_screen(document,
  projection)` in the screen package, the function of D15, with a keyword for
  each tracker (`gesture_tracking = true` in step 6). `make_editor`, the gallery
  and every host that makes an editor call it. (Q20, owner 2026-09-27.)
- **D49.** The kernel has an event layer and, right above it, a gesture layer,
  because they hold different things. The event layer holds the records of what
  the hardware or the system did, with no meaning: the events, `ModifierKeys`,
  `MouseButtons`, and the pattern of one event, which names no gesture. The
  gesture layer holds `abstract type Gesture` and the standard gesture types,
  also the ones that the trackers make (`MouseClick`, `KeyChord`, `MouseDwell`,
  `MouseEnter`, `MouseLeave`, and the hover and drag gestures when they come),
  the recognition protocol of D51 and the case macro of D50. The binding layer
  stays above the intent layer, because the meaning of a gesture is an
  operation. The layers follow the ladder of the naming rules: Event → Gesture →
  Intent → Operation. This changes D31, which kept the gesture types in the
  event layer. (Q21, owner 2026-09-27.)
- **D50.** One case macro for the readers, `@gesture_case`, in the gesture
  layer. It matches events and gestures, because a reader receives both (D23),
  and an event is the gesture of one event. It takes the place of
  `@event_case`. (Q22, owner 2026-09-27.)
- **D51.** The recognition machinery is in the kernel gesture layer, open to new
  gestures, and a projection uses it. Each kind of gesture is one pure
  recognition: `abstract type GestureRecognition`, a function that makes its
  first state, and `recognize(recognition, state, input, window)`, which answers
  a `RecognitionStep` with the next state, the gestures that the input
  completes, a deadline or `nothing`, and whether the input is held (a key of a
  chord, a click during a drag). A timer is one more input: at the deadline, the
  recognition reads the `TimerExpire`. A recognition answers a deadline and not
  an operation, so the gesture layer needs nothing above it. The click, the
  chord and the dwell are standard recognitions of the kernel.
  `GestureTrackingProjection(; inner, recognitions)` runs the recognitions in
  order, so the gestures of one are inputs of the next; it keeps the state of
  each recognition in its wrapper document (D10), turns a deadline into a timer,
  and gives the gestures to the content after the event (D46). A package adds a
  gesture with a gesture type, a recognition and its methods, and a host adds
  the recognition to the list, as a package extends the case macro. This
  refines D8: the editor recognizes nothing, a projection recognizes, and the
  mechanism that it uses is in the kernel. The names are Claude's proposal, and
  the naming guard checks them when they are written. (Q23, owner 2026-09-27.)
- **D52.** The mouse target tracker and the drag tracker do more than recognize:
  they need the part under the point, and they give their gestures by route to
  that part (D12, D13). Whether their state machines use the recognition
  protocol with a view context is decided at step 8, when the first of them is
  built. Their delivery by route stays in their own projections. (Q24, owner
  2026-09-27.)
- **D53.** `WindowInput` is generic over its input, so it stays in the event
  layer and names no gesture. (Owner 2026-09-27.)
- **D54.** The whole pattern language is in the gesture layer: the pattern of
  one input, its constructors, its parser, its descriptions and
  `@gesture_case`. The event layer holds only records: the events,
  `ModifierKeys`, `MouseButtons`, `WindowInput`, and `get_event_time` and
  `get_modifier_keys` for events, which the gesture layer extends for gestures.
  The one matcher of D50 matches both kinds, so it belongs where both kinds are
  known, and it needs no extension point. This refines D49, whose event layer
  kept the pattern of one event. (Q25, owner 2026-09-27.)
- **D55.** The names of the pattern language follow D50, because an event is
  the gesture of one event: `EventPattern` becomes `GesturePattern`,
  `matches_event_pattern` becomes `matches_gesture_pattern`,
  `describe_event_pattern` becomes `describe_gesture_pattern`, and the names of
  the parser change the same way. `KeyDownPattern`, `MouseClickPattern` and the
  other constructors keep their names. (Q26, owner 2026-09-27.)
- **D56.** The gesture layer is layer 8, after the device layer. The device
  layer and the gesture layer depend only on the event layer, so their order is
  free, and in this place the later layers keep their numbers. (Claude,
  2026-09-27, with no objection from the owner.)
- **D57.** The mouse target tracker is a projection of its own, with its own
  logic, and not a user of the recognition protocol: its work is the view (the
  part at a point, by `map_reference_backward`) and the delivery of each
  gesture by route to its part, and the protocol has neither. The drag tracker
  decides for itself at step 10. (Q27, answers D52, owner 2026-09-27.)
- **D58.** An enter goes to each part of the new path that is not on the old
  one, the outer parts first; a leave goes to each part of the old path that is
  not on the new one, the inner parts first (D13). A part is a prefix of the
  path that names a document. A point step at the end of a path is not a part of
  the target, so a plot is the same target at every point of it. A `MouseHover`
  goes to the deepest part on each move over the same target, with the
  position. (Q28, and Q4 of the plan of the domain part, owner 2026-09-27.)
- **D59.** The crossings that one input makes wait in the state of the tracker
  and reach the content one in each read, after the operation of the input, as
  D46 says. The loop reads until the input runs out and prints once, so they
  cost no frame. (Q29, owner 2026-09-27.)
- **D60.** The `hover` flag of the gallery and of the campaign window chooses
  the target tracker, through the keyword `mouse_target_tracking` of
  `make_tracking_screen`. `FocusCyclingProjection` stays in every window wrap
  whatever the flag (D2). (Q30, owner 2026-09-27.)
- **D61 (withdrawn).** The live check of step 8 moves the real pointer with
  XTest. (Owner 2026-09-27.) On this desktop XTest asks to allow "remote
  interaction", and the owner does not allow it (owner 2026-09-27: "I don't want
  to allow remote interaction"). The way of the live check is open.
- **D63.** A tooltip is the meaning of a dwell at the part under the pointer,
  and the part's own gesture table gives it: a type binds `MouseDwellPattern()`
  to an `OpenTooltipOperation` in its `@gestures` table, with a description. So
  the command palette, the gesture help and an agent see it and can run it, and
  the meaning belongs to the thing. The target tracker sends the dwell to the
  target by route, as it sends the crossings. The tooltip package owns the
  operation and the pattern helpers, and a domain that has a tooltip depends on
  it; `compute_tooltip` is no longer the interface. (Q32, owner 2026-09-28.)
  The ways that were weighed and dropped: a tooltip projection at the screen
  that read the target tracker's state (a projection must not read the state
  of another, D68); a tooltip projection that read the route of the dwell (a
  central component, which the projections on the path can not control); and a
  requested intent on the carrier, which a wrapper writes and each part answers
  by dispatch (more mechanism, and the palette can run only bindings).
- **D64.** The outward search is driven by the answer. At each enclosing
  document on the route, deepest first: when the deeper part answered nothing,
  the document reads the gesture with its own table, and the nearest that
  answers wins; when the deeper answer is an operation that collects (a trait
  of the operation type, which its package owns, such as `OpenTooltipOperation`),
  the document also reads the gesture, and an answer of the same kind is joined
  by the package's join (it adds a layer); any other answer stops the search, as
  today. So the tooltip holds every part that has something to say, nearest
  first (way c of Q33, collected at once), and the window first shows the
  nearest (way a). The walk asks the documents' tables (`read_gesture`), not the
  projections' readers; a projection changes an answer on the way up. It runs
  in `read_routed_child` for each container's own stretch of the route, and in
  the shared click-routing helpers for a gesture that goes by position. A
  gesture needs no mode of its own. (Q33, owner 2026-09-28: "I think the mode
  depends on the operation"; an earlier proposal of a mode for each gesture,
  `:none`, `:first` and `:collect`, was dropped.)
- **D65.** A tooltip is drawn by the natural projection, so it can be any
  document that the natural projection draws, for example markdown, and not
  only text. (Owner 2026-09-28.)
- **D66.** A small tooltip wrapper keeps the life of the window, with its own
  state only: it sees the `OpenTooltipOperation` go up and opens the window, and
  it sees the inputs come down. It closes the window on a move of the pointer off
  the described part, on Escape (which it takes, so the first Escape closes only
  the tooltip), on a press, a scroll and the leave of the window; every other key
  passes on and leaves it open, so a person can type while it shows. (Q34, owner
  2026-09-28; Claude read "the closers" as the move rule that Claude suggested, a
  move off the part, and not a move of 4 px.)
- **D67.** While a tooltip is open, F2 shows one more of the collected layers,
  outward, and Shift+F2 one fewer; nothing is sent down again, so there is no
  synthetic event. The wrapper declares both keys, so the gesture help lists
  them. F2 also renames a tab (`PaneGestures.jl`); while a tooltip is open the
  tooltip takes F2, so the rename waits until it closes. (Owner 2026-09-28: "I
  don't see a problem there".)
- **D68.** No central component gives a behavior that the projections on the
  path can give. A central piece exists only where no local one can do the
  work, and it says why. The projections on the path must be able to transform
  and control what a gesture means: a meaning is an operation that bubbles up
  through them. A meaning is a gesture binding, so the palette, the help and an
  agent can see and run it. This extends D40, and step 11 writes it into the
  rules. (Owner 2026-09-28: "there should be no central component which
  provides global behavior unless there's no other way.")
- **D69.** The context menu works the same way: a type binds
  `MouseClickPattern(:right)` to an `OpenContextMenuOperation`, a
  `WidgetContextMenu` has its own binding, and the nearest part wins by the
  outward search. A right press that selects a row and opens a menu: the row
  answers the selection, and the view that knows what the row shows adds that
  thing's menu to the answer on the way up. (Owner 2026-09-28, "this could also
  be done for the context menu"; the details are open in step 9.)
- **D70.** The context menu collects too, as the tooltip does (D64), and while
  it is open F2 shows the next outer layer and Shift+F2 one fewer (D67). (Owner
  2026-09-28.)
- **D71.** In a tooltip and in a context menu, each extended layer starts with a
  separator and a mark that names its source, `get_document_title` of the part
  that answered; the layers carry that part's path. While only the first layer
  shows it has no mark; once F2 adds a layer, every layer has its mark. (Owner
  2026-09-28; the rule for the first layer is Claude's suggestion, for the owner
  to confirm.)
- **D72.** A small wrapper keeps the tooltip window, the one central piece,
  because a window belongs to the screen and no part can close its own tooltip
  when the pointer goes to another part (D68). It sits at the screen outside the
  target tracker, gesture(tooltip(target(screen))), with a wrapper document of
  its own: whether a tooltip is open and its window id, the collected layers with
  their source paths, and how many show. It passes the dwell down, takes its own
  `OpenTooltipOperation` out of the answer, and opens the window at the point
  that the readers moved up into screen coordinates (`map_operation_position`).
  While a tooltip is open it maps each move's point backward (D11) and closes the
  tooltip when the path leaves the source of the first layer; it closes it on
  Escape (taken), a press, a scroll and the leave of the window; F2 and Shift+F2
  change how many layers show and update the window in place. The context menu
  has a wrapper of its own, because the two are alike but not the same (a menu
  closes on a choice, a click outside it or Escape); a small shared helper holds
  the layers and the F2 logic. (Owner 2026-09-28.)
- **D73.** A tooltip or a menu runs without a pointer too, from the command
  palette or from an agent: its binding works with the event and without it (the
  palette gives `nothing`), so it keeps its name. The operation carries the
  layers, the source path of each, and a point that may be missing. From the
  palette the answer goes up the same path to the wrapper, which opens the window
  beside the pointer when there is a point, and else at the forward image of the
  first layer's source, in screen coordinates. A named run fires one binding on
  one document, so it has one layer; the closers of D66 hold, so a move of the
  mouse closes it. The context menu works the same way. (Owner 2026-09-28.)
- **D74.** A right click never moves the selection; only a left click does.
  The light already shows the part under the pointer, and each layer of a menu
  carries the source path of its part (D71), so its items act on that part
  without the selection. So no selection is joined with a menu, and the outward
  search of D64 has no exception. This drops D10 of
  [a-press-on-a-menu-name-opens-its-menu.md](../done/a-press-on-a-menu-name-opens-its-menu.md)
  (a right press on a row selected it and opened its menu). (Owner 2026-09-28:
  "the light already shows what's under the cursor, I think there's no need to
  merge selection with context menu operation".) With it, as Claude proposed
  and the owner did not object: a `WidgetContextMenu` answers with the
  collecting menu operation of D70 instead of a raw `OpenPopupOperation`, so it
  gives the nearest layer; and the window's own menu, today
  `compute_context_menu(shell)`, becomes the shell's right-click binding, the
  outermost layer, so F2 always reaches it. The text view already answers only
  a left press.
- **D75.** The hover inspector goes away as a whole: `HoverProbeProjection`,
  the gallery's `inspector` option and `_multi_window_projection_inspector`,
  `test_hover_probe` and `test_hover_probe_pipeline`, and the text about it in
  the documents. The rest of the inspector package stays: the shell's Selection
  tool (`SelectionInspector`) and the `ReferenceInspector` document, which are no
  probes. (Owner 2026-09-28: "we can remove the inspector feature as a whole";
  Claude read it as the hover inspector, for the owner to confirm.)
- **D76.** A route is fixed in advance only to return an operation from one
  place. "The predefined route is only for the case when the operation is to be
  returned from that specific projection. It's enforcing that because the
  function called by the assistant is a verb which needs to return the operation
  from that place. In all other cases the route is not yet decided and should
  follow the normal routing based on position for mouse events and gestures. For
  keyboard gestures each projection decides, but they usually take the selection
  path. But again this the composition, there should be no global component to
  decide the route. [...] Nothing is decided globally which can be done
  locally." (Owner 2026-09-28.) Written as `PAR-NO-GLOBAL-ROUTING` and
  `PAR-DECIDE-LOCALLY` in
  [architecture-invariants.md](../../documentation/rule/architecture-invariants.md).
  It supersedes the part of D63 that made the target tracker send the dwell to
  its target by route, and Claude's proposal to route the right click to the
  lit part (way (a) of the question of step 9d), which the owner rejected. The
  consequences are in step 9 and in Q35.
- **D62.** A crossing reaches a widget that a view makes by its route (Q31,
  way A). A routed gesture goes forward through the stages of a chain as far as
  the forward maps answer; the deepest stage reads it first, and an earlier
  stage reads it when the later answers nothing. A routed operation keeps to
  the stages that show the place as the same document. The prefixes of the
  path inside a projection step are parts too, and a list, a table or a tree
  turns its light off on the leave of the lit row. (Owner 2026-09-27, "let's
  try A".)

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
  fills it, and [key-chords-from-bindings.md](../pending/key-chords-from-bindings.md) is
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
   projection; the tracking projections make the gestures (D9), with the
   recognitions of the kernel's new gesture layer (D49, D51).
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

- **Q17 (answered 2026-09-27: the introduced reference now, the domain part
  later in [a-view-names-the-domain-part-under-a-point.md](../pending/a-view-names-the-domain-part-under-a-point.md)).
  The part at a point inside a view that maps nothing back (found in step 4f).** A view prints a domain document as widgets, and its
  `map_reference_backward` answers `nothing` on purpose, with comments such as
  "no caret into a log (v1)". A point on a button of such a view stops there,
  so the part under the pointer is the whole view. With the mouse target
  tracker of step 8, an enter and a leave then reach the view and not the
  button, so the button does not light. Today the hover tracker finds the
  button by its position, so nothing shows the fault yet. Three ways:
  - **Claude's recommendation: an introduced reference.** The view maps a
    widget part back to `proj(view projection, ^(widget path))`, the kernel
    default that the file explorer already uses. Forward, the view maps only
    that form back to the widget path, and still maps nothing else, so no
    caret goes into the view. It needs no new mechanism, only one small shared
    function for the forward half, and two lines in each view.
  - **A domain part.** The view maps a widget part to the domain part that it
    shows (a log line, a module, a result row), and chrome to an introduced
    reference. This is the most exact answer, but each of the 45 views needs
    its own knowledge. It can come later, view by view, in a plan of its own.
  - **No change.** The whole view is the part, and the buttons of a view do
    not light on hover after step 8.

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

- **Q31 (answered by D62, found in step 8b, 2026-09-27). A crossing does not reach a
  widget that a view makes.** A point on a widget inside a view maps back to a
  domain part, or to an introduced reference of the view. The widget is then
  no part of the target, and a crossing stops at the view:
  - The Files navigator (`FileSystemToWidgetTree`) maps a row back to its file,
    through a `ProjectionReferenceStep` of the folder view. The chain routes a
    change only while each stage shows the place as the same document, so the
    hover stops at the view that shows a file as a row.
  - The campaign's Run button maps back to `SimulationFilter` and the
    introduced reference of `SimulationFilterToWidgetForm`. A projection step
    evaluates to its output path, not to the widget, so the button is no part
    (it gets no enter), and the same check stops the hover at the view.
  - So no widget inside a view lights: the campaign, the IDE and the
    application windows. A widget that no view makes (a shell, a list in a
    layout, a popup menu) lights. The old tracker sent crossings by position in
    the widget tree, and it had no such gap.
  - The ways, for the owner:
    - A. A crossing goes forward through every stage whose forward map answers,
      and a row widget turns its light off on the leave of the node that holds
      the lit row. Plus: an introduced reference of a stage passes the check of
      the chain, and a part can be an introduced widget.
    - B. Each view reads the crossings of its parts and writes the light of its
      own widgets.
    - C. Two targets: the widget under the pointer for the light, and the part
      of the document for the meaning (tooltip, context menu, agent), as a
      toolkit keeps them. The widget target needs a backward mapping that stops
      at the widget layer.


- **Q35 (answered 2026-09-28: the leave keeps its route). The crossings under D76.** Step 8 makes the target tracker send
  `MouseEnter`, `MouseLeave` and `MouseHover` to the parts by route (D62, way A
  of Q31). Under D76 a hover and an enter can travel by position, from the point
  of the move. A leave can not simply do so: the pointer is no longer over the
  part it left, so the point of the move does not reach that part. The ways that
  Claude sees: keep the crossings routed as the one exception, because the
  tracker only tells each part what changed and chooses no part for a click;
  send a leave by position at the point that the pointer left; or let each
  container keep which of its children the pointer is over and send the
  crossings to its own children, which §3.4 described as the state before step
  8. The owner: "if it can only reasonably done by a global component then
  that's what needs to be done. So the leave can be routes by path, it's fine
  because that's exactly what needs to be done." Claude's reading, for the owner
  to correct: the hover and the enter travel by position, and a part knows from
  its own state (`hovered`) that the pointer entered it; only the leave is routed
  by the target tracker, which keeps the path that the pointer was over.

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
  - The rule `PAR-NO-NEW-SYNTHETIC-EVENT` still names `SyntheticEvent`. Step 11
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
    nothing). The list reads no route until step 8, so the kernel test covers a
    route deeper than a leaf with a probe leaf.
  - Compared with `main`: the kernel, substrate, shell, referenced document,
    application, mouse click and history sweep suites fail the same tests;
    omnet-julia's 27 test functions give the same summaries.
- [x] 4. **The part at a point (D11).** `map_reference_backward` from a
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
  - [x] 4d. The charts. Each maps a point with the hit tests of its reader of a
    click, in that order, so a point maps to what a click there selects. The
    chart: a legend item to its series, the rest of the legend to the legend, a
    part of the frame, a data point, a series line; the sequence chart: an event,
    an arrow, a band or a lane of the body, and a lane of the label strip. Any
    other point of the plot area or of the body maps to the plot at the point,
    `ConcreteReference(PointReferenceStep(x, y))`, which the cursor readout
    reads. A point past the chart's canvas maps to nothing: a click never arrives
    there, but the frame tests would name the title. The forward mapping still
    declines. The move reader of the sequence chart and its mapping share
    `_find_sequence_chart_part`. Tests: `test_chart` 350 pass and
    `test_sequencechart` 283 pass (`main` 345 and 279); the mapping equals the
    path of a click, and the chain carries it on to the chart.
  - [x] 4e. The screen and the window scene need no new code: the screen peels
    `windows[i].content`, the window managing projection and the scene pass the
    rest on, and the projection of the window maps the point in the window's
    frame. So a point of a window is `windows[i].content` and a point step, and
    a popup maps its points as the first window does (the case of H1). A fact
    found: in a shell, an auto-sized widget fills the offered area, so a point
    anywhere in it maps to that widget, and a click there reaches the same
    widget. Test: `test_shell` 236 pass (a list row and the list itself in the
    first window, a menu item in a popup, nothing past the menu).
  - [x] 4f. The projections outside the substrate. A walk of the real
    application window found one stage that stopped every point: the command
    palette decorator. It now passes a point to its content in the same frame
    while the palette is closed, and maps nothing while it is open, because the
    open palette owns every event. After it, "File" and "Help" map to their menu
    items, an explorer entry to its folder and a `ProjectionReferenceStep`, and a
    word of a JSON tab to its text position. A JSON bracket maps to nothing: it
    is chrome, with no part in the domain. Test: `test_command_palette_decorator`
    66 pass.

    A search for backward mappings that always answer `nothing` found 45 in
    omnet-julia and 54 in projectured-julia. Most are correct: a leaf widget
    maps nothing, and its container takes it as the part; a text-to-string
    stage ends in no graphics. Two were gaps of the kind of 4b and 4c, and they
    are fixed. The graph layout maps a point to the vertex whose box holds it,
    with the hit test of a click (`_find_vertex_at`), and on into the content
    of the vertex; a point in the box on no part of the content is the vertex.
    The configuring projection maps a reference into its document side back
    through the inner projection; its control is a view, below. Tests:
    `test_graph` 377 pass, `test_projection_configuring` 2 more pass.

    The views that print a domain document as widgets mapped nothing back on
    purpose ("no caret into the view"), so a point stopped at them (Q17). The
    owner chose the introduced reference now, and a plan of its own for the
    domain part: [a-view-names-the-domain-part-under-a-point.md](../pending/a-view-names-the-domain-part-under-a-point.md).
    `find_introduced_path(projection, reference)` (kernel, beside
    `make_introduced_reference`) gives the output path of an introduced
    reference of `projection`, and `nothing` for any other. Each view now maps
    back by the kernel default, which names a widget part by an introduced
    reference, and maps forward only such a reference, so still no caret goes
    in. 5 views in projectured-julia work so (the file chooser, the cell table,
    the object form, the query result, the control of a configuring
    projection), and 41 in omnet-julia. Four stay as they are:
    `HanoiToGraphics`, `ModuleAppearanceToGraphicsCanvas` and
    `TimelineStripToGraphics` print graphics directly, and
    `SimulationResultFrameToWidgetTable` sends a selection that is not a row
    pick to the kernel default reader, which would put a caret into the view.

    A fact found: 32 view printers of omnet-julia built their IO map with no
    projection (`SimpleIoMap(nothing, view, body)`). In projectured-julia that
    form means a pass-through, whose output is its input. The type dispatcher
    maps a reference through `iomap.projection`, so a point on such a view
    failed there. Each of these IO maps now names its projection.

    Tests: `test_introduced_path` 6 pass; `test_cell_table_to_widget_table` 4
    more; `test_projection_configuring` 3 (the control maps to the control);
    in omnet-julia, a point on each button of the session bar names that
    button (8 pass). `test_application` fails the same 2 tests as `main`. The
    64 test functions of omnet-julia that touch the views and the pointer give
    the same summaries as on `main` (the 3 known failures), plus the new test.
- [x] 5. **The start over of Tab leaves the hover tracker (D2, §5 of the plan of
  D33).** A small wrapping step does only the start over at the ends, and the
  hover tracker loses its branch for Tab. Tests: the focus traversal tests; Tab
  at the last stop goes to the first, and Shift+Tab goes the other way.

  Done on the branch `gesture-type`:

  - `FocusCyclingProjection` (`source/focus/FocusCycling.jl`, beside
    `SelectionWalkingProjection`, the same shape) answers a Tab that nothing
    inside answered with the first stop of its input, and a Shift+Tab with the
    last stop. Its reader is the branch of the hover tracker, moved without a
    change, so it still walks the whole input with `get_first_focusable_path`.
    The other way, to give the declined Tab back to the parts with no selection
    (§5 of the plan of D33), waits with that plan.
  - The hover tracker passes every event other than a move straight through.
  - The new wrapper is just inside the hover tracker in each of the 15
    compositions that held the hover tracker: the window wrap, the examples,
    the gallery; in omnet-julia the Qtenv window, the campaign window, the
    embed, the examples, the watch demo and the program builder; the demo of
    inet-julia. So Tab starts over as before. The program builder and the
    campaign window reach it as `ProjecturedWidget.FocusModule`, because they
    load `ProjecturedWidget` and not `ProjecturedFocus`.
  - A fact for step 8: the gallery and the campaign window add the hover
    tracker only with their `hover` flag, so the start over still comes and
    goes with that flag (D2 says they are unrelated). Step 8 changes these
    compositions, and must keep the start over when it removes the hover
    tracker.
  - The focus, widget and shell guides name the new wrapper.

  Tests: a new test shows that the hover tracker alone passes Tab through at
  the last stop and the new wrapper starts over, in both directions; the
  composite and layout Tab tests pass with the new wrapper; the window wrap
  tests check the new order. `test_widget_button_behavior`,
  `test_selection_walking`, `test_pane_gestures`, `test_tool_views`,
  `test_assistant_composer_panel`, `test_widget_text_editing`,
  `test_gallery_wrappers` and `test_shell` (237) pass; `test_application`
  fails the same 2 tests as `main`; the naming guard passes. In omnet-julia the
  64 test functions of step 4f and `test_qtenv` give the same summaries as on
  `main` (one test of the demo catalog walked the IO map to a fixed depth, and
  now walks one level more); the fold of the `:hover` wrapper builds the hover
  tracker over the new wrapper. In inet-julia, `test/presentation/demo.jl`
  passes 219, as on `main`, in a scratch environment on the three worktrees.

- [x] 6. **The gesture tracking package (D8, D9, D25, D30, D32).**
  `ProjecturedGestureTracking`, with `GestureTrackingState` and
  `GestureTrackingProjection`: the click with its count, the chord and the dwell
  (steps 2 and 1). The editor no longer owns a recognizer, and the gesture layer
  leaves the kernel. The composition function of the screen package wraps the
  screen, and every host uses it, also those of omnet-julia. The tests of the
  recognizer move to the package. Tests: the moved tests of the recognizer, the
  test of the input of SDL, the application.

  Done on the branch `gesture-type`, with the decisions D46 to D48:

  - [x] 6a. `MouseDwell(x, y, modifiers, time)`, a gesture of the kernel event
    layer, with `MouseDwellPattern`.
  - [x] 6b. `ProjecturedGestureTracking` (`source/gesturetracking/`), a
    substrate package that depends only on the kernel. `GestureTrackingState`
    wraps the content and keeps `presses`, `last_click`, `chord_keys`, `waiting`
    and `motion`, each an immutable value that a view state operation replaces.
    `GestureTrackingProjection` prints the content through `inner` (not through
    the recursion, so the screen stays the root of its own world), gives every
    event to the content and adds the `content` step to the answer, and follows
    a route through `get_child_iomaps` and `read_routed_child`. The click and the
    kept keys of a broken chord wait in `waiting`; the timer
    `:gesture_tracking_waiting` at the time of the event brings them in, one in
    each read. The dwell timer is `:gesture_tracking_dwell`. A dwell follows the
    rules of the tooltip probe for the mouse (a move with no button starts the
    wait; a move with a button, a down, a click, a scroll and `WindowLeave` stop
    it; one motion, one dwell), but **a key does not stop it**: a dwell is no
    motion of the mouse (D4), and a write of the state on a key would make the
    answer to every key an operation, which hides Escape and the zoom keys from
    the editor. Step 9 decides whether a key closes a tooltip. With a chord
    table, a kept or a broken chord writes the state, so Escape and the zoom keys
    can not follow a kept key; no running editor has a chord table.
  - [x] 6c. The code that reads the root of the editor as the screen finds it
    with `get_wrapped_document`: the kernel opens the native windows of the
    screen (`make_editor`, `play_live!`), `get_window_tree` finds the tree, and
    the tooltip feed reads the first window. The code that searches from the
    root works unchanged, except that a pane search did not step from a wrapper
    into a screen: `_can_hold_pane` now counts a document with `windows`.
  - [x] 6d. The kernel has no gesture layer: `source/kernel/gesture/` is gone,
    the editor has no `recognizer`, and `read!` gives each input of the backend,
    or a due timer, to the projection; the kernel has twenty-two layers. The
    screen package depends on the tracking package and has
    `make_tracking_screen`; its `make_editor` and the gallery
    (`_make_window_scene_editor`, behind `make_example_editor` and `run_example`)
    use it, so every host of the three repositories that opens a window gets
    the tracker. `run_frame!` reads the waiting click in the same frame as the
    release. The SDL test keeps its check of the times that SDL stamps.
  - Not changed: the precompile workloads and the warm-ups
    (`source/repl/record/driver.jl`, `Application.jl`, `FileEditor.jl`, the
    workloads of omnet-julia and inet-julia) drive `read_intent` with events
    that they build, never through `read!`, so they never used the recognizer.
    They do not compose the tracker, so the first press of a new session
    compiles its reader. Adding it to them, and a timing check, waits for the
    owner.
  - The guides describe the kernel of twenty-two layers, the read loop with no
    recognizer, the tracking projection, and the root of the editor under the
    state; `SEALING.md` has no gesture layer, and its later layers moved down.

  Tests: `test_gesture_tracking` 39 pass; the new `test_tracking_screen` presses
  a button through a real editor and a headless backend, and it clicks once with
  the tracker and never without it; `test_shell`, `test_input_coalescing`,
  `test_referenced_document_editor`, `test_history_sweep`, the layering guards
  and the naming guard pass; `test_kernel`, `test_substrate`,
  `test_mouse_clicks` and `test_application` fail the same tests as `main`
  (the application test that makes its editor with `make_editor` now finds the
  screen under the state). In omnet-julia the 64 test functions and
  `test_qtenv` give the same summaries as on `main`; omnet-julia and inet-julia
  need no change, because their windows open through the screen's
  `make_editor` and the gallery.
- [x] 7. **The gesture layer of the kernel (D49 to D56).** Added with the
  owner's agreement on 2026-09-27, before the next tracker, so that the next
  trackers are built on it. Two parts, each with its commits:
  - [x] 7a. The layer, the move and the renames of D54 and D55, with no change
    of behavior: the suites give the same results as before the move.
    `source/kernel/gesture/` holds `GestureModule` in five fragments
    (`GestureInterface.jl`, `MouseGesture.jl`, `KeyboardGesture.jl`,
    `GesturePattern.jl`, moved from the event layer, and later the
    recognitions). `WindowInput{E}` is generic. The rename tool renamed the
    code, and a text pass renamed the prose outside the plans. A script added
    `using ..GestureModule` to the 26 modules that use a moved name, split the
    import lists and added the alias `GestureModule` to the packages. Facts
    found on the way:
    - An import list across two lines lost its second line in the split
      (5 places), and one moved name on a second line was missed (the video
      package): Julia only warns about such an import, so a name that a method
      body reads is found only at run time. The global name check of
      omnet-julia (`test/globals.jl`, run over the 120 packages of
      projectured-julia too) found it; it finds the same 9 older names on the
      branch and on the commit before, and one older name in omnet-julia
      (`OmnetLegacySimulator.omnetpp`).
    - The generated files `asset/precompile/PrecompileStatements.jl` and
      `WorkloadStatements.jl` name module paths of the time they were recorded;
      they stay as they are, and the statements that name a moved type do
      nothing until the files are recorded again.
    - The tests of the event module split: `EventModuleTest.jl` tests the
      events, and `GestureModuleTest.jl` and `GestureCaseTest.jl` (moved) test
      the gesture layer.
    Checks, against a baseline worktree at the commit before: the same results
    in the kernel, substrate, shell, JSON, math, conversation, chart, sequence
    chart, file system, graph, application, mouse click, click round trip,
    gesture log, hover probe, dragging, table, text, construct, type-in,
    assistant, evaluator, file tab, inspector, palette, gesture help and SDL
    input suites; the naming guard and the layering guards pass; the 64 test
    functions of omnet-julia and `test_qtenv` as before; the demo of inet-julia
    219.
  - [x] 7b. The recognition protocol, the standard recognitions, and the
    projection that runs them. `GestureRecognition.jl`, `ClickRecognition.jl`,
    `ChordRecognition.jl` and `DwellRecognition.jl` in the gesture layer; the
    standard list is the chord, the click, the dwell. `GestureTrackingState`
    keeps `states` (one for each recognition, made on the first read) and
    `waiting`. The projection runs the list for each input; the inputs that a
    recognition gives run through the recognitions after it; the content reads
    the input, or, when a recognition holds it, the first input given; the rest
    waits for the timer `:gesture_tracking_waiting`. The timer of a recognition
    is `:gesture_tracking_<index>` and goes to it alone. The states are written
    only when they change. `make_tracking_screen` takes `recognitions`.
    Tests: each standard recognition alone (28 pass); the projection (47 pass),
    with the order of the recognitions, a recognition that holds the click, and
    a long press that a test package adds, which its reader then receives; the
    tracking screen through a real editor; the kernel layering guard, the
    naming guard and the global name check (the same 9 older names). The
    kernel, substrate, shell and application suites fail the same tests as
    before the step; the 64 test functions of omnet-julia and `test_qtenv` as
    before; the demo of inet-julia 219.
  - The guides describe the twenty-three layers with the gesture layer, the
    event layer of records, the pattern language and the recognitions, and the
    tracking package that runs them.

  The content of the step:
  - A kernel layer `gesture/`, right above `event/`, holds `Gesture`, the
    standard gesture types and their patterns, `@gesture_case`, and the
    recognition protocol with the recognitions of the click, the chord and the
    dwell, which move out of the package of step 6.
  - The event layer keeps the events, `ModifierKeys`, `MouseButtons`, the
    pattern of one event, and `WindowInput`, generic over its input.
  - `@gesture_case` takes the place of `@event_case` in the three repositories,
    with the rename tool.
  - `GestureTrackingProjection(; inner, recognitions)` runs the recognitions in
    order, and `GestureTrackingState` keeps one state for each recognition and
    the inputs that wait. `make_tracking_screen` gives the standard list.
  - Tests: each standard recognition alone, inputs in and gestures out; the
    projection (the order of the recognitions, a held input, a deadline that
    becomes a timer, the delivery after the event); a recognition of a test
    package, for example a long press, that a host adds and that its reader
    then receives, which proves the extension; the tracking screen test; the
    kernel layering guard; no `@event_case` is left.
- [x] 8. **The mouse target tracking package (D6, D13, D17, D27, D29, D52, D57 to D62).**
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
  - [x] 8a. The package (commit 53854015): `MouseTargetTrackingState` (target,
    parts, position, waiting), the projection, and `MouseHover` in the gesture
    layer. Nothing used it yet.
  - [x] 8b. The rows, the containers and the rule of the hover. **Q31**: a widget
    that a view makes got no crossing; D62 answers it. Facts found and decisions made:
    - A row of a list or a table and a node of a tree is no document, so the
      list, the table and the tree are the deepest part. **The route of the
      `MouseHover` is the whole target**, not the deepest part, so the widget
      reads its row from the rest of the route (`items[2]`, `rows[1][2]`,
      `column_headers[1]`, `roots[1].children[2]`). The route of step 3 gives
      that rest to a widget that holds no child IO map.
    - **The hover comes on each move, after the enters**, and not only on a
      move over the same target: else a row does not light on the move that
      enters its list. A `DisplayUpdate` gives a hover when the target changed
      (D41). This changes the letter of D58, not its intent. (Claude,
      2026-09-27, for the owner to confirm.)
    - A `MouseLeave` whose route ends at the widget turns its light off; a
      leave of a part inside it does not. A bare `MouseMove` lights no row.
    - No container sends a crossing by position: the composite, the shell, the
      split, the tabbed pane, the scroll and transform panes, the toolbar, the
      card, the accordion, the menu and the layouts lost their `MouseEnter` and
      `MouseLeave` arms. A `MouseMove` still goes by position, for the drags of
      step 10.
    - A menu item holds child IO maps, and the kernel gives a routed change to
      a child, so a gesture at the item's own place got no answer. The menu
      item has a 4-arg reader that reads a crossing at its own place. A button
      and a toolbar item hold no child IO map and need none.
    - The charts keep their light by `MouseMove` until step 10, which moves
      their pan and zoom; their `MouseLeave` comes by route.
    - `WidgetHoverTrackingProjection` is removed. `FocusCyclingProjection`
      stays in every window wrap (D60).
    - A lone widget that is the whole content of a window gets no light: the
      root of the content is no part, and the widget maps a point to nothing.
      A window of the product holds a container, so the tests use one.
    - The tracker delivers a route with the type of each node, because a view
      that maps a route forward checks the types (the pane views do). A crossing
      whose part is gone is not delivered: no reader can reach it.
    - A point that a layout passes to a `WidgetText` or a `WidgetTextarea` as a
      bare step made a path whose tail was a step, and the layout failed to type
      it. A point on a text now maps to its content, at the point.
    - D62, as built. `_read_routed_chain` maps a routed gesture forward while
      the forward map answers a reference that names a node of the next stage;
      `_read_routed_gesture` reads from the deepest stage back and carries the
      answer back, as `_read_chain_from` does. A routed operation keeps the
      check of the same document.
    - D62, the parts. The kernel has no walk over every IO map (only a
      container names its children, for a route), so the tracker does not
      evaluate a path inside a view's output. Each prefix of that path is a part
      instead, and a crossing of a prefix that names no widget reaches no
      reader. So no new kernel helper was needed. (Claude, 2026-09-27; this
      differs from the walk through the IO maps that Claude proposed with A.)
    - D62, the rows. A list, a table (both IO maps) and a tree turn the light
      off on a leave whose route names the lit row, and on a leave at their
      own place.
    - D62, the introduced reference. A view can name a widget by an introduced
      reference and map only its own input forward (the runner form of omnet,
      `SimulationFilterToWidgetForm`). When the forward map of a stage answers
      nothing for a routed gesture, the chain takes `find_introduced_path` of
      that stage, so no view needs code of its own for it.
    - Tests that read a widget that a view makes find it through the IO maps,
      because it is in no document (the navigator of the application, the Run
      button of the IDE window).
  - [x] 8c. The screen and the hosts:
    - `make_tracking_screen(...; mouse_target_tracking = true)` puts the target
      tracker inside the gesture tracker: gesture(target(screen)) (D29).
      `ProjecturedScreen` depends on `ProjecturedMouseTargetTracking`.
    - The `hover` flag of the gallery chooses the target tracker (D60), and
      **its default is now `true`**: the widget examples and the omnet and inet
      hosts had the old tracker in their own projections, and they keep the
      light. `hover = false` turns it off. (Claude, 2026-09-27, for the owner to
      confirm.)
    - omnet: the campaign keyword `hover` is now `focus_cycling`, and the build
      wrapper `:hover` is now `:focus_cycling`. Both only kept a second wrapper
      out, and the light is on the screen now. (Claude, 2026-09-27, for the
      owner to confirm; D60 named the campaign flag.)
    - Tests (2026-09-27): a row of a popup lights, and the light moves to the
      list of the first window (H1); the leave of the window turns it off (H3);
      the light follows from row to row; a row turns off when the pointer moves
      onto another widget (§3.4); a list that scrolls under a still pointer
      lights the row now under it (D41); a light changes the layout of no
      widget (D44); a row of a part and a button of a view light (D62); the
      navigator of the application, and the buttons and the run table of the
      campaign, light. Suites against the baseline: kernel, substrate (164 cell
      assertions fewer: the removed wrapper had them), shell, application,
      mouse clicks, click round-trips, and the rest of the sweep, the same
      known failures and no new one; the global name check the same 9
      findings; the naming guard passes. omnet: the three known failures, and
      the four tests that step 8 added pass; its global check gives its one
      known finding. inet: the demo passes 219.
  - [x] 8d. The live check, by pushed SDL events (the owner's choice,
    2026-09-28). XTest is out (D61 withdrawn): a first run opened the X display,
    and the desktop asked to allow remote interaction; no pointer moved. The
    check opens the real application window with one file open, finds the
    places by the texts that the window draws (also inside a viewport), and
    pushes `SDL_MouseMotionEvent`, `SDL_MouseButtonEvent` and the window leave
    into the SDL queue, in device pixels. It reads each light through the IO
    maps, because a view makes the lit widget. 7 of 7 pass: a row of the
    navigator lights, and its pixels change; the menu item File lights and the
    row turns off; a click opens the popup, and its item Close tab lights (H1);
    the leave of the window turns every light off (H3). A pushed event does not
    pass the X server, so a fault of the window manager stays out of reach.
- [x] 9. **The probes go away (D7, D63 to D75).** A tooltip is the meaning of a
  `MouseDwell` at the part, given by the part's gesture table (D63); the feed,
  the probe, `TooltipRest` and `PointerRest` of the tooltip package go away. The
  hover inspector goes away (D75). The context menu is the meaning of a right
  click at the part (D69, D74). Tests: a tooltip opens after a dwell in any window, not
  only the first; F2 and Shift+F2 show more and fewer layers; the closers of
  D66; a view changes a tooltip on the way up; the palette runs "show the
  tooltip" on the selection; the context menu opens for the part, a nearer
  `WidgetContextMenu` wins, and F2 adds the window's menu.
  Open points, to settle one by one before the code:
  1. ~~the outward search~~: settled by D64 (driven by the answer);
  2. ~~how a level adds its layer~~: settled by D64 and D71 (the package's join,
     a separator and a source mark);
  3. ~~the tooltip wrapper~~: settled by D72;
  4. ~~a run without a pointer~~: settled by D73;
  5. ~~the context menu~~: settled by D74;
  6. ~~the inspector~~: settled by D75 (it goes away).

  The parts, with a commit for each:
  - [x] 9a. **The outward search in the kernel (D64).** `is_collecting_operation`
    and `join_collected_operations` in `OperationModule`; a wrapping operation
    asks and joins through what it wraps. `read_routed_child` keeps the documents
    on the route and walks outward from the deepest (`_read_outward` in
    `ProjectionDefaults.jl`). The walk runs only for a gesture with no operation,
    so an operation keeps the same-document rule. The default leaf reader reads
    any `Gesture` with its table (`read_gesture`), not only the keys and
    `CollectIntents`. Tests: four cases in `test_routed_change` (a dwell collects
    two layers; the nearest right click wins; a container reads its own table; an
    operation is not read). The kernel suite has 8 more passes, and every other
    suite of the sweep has the counts of step 8.
  - [x] 9b/9c. **The tooltip as bindings, and the tooltip window (D63, D65 to
    D67, D72, D73).** The target tracker routes a `MouseDwell` to its target
    (`_read_dwell`). `ProjecturedTooltip` holds `OpenTooltipOperation` (it
    collects; the join adds the outer layers after the inner ones),
    `make_tooltip_binding`, `TooltipContent` and `TooltipWindowProjection`,
    which `make_tracking_screen(; inner_wrappers = [wrap_tooltip_window])` puts
    around the target tracker. The natural projection draws `TooltipContent`
    (`TooltipContentToVerticalLayout`, `make_natural_tooltip_row`). The window
    of the pointer moves the point of a routed answer to the screen
    (`_open_popup_window` in `ScreenToScreen.jl`). The bindings: a widget "Show
    the tooltip", a Julia function "Show the signature", a docstring "Show the
    documentation", a fault report "Show the fault". `compute_tooltip`, the
    probe, the feed, `TooltipRest` and `PointerRest` are gone, and so are the
    `tooltip`, `pointer` and `tooltip_feed` keywords of the window wrap and of
    the application window. Found in the work:
    - A reader that an author wrote, such as the reader of a widget leaf, does
      not ask the table of its input. So the outward walk of 9a also reads the
      input of the child that took the route when that child answered nothing.
      A default leaf then reads its table twice when it answers nothing, which
      changes no answer.
    - A command that an agent runs goes by route (`read_rooted_operation`), and
      a routed change passes the tooltip wrapper on its routed branch. So the
      wrapper takes a tooltip from a routed answer too; else the editor gets an
      operation that it can not evaluate.
    - The window manager applies an `OpenWindowOperation` only when it passes it
      on the way up, and the tooltip wrapper is outside the screen projection.
      So `evaluate_operation` of the screen package now opens, updates and closes
      a window on the screen that the editor's document wraps, with the same
      code as the manager (way A, owner 2026-09-28). This also makes
      `open_file_dialog!` open its window, which it did not do before: no test
      checked the window, and `test_file_dialog()` now does.
    - No projection that ends in graphics maps a widget forward, so a tooltip
      that a command opens with no point stands at the corner of the screen.
      The owner chose to complete the forward map (way (c), 2026-09-28):
      [the-forward-image-of-a-part.md](../done/the-forward-image-of-a-part.md). Until
      then that one assertion of `test_tooltip_window()` is `@test_broken`.
    - The omnet IDE moves to the wrapper in this part, not in 9f, so omnet
      loads after each commit: `make_ide_window_wrap` loses `pointer` and
      `tooltip_feed`, `run_omnet_ide` gives `inner_wrappers =
      [wrap_tooltip_window]` to the editor and loses its named `backend`, and
      `make_ide_opened_window_projections` starts with the natural tooltip row
      (`OmnetIde` depends on `ProjecturedNatural`).
    - `test/shell/TooltipProbeTest.jl` is now `ContextMenuProbeTest.jl`, with
      only the context menu probe, until 9d. `test_tooltip_window()` drives a
      real editor with a headless backend: the times of the events are long
      past, so the wait of the dwell ends in the same frame.
    - Checks: the sweep has the counts of 9a, except the kernel (+2), the
      substrate (+5) and the shell (265 passes and the one broken placement,
      no failure); the naming guard passes; the omnet tests of step 8 pass
      (186 in 8 tests).
  - [x] **D76 changes 9a to 9c.** The dwell travels by position, as a click
    does: the target tracker no longer sends it by route (`_read_dwell` goes).
    The outward reading of the gesture tables (D64) then runs in the shared
    helpers that hand a pointer gesture to the child at its point, in the
    widget and the layout packages, as D64 named; when no gesture travels by
    route, the walk in `read_routed_child` of 9a has no use, unless Q35 keeps
    the crossings routed.
    Done by step 7 of
    [a-document-knows-the-part-under-the-pointer.md](../done/a-document-knows-the-part-under-the-pointer.md)
    (2026-10-01): the dwell and the right click travel by position.
  - [x] 9b′. **Replaced before it started** by
    [a-document-knows-the-part-under-the-pointer.md](../done/a-document-knows-the-part-under-the-pointer.md)
    (owner 2026-09-28): every document stores the path of the part under the
    pointer like its selection, a move becomes that path as a click becomes the
    selection, and the dwell and the click travel by position. That plan
    replaces the mouse target tracker of step 8, so steps 8 to 12 are planned
    again from it before 9d goes on.
  - [x] 9d. The context menu as bindings. Done (2026-10-01), ported from the
    kept code: `OpenContextMenuOperation` collects; `make_context_menu_binding`
    binds a right click, also with no gesture; `WidgetContextMenu` and
    `WidgetShell` (the window menu, the outermost layer) answer from their own
    tables, and so do `DataFrameColumn` and `DataFrameView`;
    `ContextMenuWindowProjection` with `wrap_context_menu_window` opens the
    window at the click, or below the part with no point, and F2 / Shift+F2 show
    one more or one fewer layer through the helper of the screen,
    `WindowLayers.jl`, which the tooltip window uses too. The probe and the
    `context_menu` keyword of the window wrap are gone; the application and the
    omnet IDE put the menu window beside the tooltip window. D74: a right click
    selects nothing in the text field, the tab strip, the math view, the
    sequence chart, the cached canvas, the conversation and the pane focus
    (the list, the table, the tree, the chart, the graph and the text view
    answered only a left click already). Test: `test_context_menu_window` (36).
    Two points for the owner: `DataFrameColumn` is now a `Document`, because
    the outward walk reads the tables of documents only, and the data frame view
    maps a header back to its column; a host with no menu window (the gallery,
    the screen examples) opens no menu on a right click, because only the
    wrapper opens it. Decided (owner 2026-10-02, "Agreed" to both): the first
    stays, and a part that a path names and that has a gesture table of its own
    is a `Document`, even when it holds no cells and is made on demand, which
    `document.md` records; the second is step 9f. On main as `63de70c7e`, with omnet `69e7e65c` (the IDE
    window keeps the menu window); the context menu, tooltip, platform (only
    the file system test under `unshare -r` fails) and omnet pointer, IDE and
    campaign tests pass.
  - [x] 9e. The hover inspector goes away. Done (2026-10-01): `HoverProbe.jl`
    with `HoverProbeProjection`, the gallery's `inspector` option and
    `_multi_window_projection_inspector`, the two probe tests, and the text
    about the probe in the documents. `test_reference_inspector_text` moved to
    `ReferenceInspectorTest.jl`; the Selection tool and `ReferenceInspector`
    stay. The repls, the application, the gallery wrappers and the platform
    pass as before.
  - [x] 9f. The hosts, the checks and the documents.
    **Settled** (owner 2026-10-02: "Agreed", on Claude's option a): the tooltip
    window and the context menu window are two wrappers of `build_editor`,
    `tooltip` and `context_menu`, on by default. Each adds its window function
    to a list in the editor parts, and the `window` wrapper puts the functions
    of that list inside the trackers, as it takes the rows of
    `opened_window_projections` from the other wrappers; the screen slice names
    neither window, because the tooltip and the widget slices depend on it. A
    host turns a window off with `tooltip = false` or `context_menu = false`,
    and the application passes the two windows no longer. Facts behind it
    (2026-10-02): `inner_wrappers` of the `window` wrapper defaults to empty,
    and only the application (and the IDE of omnet) passes the two windows, so
    `build_editor` with its defaults, the gallery and the screen examples
    opened no tooltip and no context menu. Rejected: option b, every host passes
    the windows itself.
    Built (2026-10-02): `EditorParts.window_wrappers` (kernel `EditorBuild.jl`);
    the `tooltip` wrapper (`:window => -20`, `TooltipWindow.jl`) and the
    `context_menu` wrapper (`:window => -10`, `ContextMenuWindow.jl`) push their
    window functions there, and the `window` wrapper puts `window_wrappers`
    before its own `inner_wrappers`. The application passes the two windows no
    longer; the gallery, which calls `make_tracking_screen` itself, passes them;
    the omnet IDE passes them no longer. Test: `test_tracking_screen` checks the
    order of the states and the two keywords off; an application test counts two
    more levels.
- [x] 10. **Replaced by step 5b of
  [a-document-knows-the-part-under-the-pointer.md](../done/a-document-knows-the-part-under-the-pointer.md)**
  (Q13 there, settled 2026-10-01: the drag wrapper keeps the path of the part
  whose drag is on, local drags keep their own state, the part under the
  pointer lights during a drag, which replaces D29). The first plan of the step:
  **The drag tracking package (D14, D19, D20, D21, D26, D29, D52).**
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
- [x] 11. **The rules and the documents (D16, D40).** `PAR-NO-NEW-SYNTHETIC-EVENT`
  is written again; the rules of D40 and D44 join the invariants; the concepts (event,
  gesture, tracking projection) go into the design documents; the documents of
  the kernel, the widgets, the screen, the tooltip, the dragging and the
  backends change. This step takes step 4 of the plan
  [every-window-tracks-the-pointer-and-says-when-it-leaves.md](every-window-tracks-the-pointer-and-says-when-it-leaves.md).

  **Each feature of this work is documented on its own, twice** (owner
  2026-09-29: "document the features separately: tooltip, mouse target, popup
  window, context menu, etc. implemented here. We need both design and user
  interface documentation."):

  - a **design document**, for a developer: how the feature works, how it fits
    with the others, why it is built so, how to use it from code, and its
    limits, in the form of the package documents;
  - a **user interface document**, for a person who uses the editor: what the
    person does, what the person sees, and which keys and clicks work, as
    numbered steps, with the gesture help and the command palette as the way to
    find the rest. Each one is linked from
    [keyboard-and-mouse-guide.md](../../documentation/guide/keyboard-and-mouse-guide.md).

  The features and their places (Claude's proposal; owner 2026-09-29: "Yes"):

  | Feature | Design document | User interface document |
  | --- | --- | --- |
  | Gestures: the event and the gesture, the click, the chord and the dwell, the gesture tables, and the outward reading of D64 | `package/kernel/gesture.md` (new), `package/gesturetracking/gesturetracking.md` | `guide/gestures-guide.md` (new) |
  | The mouse target: the part under the pointer, stored like the selection, and the light | `package/kernel/mouse-target.md` (new, beside `selection.md`) | `guide/pointer-guide.md` (new) |
  | The tooltip: the dwell, the layers, F2 and Shift+F2, the closers, the command | `package/tooltip/tooltip.md` | `guide/tooltip-guide.md` (new) |
  | The popup window: a menu, a list of a select, a dialog, a tooltip and a context menu, each in a window of its own; how it opens, where it stands and how it closes | `package/screen/popup-window.md` (new) | `guide/popup-window-guide.md` (new) |
  | The context menu: the right click, the layers, F2 and Shift+F2, the window menu, the command | `package/widget/context-menu.md` (new) | `guide/context-menu-guide.md` (new) |
  | The place of a part: the forward path and the box of a part, and a window that a command opens below it | `package/kernel/reference.md` (a section) | in the tooltip and context menu guides |
  | The timer and the display event | `package/kernel/editor.md` (a section) | none: a person does not see them |
  | Dragging (step 10) | `package/dragging/` | `guide/dragging-guide.md` (new) |

  Each path is under `documentation/`. The folder `package/<package>/` may hold
  more than one document, as `package/kernel/` does. The paths go into
  [documentation/README.md](../../documentation/README.md) and
  [package/README.md](../../documentation/package/README.md). The named paths of
  [named-paths-in-a-document.md](../tentative/named-paths-in-a-document.md) are
  an idea, and get no document until they are planned.

  Done so far (2026-10-01): every row of the table but the drag. New:
  `package/kernel/mouse-target.md`, `guide/pointer-guide.md`,
  `package/kernel/gesture.md`, `guide/gestures-guide.md`,
  `guide/tooltip-guide.md`, `package/platform/screen/popup-window.md`,
  `guide/popup-window-guide.md` and `guide/context-menu-guide.md`; a section
  "The timer and the display event" in `editor.md`, and the forward path
  through the node of a slot in "The place of a part" of `reference.md`, which
  had that section already. The design documents of the tooltip and the
  context menu were written with steps 9c and 9d. The four steps of the context
  menu moved from `keyboard-and-mouse-guide.md` into its own guide. The
  documents of the drag came with step 5b of the pointer plan (2026-10-02):
  `package/platform/dragtracking/dragtracking.md` and `guide/dragging-guide.md`.
  Open: the rules (`PAR-NO-NEW-SYNTHETIC-EVENT`, D40, D44).
  The rules, decided one at a time (owner 2026-10-02). A fact first: two rules
  of today contradict the approved drag. `PAR-NO-NEW-SYNTHETIC-EVENT` forbade a
  `read_intent` method for a new payload type, and the readers read `DragMove`,
  `DragEnd` and `DragCancel`; `PAR-NO-GLOBAL-ROUTING` said that no global
  component fixes the path of an input, and the drag wrapper sends the drag
  gestures by a kept path. D40 is `PAR-DECIDE-LOCALLY` already.
  - 4a ("Agreed", on Claude's option a): `PAR-NO-NEW-SYNTHETIC-EVENT` is
    written again along the real line. The reader chain reads what a person
    does, an event of a device and a gesture that a recognition or a tracker
    makes of such events (a click, a dwell, a chord, a part of a drag); no
    `SyntheticEvent` type and no `read_intent` method for a payload that carries
    an operation, a request or a question; a new gesture type only with the
    owner's agreement, as for the three drag gestures. Rejected: option b, the
    rule as it was with a list of accepted exceptions.
  - 4b ("Agreed", on Claude's option a): `PAR-NO-GLOBAL-ROUTING` names the drag
    as the second case of a fixed route: a route is fixed in advance only to
    return an operation from one place, or to give a drag to the part that
    started it. The part answers `StartDragOperation` with its own path, and the
    drag wrapper sends it the parts of its drag by that path until the drag
    ends; the part chose the route, so no global component chooses the part,
    and the raw events of the drag still go by position. Rejected: option b, an
    accepted exception below the rule.
  - 4c ("Agreed", on Claude's option a): D44 becomes the rule
    `PAR-LIGHT-KEEPS-LAYOUT`, beside `PAR-REPEATED-MOVE-WRITES-NOTHING`: a light
    changes no size and no place; a part that lights draws a layer, a colour or
    a frame over what it draws. After a changed frame the backend sends a move
    at the still pointer, and a light that moved another part under the pointer
    would light that part next, frame after frame. Rejected: option b, the
    sentences in `mouse-target.md` and `widget.md` and their test only.
  - Written (2026-10-02) in `architecture-invariants.md`: the two rules again and
    `PAR-LIGHT-KEEPS-LAYOUT`, with their rows in the table;
    `mouse-target.md` and `widget.md` link the new rule.
- [x] 12. **The check against `main`, and the move of this plan and of the plan of
  `WindowLeave` to `plan/done/`.**
  Decided (owner 2026-10-02, "Agreed", on Claude's option a): after 9f, the
  rules and the moves of the browser are built, the check runs the suites of
  each change, the guards, `test_repls`, the omnet sets, and a live check in a
  real SDL window with pushed SDL events (no XTest): the light, a tooltip, a
  context menu with F2, the drag of a slider, a divider and a tab, Escape
  during a drag, and a list that scrolls under a still pointer. Then this plan,
  the plan of `WindowLeave` and the study `pointer-hover-and-windows-today.md`
  move to `plan/done/`, and Q15 moves into a small pending plan of its own.
  Rejected: option b, the check without the live check.
  Found by the live check (2026-10-02):
  - A slider in a tab of a pane tree did not follow a held move, and its drag
    never ended. The drag tracker kept the path of the part with no node types,
    and `PaneGroupToWidgetTabbedPane` refuses an under-typed path when it maps the
    route forward. Fixed: `_read_drag_part` gives the route the types of the
    content as it is now (`annotate_reference_types`), as `find_part_place` does.
    `DragTrackingTest` drags a slider in a tab.
  - A right click on a part that has its own position inside a
    `WidgetContextMenu` opens no menu: the box of the menu is the size of the
    child canvas, without the place of that canvas, so the point is outside it.
    The size code is older than this plan. Not fixed here; it goes to the owner.
  - Not faults: Escape puts back the value from before the press, as
    `DragTrackingTest` specifies; a click on a tab waits for the double-click
    timer when a part at the point has a double click; a list in a scroll pane
    lights its row in a tab. The first driver read cells from a second thread and
    chose a row below the visible pane, and its results varied between runs.
  - A list that scrolls under a still pointer can not be checked with pushed
    events: the wheel and the move after a changed frame read the position of the
    real pointer (`SDL_GetMouseState`, `SDL_GetMouseFocus`), and pushed events do
    not move it. `ScrollPaneHoverTest` keeps the check without a window.
  The sweep (2026-10-02, projectured at `d0c5ee124`, omnet main): platform
  85430 pass, 1 fail (the file system test under `unshare -r`), 8 broken (older
  markers); display 28; chart 361; web 118; data frames 267; application 344 and 2
  broken; `test_repls` 23172 and 5 broken; the argument guard 6 (the 2 new ones
  in `Theme.jl` came with the appearance work), the export guard 4. omnet: campaign
  188; text clipboard 9; `test_view_lights` 3 and 1 fail (the catalog draws two
  lists now, and both light; the test counts one); `test_legacy` 7 fail and 120
  errors (the NED reader 114, a list table printed with no offered height 5, the
  run table 4 known since 2026-09-23, layout widths and a collapse mapping);
  `test_ide` 3 fail and 10 errors, all from the settings wrapper (`slice`, `log`,
  the Settings tool). By the messages, none comes from the pointer work.

Not in the steps: the web client sends no motion while no button is held (study
§4), so the browser has no hover. That needs a decision of its own. Decided (owner
2026-10-02, "Agreed", on Claude's option a): the browser sends every move. The
client sends a move with no button held at most once per animation frame
(`requestAnimationFrame`), and the server stops dropping it, so the light, the
tooltip, the lit brackets and the light during a drag work in the browser as on
SDL. Facts: `asset/web/client.js` sent a move only while a button was held, and
`WebBackend.jl` dropped a move with no button too; the leave of the window is
sent already. Rejected: option b, no hover in the browser as a documented limit.
Built (2026-10-02): `asset/web/client.js` sends a held move at once and keeps
the last move with no button for the next animation frame; `WebBackend.jl`
passes every move; `test_web` (118) checks a move with no button; `web.md`
follows.

Also open: Q15 of
[a-document-knows-the-part-under-the-pointer.md](../done/a-document-knows-the-part-under-the-pointer.md),
a document that a view shows inside a widget and that a second view draws gets
no mouse target. Decided (owner 2026-10-02, "Agreed", on Claude's option a):
find the cause first, with the smallest case in projectured alone, and bring the
ways to fix it with their costs; no change to the source before that.
Found (2026-10-02): the omnet inspector view puts its own input, the reflected
shadow, into a scroll pane of its output, and `ReflectionToWidget` draws it later.
The answer of the second view, `proj(ReflectionToWidget, .roots[1])`, reaches the
inspector, which has no backward map of its own, and the default wraps it again
as a part of the inspector, although the path has a pre-image: the shadow is its
input (`PAR-CROSS-DOMAIN-LATE`). The chain write stops at the shadow with that
path, and `ReflectionToWidget` can not read it. A case in projectured alone shows
it, and a backward map that walks the output path to the node that is the input
and answers the rest makes the row light. The ways to fix it, for the owner: (a) a
backward map in each view that puts its input into a slot, with a small helper
that does the walk; (b) the view prints the shadow itself with `print_child`;
(c) the walk in the default `map_reference_backward` of the kernel. Also found:
`SimulationTopologyToWidget` puts a graph that it makes into its output, and its
outer walk leaves the graph out, a case of its own.

The files of the kernel that the refactor changes are unsealed, and they stay
unsealed after the work (D34).
