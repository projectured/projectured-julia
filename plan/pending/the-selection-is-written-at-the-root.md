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

1. **The pane verbs never enter the projection chain.**
   `apply_pane_operation!(tree, operation)` evaluates against a `PaneHost` whose
   document is the tree, so a verb moves the focus in the tree alone. The chain
   already reroots every answer on its way out: the undo buffer, the shell and
   the clipboard prefix `content`, and the screen prefixes `windows[i]`. A focus
   that a key or a click makes goes through them and works. The focus that the
   application builds its tree with never goes through them either.
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

- **A selection write is an answer of the chain.** A reader answers a
  `ReplaceSelectionOperation` at its own level, and every wrapper projection on
  the way out reroots it by its step. So the operation arrives at the editor
  rooted, and each document on the path gets its suffix. No code sets the live
  selection of an inner document.
- **A verb goes through the chain as a reader does.** A pane verb that has the
  editor reads its tree-level operation through `editor.projection` with the
  editor's io map, as a reader payload that the pane tree's reader answers with
  the operation. The wrappers reroot it, and the verb evaluates the rooted
  answer through the editor. The kernel's precedents for a payload are
  `ClaimedGesture`, `CollectIntents` and the tooltip's `PointerRest`: every
  reader that does not know a payload declines it.
- **The window's first focus goes through the chain too.** The tree is built
  with its focus, before a window exists. After the first print, the start of
  the window sends that focus through the chain with the same verb. omnet's
  `focus_runner_group!(editor)` already runs at that point.
- **The clipboard reads its own selection only.** `_get_clipboard_selection`
  goes; `_selected` and the two other callers read `input.selection`.
- **A dormant selection stays where it is kept.** A group off the live path
  keeps the tab it shows as a dormant selection. That is not the live
  selection, and the rule does not move it.
- **A headless caller that holds the tree is its own root.** `focus_pane!(tree,
  …)` and the other verbs still take a bare `PaneTree`; there the tree is the
  root, and `apply_pane_operation!(tree, …)` writes at the root.

**What changes as a result.** A verb's edit now passes the window's undo buffer.
An open, a close or a duplicate by a verb becomes one undo step, as the same
key's already is; a focus move alone is a bare selection move and is not a step.
The gesture log records the payload.

Names, checked against `naming-rules.md`:

| Name | What it is |
| --- | --- |
| `ApplyPaneEdit(operation)` | the payload: a tree-level operation that the pane tree's reader answers; a verb phrase, as `CollectIntents` is |
| `apply_pane_operation!(editor, operation)` | a new method beside the one for a tree: reads the payload through the chain and evaluates the rooted answer; prints once first when the editor has no io map |

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
      the later steps assert that it answers none.

### Step 1 — the pane verbs go through the chain

- [ ] `ApplyPaneEdit`, and the method of `PaneTreeToWidget`'s reader that
      answers it with its operation.
- [ ] `apply_pane_operation!(editor, operation)`.
- [ ] `open_pane!`, `focus_pane!`, `duplicate_pane!` and `_restore_focus!` use
      it when they have an editor.
- [ ] `_restore_shown!`: check whether `replace_selection!(group, …)` on a group
      off the live path makes a second live branch. If it does, write the kept
      tab as a dormant selection.
- [ ] Tests in `test_pane()` and `test_application()`: after each verb, the
      root's selection names the focused tab, and no selection is stray; an
      open by a verb is one undo step, and a focus move is none.

### Step 2 — the window's first focus

- [ ] The application's start sends the tree's focus through the chain.
- [ ] Test: as the window opens, `get_selection(editor.document)` names the
      focused tab.

### Step 3 — the clipboard reads its own selection

- [ ] `_get_clipboard_selection` goes; its three callers read `input.selection`.
- [ ] The test of Step 0 passes. `test_clipboard()` and `test_shell()` hold.

### Step 4 — the other writers below the root

Each answers a `ReplaceSelectionOperation` from its reader, which the chain
reroots, instead of writing a selection in its `evaluate_operation`.

- [ ] `SelectTabOperation` (`WidgetDocument.jl:2759`).
- [ ] `ReloadFileOperation` (`DocumentFile.jl:181`).
- [ ] The assistant's `_set_input!` (`AssistantTurn.jl:179`).
- [ ] `ConversationEditor.jl:80, 87, 96, 299`.
- [ ] The command palette (`CommandPaletteDecorator.jl`): first check whether
      the palette is in the window's document at all. A document that a
      decorator holds for itself is not under the root, and the rule does not
      reach it.

### Step 5 — omnet-julia

- [ ] `focus_runner_group!` and `_open_file_navigator!` use
      `apply_pane_operation!(editor, …)`.
- [ ] `open_simulation_pane!(tree, …)`: take the editor where a caller has
      one.
- [ ] `EmbedPanes.jl:510`: the embedded tree is built with its focus; check
      that the focus reaches the root the same way.
- [ ] `test_select_and_paste()`: lines 304–317 and 434 pass.

### Step 6 — the guides, and close

- [ ] `selection.md`: a selection write is an answer of the chain, and a verb
      goes through it. `clipboard.md`: the clipboard reads its own selection.
      `pane.md`: a verb goes through the chain, and its edit is an undo step.
- [ ] Move this plan to `plan/done/`.

## 5. Risks

| Risk | What is done about it |
| --- | --- |
| A verb now writes through the chain, so a write that was local to the tree reaches every level of the path. | That is the point of the rule. Each level already takes the suffix, because a click writes the same path. |
| An operation type of a verb that does not reroot. | The surgery makes a write, a selection move and `MoveRangeOperation`; the first two reroot, and the third carries its own collections. A new type gets a test with the verb that makes it. |
| A reader that does not decline an unknown payload. | Every reader must decline one already, for `PointerRest` and `CollectIntents`. Step 1's tests run the payload through the whole window. |
| A test that drives a bare tree now tests a different path from the window. | The bare tree stays a root of its own, and each verb gets a case with an editor too. |
| Another session edits the same files. | Rebase before each landing, and run the suites of the files that moved. |
