# Pointer, hover and windows: what the system does today

> A study, not a plan. It records what is implemented on `main` at `ee1e494d`
> (2026-09-26) for the pointer, its motion, crossings, hover, rest and windows,
> as the input to the design of a refactor. The branch `window-leave` changes
> two facts, marked **[branch]**. The plan that this study feeds is
> [every-window-tracks-the-pointer-and-says-when-it-leaves.md](every-window-tracks-the-pointer-and-says-when-it-leaves.md).
>
> Five read-only studies collected the facts: the kernel events and the editor
> loop, the backends, the screen and the shell, the widgets and the layouts, and
> the tooltips and the probes with the uses in omnet-julia. The claims that the
> design rests on were checked against the code again.

## 1. Summary

1. **The pointer has no state of its own.** Its position exists only inside the
   `MouseMove` that a backend reports, and in `get_pointer_position`, which
   answers the global screen position from the backend. Nothing keeps "where the
   pointer is now", in which window, or since when.
2. **Crossings are made in one place, outside the kernel.**
   `WidgetHoverTrackingProjection` in the widget package makes every
   `MouseEnter` and `MouseLeave` from motion. The kernel declares both events
   as synthetic and says that "the code that tracks the region" makes them, but
   no kernel stage does.
3. **Only the first window tracks crossings.** The shell wraps the content of
   the first window in the tracker; no window opened later has one: popups,
   dialogs, the gesture help, tooltips.
4. **Hover is two things with no shared model.** A whole widget lights from a
   crossing (a `hovered::Bool`); a part of a widget lights from motion inside it
   (a row index, or a reference to a row, a node or a series). Only widgets and
   the two charts show hover; no other domain does.
5. **Rest exists only for tooltips.** A tooltip feed wakes the editor loop at a
   deadline and reads a `PointerRest` through the projection; only the tooltip
   probe answers it.
6. **Four mechanisms ask "what is under the pointer",** each by running the
   chain of readers again with a fake event: the hover tracker (a fake
   `MouseEnter` on each move), the tooltip probe (a fake Alt+press at rest), the
   context menu probe (a fake Alt+press on a right press) and the inspector
   probe (a fake plain press on each move).
7. **A window is a document.** The screen is a `ScreenDocument` of
   `WindowDocument`s; the window manager opens and closes windows by operation,
   routes each input by window id, and applies the close rules of popups.
8. **Backends differ in what they report.** SDL reports motion with and without
   a held button, but no crossing of a window edge **[branch: it reports
   `WindowLeave`]**. The web client sends motion only while a button is held, so
   hover and tooltips do not exist in the browser. The console has no pointer.
9. **Several things live in the wrong place:** the Tab wrap-around in the hover
   tracker, the tracker's state on the projection instance, a leave routed to
   the last position before the move.

## 2. The concepts as the code uses them

| Concept | What stands for it today | Where |
| --- | --- | --- |
| Pointer position | only the `x`, `y` of the newest `MouseMove`; the global position from the backend | `MouseEvent.jl:125`, `BackendInterface.jl:88` |
| Motion | `MouseMove <: DeviceEvent`, with the held `MouseButtons` | `MouseEvent.jl:125-137` |
| Press | `MouseDown`, `MouseUp` from the device; `MousePress`, a click, made by the gesture recognizer | `MouseEvent.jl:52-116`, `GestureRecognizer.jl:93-118` |
| Crossing | `MouseEnter`, `MouseLeave <: SyntheticEvent`, made by the hover tracker | `MouseEvent.jl:147-180`, `WidgetHoverTracking.jl:88-129` |
| Hover state | a `hovered` field on the widget, or on a chart, written as view state | `WidgetDocument.jl:254,421,669,721,2236,2424`, `ChartPlot.jl:64`, `SequenceChartPlot.jl:79` |
| Rest | `PointerRest <: SyntheticEvent`, made by a tooltip feed | `TooltipRest.jl:20-101` |
| What is under the pointer | a fake event read through the chain; the answer's path or target | four probes, section 8 |
| Window | `WindowDocument` in a `ScreenDocument`; an input comes as `WindowInput(window_id, event)` | `ScreenDocument.jl`, `WindowInput.jl:10-13` |
| Leaving a window | nothing on `main` **[branch: `WindowLeave <: DeviceEvent`]** | `WindowEvent.jl` |

## 3. The path of a pointer event

1. **The backend** reads the platform event, converts device pixels to logical
   pixels, and wraps it as `WindowInput(window_id, event)`. SDL collapses a run
   of motion into its newest sample and limits motion with no button held to
   one sample every 30 ms, and it holds back the last sample so that a stopped
   pointer still arrives (`Sdl.jl:2772-2806`, `603`). A drag is never limited.
2. **The gesture recognizer** (`GestureRecognizer.jl:93-118`) makes a
   `MousePress` from a `MouseDown` and a `MouseUp` near in place and time, and a
   `KeyChord` from keys. Every other event passes unchanged: motion, scroll,
   window events. It has no notion of rest or crossing.
3. **The editor** (`ReadEvaluatePrint.jl:26-70`) reads the projection with
   `Intent(window_input, nothing)`. With no operation back, it tries the zoom
   keys, then the Escape that quits. Up to 32 operations are read in one frame
   before one repaint (`EditorLoop.jl:35,60-90`); the comment ties that bound to
   a hover highlight that fell behind the pointer.
4. **The window manager** (`WindowManaging.jl:49-110`) drops the input of other
   windows while a modal window is open, turns a resize into
   `ResizeWindowOperation`, closes on a native close, applies the close rules of
   popups (section 5.3), and passes the rest to `ScreenToScreen`.
5. **`ScreenToScreen`** (`ScreenToScreen.jl:166-215`) routes the input to the
   window with the same id, reads its content, puts `windows[i]` in front of a
   path in the answer, and turns an `OpenPopupOperation` into an
   `OpenWindowOperation` at the screen origin of the window.
6. **The content of the window** reads the event through its own chain. In the
   first window of the application that chain is the shell's fold (section
   5.4): gesture log, command palette, gesture help, context menu probe, tooltip
   probe, clipboard, hover tracker, shell, history.
7. **Containers** route a positioned event to the child under the point by hit
   test (`hit_element_at`, `GraphicsDocument.jl:646`) and move it into the
   child's frame: `_route_to_children` exists twice, in `LayoutToGraphics.jl:220`
   and `WidgetToGraphics.jl:1258`, and crossings have their own routing
   (`_route_crossing_to_children`, `WidgetToGraphics.jl:1284`; `_route_crossing`,
   `LayoutToGraphics.jl:276`) and one translation per container (tabbed pane,
   scroll pane, transform pane, card: `WidgetToGraphics.jl:4410,4859,5045,5815`).
8. **A leaf** checks its bounds with `_outside_widget` (`WidgetToGraphics.jl:1442`),
   which lets every `MouseLeave` through, "a MouseLeave is outside by definition",
   and answers with an operation or nothing.

## 4. Backends

| What | SDL | Web | Console | Video | Headless test |
| --- | --- | --- | --- | --- | --- |
| Motion, no button | yes, limited to 30 ms | **no**: the client and the server both drop it (`client.js:613`, `Web.jl:579`) | no | from the timeline | no |
| Motion, button held | yes, never limited | yes | no | from the timeline | no |
| Down, up, scroll | yes | yes | no | from the timeline | no |
| Focus lost | event 12, which is the focus **gained** **[branch: 13]** | `blur` is decoded, but the client never sends it | no | no | no |
| Pointer leaves a window | dropped **[branch: `WindowLeave`]** | nothing **[branch: `leave` on `mouseleave`]** | no | no | no |
| Window close, resize | yes | yes | no | no | no |
| `get_pointer_position` | global screen position, not converted (`Sdl.jl:613`) | default `(-1, -1)` | default | the position of the timeline | default |
| Windows | native windows by style (section 5.2) | the first window in the page, every other one a browser window with no difference by style | one fixed id `:console` | one window | none |

The web client opens a spare browser window at the first user gesture and gives
it to the next window that opens with none, because a browser opens a window only
inside a user activation (`client.js:60-81`).

## 5. Windows

### 5.1 The model

- `ScreenDocument` holds `windows`, a `CellVector` of `WindowDocument`.
- `WindowDocument` (`ScreenDocument.jl:55-69`): `id`, `title`, `x`, `y`
  (`-1`: the backend chooses), `width`, `height`, `minimum_size`,
  `maximum_size` (`(0, 0)`: a fixed size; otherwise the window fits what it
  draws), `bg`, `style` (`:normal`, `:tooltip`, `:floating`, `:popup`),
  `auto_dismiss`, `modal`, `content`.
- Operations: `OpenWindowOperation`, `OpenPopupOperation` (a position in the
  frame of the reader that holds it, moved outwards by
  `shift_operation_position` and `map_operation_position`,
  `OperationPosition.jl:19-43`), `CloseWindowOperation`,
  `ResizeWindowOperation`. The manager applies open and close to the input
  screen, and `ScreenToScreen` mirrors them into the output.

### 5.2 SDL native windows

- The reconcile loop (`Sdl.jl:3061-3101`) closes the windows that left the
  screen, and for each window fits its size, places it, opens it hidden,
  paints and shows it, or updates its geometry.
- Flags by style (`Sdl.jl:448-475`): `:tooltip` with `SDL_WINDOW_TOOLTIP` and
  `:popup` with `SDL_WINDOW_POPUP_MENU`, both borderless and not managed by the
  window manager on X11, so they never take the focus; `:floating` resizable and
  above; `:normal` resizable.
- A window with a maximum takes the extent of what it drew, and stays inside
  the work area; a tooltip also goes beside the pointer, a popup stays under it
  (`_place_fitted_window!`, `compute_window_place`).
- The document takes the place that the window manager gave a window
  (`_adopt_native_position!`), so a popup opens at its window.
- Nothing keeps input from a popup or a tooltip window: SDL delivers events by
  window id to whichever window gets them.

### 5.3 The close rules of the window manager

A window with `auto_dismiss` closes on its own `WindowDefocus`, on a `MouseDown`
in another window, and on a bare Escape, which the manager answers with
`DoNothingOperation` so that the editor does not quit. A `:popup` also closes
when another window loses the focus (`WindowManaging.jl:80-106`).

### 5.4 The kinds of windows

| Window | Opened by | id | style | auto_dismiss | modal | Content drawn with | Hover tracker | Closes on |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| First window | `make_window_scene` | caller's | `:normal` | no | no | the caller's projection, in the shell's fold | **yes** | native close |
| Menu, select, context menu | a trigger, `OpenPopupOperation` | `:widget_popup` | `:popup` | yes | no | `make_opened_window_projections` | no | the close rules, or a pick |
| Tooltip | `TooltipProbeProjection` at rest | `:tooltip` | `:tooltip` | no | no | opened-window rows | no | the probe: a move away, a press, a key, a scroll |
| Inspector | `HoverProbeProjection` on each move | `:inspector` | `:tooltip` | no | no | opened-window rows | no | the probe, when nothing is under the pointer |
| Gesture help | F1 | `:gesture_help` | `:normal` | no | no | `GestureMap` row | no | a second F1 only |
| File dialog | File menu | `:file_dialog` | `:floating` | no | **no** | opened-window rows | no | its buttons |
| Widget dialog | `WidgetButton.dialog` | `:widget_dialog` | `:dialog` | no | **yes** | opened-window rows | no | Escape, the scrim, a button |

The command palette is not a window: it draws over the first window.

### 5.5 How the scene chooses a projection

`make_window_scene_projection` (`WindowScene.jl:76-97`) dispatches by reference:
the content of the first window gets the caller's projection, the screen gets the
window manager around `ScreenToScreen`, and the content of any other window gets
a type dispatch over `opened_window_projections`. The shell's rows for opened
windows are the gesture map, the host's content rows and the widget rows, with no
wrapper around them (`WindowWrap.jl:154-161`).

## 6. Hover today

### 6.1 Crossings: `WidgetHoverTrackingProjection`

On each `MouseMove` (`WidgetHoverTracking.jl:88-129`):

1. It gives the real move to its inner chain, so a drag below it still moves.
2. It routes a fake `MouseEnter` at the same point and takes the identity of the
   target from the answer (`_target_of`, `:146-153`): the `.widget` of the
   operation, or the `.document` of a `ReplaceReferencedValueOperation`, inside
   any wrapper.
3. If the target is the same as before, it keeps the position; otherwise it
   routes a fake `MouseLeave` to the old target **at the last position over
   it**, and answers the leave, the enter and the inner answer together.

Its state, the last target and its last position, is on the projection instance
(`:37-42`). It also holds the Tab wrap-around (`:73-87`), which has nothing to do
with the pointer.

It is built in the shell around the whole first window (`WindowWrap.jl:102`),
and by hand in the gallery, three example files, the build program, four test
files and, in omnet-julia, in Qtenv, the campaign window, the embed document,
the presentation example and a demo. Each host puts it at another depth, so what
counts as one target differs between hosts.

### 6.2 Two styles of hover state

| Style | How it is set | How it is cleared | Documents |
| --- | --- | --- | --- |
| The whole thing lights | a `MouseEnter` from the tracker | a `MouseLeave` from the tracker | `WidgetButton` (with `pressed`), `WidgetMenuItem`, `WidgetToolbarItem` |
| A part of the thing lights | the widget's own reading of `MouseMove`: a row, a node, a series | a `MouseLeave` from the tracker | `WidgetList` (`hovered::Int`), `WidgetTable` and `WidgetTree` (`hovered::Reference`), `ChartPlot`, `SequenceChartPlot` (`hovered::Any`) |

The part style still needs the tracker, for the leave. The table has two
separate hover codes for its two row sources (`WidgetToGraphics.jl:8399-8429`,
`WidgetTableList.jl:504-522`).

### 6.3 Storage and drawing

- A write is `_write_view_state(document, field, value)`, which is
  `ReplaceViewStateOperation(ReplaceReferencedValueOperation(...))`
  (`WidgetDocument.jl:2692`, copied in the two charts and the pane tree). The
  mark keeps it out of the history. No hover operation type exists.
- A widget draws `layer_hovered_color` or `layer_pressed_color` over its surface
  with `_push_state_layer!` (`WidgetToGraphics.jl:445`).
- The rule `PAR-WIDGETS-ARE-PRESENTATION` (`architecture-invariants.md:404-410`):
  hover, press, drag and scroll are not content; they live in cells on the node,
  are written by a self-contained operation, and are never saved.

### 6.4 Which documents show hover

Only widgets and the two charts. JSON, XML, YAML, SQL, text, syntax, the file
system and the graph domain read no motion and no crossing; they light only
when a widget draws them, as the navigator's `WidgetTree` does.

## 7. Rest today

- **A resting pointer sends nothing.** The backend sends the last sample of a
  motion once, so no reader can see a rest by itself (`TooltipRest.jl:1-9`).
- **The tooltip feed keeps the time.** `TooltipFeed` names a deadline
  (`moved_at + delay`, 0.5 s by default); the editor loop sleeps until it; at the
  deadline the feed reads `WindowInput(window, PointerRest(x, y))` through the
  editor's projection and posts the answer (`TooltipRest.jl:60-101`). By default
  it reads for the first window only.
- **The tooltip probe keeps the rest.** It records the position and the time of
  each move with no button, cancels the rest on a drag, a press, a key or a
  scroll, and closes an open tooltip when the pointer moves more than 4 pixels
  (`TooltipProbe.jl:95-134`). At rest it asks what is under the pointer
  (section 8) and opens a `:tooltip` window beside the pointer with the answer of
  `compute_tooltip`.
- **The host must wire three things by hand:** the feed, the pointer function
  and the same feed in the editor's feeds. The application and the omnet IDE
  repeat the same wiring.
- **An older tooltip mechanism remains:** `TooltipSource` with
  `TooltipDecoratorProjection`, a trigger function and a delay; only the gallery
  uses it.

## 8. "What is under the pointer" today

| Asker | When | Fake event | Reads back |
| --- | --- | --- | --- |
| Hover tracker | each move | `MouseEnter` | the target of the answer |
| Tooltip probe | at rest | Alt+left `MousePress` | the path of `ReplaceSelectionOperation` |
| Context menu probe | a right press | Alt+left `MousePress` | the path of `ReplaceSelectionOperation` |
| Inspector probe | each move | plain left `MousePress` | the path of `ReplaceSelectionOperation` |

The inspector probe keeps every move to itself, so a hover or a drag below it
gets no move, and the gallery refuses it together with the tooltip or the
clipboard (`inspector.md:82-83`).

## 9. Drags

A splitter, a tab of a pane, the pan of a chart, the slider and the reorder drag
of the dragging package all keep their own state, on the document or on the
projection, from `MouseDown` to `MouseUp`, and read `MouseMove` with a held
button. None depends on the hover tracker; the tracker gives the move to them
first. The text has no drag: `TextToGraphics.jl` reads only a press.

## 10. What the documents and rules say

- The kernel: `MouseEnter` and `MouseLeave` are made "by the code that tracks the
  region" (`MouseEvent.jl:143-145,165-166`); a synthetic event names "a crossing
  from the motion of the pointer" as an example (`EventInterface.jl:33-37`);
  `devices-and-backends.md:393-394` says the same. The recognizer calls itself
  the stage where events become synthetic events, and lists the events that pass
  it; the crossings are not among them.
- `ReplaceViewStateOperation` (`Operations.jl:207-224`): "what the pointer is
  over, what it holds down, what a drag carries … a history does not record it".
- `widget.md:64,201`: "the tracker detects the crossing; the widget sets its
  state".
- `web.md:89`: hover and tooltips do not exist in the browser.
- `screen.md:74-75`: a new path-carrying operation must join `_prefix_op`; at
  most one modal window is expected and not checked.
- No document defines hover, rest or pointing as a concept.

## 11. Gaps and inconsistencies

1. Only the first window tracks crossings, so no popup, dialog or help window
   shows hover.
2. The kernel's text places the making of crossings in a tracking stage that the
   kernel does not have; the maker is a widget projection that each host must
   add by hand, at a depth of its choice.
3. The tracker's state is on the projection instance, so one instance can not
   serve several windows.
4. A leave is routed at the last position over the old target, through the
   current layout; if the layout changed, it can reach another thing or nothing.
5. On `main` no event says that the pointer left a window, and SDL reads a
   gained focus as a lost one **[branch: both fixed]**.
6. Hover has two styles, three shapes of state (`Bool`, `Int`, a reference),
   one duplicated implementation in the table, and exists only for widgets and
   charts.
7. Four probes ask what is under the pointer, each with another fake event and
   another rule about passing the move on.
8. Rest exists only inside the tooltip package, only for the first window by
   default, and needs three pieces of wiring per host; a second, older tooltip
   mechanism remains.
9. The Tab wrap-around lives in the hover tracker.
10. Crossings need one translation per container, next to the translation of
    every other positioned event.
11. The web backend has no hover motion and never receives `blur`; it opens
    every window the same way, whatever its style.
12. A floating thing opens by two families of operation: tooltips and the
    inspector by `OpenWindowOperation`, menus by `OpenPopupOperation`.
13. The gesture help window closes only by a second F1; the file dialog is not
    modal while the widget dialog is; the widget dialog opens with the style
    `:dialog`, which no document lists and which SDL opens as a normal window
    (`WidgetToGraphics.jl:1942`).
14. The pointer position of `get_pointer_position` is global, in screen
    coordinates; the position in events is in window coordinates.

## 12. What the branch `window-leave` changed so far

- `event/WindowEvent.jl` and `event/EventModule.jl` are unsealed, with the
  owner's permission.
- SDL reads event 13 as `WindowDefocus` and ignores 12.
- `WindowLeave(; time)` is a device event; SDL reports it from event 11, the web
  client sends `leave` on `mouseleave`, and the web backend reports it.
