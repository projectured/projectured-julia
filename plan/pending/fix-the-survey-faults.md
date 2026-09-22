# Fix the faults that the documentation survey found

**Status (2026-09-22): IN PROGRESS.** Step 0 runs.

**Goal:** the faults in the code that `plan/done/package-design-documents.md`
lists in its section 7 are fixed, each one with a test that fails before the fix
and passes after it. The design documents that describe a fault as a limit are
updated in the same commit.

**Worktree:** `/home/projectured/workspace/projectured-julia-survey-faults`,
branch `survey-faults`, from `main` at `8c934f40`.

## 1. The request

> fix them, some hints from me:
>  - letter typed into a number clears the number should be ignored
>  - where the server starts should be controllable, also from the command line
>  - ignore tooltip/hover probe issues
>  - extend widget readers where they do nothing in a reasoable way

## 2. How the hints are read

- **A letter in a number.** A key that can not be part of a number is ignored:
  the number keeps its value and its text. A key that can start or continue a
  number (a digit, a sign, a point, an exponent) stays an edit as today.
  (My reading; the owner can correct it.)
- **Where the server starts.** The address of the MCP server, the host and the
  port, is a keyword of the editor and an option of the command line. The
  server also publishes the tools that `on_start` registers. (My reading.)
- **The probes.** The tooltip probe and the hover probe keep their faults;
  `plan/pending/hover-drag-and-tooltip-share-the-pointer.md` holds them.
- **Widget readers.** Each interactive widget whose reader does nothing gets
  the reader that its kind has in a common toolkit: a click toggles a toggle, a
  radio group selects an option, a text area edits text.

## 3. How a fault is fixed

1. Read the code, and confirm the fault. A claim of the survey that the code
   does not confirm is recorded as such and not changed.
2. Write the narrowest test that shows the fault, and run it red.
3. Fix the code, and run the test green, with the suite of the package.
4. Update the design document if it states the fault as a limit.
5. Commit, one commit for each fault or for a small group in one file.

Every run goes to one warm Julia session in the lane `taskset -c 24-27`, with a
memory cap of 20 GB. No second Julia process runs at the same time.

## 4. Steps

### Step 0: the worktree and the session

- [ ] The worktree, `LocalPreferences.toml` copied, the warm session loaded.

### Step 1: behaviour a user sees

- [ ] The statistics tab has a natural row.
- [ ] XML reads a numeric character reference, so a save does not change it.
- [ ] XML `=` in an attribute name (confirm first).
- [ ] SQL: a file with several statements, a function call, `JOIN … USING`.
- [ ] Console: Escape, an Alt chord, and a CSI key with modifiers.
- [ ] Assistant: Return while a turn streams does not start a second turn.
- [ ] PDF: the text size follows the font zoom; glyph fallback.
- [ ] YAML: export to a `.yml` path.
- [ ] JSON: a `\u` surrogate pair.
- [ ] A letter typed into a number is ignored.
- [ ] Value viewer: a chevron click opens the node (confirm first).
- [ ] `FaultCatchingProjection` follows the fault policy and passes an
      interrupt through.
- [ ] `FaultLog` keeps two exception types of one origin apart.
- [ ] The precompile recording sends Enter as `:return`.

### Step 2: the MCP server and the direct writes

- [ ] The address of the MCP server is a keyword and a command-line option.
- [ ] The MCP server publishes the tools that `on_start` registers.
- [ ] The assistant task and the MCP task post their operations through the
      inbox (confirm the design against `plan/done/the-editor-survives-a-fault.md`).

### Step 3: the widget readers

- [ ] List every interactive widget whose reader does nothing.
- [ ] `WidgetToggle`, `WidgetRadioGroup`, `WidgetTextarea`, and any other on the
      list, get a reader.
- [ ] `DuplicateTabOperation` travels unchanged.

### Step 4: text, collection, versioning, natural, graph, web

- [ ] `WordWrapping` and `TextFiltering` map a whole-element box (confirm).
- [ ] `TextFirstLine` maps the flat caret; `TextLineNumbering` maps a selection.
- [ ] `copy_document` of an endless `ListNode` ends.
- [ ] A version made with Ctrl+Shift+S has its author and time.
- [ ] The natural notation takes the most derived type; `_SYNTAX_PAIRS`.
- [ ] `GraphToGraphics` and the `GraphLayoutToGraphics` export.
- [ ] The web backend waits for input and can be woken; a test for it.
- [ ] `OdbcAdapter` catalog calls honour their `database` argument.

### Step 5: tests, dead code, comments

- [ ] `test_video()` runs its layering guard; the process atoms are in the catalog.
- [ ] Dead code: `SelectTabOperation`, the unused fields and functions.
- [ ] The stale comments and docstrings of section 7 of the survey plan.

### Step 6: close

- [ ] The suites of the changed packages pass, against a baseline of `main`.
- [ ] Land on `main`, and move this plan to `plan/done/`.

## 5. Decisions

## 6. Facts found on the way
