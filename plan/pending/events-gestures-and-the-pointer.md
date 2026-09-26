# Events, gestures and the pointer

> **Status (2026-09-26): design, no code.** The owner and Claude write this
> document over several sessions. It records the concepts, what is wrong today,
> the owner's decisions and the questions that are still open. The steps of the
> refactor come after the open questions have answers.

The facts of the code are in the study
[pointer-hover-and-windows-today.md](pointer-hover-and-windows-today.md). This
document cites the study by section ("study §8") and does not repeat it. Step 3
of [every-window-tracks-the-pointer-and-says-when-it-leaves.md](every-window-tracks-the-pointer-and-says-when-it-leaves.md)
waits for this design.

## 1. The concepts

The owner's definitions, from the conversation of 2026-09-26:

- **Event.** A data structure that describes something that the hardware
  generated, as the platform reports it: a key goes down, a button goes up, the
  pointer moves, the pointer leaves a window. An event has no meaning of its own.
- **Gesture.** A pattern that matches a sequence of events. The pattern can leave
  out events. A click is a down and an up of one button, near in place and in
  time. A chord is a sequence of keys. A rest is no motion of the mouse for a
  short time. The gesture recognizer can hold any number of these patterns.
- **Rest.** A gesture: no motion of the mouse for a short time. It does not
  depend on the view under the pointer, so a rest alone is not a hover over a
  particular thing. The thing at the position of the rest gives it a meaning, as
  for a click.
- **The thing under the pointer.** It follows from two inputs: the position of
  the pointer, and the view (what is drawn where). It is neither an event nor a
  gesture. It changes when either input changes. `MouseEnter` and `MouseLeave`
  are changes of this fact, so they are neither events nor gestures.
- **Meaning.** A reader takes a gesture and answers the edit that the gesture
  means. The meaning belongs to the thing that the gesture lands on.

The owner's first principle of hover was: "a pointer that rests on the same
thing for a while is a gesture". Decision D4 makes it exact: the gesture is the
rest, and the thing is not a part of the gesture. The reader finds the thing at
the position of the rest.

The naming rules already name this ladder: "Event → Gesture → Intent →
Operation → Document" ([naming-rules.md:192-200](../../documentation/rule/naming-rules.md)).
The code does not follow it (§3).

## 2. The owner's decisions

| # | Decision |
| --- | --- |
| D1 | The pointer that leaves a window is an event, `WindowLeave`. Done on the branch `window-leave`. |
| D2 | The Tab wrap-around is unrelated to hover. |
| D3 | `SyntheticEvent` must not exist. A gesture is a gesture, with a type of its own, so that gestures and events do not mix. |
| D4 | A rest (a "pointer rest", or a "mouse rest") is a gesture: the event pattern of no mouse motion for a short time. It is independent of the view under it, so in itself it is not a hover over a particular thing. |
| D5 | The gesture recognizer can hold any number of event patterns (gestures). |
| D6 | `MouseEnter` and `MouseLeave` are neither events nor gestures. |
| D7 | A reader must not answer a question that is not a gesture. In the owner's words: "how should a projection reader know what is the total set of possible questions?" |

All of them are from 2026-09-26.

The owner also gave a direction for the question "what is at this point":
`map_reference_backward` of the projection, at the position of the pointer,
gives what a gesture there acts on, "so you would not even need to track it".
This is a direction, not yet a decision.

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

### 3.3 The rest lives in the tooltip package

- A feed of each window names a deadline, the loop sleeps until it, and the feed
  reads a `PointerRest` through the projection (study §7). Only the first window
  has a feed by default, and each host wires it by hand.
- The tooltip probe keeps the time of the last move itself. So the recognizer,
  the feed and the probe each keep a part of the state of the pointer.

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

- Four probes ask "what is under the pointer" through `read_intent` (study §8).
  Each probe puts the question in the form of a fake gesture. Each reads the
  answer from the inner shape of an operation: `_target_of` takes the root of a
  hover write (`WidgetHoverTracking.jl:146`), and the three others take the path
  of a `ReplaceSelectionOperation`. No reader promises these shapes.
- A reader changes its answer for the sake of a probe: the table writes on every
  enter only so that the tracker finds it (`WidgetToGraphics.jl:8317`).
- The rule `PAR-NO-NEW-SYNTHETIC-EVENT` already forbids this use: "The reader
  chain reads what a person does. It is not a channel to carry an operation, a
  request or a question through the projection hierarchy"
  ([architecture-invariants.md:503-514](../../documentation/rule/architecture-invariants.md)).
  The four probes break it. The rule also says that a synthetic event that
  exists now is not a precedent for a new one.

### 3.6 The pointer position has no home

- The position exists only in the newest `MouseMove`, and in
  `get_pointer_position`, which answers screen coordinates while an event holds
  window coordinates (study §11, item 14).
- The web client sends no motion while no button is held, so the browser has no
  crossing and no rest (study §4).

## 4. What we want to change

The direction that follows from the decisions so far:

1. Remove `SyntheticEvent` (D3). The events stay under `Event`, and the gestures
   get a type tree of their own.
2. The recognizer holds an open set of gesture patterns (D5): the click with its
   count, the chord, the rest, and the gestures that come later.
3. The rest moves from the tooltip package into the recognizer, as the pattern
   of no mouse motion for a short time (D4). A tooltip is then one meaning of a
   rest, which the thing at the position gives.
4. `MouseEnter` and `MouseLeave` go away (D6). The light of the thing under the
   pointer follows from the position and the view. How it follows is open (Q4).
5. No reader answers a question (D7). The four probes go away. The question
   "what is at this point" goes to reference mapping, with
   `map_reference_backward` at the position as the direction.
6. The Tab wrap-around leaves the hover tracker (D2). Its new place is a question
   of the focus traversal, not of this design.

## 5. Open questions

- **Q1. The names.** The root type of a gesture, and the name of the rest
  (`PointerRest` or `MouseRest`). The naming law has a form for an event and none
  for a gesture. Does it need one?
- **Q2. What a reader receives.** Only gestures, or gestures and events? A
  splitter, a tab of a pane, the pan of a chart, a slider and a reorder drag read
  `MouseDown`, `MouseMove` and `MouseUp` today (study §9). Is each of these
  events also a gesture of one event, or is a drag a gesture of its own?
- **Q3. Time with no input.** A rest ends when no event arrives, so the
  recognizer needs a deadline that the loop sleeps until, as the tooltip feed
  does today. Who keeps that deadline?
- **Q4. The thing under the pointer.** Where it is found, where it is kept, and
  how a thing shows that it is under the pointer. What does the word "hover"
  name in the new model?
- **Q5. The pointer position.** One for each editor or one for each window, in
  which coordinates, and what `WindowLeave` sets it to.
- **Q6. The answer of `map_reference_backward`.** Can it answer "what is at this
  point" for every projection today? The facts to collect: which projections map
  a position of the graphics backward, and what the inspector, the context menu
  and the tooltip need from the answer.
- **Q7. A gesture across windows.** A drag can start in one window and end in
  another. Which window owns the gesture?

## 6. Next steps

1. Answer the open questions with the owner, one at a time, and record each
   answer in §2.
2. Collect the facts that an answer needs at the time it needs them (Q2, Q6).
3. Then write the steps of the refactor in this document, each with its test.

The refactor changes sealed files: every file of `event/` except `EventModule.jl`
and `WindowEvent.jl`, and both files of `gesture/`. Each file needs the owner's
word before a change ([SEALING.md](../../SEALING.md)). The rule
`PAR-NO-NEW-SYNTHETIC-EVENT` names `SyntheticEvent`, so its text changes too, and
a change of a rule is the owner's decision.
