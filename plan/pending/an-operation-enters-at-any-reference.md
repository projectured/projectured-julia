# An operation enters at any reference

**Status (2026-09-23): DESIGN.** Not approved for implementation. Nothing is
implemented. The shape of the entry is decided (§3); how the route travels is
open (§5).

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

**An interaction is a gesture at a place in the projection state, and the reader
pipeline is its only interpreter.** The editor loop is one source of such pairs:
it takes the place from the backend (a window and a coordinate) or from the
selection. Every other source gives a place and a gesture, and the pipeline does
the rest in the same way.

The readers route in two ways now:

| Routing | Used by | How a structural reader picks the child |
| --- | --- | --- |
| by selection | keys | the child that the selection names |
| by coordinate | the mouse | the child under the pointer |

This plan makes the path of the routing by selection an input. By default it is
the selection, so the editor loop does what it does now. A caller can give
another path. So a gesture reaches a place that the selection does not name,
such as a pane that is not in focus, and it is still read by the readers of the
whole pipeline.

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
- **The verbs take and return references from the root (option B).** The code
  that makes a reference for a caller makes it from the root, so a verb does not
  need to find the path itself.
- **A program concatenates the two paths itself (option 3).** `window` is the
  path from the root to the tree, and the path in the tree is typed against the
  tree object, as now:

  ```julia
  window = get_window_tree_reference(editor)
  tree   = get_window_tree(editor)
  where  = concat_references(window, @reference(tree, root.elements[1].tabs[1]))
  ```

  A caller that already has a typed reference concatenates it with no tree
  object. A caller that writes a path by hand needs the tree object to type it.
  The typing keeps the stale check of `_refuse_stale`.
- **`get_window_tree_reference(editor)` is a new function in the pane slice**
  beside `get_window_tree`. It follows the same descent (the first window, then
  each wrapper through `get_wrapped_document`) and names each step by identity:
  the index of the window, and the field of the wrapper that holds the next
  node. It looks at one level at a time and walks no content of a tab.

- **Three separate pieces, which a caller combines** (2026-09-23):
  1. **Make an operation through the readers.** Route an `Intent` (no gesture,
     the operation filled in at the place, the route) through
     `editor.projection` with `editor.iomap`, and return the rooted answer. It
     evaluates nothing. This is the new piece. It runs on the editor's task,
     because it reads `editor.iomap`, which the frame prints.
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

Kept from the first version of this plan:

- **The clipboard reads its own selection only.** `_get_clipboard_selection`
  goes, and its callers read `input.selection`.
- **A dormant selection stays where it is kept.** A pane group that is not on the
  live path keeps the tab it shows. That is not the live selection.

## 4. Where the code writes below the root

Found on 2026-09-22 and 2026-09-23 by a read-only search of both repositories.
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
   - **What the gesture log records.** It keeps every operation that is not a
     selection move, so a verb's operation appears with an empty gesture.
4. **Part 2 is separate.** An evaluation that writes a selection below the root
   is not a verb. It must say its selection change in the operation it answers
   from the root. The routing does not fix it.
5. **Undo.** When a verb's gesture goes through the pipeline, the undo reader
   records the answer as it does for a person. So an open or a close by a verb
   becomes an undo step. Check that this is wanted, and what a focus move does.
6. ~~The family of verbs for one action.~~ Decided (2026-09-23): two names for
   each action, `make_close_pane_operation(editor, tab)` (through the readers)
   and `close_pane!(editor, tab)` (made and evaluated now), and the generic
   `post_operation!` for later. No `post_…_operation!` for each action, and no
   argument for now or later, because such an argument changes what the verb
   returns. The verb stays for the assistant: a `make_` call without an
   evaluation does nothing and says nothing, and a verb returns a useful
   result, such as the place of a new tab.
7. **A value that names a place from the root: `DocumentLocator`** (decided
   2026-09-23). It is a `Document` itself, with two fields, `start` and
   `reference`. The target is derived by evaluating the reference from the
   start, so it is not stored, and the stale check is the check of the types on
   the path, as `_refuse_stale` makes now. A new macro (not `@reference`, which
   stays as it is) makes one locator from another and a path. Most locators
   are temporaries in the caller's code, and a document does not hold one: a
   generic walk follows the fields of a document, so a locator held in the
   window would make a cycle back to the root. Its docstring says so. Still
   open: the macro's name.

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

- [ ] Make the `Intent` struct change first, before a warm session loads it:
      the `route` field, and the constructors and `with_intent_labels` keep it.
- [ ] `get_window_tree_reference(editor)`.
- [ ] The readers 1 to 18 follow the route on the way down and do not take the
      operation until it comes back up.
- [ ] `focus_pane!` takes a reference from the root, sends
      `Intent(nothing, operation; route)` through `editor.projection`, and
      evaluates the answer against the editor.
- [ ] Test, in the window as the binary opens it: after `focus_pane!` on the
      navigator, every level holds its suffix of one path, and Ctrl+C copies
      the navigator. The rooted operation is the same one that a press on the
      same tab makes.

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
      walk policy that says where to descend.
- [x] **The search finds live tabs with complete paths.** As the window opens,
      `search_references(editor.document, node -> node isa PaneTab)` finds the
      three tabs, each as `windows[1].content.content.content.content.root…`.
      Not yet tested: a closed tab that the undo history holds, and a tab that
      the clipboard holds as a copy. The Ctrl+W of the probe ran the menu
      action, which writes on the tree and so records nothing, and Ctrl+C gave
      no operation, because the selection chain is broken as the window opens.

### Step 1 — examples for question 3

Collect examples, each with the place, the gesture a person makes, the reader
that answers it, and what each reader on the way out does with the answer:

- [ ] Focus a pane that is not in focus (`focus_pane!`): a press on its tab.
- [ ] Close a tab: a press on its close button.
- [ ] Open a file from the navigator: a selection of a row, then Enter.
- [ ] Delete the third element of a sorted view: the element is found in the
      source by the reader of the sorting projection.
- [ ] Type text at a position in a field of a pane that is not in focus.
- [ ] The first focus of the window at start (part 3).
- [ ] An assistant that pastes into a pane.

### Step 2 — the design

- [ ] Answer question 3 from the examples.
- [ ] Where the route lives, and how a structural reader uses it.
- [ ] Rewrite the verbs of §4 part 1 as gestures at a place.
- [ ] Part 2 and part 3, each by its own means.
- [ ] Tests: in the window as the binary opens it, Ctrl+C copies the focused
      tab as the window opens, after `focus_pane!`, after a file opens from the
      navigator, and after Ctrl+T and a paste. A test helper finds every
      document whose live selection is not on the root's live path, with
      `search_documents` (PAR-SEARCH-DONT-WALK).

### Step 3 — implementation, omnet-julia, the guides

Outline only: the route, the verbs, the clipboard without its search, the
writers of part 2, omnet-julia, and the guides (`selection.md`, `clipboard.md`,
`pane.md`, and a guide for the routing).
