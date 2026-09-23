# A gesture is read at any reference

**Status (2026-09-23): DESIGN.** Not approved for implementation. One question
(§5, question 3) is open and needs more examples. Nothing is implemented.

**Goal:** code that is not the editor loop — a verb, the assistant, an MCP tool,
a test, a replay, the start of an application — can do anything a person can
do, and it does it the way a person does: it gives a gesture at a place, and the
reader pipeline of the whole editor reads it. The place is a reference, and the
readers route the gesture along it. So the reader of the place makes the
operation, and every reader on the way out transforms it, as for a gesture of a
person.

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
3. **What does the reader of the place get, and what does it do with it?** It
   must act as if a person did the gesture there, and it must stay pure. The
   owner's view: the answer is probably specific to the reader, the gesture and
   the operation. More examples are needed before a design. See §6.
4. **Part 2 is separate.** An evaluation that writes a selection below the root
   is not a verb. It must say its selection change in the operation it answers
   from the root. The routing does not fix it.
5. **Undo.** When a verb's gesture goes through the pipeline, the undo reader
   records the answer as it does for a person. So an open or a close by a verb
   becomes an undo step. Check that this is wanted, and what a focus move does.

## 6. Steps

No step is approved to start. Each step needs the owner's word first. Step 2
and Step 3 are an outline.

### Step 0 — facts

- [ ] How the readers route by selection now: which readers take the selection
      to pick a child, and where they read it (the document, the iomap, or the
      output selection).
- [ ] Whether the files of `kernel/intent/` and the other files the route would
      touch are sealed (`SEALING.md`).
- [ ] How `ProjectionReferenceStep` names an intermediate node, with one
      example that goes through two stages.
- [ ] Whether a gesture exists that a reader knows with no coordinate, such as
      a press on the whole of an element.

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
