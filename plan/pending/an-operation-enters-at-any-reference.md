# An operation enters at any reference

**Status (2026-09-23): IMPLEMENTED IN projectured-julia, on the branch
`selection-root`.** Steps 1b, 2 and 3 are done there, with the guides and the
audit of `DocumentWalk.jl`. Open: omnet-julia (it needs the projectured-julia
part visible to it), sealing `DocumentWalk.jl` again, and the docstring of
`search_references` in the sealed `ReferenceSearch.jl`; each waits for the
owner's word.

**Goal:** code that is not the editor loop — a verb, the assistant, an MCP tool,
a test, a replay, the start of an application — can do anything a person can
do, and the reader pipeline of the whole editor treats it as it treats a person.
The caller already knows what it wants, so it gives an operation at a place.
The place is a reference, and the readers route along it. At the place the
operation stands where the reader of the place would put its answer, and every
reader on the way out transforms it, as for a gesture of a person.

**Repositories:** projectured-julia, then omnet-julia.

**Rules this plan keeps:** PAR-SELECTION-WRITTEN-AT-ROOT and
PAR-NO-NEW-SYNTHETIC-EVENT (both added on 2026-09-23), PAR-RECURSION-CONTRACT,
PAR-READER-IS-PURE, PAR-DELEGATE-AND-LIFT.

## 1. The problem

The live selection is one path from the root, and each document on it holds its
suffix. PAR-SELECTION-WRITTEN-AT-ROOT says that every write of it starts at the
root, and that a reader reads only its own selection.

Only a gesture has a route to the root now. A gesture goes through the readers,
and each reader on the way out lifts the operation: it reroots it, maps an index
back, or changes its type. Code that is not a gesture has no such route. It
holds an inner document and writes there. Three kinds of code do this:

1. **A verb** (`open_pane!`, `focus_pane!`, a menu action) says its edit with a
   path from the document it knows, the pane tree, and writes it on that
   document.
2. **An evaluation** sets a selection below the root while it runs
   (`SelectTabOperation`, `ReloadFileOperation`).
3. **A composition** builds a document with a selection and then puts it into a
   larger tree. The application builds the pane tree with its focus, and then
   puts the undo buffer, the shell and the clipboard around it, which hold none.

The clipboard's search below itself (`_get_clipboard_selection`) is a symptom:
it exists because parts 1 to 3 leave its own suffix wrong.

### The example: `focus_pane!` in the application window

Measured on 2026-09-23 in the window as the binary opens it, after
`focus_pane!(editor, where)` on the navigator tab:

```
ClipboardSlice    nothing
WidgetShell       nothing
UndoBuffer        content.root.elements[2].tabs[1].content.content    ← old: the file
PaneTree                  root.elements[1].tabs[1]                    ← new: the navigator
```

Ctrl+C then copies nothing. `where` is a path from the tree, and
`apply_pane_operation!(tree, …)` evaluates against the tree as if it were the
root.

### Why the path alone is not enough: the sorting example

A sorting projection shows a set of elements in another order. An operation on
the third element *as shown* must reach the document as an operation on the
element *where it came from*. Only the reader of the sorting projection knows
that map. So code that acts on a projected element can not make the operation
itself and add a prefix: it must go through the reader pipeline, and every
reader between the place and the root must have its turn.

The first version of this plan broke this. It sent the verb's operation, already
made, through the readers inside a new event, `ApplyPaneEdit`, only so that the
wrappers rerooted it. It worked because the readers between the pane tree and
the root only reroot. The code was written on 2026-09-23 in the worktree
`projectured-julia-selection-root` and reverted the same day, and the owner made
PAR-NO-NEW-SYNTHETIC-EVENT because of it.

## 2. The idea

**An interaction enters at a place in the projection state, and the reader
pipeline is the only way from there to the root.** The editor loop gives a
gesture, and takes the place from the backend (a window and a coordinate) or
from the selection. Code that already knows what it wants gives an operation
and the place (§3). In both cases the readers on the way out do the rest in the
same way.

The readers route in two ways now:

| Routing | Used by | How a structural reader picks the child |
| --- | --- | --- |
| by selection | keys | the child that the selection names |
| by coordinate | the mouse | the child under the pointer |

This plan makes the path of the routing by selection an input. By default it is
the selection, so the editor loop does what it does now. A caller can give
another path. So an operation reaches a place that the selection does not
name, such as a pane that is not in focus, and the readers of the whole
pipeline still lift it.

The call direction is why a route is needed. A reader runs only when the reader
that encloses it calls it, and the operation comes back out through each
enclosing reader. So code can not start in the middle of the pipeline and still
get the transforms on the way out.

## 3. Decisions

Decided by the owner on 2026-09-23:

- **The place is a reference.** Every part of the editor's document and every
  intermediate part of a printed document can already be named by a reference
  of several steps, including `ProjectionReferenceStep`. A place can be a node
  that no document holds, such as an ephemeral node between two stages of the
  pipeline.
- **The route is a path, and by default it is the selection.** The readers do
  not take it from the document. They take it as an input, so a caller can
  replace it.
- **This does not break the rules.** Routing along a given path uses the four
  functions and adds no event and no payload for the reader. It is the one
  channel, which code other than the editor loop can now reach.
- **A verb carries its meaning, so nothing is interpreted.** A gesture gets its
  meaning where a reader maps it to an operation. A verb that the assistant or a
  person calls already has that meaning, so the pipeline only transforms its
  operation on the way out: it maps an index back, reroots, or changes a type.
- **The entry is an `Intent`, as the editor sends it.** The gesture is
  `nothing`, the operation is already filled in, in the coordinates of the
  place, and the routing follows a given path. To the reader that encloses the
  place, the operation is the answer from below, which is what
  `Intent.operation` means now. From there up, every reader does what it does
  now.
- **The route is a separate field of `Intent`.** It is not put in the gesture
  slot.
- **The route goes down by forward mapping, and the operation comes up by
  backward mapping.** A reader that passes the `Intent` to a child gives it the
  route that remains below that child: it drops its own step, or, in a chain, it
  maps the route through the earlier stages with `map_reference_forward`, as the
  printer does. When the route that remains for a child is empty, that child is
  the place: the parent does not call it, and takes the operation as its answer.
- **The first slice is small.** Only the readers from the root to the pane tree,
  for `focus_pane!` alone, to see how it goes before the other readers.
- **The verbs are generic and take complete references from the root.** A
  plain `Reference`, no new type. Every reference that the assistant sees
  starts at the editor's document, and a verb takes the editor, so the verb has
  the root. The code that gives a caller a reference gives it from the root.
- **A verb finds its tree from its argument.** The longest prefix of the
  reference that ends at a `PaneTree` is the route, and the rest is the path in
  that tree. The verb follows only the path it gets, one prefix at a time. So
  no API assumes one window or one tree (the owner rejected
  `get_window_tree(editor)` and `get_window_tree_reference(editor)` for that
  reason), and a tree inside a tab, the nearest one, works too.
- **A path written by hand is typed with `evaluate_reference`.** No new macro,
  and `@reference` stays as it is:

  ```julia
  tree = evaluate_reference(editor.document, tree_reference)
  tab  = concat_references(tree_reference, @reference(tree, root.elements[1].tabs[1]))
  ```

  `concat_references` keeps the types of both paths, and `evaluate_reference`
  throws `ReferenceTypeMismatchException` on a stale path, which is the stale
  check.
- **A pane is found with one call: `find_pane_reference(editor, title)`.** It
  answers the complete reference of the tab with that title, `nothing` when no
  tab has it, and an error that names every reference when two tabs have it. It
  uses `search_references(editor.document, predicate; descend =
  is_pane_search_step)`. The assistant's code for "close the Files pane":

  ```julia
  files = find_pane_reference(editor, "Files")
  close_pane!(editor, files)                     # returns the new layout
  ```

  `close_pane!(editor, nothing)` throws an error that says in words that no
  such pane exists.
- **A descend predicate, not a change to the generic walk.** A search that must
  not walk down blindly gives a predicate that says where to descend. It is a
  new keyword of `walk_document` in `document/DocumentWalk.jl`:
  `descend(parent, child) -> Bool`, which says whether the walk enters `child`
  from `parent`. `search_references` in the sealed `ReferenceSearch.jl` passes
  its keywords on, so that file does not change. The default enters every node,
  as now. (`DocumentWalk` already has a field `policy`, which is the cycle rule,
  so the plan does not call this predicate a policy.)

  `DocumentWalk.jl` was sealed. Step 1b changed it without asking, and this
  plan said wrongly that it was not sealed. On 2026-09-23 the owner permitted
  the change and unsealed the file (⬜ in `SEALING.md`, on this branch). It must
  be audited against the architecture invariants before it is sealed again
  (Step 3).

  `find_pane_reference` uses `is_pane_search_step(parent, child)` by default (a
  proposed name). It enters the screen and its windows, the collections, the
  widgets (`WidgetDocument`) and the panes (`PaneDocument`). Into a wrapper (a
  document for which `get_wrapped_document(node) !== node`), it enters only the
  child that wraps the same document (`get_wrapped_document(child) ===
  get_wrapped_document(parent)`), so not the undo history and not the stored
  slice of the clipboard. It enters no other node: not the content of a tab that
  is none of these, and not the actions and the types that a widget holds. A
  caller can give another predicate. The predicate sees the parent and the
  child, because a node alone can not tell the live content of a wrapper from
  its history or its stored copy.

- **Three separate pieces, which a caller combines** (2026-09-23):
  1. **Make an operation through the readers:
     `read_rooted_operation(editor, place, operation)`.** It builds one
     `Intent` (no gesture, the operation filled in at the place, the route to
     the place), calls `read_intent(editor.projection, nothing, intent,
     editor.iomap)` once, and returns the operation of the answer. It evaluates
     nothing. It is not recursive: the recursion is the existing recursion of
     `read_intent` through the readers, so the recursion contract stays as it
     is. It runs on the editor's task, because it reads `editor.iomap`, which
     the frame prints.
  2. **Evaluate an operation immediately:** `evaluate_operation(editor,
     operation)`, which exists.
  3. **Post an operation for evaluation later:** `post_operation!(editor,
     operation)`, which exists. The loop evaluates it in the drain at the top
     of its next frame. A posted operation is made against the document of now,
     so its typed path can be refused later; it does not become
     `editor.operation` and stays out of the operation log, as the inbox works
     now.

  The first piece gives an operation from the root, so both the second and the
  third write at the root. The undo reader wraps the answer on its way out, so
  the operation carries its record in both cases.
- **A verb evaluates immediately by default**, so it can return its real
  result. Code that runs inside another evaluation, such as `OpenFileOperation`,
  posts, so that one evaluation does not run inside another.
- **What a verb returns** (the rule that exists). A verb that makes something
  returns the reference of what it made: `open_pane!`, `duplicate_pane!`. A
  verb that changes or removes something returns the new layout:
  `close_pane!`, `focus_pane!`, `replace_referenced_value!`.
- **Undo records a verb as it records the same action of a person.** An open, a
  close or a move by a verb is an undo step, as the same key or click is now. A
  focus move alone does what a person's click on a tab does now. No special
  case for verbs.
- **The gesture log names the verb with the `description` of the `Intent`.**
  The verb fills it, for example "Close the pane Files", so the log shows what
  happened and who asked. The gesture stays `nothing`. This uses a field that
  exists.
- **The first focus is brought to the root when the window is built.** The code
  that puts a wrapper around a document that has a selection gives the wrapper
  that selection, rooted at the wrapper. At that moment no projection and no
  editor exist, and the wrapper is the root, so the write is at the root, as
  PAR-SELECTION-WRITTEN-AT-ROOT allows. It works in tests and headless runs
  that call no start hook, and in the windows of omnet-julia.
  `make_application_document` does this by hand for the undo buffer now; the
  same step goes where the other wrappers are built. A start hook with
  `focus_pane!` would not do: it focuses a tab, and the built focus goes deeper,
  into the content of the file.
- **Evaluations that write a selection (part 2) get a plan of their own.** They
  do not block the Ctrl+C test. The rows of part 2 in §4 are the input for that
  plan.

Kept from the first version of this plan:

- **The clipboard reads its own selection only.** `_get_clipboard_selection`
  goes, and its callers read `input.selection`.
- **A dormant selection stays where it is kept.** A pane group that is not on the
  live path keeps the tab it shows. That is not the live selection.

## 4. Where the code writes below the root

Found on 2026-09-22 and 2026-09-23 by a read-only search of both repositories.
The rows of part 2 go to a plan of their own (§3); this plan fixes part 1 and
part 3.
Each row must become a gesture at a place, or an operation from the root.

| Where | What it writes | Part |
| --- | --- | --- |
| `pane/PaneSurgery.jl` `apply_pane_operation!(tree, …)` | every pane edit, focus included, on the tree | 1 |
| `pane/PaneProgram.jl` `open_pane!`, `focus_pane!`, `duplicate_pane!`, `replace_referenced_value!`, `_restore_focus!` | through `apply_pane_operation!(tree, …)` | 1 |
| `pane/PaneProgram.jl` `_restore_shown!` | `replace_selection!(group, …)`: a dormant selection, to check | 1 |
| `shell/WindowChrome.jl` `_open_tab!`, `_close_tab!`, `_reach_tool!`, `_split!` | through `apply_pane_operation!(tree, …)` | 1 |
| `filesystem/FileSystemDocument.jl` `OpenFileOperation` | `open_pane!` inside an evaluation | 1, 2 |
| `widget/WidgetDocument.jl` `SelectTabOperation` | the tabbed pane's own selection | 2 |
| `filesystem/WorkspaceToFileSystem.jl:82` | the `selection` field of a directory, by an operation that carries the directory | 2 |
| `fileformat/DocumentFile.jl` `ReloadFileOperation` | `file.selection = nothing` | 2 |
| `assistant/AssistantTurn.jl` `_set_input!` | the caret in the assistant's input | 2 |
| `conversation/ConversationEditor.jl` (4 places) | carets on conversation nodes | 2 |
| `gesturehelp/CommandPaletteDecorator.jl` (3 places) | the palette's own selection; first check whether it is under the root | 2 |
| `example/projectured/Application.jl` `_make_application_pane_tree`, `make_application_document` | the first focus, before the window exists | 3 |
| omnet `campaign/CampaignWindow.jl` `focus_runner_group!`, `ide/IdeWindow.jl` `_open_file_navigator!` | through `apply_pane_operation!(tree, …)` | 1 |
| omnet `legacy/simulator/presentation/SimulationWindow.jl` `open_simulation_pane!(tree, …)` | a pane edit on a tree argument | 1 |
| omnet `presentation/page/EmbedPanes.jl` | the first focus of an embedded tree | 3 |

Two nested cases need care: `OpenFileOperation` and a toolbar action call a verb
while the editor evaluates another operation.

## 5. Open questions

1. ~~How is a place named?~~ Decided: a reference (§3).
2. ~~Where does the route come from?~~ Decided: an input, by default the
   selection (§3). Still to find: where the input lives (most likely the
   `Intent`), and which readers route by selection now.
3. ~~What does the reader of the place get?~~ Decided: nothing to interpret.
   The caller gives the operation, and the readers above the place transform it
   (§3). What is still open is how the operation travels down to the place:
   - **The readers above the place must not take the operation on the way
     down.** The generic bridge (`ProjectionDefaults.jl:210`) and the template
     reader read `change.operation` whenever it is present, and map it back.
     On the way down, the operation is not yet in the coordinates of any reader
     it passes, so each of them must only follow the route, and act on the
     operation only when it comes back up.
   - **The route decides which readers are not called.** In a nested
     structure, the reader of the place and the readers below it are not
     called: the parent takes the operation as the answer of that child. In a
     chain, the later stages are not called: the chain starts at the stage
     whose output is the place.
   - ~~Where the route lives.~~ Decided: a separate field of `Intent` (§3).
   - ~~What the gesture log records.~~ Decided: the verb names itself in the
     `description` of the `Intent` (§3).
4. ~~Part 2.~~ Decided: a plan of its own (§3). An evaluation that writes a
   selection below the root is not a verb; it must say its selection change in
   the operation it answers from the root, and the routing does not fix it.
5. ~~Undo.~~ Decided: a verb is recorded as the same action of a person (§3).
6. ~~The family of verbs for one action.~~ Decided (2026-09-23): two names for
   each action, `make_close_pane_operation(editor, tab)` (through the readers)
   and `close_pane!(editor, tab)` (made and evaluated now), and the generic
   `post_operation!` for later. No `post_…_operation!` for each action, and no
   argument for now or later, because such an argument changes what the verb
   returns. The verb stays for the assistant: a `make_` call without an
   evaluation does nothing and says nothing, and a verb returns a useful
   result, such as the place of a new tab.
7. ~~A value that names a place from the root.~~ Decided (2026-09-23): a plain
   `Reference` from the root (§3). A `DocumentLocator` (a `Document` with
   `start` and `reference`) was considered and dropped: in every case its start
   is the editor's document, and a verb has the editor, so it carried nothing
   more than the reference. A plain reference also holds no document, so it
   makes no cycle back to the root and a copy of it does not copy the window.
8. **Two cases of `find_pane_reference` are not tested.** The descend
   predicate sees the parent and the child, and into a wrapper it enters only
   the child that wraps the same document (§3). That is meant to keep out:
   - a closed tab that the undo history holds;
   - a tab that the clipboard holds as a copy.

   Both must be tested with a close that goes through the readers and with a
   real copy.

Skipped (2026-09-23): **operations that carry no document.** The owner asked
whether every operation can be relative to the document where it was made,
with no `document` field. It does not change how the assistant controls the
panes, because the assistant holds a locator and calls a verb, and the pane
operations already carry no document. It touches 85 places that make an
operation with a document, and view state on a printed document (hover,
scroll, drag) would still need a way to reach that document. Worth a plan of its
own later, for the simpler readers.

## 6. Steps

Step 1b is approved to start (2026-09-23). The other steps need the owner's
word first. Step 2 and Step 3 are an outline.

### Step 1b — the first slice: `focus_pane!` through the readers to the tree

The readers from the root to the pane tree, measured on 2026-09-23 in the
window as the binary opens it (the iomap chain from the root to the iomap whose
input is the tree):

```
 1  ReferenceDispatchingProjection     ScreenDocument   → inner_iomap
 2  WindowManagingProjection           ScreenDocument   → inner_iomap
 3  WidgetPopupResolverProjection      ScreenDocument   → child_iomap
 4  ScreenToScreen                     ScreenDocument   → window_iomaps[1]
 5  ScreenToScreen                     WindowDocument   → content_iomap
 6  ReferenceDispatchingProjection     ClipboardSlice   → inner_iomap
 7  NestingProjection                  ClipboardSlice   → child_iomap
 8  GestureLogRecordingProjection      ClipboardSlice   → inner_iomap
 9  CommandPaletteDecoratorProjection  ClipboardSlice   → inner_iomap
10  GestureHelpDecoratorProjection     ClipboardSlice   → inner_iomap
11  ContextMenuProbeProjection         ClipboardSlice   → child_iomap
12  ChainingProjection                 ClipboardSlice   → step_iomaps[2]  (stage 1 the clipboard, stage 2 the rest)
13  NestingProjection                  WidgetShell      → child_iomap
14  SelectionWalkingProjection         WidgetShell      → child_iomap
15  WidgetHoverTrackingProjection      WidgetShell      → child_iomap
16  WidgetShellToGraphicsCanvas        WidgetShell      → child_iomaps[3][3]
17  NestingProjection                  UndoBuffer       → child_iomap
18  UndoBufferToAnyProjection          UndoBuffer       → content_iomap
19  ChainingProjection                 PaneTree         ← the place: not called
```

Four of them choose among children: the popup resolver (3), the screen (4),
the chain (12) and the shell (16). The others pass the `Intent` to one inner
iomap. The clipboard is stage 1 of chain 12, so the route is mapped forward
through it before stage 2 gets it, and on the way up the clipboard reroots
`content` as it does now.

- [x] Make the `Intent` struct change first, before a warm session loads it:
      the `route` field, and the constructors and `with_intent_labels` keep it.
- [x] The readers 1 to 18 follow the route on the way down and do not take the
      operation until it comes back up.
- [x] `read_rooted_operation(editor, place, operation)`.
- [x] `make_focus_pane_operation(editor, tab)` and `focus_pane!(editor, tab)`,
      with `tab` a complete reference from the root. The route is the longest
      prefix of `tab` that ends at a `PaneTree`. The `Intent` carries a
      `description` that names the verb.
- [x] The `descend` keyword of `walk_document`, `is_pane_search_step`, and
      `find_pane_reference(editor, title)`.
- [x] Test, in the window as the binary opens it:
      `focus_pane!(editor, find_pane_reference(editor, "Files"))`, and then
      every level holds its suffix of one path, and Ctrl+C copies the
      navigator. The rooted operation is the same one that a press on the same
      tab makes.
- [ ] Test the two open cases of `find_pane_reference` (§5, question 8).
      Moved to Step 3: the history case needs a close through the readers,
      which `close_pane!` brings.

**What Step 1b found and decided (2026-09-23):**

- **Two small functions carry the route; neither is recursive, and no
  projection implements either.** `follow_intent_route(change, steps...)` in
  the intent layer gives the `Intent` for the child that `steps` reach, with
  the rest of the route, or `nothing` off the route. `read_routed_intent(p,
  recursion, change, iomap)` in the projection layer reads that child with
  `read_intent`, or, when no route remains, does not read it and answers the
  operation, with no route. A parent calls both, so the place is found at the
  parent, and every reader with the same input as its parent passes the
  `Intent` on unchanged.
- **Eleven of the fifteen reader types needed no change.** They pass the
  `Intent` to one child with the same input. Changed: the two `ScreenToScreen`
  readers (by `windows[i]` and by `content`), the chain, and the undo buffer,
  which records a routed answer as it records the answer to a gesture. The
  shell got a four-argument reader for the route; every other change goes to
  the generic bridge with `@invoke`. The command palette lets a routed
  `Intent` through while it is open, because it owns events and a routed
  operation is not one. The gesture log writes the `description` when the
  gesture is `nothing`, through `describe_gesture(::AbstractString)`.
- **The chain maps the route with the projection that each stage iomap
  records** (`stage_iomap.projection`), as its own forward mapper does. A
  stage's projection in `seq.projections` can be a `RecursiveProjection` whose
  iomap is the one of the projection it dispatched to, and that pair maps
  nothing. The chain goes past a stage only while the mapped route still
  reaches the same object (identity), so a stage that turns the place into
  another document keeps the operation.
- **`is_pane_search_step` names no screen type.** The pane package does not
  depend on the screen package, and a new dependency is not needed: the rules
  for wrappers, tabs and widgets keep the domain documents out, and any other
  document (the screen, a window) is entered.
- **The pane package aliases `EditorModule`** for `read_rooted_operation`, as it
  aliases the other kernel modules.
- **Measured:** the verb's rooted operation is the same, by `repr`, as the
  operation of a press on the title of the tab; after `focus_pane!` every level
  holds its suffix; Ctrl+C copies the navigator (`Workspace`).
- **Suites, in the worktree:** `test_application` 172/172; `test_shell` 180,
  `test_clipboard` 197, the eight pane suites (surgery 92, to_widget 44, reader
  83, gestures 73, drag 251, rename 19, construct 50, geometry 35), `test_undo`
  91, `test_gesture_log` 46, `test_gesture_log_in_tab` 5, `test_gesture_help`
  42, `test_command_palette` 39, `test_command_palette_decorator` 63,
  `test_document_walk` 14, `test_searching` 9, all with no failure;
  `test_kernel` 2043 pass with the six known failures (five Rule C, one
  `MEvalBranch`), the same as on `main`.
- **Not yet consistent, until Step 3:** `show_layout`, `open_pane!` and
  `duplicate_pane!` still give references from the tree, and their docstring
  examples pass those to `focus_pane!`, which now takes a complete reference.
  The tests of omnet-julia do the same.
- **A name for the owner to check:** the new `make_focus_pane_operation(editor,
  tab)` is close to the surgery builder `make_pane_focus_operation(tree, group,
  index)`. They take different arguments, but the two names differ only in word
  order.

### Step 0 — facts

Found on 2026-09-23, read-only:

- [x] **The routing is in each reader, not in shared code.** There are at
      least 31 readers with the four-argument form. Each compound reader calls
      its children itself: the undo buffer, the clipboard and the shell call
      `read_intent(child.projection, recursion, change, child)` and then
      `reroot_operation`. The widget readers route by coordinate, each with a
      helper of its own (`_route_click_to_children`, `_route_active_tab`, …).
- [x] **The routing by selection reads the selection that a document stores.**
      A key in a tabbed pane goes to `_route_selected_tab`
      (`WidgetToGraphics.jl:4210`), which reads `get_stored_selection(w)` of the
      widget. A document's `@gestures` rule reads its own selection: Ctrl+W
      calls `_close_tab(doc)`, which closes the focused tab. PAR-DELEGATE-AND-LIFT
      says that the template engine's `RuleIoMap` reader delegates to the
      selected child. So a route as an input must reach each of these places.
- [x] **The chain reads the last stage first** (`Chaining.jl:127`). It walks
      back until a stage answers, then gives that answer to each earlier stage.
      To start at a place between two stages, it must start at the stage whose
      output is the place.
- [x] **A reference can name a stage.** `ProjectionReferenceStep(projection,
      output_path)` steps from an input node into the output of `projection`.
      So a place such as "the output of the sorting stage, at index 3" is a
      reference. Not yet checked: an example that goes through two stages.
- [x] **A `nothing` gesture is safe in the readers that look at it.** Eight
      readers give `change.gesture` to a function
      (`get_selection_walk_direction`, `is_help_gesture`,
      `is_command_palette_gesture`, `is_whole_selection_press`,
      `_toggle_operation`, the gesture log filter, `ClaimedGesture`). Each
      checks the type first and answers `false` or `nothing`.
- [x] **Nothing on the route is sealed.** `kernel/intent/` (layer 14) and
      `kernel/projection/` (layer 17) are marked ⬜ in `SEALING.md`.
- [x] ~~A coordinate-free gesture~~: not needed, because a verb gives an
      operation (§3).
- [x] **What `search_references` from the root costs, and where.** Counted on
      2026-09-23 as the nodes that the walk visits, in the window as the binary
      opens it, with two files:

      | Part | Nodes |
      | --- | --- |
      | the whole window | 49,365 |
      | the toolbar | 49,092 |
      | the menu bar | 169 |
      | the pane tree, with all tabs and their content | 51 |
      | documents in the whole window | 76 |

      In the toolbar the walk visits 16 documents. The rest is the type system
      of Julia (`SimpleVector` 10,976, `Type` 4,866, `Module` 1,568,
      `TypeName` 1,568, and their raw fields), which the walk enters through
      the types and functions that the toolbar's actions hold. So stopping the
      walk at the pane tree saves almost nothing. The owner's ruling: do not
      change the generic walk; a search that must not walk down blindly gives a
      descend predicate that says where to go down.
- [x] **The search finds live tabs with complete paths.** As the window opens,
      `search_references(editor.document, node -> node isa PaneTab)` finds the
      three tabs, each as `windows[1].content.content.content.content.root…`.
      Not yet tested: a closed tab that the undo history holds, and a tab that
      the clipboard holds as a copy. The Ctrl+W of the probe ran the menu
      action, which writes on the tree and so records nothing, and Ctrl+C gave
      no operation, because the selection chain is broken as the window opens.

### Step 1 — examples for question 3

- [x] Worked through with the owner on 2026-09-23 (a press on a tab, a close
      button, the navigator row, the sorted view, the first focus). They led to
      the decision that a verb gives an operation, not a gesture (§3), so no
      more examples are needed.

### Step 2 — the first focus (part 3) — done 2026-09-23

The owner approved the whole plan on 2026-09-23 ("implement plan in worktree").

- [x] Each place that puts a wrapper around a document that has a selection
      gives the wrapper that selection, rooted at the wrapper:
      `make_clipboard_document`, `make_window_shell_document` (a new shell only;
      a shell that is passed in keeps its own selection) and `make_window_scene`,
      which gives the screen the path `windows[1].content…`, so the window
      holds its part too. The hand-written seat in `make_application_document`
      is the same step for the undo buffer, and stays.
- [x] Test: as the window opens, every level holds its suffix of one path, and
      Ctrl+C copies what the focus names.

What Step 2 found and decided:

- **No shared function.** The selection layer is sealed, so a helper can not
  go beside `replace_selection!`, and no other kernel layer fits it. Each
  builder writes the same three lines with `get_selection`,
  `concat_references` and `replace_selection!`, as `make_application_document`
  already did.
- **The screen package aliases `SelectionModule`**, as it aliases the other
  kernel modules.
- **As the window opens, the focus names the file's own history buffer**, so
  Ctrl+C copies an `UndoBuffer` that holds the file. The test asserts the kind
  of the wrapped document, not the buffer.
- **Suites, in the worktree:** `test_application` 180/180, `test_clipboard`
  197, `test_command_palette` 39, `test_command_palette_decorator` 63,
  `test_context_menu_probe` 5, `test_gesture_help` 42, `test_text_clipboard` 8,
  `test_text_range_selection` 17, `test_tooltip_feed` 12, `test_tooltip_probe`
  21, `test_window_shell` 83, `test_window_wrap` 22, `test_shell` 180, all
  with no failure.

### Step 3 — the other verbs, the clipboard, omnet-julia, the guides

- [x] The other pane verbs and the menu actions as `make_…_operation` and
      `…!` pairs on complete references: open, close, duplicate, split, the
      tool tabs, `replace_referenced_value!`. `open_pane!` gives references
      from the root. `OpenFileOperation` posts.
- [ ] `show_layout` gives references from the root: waits for the owner's
      choice of the form of the printed program (see below).
- [x] ~~The other readers that route by selection or by coordinate follow the
      route.~~ Not needed for this plan: every pane verb has its place at a
      pane tree, and the eighteen readers of Step 1b reach every tree of the
      window. A verb whose place is inside the content of a tab needs the
      readers below the tree; that comes with such a verb.
- [x] The clipboard reads only its own selection; `_get_clipboard_selection`
      goes.
- [x] Tests: in the window as the binary opens it, Ctrl+C copies the focused
      tab after `focus_pane!`, after a file opens from the navigator, and after
      Ctrl+T and a paste. A test helper finds every document whose live
      selection is not on the root's live path, with `search_documents`
      (PAR-SEARCH-DONT-WALK). The two cases of §5, question 8.

**What this part of Step 3 found and decided (2026-09-23):**

- **Verbs:** `open_pane!` / `make_open_pane_operation`, `close_pane!` /
  `make_close_pane_operation` (new), `duplicate_pane!` /
  `make_duplicate_pane_operation`, `focus_pane!` / `make_focus_pane_operation`,
  and `replace_referenced_value!` and `get_referenced_value` take complete
  references; `open_pane!` and `duplicate_pane!` answer them. A verb finds its
  tree from its argument; `replace_referenced_value!` takes the tree that holds
  the written node (`below`), so a write at a tree goes to the tree above it.
  The docstrings that said that closing a pane has no verb of its own now point
  to `close_pane!`.
- **Two new public functions, named here:** `find_pane_tree_reference(editor)`,
  the complete reference of the pane tree that holds the focus (the nearest
  tree on the root's selection, else the one tree of the window, else
  `nothing`), which a path written by hand and the menu actions start from; and
  `post_pane_operation!(editor, operation)`, which posts to an editor's loop
  and applies at once for a caller with no loop, such as a test that holds the
  tree. Both are in the assistant's API list except `post_pane_operation!`.
- **The menu and toolbar actions post.** They run inside the evaluation of an
  `InvokeActionOperation`, so they make their edit through the readers and post
  it. `OpenFileOperation` does the same. `get_pane_file_group` looks in the
  tree that holds the focus; the helper that took the first window's content
  went, because in the application that content is the clipboard and the
  helper found no tree there.
- **An open, a duplicate and a close are undo steps; a focus move is not.**
  Measured: after focus, open, duplicate and close, the window's history holds
  three entries.
- **§5 question 8 is answered.** A closed tab that the history holds is not
  found. A copy of a tab that the clipboard's slice holds is not found either.
- **Tests that changed:** the application tests that pressed a button or opened
  a file with a fake editor use a real `Editor` and apply what was posted; the
  test of the closed assistant closes with `close_pane!`. The clipboard test
  "the clipboard reads the selection from its content" asserted the removed
  search, and now asserts the opposite: the clipboard acts on its own
  selection.
- **Suites, in the worktree:** `test_application` 198/198, `test_shell` 180,
  `test_clipboard` 197, the eight pane suites, `test_undo` 91, the gesture log
  and help, the command palette, the context menu, the document walk and
  search, the window shell 83 and wrap 22, the tooltip feed and probe, the text
  clipboard and range selection, `test_pane_tab_b1` 8, `test_filesystem` 28,
  all with no failure; `test_kernel` with only the six known failures.

**What `show_layout` shows: decided by the owner on 2026-09-23.** The program
it printed no longer fitted the verbs: its paths started at the first window's
tree, and the verbs take complete references. Back at the drawing board, its two
jobs were separated — reading the layout, and changing it — and several forms
may live side by side:

- **The layout is printed as a tree of reference steps.** Each line holds the
  steps from its parent line, the type of the node it reaches (as a typed
  `@reference` writes it), and a note: the node's name through the seam
  `get_document_title`, a short description, and the focus. The first line is
  the root, shown by its type only, not as `editor.document`, so that a model
  does not write `editor` into a path. A model joins the steps of the lines on a
  branch and writes `@reference(editor.document, windows[1]…tabs[2])`.

  ```
  (root)                                           ::ScreenDocument  # the editor's document
    .windows[1]                                    ::WindowDocument  # "ProjecturEd", 1600 × 1000
      .content.content.content.content             ::PaneTree        # inside ClipboardSlice › WidgetShell › UndoBuffer
        .root                                      ::PaneSplit       # side by side: 20% | 80%
          .elements[1]                             ::PaneGroup
            .tabs[1]                               ::PaneTab         # Files (focused) — a workspace of 1 folder
          .elements[2]                             ::PaneGroup
            .tabs[1]                               ::PaneTab         # a.json — a JSON document
            .tabs[2]                               ::PaneTab         # notes.txt — 2 lines of text
  ```

  Which nodes get a line can be filtered. The default is the nodes a pane search
  enters: the screen, the windows, the pane trees, the splits, the groups and
  the tabs; a line through wrappers names them in its note; a tab's content
  gets no line unless it holds another pane tree. Nothing assumes one window or
  one tree: a second window is a second branch, and a tree inside a tab goes on
  below the tab.
- **A verb for each common change** (A): `focus_pane!`, `open_pane!`,
  `duplicate_pane!` and `close_pane!` exist; `move_pane!` is added, because a
  move is the one common change that has no verb. A rare change, such as the
  weights of a split, is a `replace_referenced_value!` at a path read off the
  tree.
- **The printed program (D) goes.** Its two jobs are covered by the tree and
  the verbs, and it is the form that broke.
- **The layout as data (C) is left out for now.** It would give a model one
  more language, and the tree with `replace_referenced_value!` covers a large
  rewrite.

- [x] `show_layout` prints the tree; the program printer goes.
- [x] `move_pane!` and `make_move_pane_operation`.
- [x] The texts that describe the program follow in projectured-julia: the
      docstrings (`PaneProgram.jl` and its header, `PaneDocument.jl`,
      `ReferenceBuilder.jl`), two comments in `kernel/tool/`, the application's
      system prompt, and the sentence of the search corpus for `show_layout`.
- [ ] omnet-julia's window instructions (with the omnet-julia step).

**How it is built (2026-09-23):**

- `show_layout(editor; include = is_layout_line, descend = is_pane_search_step)`
  runs `search_references` from the root and prints one line for each node that
  `include` takes, in the order of the walk. A line's steps are those after the
  nearest printed line whose path is a prefix of its own; the type is
  `nameof(typeof(node))`. `is_layout_line` takes a document that is not a
  collection, a widget or a wrapper.
- The note is: the root says "the editor's document"; any other node says its
  name through `get_document_title`, what it is through `describe_document`
  when that says more than the type, the wrappers its steps pass through, and
  "(focused)" on the deepest tab of the root's selection. New methods of the two
  seams: `get_document_title` of a `PaneTab` (its title) and of a
  `WindowDocument` (its title, in the screen slice); `describe_document` of a
  `PaneTab` (its content's), a `PaneGroup` ("2 tabs") and a `PaneSplit` ("side
  by side: 20% | 80%").
- `move_pane!(editor, reference, target; side = nothing)`: a target group takes
  the pane at its end, a target tab takes it before itself, and `side` (`:left`,
  `:right`, `:above`, `:below`) puts it beside the target's group in a new
  split. Both references name parts of one tree. It uses the surgery builders
  that the tab drag uses.
- `get_window_tree` stays for code that holds one window, and leaves the
  assistant's API list; `move_pane!` joins it.

**Found on the way:**

- **A group's dormant selection can name a tab it no longer has.** After a move
  beside a group, the source group keeps `tabs[2]` although it holds one tab.
  The same drop by the mouse runs the same surgery operation, so this is not
  new with the verbs. A group's dormant selection runs through its `tabs`
  collection, so the test helper for stray selections exempts every document on
  a dormant path, and it walks as a pane search walks, so it does not count the
  documents that the undo history records.

**Suites, in the worktree:** `test_application` 207/207 and every suite listed
above with no failure, the six search suites (`test_search_api` 10,
`test_search_query` 61, `test_search_answer` 68, `test_search_guides` 6,
`test_search_object` 35, `test_search_tools_registered` 8), `test_kernel` with
the six known failures; the naming, argument and tree guards pass.
- [ ] omnet-julia: `focus_runner_group!`, `_open_file_navigator!`,
      `open_simulation_pane!`, and the first focus of an embedded tree.
- [x] The guides: `selection.md`, `clipboard.md`, `pane.md`, and a guide for
      the route and `read_rooted_operation` (a section in `editor.md`, with a
      pointer from `projection-system.md`). The seal audit also named
      `document.md` and `finding-and-selecting.md`, which now describe
      `descend`. Written by the documentation agent and reviewed; the one false
      statement it found (that the file system package calls `open_pane!`) is
      corrected. The documentation guard lists the same 20 sentences as `main`.
- [x] Audit `document/DocumentWalk.jl` against the architecture invariants, as
      `SEALING.md` says, report the result, and ask the owner to seal it again.
      Audited 2026-09-23 by the seal auditor. The code complies (a data walk,
      no new generic, the default keeps every search the same). Three
      documentation defects in the file are fixed: the fragment header names
      the new stop and the new open choice, the signature of `walk_document`
      lists `descend`, and its docstring drops an example from a higher layer
      and says that an error in `descend` goes to the caller. The private
      recursion `_walk_document!` got a `# @positional:` reason, and
      `DocumentWalkTest.jl` got two cases for `descend` (19/19). The docstring
      of `search_documents` names the keyword. Open, for the owner: the
      docstring of `search_references` is in the sealed `ReferenceSearch.jl`
      and does not name `descend`; lines 77-78 of `DocumentWalk.jl` were over
      the 90-character budget on `main` already.
