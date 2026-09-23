# An evaluation moves the selection from the root

**Status (2026-09-23): PROPOSED.** Written at the owner's request ("write the
plan first"). Nothing is implemented. The choices in §5 are the owner's, and no
step starts before the owner answers them and asks for the implementation.

**Goal:** after every operation, the live selection is one path from the root.
No evaluation writes the live selection of a document below the root, also when
that document is not on the root's live path.

**Repositories:** projectured-julia. omnet-julia has no site of this kind (§2),
but its suites drive the assistant, the composer and the evaluator, so they run
after each step.

**Rules this plan keeps:** PAR-SELECTION-WRITTEN-AT-ROOT, PAR-READER-IS-PURE,
PAR-ONE-WAY-TO-EDIT, PAR-REGISTER-NEW-OPERATION, PAR-NO-NEW-SYNTHETIC-EVENT.

## 1. The problem

This is part 2 of plan `an-operation-enters-at-any-reference` (in `plan/done/`).
That plan fixed the verbs, which now say their edit at a place and let the
readers lift it to the root. It left out the evaluations that write a selection,
because routing can not fix them: an operation is evaluated after the readers
have run, so no reader lifts what the evaluation writes.

PAR-SELECTION-WRITTEN-AT-ROOT says: the live selection is one path from the root,
and each document on that path holds its suffix of it. A write that starts below
the root changes the suffixes below its start and leaves every document above it
with an old path or none. A dormant selection, which a document keeps off the
live path, is not the live selection, and the rule does not apply to it.

The code has two shapes of such a write:

- **A. The operation names a document, not a path.** The composer's operations
  carry their draft, `ReloadFileOperation` carries its file, and the assistant's
  operations carry the assistant. The evaluation writes a caret on that document.
  In the composer, `sync_draft_selection!` then writes the caret again from the
  root, but only when the root's selection already passes through the draft.
  When it does not, the local write stays: a live selection off the root's path.
- **B. A fallback writes the document's own selection.** The evaluator writes
  from the root when the root's selection passes through the toplevel, and
  otherwise it writes the toplevel's own selection.

## 2. What the code writes now

Found on 2026-09-23 by a read-only search of `source/` and `example/` in both
repositories, for `set_selection!`, `replace_selection!`, `clear_selection!` and
a direct write of a `selection` field or cell: 47 lines in projectured-julia, 2
in omnet-julia. **Not yet measured in a running window**; Step 0 does that.

### Writes of a live selection below the root

| Where | What it writes | When | Shape |
| --- | --- | --- | --- |
| `conversation/ConversationEditor.jl`, `_set_value!` (called at lines 266, 274, 283) | the caret in the active part's content | a character, a new line or a delete in the composer | A, then a sync from the root when it can |
| `conversation/ConversationEditor.jl`, `_replace_active!` (called at lines 329, 345, 374, 381) | the caret at the end of the document that takes the active part's place | the composer grows, commits or evaluates a part | A, then a sync when it can |
| `conversation/ConversationEditor.jl`, `reset_draft!` (line 438) | the draft's own selection, on its first part | after a submit (`AssistantTurn.jl` lines 295 and 344) | A, then a sync when it can |
| `assistant/AssistantTurn.jl`, `_set_input!` (line 180; called at 189, 195, 222, 270) | the caret at the end of the assistant's input | clear, reset, submit of Julia, submit of prose | A, with no sync from the root |
| `fileformat/DocumentFile.jl`, `ReloadFileOperation` (line 181) | `file.selection = nothing` | Ctrl+R on a file | A; the documents above keep a path into the old content |
| `conversation/Evaluator.jl`, `_select_in_toplevel!` (lines 342–347) | the toplevel's own selection | Up, Down or a press on a form, when the root's selection does not pass through the toplevel | B |

### Writes that keep the rule

- **At the root:** `ReplaceSelectionOperation` and `SelectNextInsertionOperation`
  (`kernel/operation/Operations.jl`), `ReplaceTextRangeOperation`
  (`text/TextDocument.jl`), the primitive edits (`primitive/PrimitiveDocument.jl`),
  the undo restore (`undo/UndoDocument.jl`) and the fault barrier all write at
  `editor.document`. `_select_under!` and `sync_draft_selection!` write from the
  root.
- **When a wrapper is built:** `ClipboardWrapper.jl`, `WindowShell.jl`,
  `WindowScene.jl` and `make_application_document` lift the inner selection to
  the new root (part 3 of the earlier plan, done).
- **A document that nothing holds yet:** the clipboard and the versioning clear
  the selection of a copy; `_with_hole` (`math/MathToGraphics.jl`) and
  `_new_typein` point a new node at its hole or caret, and the code that inserts
  it then writes from the root; the video recorder selects in its own root.
- **Dormant:** `_restore_shown!` (`pane/PaneProgram.jl`) and the embedded panes of
  omnet-julia (`presentation/page/EmbedPanes.jl`) set the tab that a group
  shows. The widget's tabbed pane, its page and the split pane keep a dormant
  selection too. The earlier plan's row `SelectTabOperation` is gone: no such
  operation exists now.

### Selections outside the editor's document

- **The command palette** (`gesturehelp/CommandPaletteDecorator.jl`, lines 185,
  215, 221). The palette document lives in the decorator's state and is drawn
  over the output; nothing in the editor's document holds it, so it is its own
  root. Its reader writes the palette's query and selection, which is a question
  for PAR-READER-IS-PURE, not for this plan.
- **The file-system view** (`filesystem/WorkspaceToFileSystem.jl`, lines 76–84).
  A selection inside the view names a node of a computed document, a projection's
  output, which has no path from the root. The reader answers an operation that
  writes that selection on the computed document, and selects the workspace as a
  whole. So two selections show at once: the root's, which ends at the
  workspace, and the computed document's own. §5, question 3.

## 3. What the fix must give

- After every operation, each document that holds a live selection is on the
  root's path, and each other document holds none or a dormant one that its
  type allows (`has_dormant_selection`).
- The caret still lands where a person expects it: at the end of a typed text, in
  the new type-in after a submit, and nowhere inside the old content after a
  reload.
- An evaluation that runs while the person works elsewhere does not take the
  focus. Example: a turn that ends, or a submit that an MCP client makes, must not
  move the live selection into the assistant while the person types in another
  pane.

## 4. The options

**Option 1 — the reader says the selection.** The reader that answers a composer,
reload or evaluator operation also answers the selection change: a
`ReplaceSelectionOperation` at a path from its own input, in one
`CompoundOperation` with the edit. Every reader above reroots it, as it reroots
the answer to a click, and the editor evaluates it at the root. The evaluation no
longer writes a selection. No new mechanism: `CompoundOperation`,
`ReplaceSelectionOperation` and `reroot_operation` exist. The cost: the reader
must know where the caret goes after the edit. For text it does, because the
caret moves by the length of the text. Where the evaluation builds the new part
(the composer evaluates an insertion into an `EvaluatorForm`), the path into the
new part must be known before the part exists, which Step 0 checks row by row.

**Option 2 — the evaluation writes from the root.** A function finds the path
from the root to the operation's document, by a search by identity
(`search_references` with `descend`), and writes the whole path at the root.
`sync_draft_selection!` and `_select_under!` already do this when the root's
selection passes through the document; the function would do it for any
document. The cost: a search for each write, a document that two paths reach is
ambiguous, and the write takes the focus from wherever the person is, which §3
forbids for a document off the live path.

**Option 3 — off the live path, no live write.** When the root's selection does
not pass through the operation's document, the evaluation writes no live
selection. Either the document keeps the caret as a dormant selection, which
needs `has_dormant_selection` for the draft, the assistant's input and the
evaluator's toplevel, or the caret is dropped and the focus puts it where the
person clicks when they come back.

**Recommended: Option 1 for every operation that a reader answers, and Option 3
for the rest.** Option 1 makes the selection change part of the answer, which is
the one thing PAR-SELECTION-WRITTEN-AT-ROOT asks for, and it keeps the reader
pure. Option 3 covers the evaluations that no gesture of the person caused, and
it keeps the focus where the person is. Option 2 is not recommended, because it
moves the focus.

## 5. Open questions for the owner

1. **Which option, or which mix?** The recommendation is in §4.
2. **May the draft, the assistant's input and the evaluator's toplevel keep a
   dormant caret?** Today only the pane and widget containers may. With a
   dormant caret, a person who leaves the assistant and comes back finds the caret
   where it was; without one, the caret goes where the click puts it.
3. **The file-system view:** may a projection's output keep a selection of its
   own, as it does now, or must the selection in the view be a path from the root
   into the workspace, through the view?
4. **Do the composer operations keep naming their draft?** The earlier plan
   skipped the question whether an operation can carry a path in place of a
   document. Option 1 does not need an answer: the selection travels as a path,
   and the edit may keep its document. The recommendation is to leave it out of
   this plan.

## 6. Steps

Every step waits for the answers of §5 and for the owner's word to implement.

### Step 0 — facts
- [ ] Move `_app_find_stray_live_selections` and `_app_is_one_path` from
      `ApplicationTest.jl` to a test helper that the conversation, assistant,
      evaluator and file-format tests can call.
- [ ] Measure each row of §2 in the application window: do the gesture, then
      check that the selection is one path and that no live selection is off it.
      Do it once with the document on the live path and once off it. Record
      which rows fail.
- [ ] For each composer operation, find whether the reader can know the caret
      after the edit (Option 1), and record the ones where it can not.

### Step 1 — the composer
- [ ] The composer operations of `ConversationEditor.jl`, by the chosen option.
      `sync_draft_selection!` and `_select_under!` stay only where the chosen
      option needs them.

### Step 2 — the assistant's input and the submit
- [ ] `_set_input!` and `reset_draft!`, and the four operations that call them.

### Step 3 — the reload of a file
- [ ] `ReloadFileOperation` moves the selection to the file as a whole from the
      root, or writes none when the file is off the live path.

### Step 4 — the evaluator's fallback
- [ ] `_select_in_toplevel!` writes no live selection below the root.

### Step 5 — the file-system view
- [ ] By the answer to §5, question 3. No change if the owner keeps the
      computed document's own selection.

### Step 6 — tests and suites
- [ ] One test for each row of §2: after the operation, the selection is one
      path and no live selection is off it, with the document on the live path
      and off it.
- [ ] Suites: `test_application`, the conversation, assistant, evaluator,
      file-format and file-system suites, `test_kernel` with its known failures,
      and in omnet-julia `test_ide` without the two model tests and
      `test_campaign_ui`. The static guards of both repositories.

### Step 7 — the guides
- [ ] `kernel/selection.md`: how an evaluation moves the selection, and which
      documents keep a dormant one. The guides of the conversation and the
      assistant, where they describe the caret.
