# A document knows the part under the pointer

> **Status:** pending. Nothing is built. It replaces the mouse target tracker of
> step 8 of [events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md),
> so steps 8 to 12 of that plan are planned again from it.

## 1. The purpose

Each document knows which of its parts the pointer is over, as each document
knows its selection. Then a projection acts on that locally, from its own
document, and a behavior comes from composition:

- a JSON array highlights its brackets while the pointer is inside it;
- a button, a menu item and a row of a list light up under the pointer;
- a view that makes widgets for a domain lights the widget of the domain part
  under the pointer;
- a part answers a dwell with its tooltip and a right click with its menu, and
  each part around it adds its layer.

No global component decides where the pointer is or which part gets an input
(`PAR-DECIDE-LOCALLY`, `PAR-NO-GLOBAL-ROUTING`).

## 2. The owner's decisions

- **M1. The path is stored like the selection.** "Another option would be to
  store the mouse target path similarly to how the selection is stored now. So a
  mouse move could be local to a document and it's projection could handle the
  mouse enter and leave and dwel and click itself because each document would
  know the path downwards. The path would be maintained locally." (Owner
  2026-09-28.)
- **M2. A move becomes the path as a click becomes the selection.** "it should
  be done the same way a mouse click turns into selection. It would be a mouse
  move turned into replace mouse target reference or something like that."
  (Owner 2026-09-28.)
- **M3. The dwell and the click travel by position.** "The dwell and the click
  also travels by position. Must be local." (Owner 2026-09-28.)
- **M4. An introduced widget gets the path by the forward map.** "The mouse
  target path should be probably forward printed like the selection does."
  (Owner 2026-09-28.) The forward map is path to path, independent of what is
  printed (Q6 of [the-forward-image-of-a-part.md](../done/the-forward-image-of-a-part.md)).
- **M5. A route is fixed in advance only to return an operation from one
  place** (D76 of the plan of the pointer). A leave needs no route under M1,
  because a part sees from its own stored path that the pointer left it.
- **M6. A move goes to the old part and to the new part.** "the mouse move would
  first be routed by the parent towards the current mouse target child, then
  towards the new mouse target child. This allows both to react, the returned
  operations and combined and transformed backward. This solution doesn't need
  the mouse enter and leave functions. Works for projection induced widgets
  too." (Owner 2026-09-29.) `MouseEnter` and `MouseLeave` go.
- **M7. Every part on the old path gets the move.** "The mouse move is
  resistively routed down along the mouse target. Every part gets it's chance."
  (Owner 2026-09-29; read as "recursively".)
- **M8. The two kinds of answer go back differently.** "The replace mouse target
  may be transformed backward while the replace referenced value for the pressed
  state would not be transformed back and it would act upon the induced widget
  if that's the case." (Owner 2026-09-29.)
- **M9. `hovered` and `MouseHover` go.** "The hovered flag is redundant with
  the mouse target." (Owner 2026-09-29.) The owner first kept `MouseHover` ("a
  real gesture which needs to be acted upon"), and then agreed that it is not
  needed, because the gesture the owner meant was the dwell of the tooltip (owner
  2026-09-29: "Yes, I agree"). Every reader of `MouseHover` today only lights a
  row (the list, the table, the tree and the table list), which the list's own
  `mouse_target` covers; an action while the pointer moves over a part comes
  from the move itself, which travels by position and reaches the old part (M6);
  and no gesture table binds `MouseHoverPattern`. So `MouseEnter`, `MouseLeave`,
  `MouseHover` and `MouseHoverPattern` go, and `MouseDwell` stays.

## 3. How it works

Example: a pane shows the JSON document `[1, [2, 3]]`, and the pointer moves onto
the `2`.

1. **The move goes down to the old part and to the new part.** Each container
   compares the child that its own `mouse_target` names (the old part) with the
   child at the point (the new part). When they differ, it hands the move first
   to the old child, with the point moved into its frame, and the old child does
   the same with its own old child, so every part on the old path gets the move
   (M7). A part that gets a move that is not on it, while its `mouse_target` is
   set, knows that the pointer left it, and it can act: a button answers the
   clear of `pressed`, and a chart cancels its drag. Then the container hands
   the move by position to the new child, and the deepest part under the point
   answers `ReplaceMouseTargetOperation(EmptyReference())`: "the pointer is on
   me". When the two children are the same, the container hands the move once.
   A child that answers no target is the target itself, in the way that
   `read_child_event` turns a press into the selection of the child
   (`convert_to_whole_selection`). The leave of a window has no point, so the
   screen hands it only to the old child. A stored path that names a part that
   is gone skips it.
2. **The answers go up and are joined, the old part's first.** Each projection
   on the way up can change them. `ReplaceMouseTargetOperation` is a path, which
   each projection transforms backward into the path of the domain part; a write
   of `pressed` holds its own document and acts on it, also on a widget that a
   view made (M8).
3. **The editor writes the path at the root**, and each document on the path
   holds its own tail, as the selection chain does: in `[1, [2, 3]]` with the
   pointer on the `2`, the outer array holds `.elements[2].elements[1]`, the
   inner array `.elements[1]`, the number the empty path, and a document off the
   path holds nothing. Only the cells whose value changes are written, so a
   move inside the same part writes nothing, and the old branch is cleared.
4. **Each projection draws from its own mouse target**, as it draws the
   selection ring from the selection: the inner array highlights its brackets,
   and a button lights while its mouse target is set (M9: no `hovered`); a
   list lights the row that its mouse target names.
5. **The printer maps the mouse target forward into the output**, as it maps the
   selection (M4). A view that shows a file as a row of a tree maps the file's
   path to the row, and the row lights. A widget container that a view made
   reads that value to find its old child.
6. **A dwell and a click travel by position** (M3). Each reader can take them. On the way up, each container reads the gesture table of the
   child's document when the child answered nothing, or answered a tooltip or a
   menu that collects (D64): the tooltip and the context menu of steps 9b to 9d.

The mouse target is view state: a history does not record it, it is not saved,
and a copy does not take it.

## 4. What it replaces

- The mouse target tracker (`ProjecturedMouseTargetTracking`): its state, its
  routes of the crossings, its dwell route (9b/9c) and its waiting crossings.
- The gestures `MouseEnter`, `MouseLeave` and `MouseHover` with
  `MouseHoverPattern`, the routes of the crossings, and the leave route of Q35
  (M6, M9).
- The `hovered` fields of the widgets and their writes (M9).
- The walk of 9a in `read_routed_child`, because no gesture travels by route.

The gesture tracker stays: it recognizes a click and a dwell from their times.
The tooltip window and the context menu window stay: each keeps one window for
the screen, which no part can do.

## 5. Facts to check before the design is final

- How a click becomes the selection in each package: the readers that answer
  `ReplaceSelectionOperation`, `read_child_event` with its two conversions, and
  the containers that ask a child directly.
- How the selection chain is written (`replace_selection!`, `_sync_selection!`
  in `source/kernel/selection/SelectionDefaults.jl`), with its dormant selection
  and its typed paths, and which parts of it the mouse target can share.
- How the output selection is wired (`PAR-REACTIVE-OUTPUT-SELECTION`,
  `map_selection_forward` in `source/kernel/projection/ProjectionTemplate.jl`),
  and which projections that end in graphics wire it.
- Every place that reads `hovered`, `MouseEnter`, `MouseLeave` or `MouseHover`.

## 6. Open points

One at a time, with the owner.

- ~~**Q1. The names.**~~ **Settled:** the field `mouse_target`, next to
  `selection` on every document, and `ReplaceMouseTargetOperation(path)`, next
  to `ReplaceSelectionOperation(path)`. (Claude's proposal; owner 2026-09-28:
  "Yes, they fit".)
- ~~**Q2. The crossing gestures.**~~ **Settled (M6 to M9).** The ideas before it:
  each container makes the enter and the leave for its own children (Claude); an
  enter and a leave function called when the `mouse_target` is written and
  cleared (the owner), which does not reach a widget that a view makes; and a
  store of every change, drained by the editor (Claude, the owner: "way too
  complicated").
- ~~**Q3. The `hovered` fields.**~~ **Settled by M9:** `hovered` goes.
- ~~**Q4. One wiring or two.**~~ **Settled: one wiring, in the general shape,
  and the selection code stays.** About ten places compute the selection of an
  output document from the input (the rule projections of the kernel, syntax to
  text, five text transformations, the workspace view, the conversation
  editor). A shared kernel helper computes every kind of path of an output
  document from the one forward map of the place, so each place calls it once,
  and a later kind adds no wiring code. The mouse target is built as the second
  kind of that general shape: its chain write and its wiring are written for "a
  kind of path". The selection keeps its own storage and machinery; the general
  model of named selections and named colour highlights is only written down,
  in [named-paths-in-a-document.md](../tentative/named-paths-in-a-document.md).
  (Owner 2026-09-29: "Option 2", after "On the long term we should support any
  number of colour coded highlights and any number of selections".)
- ~~**Q5. The order.**~~ **Settled** (owner 2026-09-29: "Yes"), all on the
  branch `gesture-type`: (1) the documents are committed first, with no code,
  and the half-built code of step 9d stays uncommitted in the worktree; (2) the
  forward maps of [the-forward-image-of-a-part.md](../done/the-forward-image-of-a-part.md),
  whose open points are asked again first; (3) this plan; (4) steps 9d, 9e and
  9f of the plan of the pointer, and then its steps 10 to 12, planned again with
  this model.

## 7. Steps

Written when this plan starts. The last step writes the design and the user
interface documents of the mouse target, as step 11 of
[events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md) lists
them.
