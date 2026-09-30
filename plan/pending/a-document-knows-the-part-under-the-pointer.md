# A document knows the part under the pointer

> **Status:** pending; the steps are written and every open point is settled (2026-09-29). Nothing is built. It replaces the mouse target tracker of
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

## 5. Facts checked before the design (2026-09-29)

- **How a press becomes the selection.** A container hands a pointer event to
  the child at the point with `read_child_event` (`LayoutToGraphics.jl`), which
  converts the child's answer in two cases: an Alt+press makes the innermost
  document the selection (`convert_to_whole_selection`), and a plain press on a
  focusable child that answers nothing selects the child
  (`convert_to_focus_selection`). About fifteen readers answer
  `ReplaceSelectionOperation` for a press themselves: the text, the graphics
  cache, math, the graph, the table, the table list, the tree, the chart, the
  sequence chart, syntax, and two of the conversation. Four containers ask a
  child directly and put the prefix on by hand: the graph layout, the table
  list, the grid of the table, and `_resolve_click` of syntax. The answer goes up
  by `reroot_operation`, and the default reader of a projection and the reader
  of a rule projection map it backward (`ProjectionDefaults.jl`,
  `ProjectionTemplate.jl`). `evaluate_operation` writes it at the root with
  `replace_selection!`.
- **How the selection is stored.** `@document` adds the field `selection` to
  every document (`DocumentMacro.jl`), `Union{Nothing, Reference,
  SelectionDocument}`, default `nothing`; a value document declares it by hand
  as `ImmutableCell{Nothing}`, last. Many printers call the constructor of a
  document with every field and pass the selection cell last, so a second field
  needs a constructor without it. `_sync_selection!` of the sealed
  `SelectionDefaults.jl` writes the chain: it goes down while the old and the
  new path agree, writes only a cell that changes, moves a caret in place, and
  clears the old branch below the place where the paths part (or keeps it
  dormant). Every function of it names `:selection`; nothing takes the kind of
  path as a parameter. **The plan believed that the selection is not saved and
  not copied; it is both:** the binary format saves it and restores it on load,
  and a copy takes a snapshot of it (`copy_selection_cell`). A history does not
  record it (`_is_no_edit`). So the mouse target must be kept out of the save
  and the copy on purpose.
- **How the output selection is wired.** `PAR-REACTIVE-OUTPUT-SELECTION`: a
  printer sets the selection of its output to the forward map of its input's
  (`map_selection_forward`, which carries a dormant selection as one). The
  places: seven wiring points of the rule projections (`ProjectionTemplate.jl`),
  the leaf and the compound of `SyntaxToText`, five text transformations (which
  read the live property, so they drop a dormant selection), the workspace view,
  and the draft of the conversation editor. **A graphics document has no
  selection:** each painter reads the selection of its own input document, the
  rings the live property and the caret of the text the stored value. So a
  widget will draw from its own `mouse_target` in the same way.
- **What goes away.** `MouseEnter`, `MouseLeave` and `MouseHover` with their
  patterns: 126 uses in 23 files of the editor (the button, the list, the table,
  the table list, the tree, the chart and the sequence chart read them; the
  tracker is the only producer). `hovered`: the list, the button, the menu item,
  the toolbar item, the table, the tree, the chart and the sequence chart, with
  175 uses; the chart and the sequence chart keep the part under the pointer in
  it, which is their mouse target. The tracker package: `make_tracking_screen`
  builds it into every editor that `make_editor` makes, and the gallery, five
  shell tests and three omnet tests use it; inet has none of it.
  `_read_outward` in `read_routed_child` is the walk of 9a.

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
- ~~**Q6. No part under the pointer.**~~ **Settled** (owner 2026-09-29): "well,
  the screen can still hold the path, the mouse can't really leave the screen,
  no?" The pointer never leaves the screen: over no window of the editor, the
  screen itself is the part under it, and the screen holds the empty path. The
  leave of a window is `ReplaceMouseTargetOperation(EmptyReference())` at the
  screen, which the screen answers after it hands the leave to the old part, by
  the rule that a part that answers no target is the target itself. So the
  operation always holds a `Reference`, as `ReplaceSelectionOperation` does;
  `nothing` is only the value of a document off the path, and of the root before
  the first move. The backend reports only that the pointer left the windows,
  not where it is, and the screen needs no more. (Claude's proposal of
  `ReplaceMouseTargetOperation(nothing)` is dropped.)
- ~~**Q7. One operation shape for every kind of path.**~~ **Settled** (Claude's
  proposal; owner 2026-09-29: "yes"). Four containers put the prefix on a
  selection by hand (the graph layout, the table list, the grid of the table,
  `_resolve_click` of syntax), and two default readers map it backward by its
  type. `ReplaceSelectionOperation` and `ReplaceMouseTargetOperation` share an
  abstract type of "an operation that replaces a kind of path", which gives the
  path and makes the same kind with another path, and each of those six places
  handles the abstract type once, so a later kind needs no code there, as Q4
  asks of the wiring. Each kind keeps its own evaluation: the selection
  `replace_selection!`, the mouse target its chain write. The names follow the
  naming rules when the step is built.
- ~~**Q8. The brackets of a JSON array.**~~ **Settled** (owner 2026-09-29: "yes,
  you can build it, the light goes back from the innermost level several
  levels, the color fading from the light color into the default gray color of
  the delimiter"). The first example of section 1, as step 9. Each syntax node
  finds its level from its own mouse target: the number of compound nodes that
  the path passes below it. The innermost node, at level 0, draws its delimiters
  in the light colour; a node further out mixes the light colour with the gray
  of the delimiter, and it is gray after the last level. The number of levels
  and the light colour are style parameters of the syntax projection; the number
  is 4 (Claude's choice, for the owner to change). In `[1, [2, 3]]` with the
  pointer on the `2`, the inner array holds `.elements[1]` and is at level 0,
  and the outer array holds `.elements[2].elements[1]` and is at level 1.

- ~~**Q9. Which layouts get the field, and how old calls stay safe.**~~
  **Settled** (owner 2026-09-29): "I choose (b) and this field can default to
  nothing, no? So no constructors need to change, no?" Only the cell layout, the
  documents that the editor holds, gets `mouse_target`; a native layout (`M`,
  the immutable one) has none, so the simulator's objects do not change. It
  defaults to `nothing`, so no call site changes. Inside the macro two pieces
  are still needed: a document whose every field has a default has no shorter
  constructor (Rule Y needs a required field), so the macro makes the one
  without the mouse target; and the full constructor takes only a cell or
  `nothing` for it, so `CellVector(x, y, z)` with three documents still reaches
  the element sugar. The ways not taken: (a) every layout, (c) a table beside
  the documents.
- ~~**Q10. A path to a part that is gone.**~~ **Settled** (Claude's choice
  in step 2; owner 2026-09-29: "Keep it this way"). The chain write keeps the
  whole path at the root and stops at the last document that exists; no
  document below it holds a path. It is the rule that ends every path, which
  often ends inside the value of a document (a range of a string), so it needs
  no code of its own. No document claims the pointer when it is not on it, and
  the next move clears the path. A reader must not expect a stored mouse
  target to resolve: an edit that deletes the part under the pointer leaves
  the same state, so step 5 skips a stored part that is gone in every case.
  The ways not taken: cut the path at the last document that exists (the root
  then holds the empty path, "the pointer is on me", which is false), keep the
  old value (the old part stays lit), and an error (a move that races with an
  edit is normal).
- **Q11. An edit that deletes the part under the pointer.** Open: does the edit
  clear the mouse target at once, or does it stay until the next move?
- **Q14. A view that changes under a still pointer.** Open (found in step 6;
  the owner, 2026-09-30: "not sure, let's investigate this further"). The
  principle is decided: D41 and D42 of
  [events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md) say
  that after a frame that changed the display, the target is found again at
  the last position of the pointer, and D3 does not allow a made-up move. Only
  a move writes the mouse target now, so after a scroll under a still pointer
  the old row stays lit until the next move. The two assertions of
  `ScrollPaneHoverTest` that check D41 are marked broken.
  Facts (investigation, 2026-09-30):
  - Only the SDL backend makes a `DisplayUpdate`: after a frame in which the
    canvas of a window differs from the frame before, at most one waits for
    each window, and the loop reads it before it sleeps. The web, video and
    console backends make none, so D41 does not hold there today either.
  - The tracker is the only reader of a `DisplayUpdate`, and the only keeper of
    the last point (its state `position`, set by a move, cleared by the leave of
    a window). It finds the target again only for the window of that point.
  - A popup that opens reports a `DisplayUpdate` with the id of the popup, not
    of the window of the pointer, so the tracker does not find the target again
    then. A popup that closes reports none, for either window. So D41 has gaps
    today for a popup that opens or closes under a still pointer.
  - The dwell recognizer keeps a point too, but a scroll clears it.
  The ways the facts allow:
  - (a) The tracker stays for this, and writes the mouse target too. Against:
    step 8 removes the tracker, and it keeps a second last point.
  - (b) The screen keeps the window and the point of the last move as view
    state, and on the `DisplayUpdate` of that window it answers the part at that
    point by the backward map of the point (`compute_part_at_point`), which is
    no move. Against: no reader of a part runs, so a part that keeps more than
    its light (the cursor readout of a chart) stays as it was until the next
    move; and the popup gaps stay unless the screen also answers on the
    `DisplayUpdate` of a window that opens, and the backend reports a close.
  - (c) As (b), with the point kept by each window. Against: the leave of a
    window must clear it, which the screen does once for all windows today.
  - (d) The dwell recognizer keeps the point for this too. Against: a scroll
    clears it, and it mixes the dwell with the target.
- **Q13. A drag.** Open in part. Under M6 and M7 alone, a dragged part (a
  slider thumb) gets only the first move off it: then the mouse target follows
  the pointer and the part is on no path. Claude's options were a capture (the
  mouse target stays on the pressed part while a button is held) and no capture
  (the containers keep their drag fallbacks). The owner's model (2026-09-30):
  "The dragging projection could store the path to the drag start and route the
  move there. It's s legitimate global control ... so the mouse target would be
  unaffected and still light what's under the mouse." Then: "there are two
  kinds of drags, local and global. A local drag is one where only one document
  part is affected, it should not need the dragging projection but could still
  share functios to avoid reinventing the wheel. A global drag is when multiple
  documents are affected, like dragging a pane in the tree, or during dragging
  one document part into another part which accepts it. This needs a bit more
  thinking." And: "I don't like storing the drag target in the gesture
  recogniser." Settled so far:
  1. A local drag keeps its path in the close parent that the drag is local to,
     not along the whole chain and not in the mouse target (owner: "the local
     drag is usually local to some close parent, so the path should be stored
     there").
  2. A part says that it accepts a dragged thing through a function (owner:
     "why not a function simply?"), not through a probe.
  3. A drag that starts local and becomes global is not supported now.
  So step 5 is two steps: 5a routes a move with no button held (the old part,
  then the new part); a move with a button held keeps today's routing, so no
  move reaches a part twice and no drag breaks. 5b is the drag, once its design
  is settled; it replaces the routing of a held button and the containers'
  drag fallbacks.
- ~~**Q12. The step 3 scope and an introduced part.**~~ **Settled** (owner
  2026-09-29). Step 3 found 75 readers in 33 files that take the selection by
  type, 29 `isa` checks in 17 files, and 7 places in omnet, where the plan had
  counted six. Three ways were put: (a) every reader takes the supertype of Q7,
  (b) the kernel asks the selection reader and converts the answer, (c) only
  the chains that the brackets need. Owner: "I like (a)". Claude's sketch of a
  reader kept the fallback that puts a flat offset of the text into an
  introduced reference; owner: "No, an introduced part should also be mapped
  forward and backward too. Some projections already do this at the innermost
  part" (the atomic wiring of the rule projections). So step 3 is two steps:
  3a makes an introduced part map both ways, and 3b is the sweep of (a).
  Owner: "Yes, but I prefer the mapper functions as one reference_case if
  possible. Add this to the rules in the documentation". The rules are in
  `PAR-CROSS-DOMAIN-LATE`, `PAR-MAPPERS-ARE-INVERSES`, `PAR-REFERENCE-DSL` and
  `PAR-PREFER-REFERENCE-RETARGET` of
  [architecture-invariants.md](../../documentation/rule/architecture-invariants.md).

## 7. Steps

Each step ends with a commit, a wide sweep against the counts of the step
before, and the omnet tests. The files of the kernel that change are unsealed
already; the sealed selection files do not change (Q4).

- [x] 1. **The field.** `@document` adds `mouse_target`, `Union{Nothing,
  Reference}`, default `nothing`, next to `selection`, and a value document
  declares it as `ImmutableCell{Nothing}`. The macro also makes the positional
  constructor without it, so the calls that pass every field but it still work.
  It is view state: the binary save skips it and a load gives `nothing`, a copy
  gives `nothing`, and a history does not record it. Tests: the field on a
  document, the save, the copy.
  Built (Q9): `@document` adds the field after the native layout is written, so
  only the cell layout has it, and only where it adds `selection` itself; a value
  document, which declares its own selection, has none and stays isbits. The
  full constructor types the parameter "a cell or `nothing`", and turns
  `nothing` into a cell when every other argument is a `ReactiveCell{Any}`, so a
  call with the old fields stays on the fast path. `_emit_mouse_target_ctor`
  makes the constructor without it for a document with no required field, and
  the kind constructors `ICFoo` and `MCFoo` get the same form, because
  `CellVector.jl` calls them with the old fields. `is_view_state_field(name)` of
  the document module is true for `selection` and `mouse_target`, and the
  places that skipped the selection as state skip both: `show`, the walk (which
  never enters the mouse target), reflection, focus, searching, the object views,
  formulas, and the file formats `PredFile`, `FileCut` and `FileSplice`. A copy
  (`copy_document_fields`, `FileCut`) and the output of `CopyingProjection`
  start with `nothing`; step 4 wires the output. The binary save writes the whole
  document with Julia's serializer, which can not skip a field, so
  `load_document` clears every mouse target instead. The marker of a bounded
  sync counts the fields that are not view state. The sweep over the examples
  has one pass more for each output document (7138), because it tests every
  cell and each document has one more. Tests: `test_document_macro()` (the
  field, the native layout and the value document without it, the old calls,
  the copy, `show`) and `test_mouse_target_field()` (three documents are three
  elements, the walk, the save and the load).
  More loops named only `:selection` as state: the dirty check of the SDL and
  web backends, `show` of a widget, `child_reference_steps` of the kernel, and
  in omnet the fields of a parameter container (`get_parameter_field_names`) and
  the list of choices of a simulation embed. They use `is_view_state_field`, and
  so do nine test helpers that walk the fields of a document. One of them,
  `_node_slots` of the construct test, took the mouse target for a scalar slot
  to type, so a number and a boolean were built as containers and lost every
  key after the first; its feed swallows exceptions, so the test showed only
  the wrong value. The inet header codec drops a last field named `selection`;
  it reads a header's native struct, which has no mouse target. The inet
  packet tests pass on the branch in a scratch environment whose packages are
  the three worktrees (18260 passes). The census of the omnet campaign test
  asks the predicate of the fields of a tuple, which are numbers, so it takes
  any name. Checks: the wide sweep has the counts of the baseline in every
  suite, with more passes in the kernel (the new checks) and the substrate (one
  cell for each output document, and the new test); the omnet tests have their
  results; the naming guard passes and the documentation check has its notes.
- [x] 2. **The operation and the chain.** `ReplaceMouseTargetOperation(path)`
  (Q7): not an edit, re-rooted as a selection is, and evaluated at the root
  of the editor. The chain write is written for a kind of path, in a new kernel
  file: it goes down while the old and the new path agree, writes a cell only
  when its value changes, and clears the old branch below the place where the
  paths part; it has no dormant state. Tests: on `[1, [2, 3]]`, the outer array
  holds `.elements[2].elements[1]`, the inner `.elements[1]`, the number the
  empty path, a document off the path `nothing`, and a move inside the same part
  writes no cell.
  Built: `ReplacePathOperation` of the operation contract is the supertype of
  `ReplaceSelectionOperation` and `ReplaceMouseTargetOperation`;
  `get_operation_path` reads the path and `make_path_operation` makes the same
  kind with another path. `reroot_operation` has one method for the supertype,
  and the undo filter drops the supertype, so a later kind needs no code there.
  The chain write is `replace_path_chain!(document, field, path)` in
  `operation/PathChain.jl`, and `replace_mouse_target!` calls it with
  `:mouse_target`. It keeps the path without its types, writes a cell only when
  the value changes, finds the child of the first step of the old and of the new
  path, clears the old child's chain when the two differ, and goes on into the
  new child with the tail. A step that reaches no document stops the chain, so
  a path to a part that is gone is kept at the root and goes no deeper. The
  inverse of the operation is `DoNothingOperation`: taking an edit back does not
  move the pointer. Tests: `test_mouse_target_chain()` (the chain on
  `[1, [2, 3]]`, no write for the same path, the clear of the old branch, the
  types, a path to a part that is gone, the operation at the root, re-rooting,
  the inverse, the description) and a check in `test_undo_buffer()`. Checks:
  the wide sweep has the counts of step 1 in every suite, with 29 passes more in
  the substrate (the new test); the omnet tests pass; the naming guard passes
  and the documentation check has no note on the changed files.
- [x] 3a. **An introduced part maps forward and backward** (Q12). Each
  projection that puts a flat offset of a later stage into an introduced
  reference (about 34 places, `PositionReferenceStep(flat)` after
  `_syntax_to_flat`, in the collection, SQL, math, the book, markdown and
  others) wraps its own output path instead, and its forward map answers that
  path (`proj(^(p), inner) => inner`); the flat branch of `_syntax_to_flat` for
  another projection's step goes. A child path maps through the child's own
  map, not by a change of its head only. Each mapper that changes is one
  `@reference_case`. `SyntaxCompoundToText` keeps its flat offsets, which are
  positions in its own output. The selection changes too: a caret on a bracket
  holds the output path of the node that printed it. Tests: a caret on a
  bracket goes back and forth in each domain that changes, and lands where it
  landed before.
  Facts (survey of 2026-09-29, about 145 projection types): the rule template
  already wraps an introduced part at the child that printed it
  (`_map_child_backward`), and its rule reader wraps `op.path`; only its forward
  maps passed their own step on, and so did about 16 hand-written node
  projections (`proj(^(p), _) => reference`) and 12 that pass on the step of
  any projection. The flat offset comes from readers that override the
  template (SQL 10 leaves in one method, math 13, FSM 5, process 6, XML 1)
  and from hand-written nodes (SQL 20, book 3, math 3, the database catalog 4,
  the collection 1). Hand-written backward maps answer `nothing` for their own
  parts, and their readers wrap. Several leaves share their selection cell with
  their input (primitive, math variable, Julia insertion, formula) or compute
  it by hand (book, math, markdown and rst styled text, insertion), so the
  input holds paths typed for the output; `SyntaxToText` reads the step of any
  projection in three places (`map_reference_forward` of the compound,
  `_leaf_cursor`, `_syntax_to_flat`) and in two arms of the leaf's forward map.
  The order of the work: the template overrides go; the hand-written nodes
  wrap their own parts in the backward map and unwrap in the forward map; the
  leaves get a forward-mapped selection cell; last, `SyntaxToText` reads only
  its own step. `test_fsm()` and `test_process()` fail on main (their tables
  put the Julia table's `Document` fallback first), so they can not check the
  FSM and process changes.
  Built: the forward maps of the rule template answer the path of their own
  introduced step (`find_introduced_path`), as the atomic wiring did; the
  readers that put a flat offset on top of the template go (SQL leaves and
  join, math 13, FSM 5, process 6, the XML element), and so do their forward
  overrides, so the rule reader wraps `op.path`. The flat offset was there
  because the forward maps passed the wrapped path on: the keyboard reader of
  the syntax tree built the next path from that output selection, and each
  move wrapped the path again. The hand-written nodes (SQL 20, book 3, math 3,
  the database catalog 4, the collection, markdown 5, rst 3, YAML 1, the file
  system directory) take off their own step in the forward map and wrap, in
  the backward map, every path that reaches no child: a last arm
  `__ => make_introduced_reference(p, iomap.input, reference)`, and the early
  `nothing` answers of the arms, inner blocks included. Their readers only map.
  The collection maps a child path through the child's own backward map.
  The leaves that shared their selection cell with their input (the three
  primitive leaves, the math variable, the Julia insertion, the two formula
  leaves) map it forward into a cell of their own, so the input holds a path of
  its own domain; their value arms take a range (`{s:e}`), which also covers a
  caret. The cells that compute an output selection by hand (book 3, math 3,
  the insertion, markdown and rst styled text) take off only their own step;
  making their forward maps cover every case, so that these cells can go, is
  left for later. An edit of a part that a projection printed has no input
  pre-image: the kernel predicate `has_introduced_step` (from the private
  `_targets_introduced_output` of the template reader) makes the default reader,
  the template reader and ten hand-written edit readers decline it, where the
  backward map answered `nothing` before. The mapper contract in
  `ProjectionInterface.jl` states the rule.
  Found while checking: the rule template wrapped a node's own part only in its
  reader, so a hand-written parent that calls the child's backward map got
  `nothing` (the `USING (…)` of an SQL join); the backward map of the template now
  wraps it, and a sub-node slot, which sees the parent's path without its
  `.children[k]` step, maps through the wiring alone so that the parent wraps the
  whole path. A backward map wraps the output path with its node types
  (`make_introduced_reference(p, iomap, path)` types it against `iomap.output`),
  because a parent splices the unwrapped path into an `@reference` literal, which
  rejects an untyped path. `SyntaxCompoundToText` knows its own step by type, not
  by identity: each instance holds text markers of its own. The "searching"
  example no longer throws, and `filesystem` and `navigator` seed a caret, so
  their broken markers go. In the graph example the corner of a vertex is on the
  `{` that the object prints, so the point names that brace (Q12), where it named
  the vertex before (owner 2026-09-30: "Yes, I accept"). "Lands where it landed
  before" was checked by the rendered
  caret places of every reached state, old code against new: the three SQL
  documents and `book` reach every place of the old code, and the nested SQL
  document 7 more (the old code had two names for some carets).
  Tests: `test_introduced_part_round_trip()` (every caret of `[1, [2, 3]]` goes
  back and forth; the inner array names its own `[`; no introduced step of the
  collection holds an offset of the text) and a check of the corner point in
  the graph test. Checks: the wide sweep has the counts of step 2 but more
  passes (the substrate 851 more, the new test and the examples that now reach
  more carets); the position navigation passes 437 more with the same 3
  failures and 2 broken where there were 6; the tree navigation 84 where there
  were 70; the text navigation invariants 11 more passes with the same
  failures; the SQL, book, markdown, rst, YAML, XML, catalog, JSON, math, file
  system, FSM and process suites, the type-in sweep and the repl sweep have
  their counts; the omnet tests pass; the naming guard passes, and the
  documentation check has its notes. The domain documents (FSM, math, XML, SQL),
  the projection system guide, the testing guide and the reference document
  state the rule.
- [x] 3b. **The backward map of every kind of path** (Q7, option (a)). The 75
  readers in 33 files that take `ReplaceSelectionOperation` by type, and the 7
  places of omnet, take `ReplacePathOperation` and answer
  `make_path_operation(operation, path)`; a reader that only does what the
  default reader does goes, where no catch-all of its projection hides the
  default. The 29 `isa` checks in 17 files are read one at a time: a check
  that maps a path takes the supertype, and a check that belongs to a press
  (the focus, the whole selection of an Alt+press, the drag) keeps the
  selection. Tests: a mouse target at a text caret of the JSON chain arrives at
  the JSON document as the path of the number, and the pointer on the inner
  `[` of `[1, [2, 3]]` leaves `‹.open{0}›` in the inner array.
  Built: 67 readers in projectured take `ReplacePathOperation` and answer
  `make_path_operation(op, path)`, with the kernel default reader, the rule
  reader, the disambiguation of the recursive projection and
  `_annotate_operation`. Of the 29 `isa` checks, 18 re-root or map a path and
  take the supertype (the graph's click and key routers, the table list's cell
  click, entry and pass-through, the table's cell click, entry and grid
  pass-through, `_retarget_op` of the widgets and of the assistant, `_prefix_op`
  of the screen and of the versioning, the workspace readers, the tab prefix,
  the control bar of the configuring projection) and the default filter of
  the gesture log, which drops every kind of path as noise; 11 belong to a
  press and keep the selection (the Alt+press whole selection, the click
  resolution of the syntax, the Alt+click inside a page, the click in a part
  of a conversation, the whole-selection press of omnet's filter, and the
  probes that make a click of their own: the hover probe, the context menu
  probe, dragging). `ObjectToWidget` and `ReflectionToWidget` decline every
  kind, as they declined the selection. In omnet the form and the embed map
  every kind; the catalog shell and the workflow turn a selection into an
  action (open a page, select a run), so they keep that method and get one
  more that only maps any other kind; the result frame maps nothing. The
  readers that only map were kept, not deleted: a catch-all of their
  projection hides the default reader in most of them (SQL), and a deletion
  adds a dispatch risk for no function. Tests: `test_every_kind_of_path()`
  (on `[1, [2, 3]]` through the collection and the text stage, because the
  substrate tests can not use the JSON package: every caret maps a mouse target
  back to the path of the selection and keeps its kind; the pointer on the
  inner `[` leaves the inner array holding its own step at `.open`, and the
  outer array `[2]` and the rest).
  Checks: the wide sweep and the suites of step 3a have the counts of the 3a
  sweep in all 46 suites, with 410 more passes in the substrate (the new test);
  the repl sweep in a fresh process has its baseline (23172 and 5 broken); the
  omnet tests pass; the naming guard passes, and the documentation check has
  its notes. The kernel docstrings of the default reader, the projection
  system guide, and the undo and gesture log documents name every kind of path.
- [x] 4. **The forward wiring** (M4, Q4). One kernel helper wires every kind of
  path of an output document from the forward map of the place, a dormant
  selection as one; the places that wire the output selection call it. A view
  that makes a widget for a part of a domain wires the widget's mouse target
  from the part's, as the tree of the workspace wires its selection; the step
  finds those views first. Tests: the mouse target of a file lights its row in
  the tree of the workspace.
  Built: `make_output_path_cells(input, map_forward; dormant = true)` in the new
  kernel fragment `OutputPaths.jl` gives the cells of every kind of path from the
  one forward map of a printer, as keywords for the output's constructor, and
  `set_output_path_computations!` sets them on an output that is built already;
  `map_mouse_target_forward` serves a printer whose selection cell is its own.
  `dormant = false` maps only a live selection, for a widget that routes keys
  by its selection (the conversation cards, the draft body, the assistant).
  About 70 places wired a selection, not the ten the facts counted: the rule
  template (seven builders and the key leaves, through `_with_output_paths`),
  28 hand-written domain printers, the leaves, the screen, the copy, sort,
  filter and search projections, the text stage (the syntax leaf maps the path
  it gets, `_leaf_cursor(leaf, path)`; the compound keeps its composed selection
  and maps the mouse target with cases 1 to 3 of the composer, because the
  chain write gives it the whole path), the five text transformations, the
  primitive text, and the views (the workspace, the file system tree, the
  database instance, the embed card, the markdown and rst layouts and table,
  the conversation, the pane, the assistant, the object field, the widget's
  plain text view). The math, book and pane selection cells stay their own; the
  pane keeps a dormant path as a plain one on purpose. A printer that passed a
  live selection now carries a dormant one, as `map_selection_forward` intends,
  except where keys route by selection. `follow_output_selection!` takes a
  `forward_mouse_target`. omnet's views (about 15 places) follow in a commit of
  their own.
  Found: the text navigation invariants skip the collection examples ("lacks
  read_intent") and `sql_nested_syntax` (a revisit of an introduced caret) for
  faults that step 3a can have removed; to check later, with a fresh document.
  With the dispatch fix of FSM and process (55378d751), the large `fsm` example
  takes half an hour in a text walk and hours in the click round trip, so both
  sweeps skip it; `fsm_toggle` covers the notation.
  Tests: `test_output_paths()` (the syntax node of each array of `[1, [2, 3]]`
  holds the part under the pointer in its own terms), a check of the rule
  template in `test_json_to_syntax()`, and the workspace tree in
  `test_workspace_to_filesystem()`: the pointer on the row of `sub/c.jl` maps
  back to the folder, and the tree holds that row. The light is step 6. Checks:
  the wide sweep has the counts of step 3b, with the new tests and the FSM
  fix's changes; the repl sweep in a fresh process has its baseline; the omnet
  tests pass; the naming guard passes, and the documentation check has its
  notes. The substrate example sweep counts 287 cells fewer when other suites
  run before it in a different order; the per-example counts of step 3b, 4a
  and 4c are equal (88774) when each example runs alone.
  Left: omnet's views (about 15 places). Several of them keep a selection as
  state, such as the chosen type of the catalog list, and do not map a path
  forward, so each needs a small design of its own; they follow with step 6,
  when it is known which of their widgets light (owner 2026-09-30: "Yes, I
  agree").
- [ ] 5. **The move** (M6, M7; 5a now, 5b the drag, Q13). A container hands a `MouseMove` first to the
  child that its own mouse target names, along the old path, with the point in
  that child's frame, and then to the child at the point; when both are the
  same child, once. `read_child_event` makes a move that the child answered
  with nothing into `ReplaceMouseTargetOperation(EmptyReference())` for the
  child, as it makes a press into a whole selection. A container that reads its
  own parts, such as a list, a table, a tree, a chart, a text and syntax,
  answers the path of its part under the point. A part that gets a move not on
  it while its mouse target is set answers what the leave means to it: the
  button clears `pressed`. The screen hands a move in another window, and the
  leave of a window, to the old window first; after the leave of a window it
  answers the empty path, the screen itself (Q6). Tests: moves across the JSON
  document, across a composite of buttons and across two windows write the
  chains of step 2; a press held on a button and moved off clears `pressed`.

  **5a, a move with no button held: done.** Built:
  - The shared pieces. `is_move_without_button` is in the event module of the
    kernel. `get_mouse_target`, `add_mouse_target(answer, path)`,
    `has_mouse_target` and `join_move_answers` are in `PathChain.jl`.
    `compute_part_at_point`, `read_child_move`, `read_child_leave` and
    `get_child_frame_offset` are in the new graphics fragment `ChildMove.jl`: the
    point step lives in graphics, and the screen, the layout, the widgets and
    the graph all use them.
  - A child that the pointer leaves gets the move at `(-1, -1)` of its own
    frame, as the old window does. The first version gave it the real point in
    its frame, and the review found two faults: a pane that clips its content
    gave the content a point on a part scrolled out of view, and in a stack a
    child under another child took the point as its own, so two paths reached
    the root.
    `read_child_event` gives a move to `read_child_move`.
  - The part readers need no code of their own. When the child under the point
    names no part, its own backward map of the point names it
    (`compute_part_at_point`), the map that the tracker uses today. So the maps
    that exist name a row of a list, a table, a tree and a table list, a cell of
    a widget table, and a place in a text. The text names the caret position
    nearest the point, `{k}`, the place that a click there selects, not a range
    of one character.
  - The containers: the layouts (the flow and the stack), the composite, the
    card, the accordion (a header is its item `items[i]`), the scroll pane and
    the transform pane (the view, and a hit on the content), the tabbed pane (a
    header is its `selector`), the split pane (a splitter is the pane itself),
    the context menu, and one generic reader for the tooltip, the menu, the
    title pane, the toolbar, the dialog and the shell. The generic reader finds
    a child by identity (`_find_child_steps`) and takes the topmost child at the
    point, as a point maps back. The graph layout gives the move to the content
    of a vertex, and a point in the box of a vertex but off its content is the
    vertex. The graph pipeline matches typed paths only, so the graph types a
    widget's path against the content of the vertex.
  - The screen. A move in another window, and the leave of the window that the
    pointer is in, give the old window a move to `(-1, -1)`, a point off it. The
    backend does not say where the pointer is after a leave, and windows can
    overlap (a popup over the main window), so a point in the frame of the old
    window can still be on it. After the leave the screen holds the empty path;
    a late leave of another window changes nothing. A window whose content
    names no part is the part itself, after the content's own point map.
  - The button clears `pressed` when a move off it reaches it. The chart and
    the sequence chart keep their own hover until step 6, and a move off them
    clears it.
  - Step 4 missed eight views that map the selection forward: the graph layout,
    the two stages of the FSM and of the process diagram, the collection
    layout, the chart and the sequence chart. Without the mouse target in their
    output, no container in the output finds the child that the pointer leaves.
    Each now wires it with `map_mouse_target_forward`, beside its selection.
  - A mouse target in a tabbed pane always takes the `.element` step, so the
    chain write reaches the document of a page that is a widget. The selection
    keeps its old form, which the pane also reads.
  - The chain write of step 2 kept each path without its types. A forward map
    builds a typed `@reference` from the mouse target, and the map of the
    assistant failed in the repl sweep. So each document now holds its path
    typed against itself (`annotate_reference_types`), and a write compares
    the paths without their types.
  Tests: `test_mouse_target_move()` (a composite of buttons, the leave of a
  pressed button, a card with a layout, a list, the split pane, the tabbed pane
  and the shell in a window, and two windows) and `test_json_mouse_target()`
  (`[1, [2, 3]]`: the `2`, the `1`, and the bracket that opens the inner array,
  which is a part of that array). The move test also covers a scroll pane that
  clips its content, a stack where one child lies over another, and a page of a
  tabbed pane that is a widget. The tooltip test now expects a move to answer
  the part under the pointer, and the test driver of the tracker writes the
  mouse target at its root, as the editor does.
  Checks: the wide sweep has the counts of step 4 with the new tests (substrate
  +56, JSON +12); the repl sweep in a fresh process has its baseline; the domain
  suites and the omnet tests pass as in step 4; the naming guard passes, and the
  documentation check has its notes. A review of the diff found the faults that
  the bullets on the leave, the tab path and the eight views describe.
  Left: the new tests apply the answers with `evaluate_operation`, not through
  an editor; step 6 tests the light through a real editor. The click route of
  the graph now also types a widget's path against the content of the vertex,
  which no test covers.
- [ ] 6. **The light** (M9). The button, the menu item and the toolbar item
  light while their mouse target is set; the list, the table, the table list and
  the tree light the row that their mouse target names; the chart and the
  sequence chart light the part that their mouse target names. `hovered` goes
  from every document and every writer. Tests: the light of each widget,
  through a real editor.
  Built so far (projectured):
  - `_is_under_pointer(w)` reads the mouse target of a widget. The button, the
    menu item and the toolbar item light from it; the menu item reads it where
    it builds its surface, not in its measure, so a light changes no extent.
  - The list lights the row `items[i]` of its mouse target, the table the row
    or the column of `_find_wt_lit_reference(target)`, the table list the whole
    row of `_find_wtl_lit_row(target)`, and the tree the node path of its mouse
    target. A point that names no row lights no row: the tree and the table
    kept the old light on such a point before, and the light no longer has a
    state that could keep it.
  - The chart computes the lit series in its element pass, which each move of
    the cursor runs already, and not in its layout. A series lights, and the
    others are veiled, when the pointer is on its line or on a sample of it, as
    on its legend item; before, only the legend item did this. The sequence
    chart lights the event or the arrow of its mouse target. Both readers write
    only the cursor on a move.
  - `hovered` is gone from the six widgets and the two plots, with their
    constructors and the three views that pass every field. The readers of
    `MouseEnter`, `MouseLeave` and `MouseHover` that wrote it are gone; the
    button still ends its press on a `MouseLeave`, which a drag needs until
    step 5b.
  - The style parameter `layer_hovered_color` keeps its name: it names a colour
    of the theme, not a state of a document.
  Tests: `test_pointer_light()` (in the shell tests, which drive a headless
  editor) counts the rects that a real editor draws in the colour of the light
  for a button, a disabled button, a menu item, a toolbar item, a list, a table
  (a row and a column) and a tree. The tests of `hovered` check the mouse target
  now; the test driver of the tracker does what a window does with a move, and
  the test view `MttContactsToWidgets` maps the mouse target forward. The two
  assertions of D41 are marked broken (Q14).
  Found:
  - A fault of step 5a: the reader of `LayoutConstraintToGraphicsCanvas`
    passed the child's answer up with no `child` step, which its backward map
    adds. So a path from inside a constraint skipped a step, and the chain
    write stopped at the constraint. The reader now adds the step.
  - A widget that a hand-written view makes lights only when the view maps the
    mouse target forward into it. The reader of such a view maps the part under
    the pointer back to an introduced part (Q12), and the forward map must
    answer that part with the path inside the output (`find_introduced_path`),
    as the Q12 rule asks. Step 3a gave this arm to the rule templates; about 8
    hand-written views in projectured (the assistant, the conversation, the
    evaluator, the pane, the file system, the markdown and rst layouts) and
    about 7 in omnet lack it. The omnet runner (the filter view) now passes
    `forward_mouse_target` to its walk and wires its table, but its forward map
    still answers no introduced part, so its button and its table do not light
    yet; `test_campaign_hover` and the IDE test of the Run button fail. The
    other omnet views need the wiring of the mouse target as well: the catalog
    list, the tables and the lists of the workflow, the optimization table, the
    batch buttons, the embed toolbar, and the three syntax views.
  The views (owner 2026-09-30: "For 1, this step"). Built:
  - A view that makes its own widgets needs three parts: its forward map
    answers its own introduced part (`find_introduced_path`); it walks its
    output for the mouse target (`follow_output_mouse_target!`, new in the
    focus package, the walk of `follow_output_selection!` for the mouse target
    alone); and its reader maps a path of every kind backward. A reader that
    knows only some parts (a list row, a form field) falls back to its own
    introduced part for the part under the pointer, and not for the selection,
    so a click beside a row still selects nothing.
  - The default reader of the kernel, and the widget containers' re-root, map
    the members of a move's answer one by one and leave out a member with no
    image; any other compound still goes back whole or not at all. So a part
    that one view cannot map does not drop the leave of a button with it.
  - projectured: the reflection view names its rows and wires its tree.
  - omnet, about 20 views (the runner, the optimization, the batch, the task,
    the result, the federation, the find view, the topology, the capture table,
    the dashboards, the execution, session and checkpoint views). Three needed
    more than the three parts:
    - The workbench prints the simulator's workflow view inside itself and
      threw its IO map away; it keeps it now and delegates both maps and its
      reader to it (the `sim` part).
    - The workflow view maps a row of a registered list or table forward as
      the inverse of its registry. The registry keeps the lists of earlier
      prints too, which a forward map passes over; that the registry grows with
      each refresh is an older fault, left as it is.
    - The catalog shell mapped every page as `page.content`, the root of a
      markdown page; a simulation entry shows the entry itself, so both maps
      now take the steps that `_open_content` opens.
    - The embed prints its panes inline, and a pane's builder keeps no IO map,
      so a part of a pane is a part of the embed: its walk enters every widget
      and layout of the panes, and stays out of a document of the domain that a
      pane shows in a widget.
  - An older fault on the branch: the embed used `is_view_state_field` with no
    import (from `98706cca`); `test_pane_choices` found it.
  Checks: in a sweep of moves, the catalog list and three of the four buttons of
  the workbench light, the catalog navigator lights, and six of the eight
  buttons of a simulation page of the catalog light. The omnet test sets have
  the failures of the older wide run only, and the projectured sweeps have their
  baselines with the three new assertions of the reflection tree.
  Left: a document of the domain that a view shows inside a widget, and that a
  second view draws later, gets no mouse target: the reflected tree of the
  inspector pane. The chain stops at the introduced part of the outer view, and
  the outer walk stays out of the document, because the chain write holds the
  mouse target of such a document when a mapped view (the form) shows it.
- [ ] 7. **The dwell and the right click by position** (M3, D76). The outward
  reading of the gesture tables (D64) runs in the helpers that hand a pointer
  gesture to the child at its point; `_read_dwell` of the tracker and the walk
  of `read_routed_child` for a gesture go. Tests: the tooltip tests, and a dwell
  in a second window.
- [ ] 8. **The tracker goes.** `ProjecturedMouseTargetTracking`, the gestures
  `MouseEnter`, `MouseLeave` and `MouseHover` with their patterns, the routes of
  the crossings, the leave route of Q35 and the timer of the waiting crossings.
  `make_tracking_screen` keeps the gesture tracker. The hosts follow: the
  gallery, the application, the shell tests, and the omnet IDE and campaign
  tests.
- [ ] 9. **The brackets** (Q8). A syntax node draws its delimiters in the light
  colour at level 0 and fades them to the gray of the delimiter over the
  levels further out. Tests: in `[1, [2, [3]]]`, a move onto `3` lights the
  innermost brackets fully and the two outer pairs less and less; a move off
  the document leaves every delimiter gray.
- [ ] 10. **The documents.** `package/kernel/mouse-target.md` and
  `guide/pointer-guide.md`, as step 11 of
  [events-gestures-and-the-pointer.md](events-gestures-and-the-pointer.md) lists
  them, and the widget, selection and screen documents. Then steps 8 to 12 of
  that plan are planned again from this model: 9d, 9e and 9f, the drag of step
  10, the rules and the documents of step 11, and the check of step 12.
