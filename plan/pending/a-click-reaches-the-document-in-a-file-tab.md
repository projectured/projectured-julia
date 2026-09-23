# A click reaches the document in a file tab

**Status (2026-09-23): IMPLEMENTED** on branch `file-reader`; landing on `main`
waits for the owner's approval. The owner reported the bug and asked for
the fix ("yes, do it").

**Goal:** a press, a key and an Alt+press inside a file tab reach the document
that the file holds: a press puts the caret in the JSON, a key edits it, and an
Alt+press selects the innermost object, not the whole file.

**Repositories:** projectured-julia. omnet-julia's IDE opens files with the same
`make_file_tab`, so it gets the fix with no change of its own.

**Rules:** PAR-DELEGATE-AND-LIFT, PAR-RECURSION-CONTRACT, PAR-READER-IS-PURE.

## 1. The problem

The owner opened a JSON file from the explorer of the application. A click in it
put no caret, and an Alt+click selected the whole content of the tab.

Found on 2026-09-23, by a probe in the application window and at the level of the
file:

- `FileToContent`, the projection that draws a `FileDocument`, has no reader of
  its own. For a press or a key, the kernel's default reader treats a projection
  with no reader as a leaf: it asks only `read_gesture` of its input document.
  That input is the `JsonFile`, whose gestures are Ctrl+S and Ctrl+O. So a press
  never reaches the JSON inside the file, and an Alt+press stops at the file and
  selects it whole.
- With the application's own projection, the JSON document alone answers a press
  on "Alice" with a caret in the string, `entries[1].value.value{0}`. The same
  JSON in its `JsonFile` answers `nothing`.
- The bug is older than the work of 2026-09-23: commit `d7a440f9` behaves the same.
  `FileToContent` came with commit `56919ed3` on 2026-09-18, and no test clicks or
  types inside a file tab.

## 2. The fix

`FileToContent` gets a reader of its own, in the form of the undo buffer's reader
(`UndoBufferToAnyProjection`), which wraps one content in the same way:

- A gesture goes to the content first. Its answer comes back with the step
  `content` in front of each reference (`reroot_operation`).
- When the content does not answer, the file's own gestures answer
  (`read_gesture` on the file: Ctrl+S and Ctrl+O).
- A collection of intents, for the command palette and the help window, takes the
  content's intents and the file's, merged.
- An operation with a route follows it through `content`.

## 3. Steps

### Step 1 — the reader
- [x] A 4-argument `read_intent` for `FileToContent`, and the 3-argument payload
      form. The package gets the alias `IntentModule` for the kernel's module, and
      `FileFormatModule` uses it.

### Step 2 — tests
- [x] At the level of the file (`FileTabTest.jl`): a press on a string answers a
      caret in it, `.content.entries[1].value.value{k}`, and Ctrl+S still answers
      the save.
- [x] In the application window: open a JSON file from the explorer, click into
      it, and the root's path ends at a caret in the string; a typed character
      edits the string; an Alt+click selects the string, not the file.
- [x] Found on the way: `test_file_tab` had one error on `main` since commit
      `2959e182` of plan `an-evaluation-moves-the-selection-from-the-root`. Its
      Ctrl+O case evaluated the key's answer with no editor, and that answer now
      holds a selection that needs one. The case now checks the answer and
      evaluates the reload alone. The suites of that plan did not include
      `test_file_tab`.
- [x] Two application test sets selected the whole file with an Alt+click on its
      text, which is the bug. They now Alt+click the string and walk out to the
      file with Alt+Up, and they keep testing what they are for: noting the file,
      and copying its reference.
- [x] Suites: `test_file_tab` 13/13, `test_application` 294/294,
      `test_filesystem` 28/28, `test_undo` 91/91, `test_file_dialog` 11/11,
      `test_text_clipboard` 8/8, `test_clipboard` 201/201, `test_command_palette`
      39/39, `test_command_palette_decorator` 63/63, `test_gesture_help` 42/42,
      `test_window_shell` 83/83, `test_shell` 180/180, `test_pane_gestures` 73/73,
      `test_substrate_layering` 203/203, `test_package_graph` 661/661; the naming,
      argument, tree and documentation guards. omnet-julia is not run: no test
      there presses or types inside a file tab (`IdeNavigatorTest` checks only
      what the tab draws).

### Step 3 — the guide
- [x] `fileformat/fileformat.md` says how a file tab reads a gesture.
