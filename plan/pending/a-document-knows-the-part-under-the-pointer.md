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
- [ ] 2. **The operation and the chain.** `ReplaceMouseTargetOperation(path)`
  (Q7): not an edit, re-rooted as a selection is, and evaluated at the root
  of the editor. The chain write is written for a kind of path, in a new kernel
  file: it goes down while the old and the new path agree, writes a cell only
  when its value changes, and clears the old branch below the place where the
  paths part; it has no dormant state. Tests: on `[1, [2, 3]]`, the outer array
  holds `.elements[2].elements[1]`, the inner `.elements[1]`, the number the
  empty path, a document off the path `nothing`, and a move inside the same part
  writes no cell.
- [ ] 3. **The backward map of the operation.** The default reader of a
  projection and the reader of a rule projection map it backward as they map a
  selection, and the four containers that put a prefix on by hand handle it
  (Q7). Tests: a mouse target at a text caret of the JSON chain arrives at the
  JSON document as the path of the number.
- [ ] 4. **The forward wiring** (M4, Q4). One kernel helper wires every kind of
  path of an output document from the forward map of the place, a dormant
  selection as one; the places that wire the output selection call it. A view
  that makes a widget for a part of a domain wires the widget's mouse target
  from the part's, as the tree of the workspace wires its selection; the step
  finds those views first. Tests: the mouse target of a file lights its row in
  the tree of the workspace.
- [ ] 5. **The move** (M6, M7). A container hands a `MouseMove` first to the
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
- [ ] 6. **The light** (M9). The button, the menu item and the toolbar item
  light while their mouse target is set; the list, the table, the table list and
  the tree light the row that their mouse target names; the chart and the
  sequence chart light the part that their mouse target names. `hovered` goes
  from every document and every writer. Tests: the light of each widget,
  through a real editor.
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
