# Cut and paste edit through the content

**Status (2026-11-10): in progress, on the branch `clipboard-edits`. Steps 1, 2, 4, 5, 6 and 7 are done; step 3 waits for the owner (D2 below).** The owner approved the plan for
implementation (2026-11-10), so the decisions D1 to D6 that the assistant
proposed are approved with the plan. The owner answered Q1 and Q2 (2026-11-10).
No question is open.

**Goal:** Ctrl+C, Ctrl+X, Ctrl+V and Ctrl+Shift+V act in the same way on a range
of text and on a whole object, in every domain. A cut is a copy and a delete in
one step. A paste of text is the typing of that text. Ctrl+Z takes back each
cut and each paste as one step.

**Repository:** projectured-julia. No file that the plan changes is sealed. The
plan changes one kernel file, `operation/Operations.jl`, which
[SEALING.md](../../SEALING.md) marks `⬜` (not sealed).

**Branch:** `clipboard-edits`, in the worktree `../projectured-julia-clipboard-edits`.

**Related plan:** [one-text-domain-and-the-missing-text-keys.md](one-text-domain-and-the-missing-text-keys.md)
(pending). Its D1 says that only the text table types or removes a character.
This plan does not wait for it. After that plan, the delete of D1 and the typing
of D2 below come from the text table in every text. Another agent now changes
the assistant draft to the text domain under that plan, so this plan changes
nothing in the draft itself.

## 1. The request

> in projectured-julia the clipboard Ctrl-X key doesn't work properly for text
> range selections, the selected part is not cut, it's simply copied. Check what
> other combinations don't work for the typical copy-cut-paste operations, what
> tests and guards do we have? I would like to make it work for structural and
> text selections as well.
>
> create a plan

## 2. What exists

### What works and what does not

The assistant drove the application window of `main` (`f78dab9dc`) through the
editor loop: `_make_application_editor` with a `HeadlessBackend`, real mouse
presses and keys, and a fake system clipboard. A range is two Shift+Right after
a click, or a drag. A whole object is an Alt+click. Each result below is the
model and, where the table says so, the drawn text.

| Selection | Keys | Result |
| --- | --- | --- |
| Range in a JSON string, a JSON key, a JSON number, a YAML string, a Markdown run, an XML text, a plain text file | Ctrl+C, Ctrl+X, Ctrl+V | Correct. The cut removes the range in the model and on the screen. |
| Range in Julia code or SQL code | Ctrl+C, Ctrl+X, Ctrl+V | Nothing happens. A typed key and Delete also do nothing (see "Not in this plan"). |
| Range in a JSON string: type `Q`, Ctrl+Z, cut `Al`, Ctrl+Z | Ctrl+Z | Wrong. The cut stays, and the typed `Q` comes back: `"QAlice"`. |
| Range, Ctrl+V | Ctrl+Z | Wrong. Ctrl+Z gives no operation. The paste stays. |
| Whole object, Ctrl+C, Alt+click another object | Ctrl+V | Correct in JSON, YAML and Markdown. |
| Whole JSON value | Ctrl+X | The value becomes the generic `DocumentNothing`. The save of the file prints `empty document`. |
| Whole element of a JSON list | Ctrl+X | The element becomes a hole. The list keeps its length. |
| Whole YAML value | Ctrl+X | The value becomes `DocumentNothing`. The YAML projection has no arm for it, so the print of the file fails. |
| Whole Markdown run | Ctrl+X | Nothing happens, and nothing is copied. The slot does not admit `DocumentNothing`. |
| Whole JSON value, JSON element, JSON key, Markdown run, YAML value | Delete, Backspace | Nothing happens. |
| Whole JSON string | Ctrl+C | The system clipboard does not change. |
| Whole JSON string, Ctrl+C, a caret in another string | Ctrl+V | Wrong. The paste types the older text of the system clipboard, not the copied object. |
| Range `Al`, Ctrl+C, Alt+click on the whole JSON string `"Paris"` | Ctrl+V | Wrong. The JSON tree gets a `PrimitiveString`, which the JSON projection can not draw or save. |

The assistant did not see "Ctrl+X only copies" in these file kinds. The owner
saw it in the assistant draft (Q1). A second probe, built as the composer test of
[ApplicationTest.jl](../../test/projectured/editor/ApplicationTest.jl) builds its
window, writes the caret into the draft from the root, types `hello world`, and
selects `world` with five Shift+Left. There Ctrl+X cuts: the draft and the drawn
text become `hello `, and the clipboard holds `world`. So the fault needs the
range that a person makes in the real window. The owner did not say if the keys
or the mouse made it, so step 6 tests both.

### The causes

1. **No history reads a clipboard edit.** The clipboard is the layer 30 of the
   `:container` layers ([ClipboardWrapper.jl:80](../../source/platform/clipboard/ClipboardWrapper.jl#L80)).
   It is around the window history, the layer 5
   ([UndoBufferToAny.jl:247](../../source/platform/undo/UndoBufferToAny.jl#L247)),
   and around the history of each file tab, which the pane tree holds. The
   clipboard makes its edits itself and answers them up. A history records only
   an answer of its content or an operation with a route
   ([UndoBufferToAny.jl:111-145](../../source/platform/undo/UndoBufferToAny.jl#L111-L145)),
   so no history records a cut or a paste.
2. **The cut has its own delete.** `_clipboard_cut` writes `DocumentNothing()`
   at the selection ([ClipboardSliceToAny.jl:431-445](../../source/platform/clipboard/ClipboardSliceToAny.jl#L431-L445)).
   It does not know a list from a field. It does not use the nothing document of
   the domain, which `@domain` makes and `get_nothing_document` gives
   ([Domain.jl:858-861](../../source/platform/domain/Domain.jl#L858-L861)).
   The text cut is a second private delete
   ([ClipboardSliceToAny.jl:394-403](../../source/platform/clipboard/ClipboardSliceToAny.jl#L394-L403)).
3. **No rule deletes a whole object.** Delete and Backspace have no answer when
   the selection names a whole object.
4. **The system clipboard does not get an object.** The application wrapper
   gives the clipboard no `to_text`
   ([Application.jl:287](../../source/platform/application/Application.jl#L287),
   [ClipboardWrapper.jl:69-78](../../source/platform/clipboard/ClipboardWrapper.jl#L69-L78)).
   A paste at a caret reads the system clipboard before the stored copy
   ([ClipboardSliceToAny.jl:382-392](../../source/platform/clipboard/ClipboardSliceToAny.jl#L382-L392)).
5. **A slot admits a document of another domain.** The rules of
   `_is_slot_accepting` and `accepts_pasted_replacement` let a `PrimitiveString`
   into a JSON slot ([Clipboard.jl:271-311](../../source/platform/clipboard/Clipboard.jl#L271-L311)).

### The tests and the guards

| Test | What it covers |
| --- | --- |
| `test_clipboard()`, [ClipboardTest.jl](../../test/platform/projection/ClipboardTest.jl) | 30 test sets on the reader, with no editor loop: copy, cut, note and paste of a slice, the text mode, the text targets (copy, cut, paste, a number, line breaks, a record that refuses text), the paste rules, tools, frames, the system clipboard, a slow system clipboard. |
| `test_text_clipboard()`, [TextClipboardTest.jl](../../test/projectured/projection/TextClipboardTest.jl) | The editor loop: a paste at a JSON caret, and a copy and a paste of a range in a plain string. |
| `test_window_wrappers()`, [WindowWrappersTest.jl](../../test/platform/shell/WindowWrappersTest.jl) | Ctrl+C copies the tab that has the focus. |
| [ApplicationTest.jl](../../test/projectured/editor/ApplicationTest.jl) | Ctrl+C copies what the focus names. Ctrl+N notes a file, and Ctrl+V puts it into a form. Copy reference. |
| [ExplorerTest.jl](../../test/platform/explorer/ExplorerTest.jl), [PaneReaderTest.jl](../../test/platform/projection/PaneReaderTest.jl) | Ctrl+V adds a card to a dashboard. Ctrl+V on panes. |

The guards are the hooks of `ProjecturedDomain`: `accepts_pasted_document`,
`accepts_pasted_replacement`, `accepts_pasted_text`,
`make_pasted_document_operation` and `find_clipboard_document`. Also
`ClipboardCopyPolicy` and the `offered_gestures` of the wrapper.

On `main`, `test_clipboard()`, `test_text_clipboard()` and
`test_window_wrappers()` give 307 pass, 0 fail, 0 error (2026-11-10).

No test presses Ctrl+X in an editor loop. No test presses Ctrl+Z after a
clipboard edit. No test cuts an element of a list, or an object of a domain. No
test reads the system clipboard after the copy of an object.

## 3. The behaviour

`|` is the caret, `[…]` is a selected range, and `⟦…⟧` is a whole selected
object. The document is `{"name": "Alice", "city": "Paris", "list": [11, 22, 33]}`.

| Before | Keys | After |
| --- | --- | --- |
| `"name": "[Al]ice"` | Ctrl+X | `"name": "|ice"`. The clipboard and the system clipboard hold `Al`. |
| `"name": "[Al]ice"` | Ctrl+X, Ctrl+Z | `"name": "Alice"` |
| `"name": "|ice"`, the clipboard holds `Al` | Ctrl+V, Ctrl+Z | `"name": "|ice"` |
| `[11, ⟦22⟧, 33]` | Ctrl+X | `[11, 33]`. The clipboard holds `22`, and the system clipboard holds `22`. |
| `[11, ⟦22⟧, 33]` | Delete | `[11, 33]`, and nothing is copied. |
| `"name": ⟦"Alice"⟧` | Ctrl+X | `"name":` the JSON hole, as Delete leaves it. The clipboard holds the string. |
| `"name": ⟦"Alice"⟧` | Ctrl+X, Ctrl+Z | `"name": "Alice"` |
| A whole object in a record that refuses a paste | Ctrl+X | Nothing happens. The clipboard keeps what it held. |
| A range in a text that takes no edit, such as a log | Ctrl+X | Nothing happens, and nothing is copied. Ctrl+C copies the range. |
| `"name": ⟦"Alice"⟧`, Ctrl+C, then `"city": "Pa|ris"` | Ctrl+V | `"city": "Pa"Alice"|ris"`: the text form of the copied object. |
| Ctrl+C of an object in this window, then a copy in another program, then a caret | Ctrl+V | The text of the other program. |
| `"name": "Alice"`, Ctrl+C of the range `Al`, then `"city": ⟦"Paris"⟧` | Ctrl+V | `"city": "Al"` (Q2). |
| Ctrl+C of the range `Al`, then `"age": ⟦30⟧`, or a whole JSON object or list | Ctrl+V | Nothing happens (Q2). |

## 4. Decisions

- **D1. A cut is a copy and a delete, in one operation.** Ctrl+X stores what
  Ctrl+C stores, and adds the answer of the content to Delete at the same
  selection. When the content gives no answer, Ctrl+X does nothing and copies
  nothing. After the cut, the selection is where the delete leaves it. Proposed
  by the assistant, approved with the plan (2026-11-10). Rejected: the clipboard keeps its own deletes. Then each
  domain needs clipboard rules, and a cut can store a copy with no delete.
- **D2. A paste of text is the typing of that text.** At a caret or a range,
  Ctrl+V gives the content a `KeyPress` whose `text` is the whole pasted text
  ([KeyboardEvent.jl:60-82](../../source/kernel/event/KeyboardEvent.jl#L60-L82)).
  The answer of the content is the paste. The clipboard drops the line breaks at
  the end of the text, as now. A text of one line declines a typed text with a
  line break in it, as it declines Return. Paste-copy of text is the same edit.
  Proposed by the assistant, approved with the plan (2026-11-10). Rejected: the clipboard makes
  `ReplaceStringRangeOperation` itself. Then a paste goes past the typing rules
  of the domain and past the history.
- **D3. A paste of an object goes down to its place by route.** The clipboard
  makes the edit with the paste rules of today. It gives the edit to the content
  as an `Intent` whose `route` is the path to the place
  ([Intent.jl:26-37](../../source/kernel/intent/Intent.jl#L26-L37)), so each
  reader and each history on the way reads it. A paste that a document takes in
  its own way (`make_pasted_document_operation`) goes down in the same way. The
  late paste of a slow system clipboard gives the same edit and the same record.
  Proposed by the assistant, approved with the plan (2026-11-10). Rejected: give the clipboard a layer number below
  the history. The history of a file tab is inside the pane tree, so it still
  would not read the edit, and the window history would record the write of the
  stored copy.
- **D4. One delete of a whole object.** Delete and Backspace on a whole selected
  object remove it from its slot when nothing inside answered the key. From a
  list, the element goes. In a field, the field gets the nothing document of its
  domain, `get_nothing_document(get_domain_insertion(owner))`, when the slot
  admits it. Else nothing happens. `SelectionWalkingProjection` answers the key,
  as it answers the Alt walk
  ([SelectionWalking.jl:36-48](../../source/platform/focus/SelectionWalking.jl#L36-L48)),
  and gives the edit down by route (D3). Proposed by the assistant, approved with the plan
  (2026-11-10). Rejected: a
  rule in each domain. The Alt selection is generic, so the delete that goes
  with it is generic too. Also rejected: the generic `DocumentNothing`, which a
  domain view can not draw.
- **D5. The system clipboard holds the newest copy.** The clipboard of the
  application gets `to_text`: the natural text of the copied object
  (`print_natural_text`), when its kind has one. So Ctrl+C and Ctrl+X of an
  object write the system clipboard. The `ClipboardSlice` keeps the text that it
  wrote last. A paste at a caret types the text of the system clipboard when it
  is not that text, because another program copied after. Else the stored copy
  decides. Proposed by the assistant, approved with the plan (2026-11-10).
  Rejected: the stored copy always wins. Then
  a copy in another program never pastes into this window.
- **D6. Ctrl+Z takes back one clipboard edit.** By D1 to D4, each change of the
  content that a clipboard key makes is an answer of the content, or it goes
  down by route. So the history of the file tab records it as one step. The
  write of the stored copy and of the system clipboard stays out of every
  history, as now. Proposed by the assistant, approved with the plan
  (2026-11-10).

### Open questions

- **Q1. Where did Ctrl+X copy and not cut?** The probe cuts a range correctly in
  JSON, YAML, Markdown, XML and a plain text file. The owner answered
  (2026-11-10): "In the assistant draft typin field. Another agent is already
  changing that to use the text domain". Step 6 makes that case a test.
- **Q2. What does a paste of a text do on a whole selected object?** For
  example: Ctrl+C of `Al`, Alt+click on the string `"Paris"`, Ctrl+V.
  - **A.** The text replaces the text of the object, as typing over its whole
    value does (`find_value_range`): `"Paris"` becomes `"Al"`. A number takes
    only a text that is a number. An object with no value of its own, such as a
    JSON object or a list, refuses. Recommended by the assistant.
  - **B.** The domain of the slot parses the text as its natural text. `{"a": 1}`
    pasted on a JSON value makes an object, and a text that does not parse is
    refused.
  - **C.** A text pastes only at a caret or a range, and a whole object refuses
    it.

  The owner agreed to A (2026-11-10): "Agreed".

## 5. Steps

Each step runs `test_clipboard()`, `test_text_clipboard()` and
`test_window_wrappers()`, and from step 6 on also `test_clipboard_edits()`. A
step that changes a delete or a typing rule also runs the suites of the domains
that its tests press keys in: `test_json()`, `test_yaml()`, `test_markdown()`.

1. [x] **One delete of a whole object (D4).** Done in `5fda3d25b`, in the clipboard projection (see below). Delete and Backspace in
   `SelectionWalkingProjection`, with the slot rules of the paste: a list
   element, a field with the nothing document of its domain, a slot that refuses.
   The edit goes down by route. Tests in the editor loop: a JSON element, a JSON
   value, a Markdown run, a YAML value, a record that refuses, and Ctrl+Z after
   each.
2. [x] **A cut is a copy and a delete (D1).** Done in `5fda3d25b`. Ctrl+X reads the answer of the
   content to Delete and adds the copy to it. `_clipboard_cut`,
   `_text_clipboard_cut` and the `cut` keyword of `_text_target_copy` go. The
   text mode keeps only its copy. The test sets of `test_clipboard()` that read
   the old shape of a cut change to the new shape.
3. [ ] **A paste of text is the typing of that text (D2).** Not built: see "D2 is not built as written" below. The paste of text goes down by route instead, in `5fda3d25b`. Ctrl+V and
   Ctrl+Shift+V at a caret or a range give the content a `KeyPress` with the
   whole text. Check that each typing rule that a paste reaches reads the `text`
   of the `KeyPress`: the primitive string, the number, JSON, YAML, Markdown,
   XML and the text table. The late paste of `ApplyOsClipboardPasteOperation`
   gives the same edit.
4. [x] **A paste of an object goes down by route (D3), and a text on a whole
   object is typed over its value (Q2, A).** Done in `5fda3d25b`, with the edit of the clipboard, not a typed key (D2). Paste, paste-copy and
   `make_pasted_document_operation` send their edit down by route. A slot
   refuses a document of another domain. A stored text on a whole object goes to
   the content as the typed text of D2, over the range that `find_value_range`
   gives for the object. An object with no value range refuses it.
5. [x] **The system clipboard holds the newest copy (D5).** Done in `481eb3e12`, with no remembered text (see below). `to_text` in the
   clipboard of the application, the last written text in `ClipboardSlice`, and
   the rule of the paste at a caret.
6. [x] **Tests in the editor loop.** Done in `a783edd45`; the draft case runs on the draft of `main`, before the change of the draft to the text domain. A new file
   `test/projectured/editor/ClipboardEditTest.jl` with `test_clipboard_edits()`,
   in [ProjecturedSuite.jl](../../test/projectured/ProjecturedSuite.jl). It
   drives the application window, as the probe did, for each row of §3 in JSON,
   YAML, Markdown and a plain text file. Each row asserts the drawn text after
   the keys, and the drawn text before them after Ctrl+Z. Each row runs under
   the default focus and under an Alt selection. The case of Q1 is a range in
   the assistant draft, made once with Shift and the arrow keys and once with a
   drag of the mouse, through the gesture tracker as the application has it,
   then Ctrl+X, Ctrl+V and Ctrl+Z. The branch takes the change of the draft to
   the text domain from `main` before this test is written, so the test reads
   the draft as it will be.
7. [x] **Documentation.** Done: the guide of the clipboard names the new test; the testing guide lists no single feature test, so it has no row for it. [clipboard.md](../../documentation/package/platform/clipboard/clipboard.md):
   the gesture table, the cut as a copy and a delete, the paste of text as
   typing, the record in the history, the system clipboard. The descriptions of
   the gestures. The new test in
   [testing-guide.md](../../documentation/guide/testing-guide.md).

### What the implementation found

- **D4 lives in the clipboard projection, not in `SelectionWalkingProjection`.**
  The delete needs the slot rules of the paste (`_find_writable_slot`), which
  live in the clipboard slice. The focus slice may use only the collection
  slice (`PLATFORM_SLICE_EDGES`), and the domain slice may use no other slice,
  so the rules can not move below both. `ClipboardSliceToAnyProjection` reads
  Delete and Backspace after its content, as the walk reads the Alt keys after
  its content. A host that leaves out `:cut` gets no delete of a whole object.
- **D1: a cut of a whole object stores the object itself**, as before, not a
  copy. The object leaves the document, so nothing shares it, and a cut and a
  paste move it, a tool too. A cut of a range stores its characters.
- **D3: an edit goes to the deepest document of its place that the readers
  reach.** The default reader follows a route only where its IO map holds
  children. A reader with none answers no operation for a route below it
  ([ProjectionDefaults.jl:244-257](../../source/kernel/projection/ProjectionDefaults.jl#L244-L257)).
  So `_read_down_to_place` tries the place, then each document above it, with
  the rest of the path in the edit.
- **The bindings of the clipboard hold its IO map, and the IO map holds the
  recursion**, as the IO map of `Copying.jl` does. So a cut reads the content's
  delete with the existing `read_intent`. No new event, payload or reader method.
- **D5 needs no remembered text.** Each copy, cut and note of an object in the
  application writes the system clipboard: the value of a primitive, the natural
  text, or an empty text for an object with none. So the system clipboard is
  never older than the stored copy, and the rule of a paste at a caret stays: the
  text of the system clipboard, else the text of the stored copy.
- **Q2:** a stored text on a whole document of another kind, or an empty stored
  copy with no `from_text`, is typed over the `value` field of that document, or
  over its only field that holds text or a number. A stored text on a document
  of the same kind replaces it, as before. An empty place
  (`is_domain_placeholder`), such as a new tab or the hole that a cut leaves,
  takes the stored document, as before; `test_application` showed it, because a
  paste into a new tab from Ctrl+T must fill it. In a hole of a domain, a stored
  text becomes the insertion of that domain with the text in it
  (`get_domain_insertion`), so the hole holds a document of its own domain.
  `is_domain_placeholder` names the general type, such as `JsonNothing`, so the
  clipboard asks it with `Base.typename(typeof(document)).wrapper`, not with the
  concrete type `JsonNothing{Cell, Cell}`.
- **Test results on the branch (2026-11-10):** `test_clipboard` 233, `test_text_clipboard`
  12, `test_window_wrappers` 74, `test_clipboard_edits` 34, `test_explorer` 383 and
  `test_pane_reader` 89 pass. `test_application` gives 405 pass, 1 fail and 2 broken, as
  `main` does (the known failure at `ApplicationTest.jl:1012`). `test_kernel` alone gives
  5144 pass and 2 broken; in a process with other test packages it fails one check at
  `BuildEditorTest.jl:257`, a known effect of the process and not of the branch.
- **D2 is not built as written.** The text of a paste comes from the system
  clipboard, which a reader can not read. So the paste of text always ends in
  the evaluation of `ApplyOsClipboardPasteOperation`. An evaluation can send an
  operation down by route (`read_rooted_operation`), but no existing way reads a
  typed key there. So the paste of text stays the edit that the clipboard makes
  (`_make_text_target_edit`), sent down by route, and the history records it.
  The owner decides between this and a new mechanism.
- **Ctrl+Z after the delete of an element failed before this plan.** The way back
  of a splice puts back the slots of the list, which are cells, and the write
  checked each item against the declared element type, which a cell is not
  (`DeclaredTypeMismatchException`). `_convert_slot_value` in
  [Operations.jl](../../source/kernel/operation/Operations.jl) now puts a slot
  back as it is, because it was in the list before.
- **At the reader level, the text table of a document answers Delete**, so the
  unit tests of `test_clipboard()` cut a range with `IdentityProjection` too.

## 6. Limits after the plan

- A whole object has a delete only in a window that has the `clipboard`
  wrapper, because only that wrapper gives the Alt walk.
- A paste of the single text `"\t"` is read as Tab.

**Not in this plan:** the caret in Julia and SQL code stops at a
`ProjectionReferenceStep` of the syntax leaf, so typing, Delete and the
clipboard all fail there ([syntax-tree-selection.md](syntax-tree-selection.md)
holds that point); a range across lines or across runs; in XML, a click on the
first letter of a text with spaces before it puts the caret into the spaces;
what the save of a file prints for a hole; in the text mode of the clipboard, which no window uses, a range made by a click and Shift+Left in an editor loop copies nothing. The cause is not found; one candidate is that `get_selection_substring` refuses a range whose start is after its stop.
