# The selection is written at the root

**Status (2026-09-22): READY.** Nothing is implemented. The owner ruled on
2026-09-22: **the selection always ends up at the root, and its path goes
through the clipboard, so the clipboard does not search for it.**

**Goal:** every write of the live selection starts at the editor's root
document. So each document on the path holds its suffix of one path, and a
reader that needs the selection reads its own `selection` field. The clipboard
reads only its own, and Ctrl+C copies the focused tab in both binaries.

**Repositories:** projectured-julia, then omnet-julia. The plan changes no
sealed file: the selection layer (`selection/`, 🔒) is called, not changed.
`document/DocumentInterface.jl` and `document/DocumentDefaults.jl` are not
sealed.

## 1. What is wrong

Measured on 2026-09-22 in the application window, as the binary opens it:

| Before Ctrl+C | Result |
| --- | --- |
| the window just opened, a file tab in focus | nothing is copied |
| a pane verb focused a tab (`focus_pane!`) | nothing is copied |
| a plain click on the tab title | the file is copied |
| an Alt+click on an object | the object is copied |

After `focus_pane!`, the selection of each level of the window's document is:

```
level 0  ClipboardSlice   nothing
level 1  WidgetShell      nothing
level 2  UndoBuffer       (not the tab)
level 3  PaneTree         the focused PaneTab
```

Two faults make this:

1. **Some writers set the selection of an inner document.**
   `apply_pane_operation!(tree, operation)` evaluates against a `PaneHost` whose
   document is the tree, so a pane verb moves the focus in the tree alone. The
   fold's wrappers (`ClipboardSlice`, `WidgetShell`) and the window scene do not
   carry the selection of what they wrap, so the focus that the application
   sets when it builds its tree stays inside.
2. **The clipboard searches.** `_get_clipboard_selection` reads its own
   selection, else the selection one level in. With the shell at level 1, the
   focus is two levels below where it stops.

omnet-julia's `test_select_and_paste()` fails at lines 304, 310, 314, 317 and
434 for the same reason.

## 2. Every writer below the root

Found on 2026-09-22 (a read-only search of both repositories).

| Where | What it writes |
| --- | --- |
| `pane/PaneSurgery.jl:159` `apply_pane_operation!` | every pane edit, focus included, on the tree |
| `pane/PaneProgram.jl` `open_pane!`, `focus_pane!`, `duplicate_pane!`, `_restore_focus!` | the focus, through `apply_pane_operation!(tree, …)` |
| `pane/PaneProgram.jl:542` `_restore_shown!` | `replace_selection!(group, …)` on each group |
| `example/projectured/Application.jl:93, 121, 124` | the first focus, before the window exists; line 93 carries it into the `UndoBuffer` by hand |
| `widget/WidgetDocument.jl:2759` `SelectTabOperation` | the tabbed pane's own selection |
| `fileformat/DocumentFile.jl:181` `ReloadFileOperation` | `file.selection = nothing` |
| `assistant/AssistantTurn.jl:179` `_set_input!` | the caret in the assistant's input |
| `conversation/ConversationEditor.jl:80, 87, 96, 299` | carets on conversation nodes |
| `gesturehelp/CommandPaletteDecorator.jl:183, 213, 219` | the palette's own selection |
| omnet `campaign/CampaignWindow.jl:221` `focus_runner_group!`, `ide/IdeWindow.jl:350` `_open_file_navigator!` | the focus, through `apply_pane_operation!(tree, …)` |
| omnet `legacy/simulator/presentation/SimulationWindow.jl:87` `open_simulation_pane!(tree, …)` | a pane edit on a tree argument |
| omnet `presentation/page/EmbedPanes.jl:510` | the first focus of an embedded tree, when it is built |

The examples that seat a selection on a bare document and then on the screen
(`Gallery.jl:233/393`, `LiveExamples.jl:120/129`) already end at the root.

## 3. Decisions

- **A write of the live selection starts at the root.** A verb that has the
  editor reroots its operation to the editor's document and evaluates it there.
  A reader answers a `ReplaceSelectionOperation`, which the projection chain
  already reroots. No code sets the live selection of an inner document.
- **A wrapper carries the selection of what it wraps when it is made.** When a
  wrapper is made around a document that holds a selection, the new wrapper is
  the root, so the selection is written there, one step longer. This is what
  `Application.jl:93` does by hand for the `UndoBuffer`.
- **The clipboard reads its own selection only.** `_get_clipboard_selection`
  goes; `_selected` and the two other callers read `input.selection`.
- **A wrapper names the step to what it wraps.** A new generic of the kernel's
  document layer, `get_wrapped_document_step(node)`, answers the one
  `ReferenceStep` from `node` to the document it wraps, or `nothing` for a
  document that wraps none. `get_wrapped_document` jumps to the innermost
  document and gives no path, so it can not serve. `UndoBuffer`,
  `ClipboardSlice` and `WidgetShell` answer `FieldReferenceStep("content")`.
- **A dormant selection stays where it is kept.** A group that is off the live
  path keeps the tab it shows as a dormant selection. That is not the live
  selection, and the rule does not move it.
- **A headless caller that holds the tree is its own root.** `focus_pane!(tree,
  …)` and the other verbs still take a bare `PaneTree`; there the tree is the
  root, and the write is at the root.

Names, checked against `naming-rules.md`:

| Name | What it is |
| --- | --- |
| `get_wrapped_document_step(node)` | the step from a wrapper to what it wraps, or `nothing` |
| `lift_wrapped_selection!(wrapper)` | writes the selection of what `wrapper` wraps into `wrapper`, one step longer |
| `get_window_tree_reference(editor)` | the reference from the editor's root to its pane tree; empty for a bare tree |
| `apply_pane_operation!(editor, operation)` | a new method: reroots `operation` by that reference and evaluates it at the root |

## 4. Steps

### Step 0 — baselines, and the tests that fail now

- [ ] projectured: `test_application()` 127, `test_shell()` 178,
      `test_substrate()` 63059 with 3 fail, 2 error, 1 broken, `test_kernel()`,
      `test_clipboard()`, `test_pane()`.
- [ ] omnet: `test_ide_window_wrap()` 32, `test_ide_file_navigator()` 8,
      `test_select_and_paste()` 81 pass, 4 fail, 1 error, `test_ide_closure()` 26.
- [ ] A test in `test_application()`, red now: in the window as the binary
      opens it, Ctrl+C copies the focused tab's content as the window opens,
      after `focus_pane!`, after a file opens from the navigator, and after
      Ctrl+T and a paste.
- [ ] A test helper, `find_stray_live_selections(root)`: every document under
      `root` whose live selection is not on the root's live path. The tests of
      Steps 2–6 assert it answers none.

### Step 1 — a wrapper names its step

- [ ] `get_wrapped_document_step` in `DocumentInterface.jl`, `nothing` in
      `DocumentDefaults.jl`, and a method each for `UndoBuffer`,
      `ClipboardSlice` and `WidgetShell`.
- [ ] `lift_wrapped_selection!(wrapper)` beside it.
- [ ] Tests in the kernel suite and in each wrapper's suite.

### Step 2 — the window is made with its selection at the root

- [ ] `make_clipboard_document`, `make_window_shell_document` and the
      `UndoBuffer` of `make_application_document` lift the selection of what
      they wrap. `Application.jl:93` goes.
- [ ] `make_window_scene` writes `.windows[1].content` and the content's
      selection into the screen.
- [ ] Test: as the application window opens, `get_selection(editor.document)`
      names the focused tab, and no selection is stray.

### Step 3 — the pane verbs write at the root

- [ ] `get_window_tree_reference(editor)`, walked as `get_window_tree` walks,
      with `get_wrapped_document_step` for each wrapper.
- [ ] `apply_pane_operation!(editor, operation)`: `reroot_operation` by that
      reference, then `evaluate_operation(editor, …)`. Every operation type the
      surgery makes reroots already: a write and a selection move get the
      prefix, and `MoveRangeOperation` carries its own collections.
- [ ] `open_pane!`, `focus_pane!`, `duplicate_pane!` and `_restore_focus!` use
      it.
- [ ] `_restore_shown!`: check whether `replace_selection!(group, …)` on a group
      off the live path makes a second live branch. If it does, write the kept
      tab as a dormant selection.
- [ ] Tests in `test_pane()`: after each verb, the root's selection names the
      focused tab, and no selection is stray.

### Step 4 — the clipboard reads its own selection

- [ ] `_get_clipboard_selection` goes; its three callers read `input.selection`.
- [ ] The test of Step 0 passes. `test_clipboard()` and `test_shell()` hold.

### Step 5 — the other writers below the root

Each is its own small design; the approach is the same: the reader answers a
`ReplaceSelectionOperation` that the chain reroots, or the operation carries
the root path.

- [ ] `SelectTabOperation` (`WidgetDocument.jl:2759`).
- [ ] `ReloadFileOperation` (`DocumentFile.jl:181`).
- [ ] The assistant's `_set_input!` (`AssistantTurn.jl:179`).
- [ ] `ConversationEditor.jl:80, 87, 96, 299`.
- [ ] The command palette (`CommandPaletteDecorator.jl`): first check whether
      the palette is in the window's document at all. A document that a
      decorator holds for itself is not under the root, and the rule does not
      reach it.

### Step 6 — omnet-julia

- [ ] `focus_runner_group!` and `_open_file_navigator!` use
      `apply_pane_operation!(editor, …)`.
- [ ] `open_simulation_pane!(tree, …)`: take the editor where a caller has
      one.
- [ ] `EmbedPanes.jl:510`: the embedded tree is its own root when it is built;
      check that the page that holds it lifts the selection.
- [ ] `test_select_and_paste()`: lines 304–317 and 434 pass.

### Step 7 — the guides, and close

- [ ] `selection.md`: the live selection is written at the root; a wrapper
      lifts the selection of what it wraps. `clipboard.md`: the clipboard reads
      its own selection. `pane.md`: a verb writes at the root.
- [ ] Move this plan to `plan/done/`.

## 5. Risks

| Risk | What is done about it |
| --- | --- |
| A verb now writes through the editor, so a write that was local to the tree reaches every level of the path. | That is the point of the rule. Each level already accepts the suffix, because a click writes the same path. |
| An operation type of a verb that does not reroot. | Step 3 lists the types; the catch-all of `reroot_operation` leaves an unknown type unchanged, so a new type gets a test with the verb that makes it. |
| A test that drives a bare tree now tests a different path from the window. | The bare tree stays a root of its own, and each verb gets a case with an editor too. |
| Another session edits the same files. | Rebase before each landing, and run the suites of the files that moved. |
