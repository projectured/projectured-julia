# Fix the faults that the documentation survey found

**Status (2026-09-22): IN PROGRESS.** Step 1 runs.

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

- [x] The worktree, `LocalPreferences.toml` copied, the warm session loaded
      (168 s). The session runs as the systemd unit `survey-faults-session`;
      `run.sh` and `restart.sh` in the scratchpad drive it.

### Step 1: behaviour a user sees

- [x] The statistics tab has a natural row. `ProjecturedStatistics` depends on
      `ProjecturedNatural` now. `e829dd19`.
- [x] XML reads a numeric character reference, so a save does not change it.
      `a89c7a84`.
- [x] XML `=` in an attribute name: confirmed; the binding has `override`.
      `d2581e7f`.
- [x] SQL: several statements parse into a `SqlStatementList`, a raw
      expression is a `SqlRawExpression` that prints unquoted, and
      `JOIN … USING` has a printer rule. `f9d8adfc`.
- [x] Console: Escape, an Alt chord, and a CSI key with modifiers. A lone ESC
      waits at most 50 ms for more bytes. `a0541528`.
- [x] Assistant: Return while a turn streams does not start a second turn.
      `7517bfee`.
- [x] PDF: the text size follows the font zoom (`2944a74d`); a text is split
      into runs by the font that draws each character, and each font is
      embedded; a CFF font is skipped (`532a3120`).
- [x] YAML: export to a `.yml` path. The guard compares the parsers, through
      the new `find_natural_parser(format)`. `f7a804bd`.
- [x] JSON: a `\u` surrogate pair. `d07ae6d9`.
- [x] A letter typed into a number is ignored: the evaluation of a number edit
      ignores a replacement with a character that can not be part of a
      number, and the template reader declines it. `5143ce0b`.
- [x] Value viewer: confirmed, with two causes. `ReflectionFeed` syncs the
      shadow on the editor task, and `ReflectionToWidget` reads the shadow in a
      cell. `3211b6ec`.
- [x] `FaultCatchingProjection` follows the fault policy and passes an
      interrupt through. The printer context carries `:fault_policy`.
      `3d3f5d79`.
- [x] `FaultLog` keeps two exception types of one origin apart: a line matches
      by the key of the record. `9b8a30b4`.
- [x] The precompile recording sends Enter as `:return`. `501b00c0`.

### Step 2: the MCP server and the direct writes

- [x] The address of the MCP server is a keyword (`mcp_host`, `mcp_port`) and
      a command-line option (`--mcp`, `--mcp=PORT`, `--mcp=HOST:PORT`).
      `stop_mcp!` now closes the transport, so the port is free after a quit.
      `158ff8ca`.
- [x] The MCP server publishes the tools that `on_start` registers: the server
      starts after `on_start`. A tool registered later is still not listed;
      the MCP library reads its own tool vector. `e95e9e5d`.
- [x] The assistant task and the MCP task write through the inbox:
      `run_on_editor_task!` runs a function on the editor task and waits for
      its answer, or runs it at once when no loop runs. `04f4d9a8`. This fixes
      the race that section 9 of `plan/done/the-editor-survives-a-fault.md`
      records.

### Step 3: the widget readers

- [x] List every interactive widget whose reader does nothing: `WidgetToggle`,
      `WidgetRadioGroup`, `WidgetTextarea`, `WidgetAccordion`. The other seven
      printer-only widgets have no field that a person changes.
- [x] The four get a reader: a press and Space or Return toggle a toggle; a
      press and the arrows select a radio option; a text area edits a text
      document as `WidgetText` does, with Return as a new line; a press on a
      header opens or closes an accordion item. `d0adbfbd`.
- [x] `DuplicateTabOperation` travels unchanged. `a0d59f09`.
- [x] `SelectTabOperation` is removed; a tab click is a
      `ReplaceSelectionOperation`. `dc8a432c`.

### Step 4: text, collection, versioning, natural, graph, web

- [ ] `WordWrapping` and `TextFiltering` map a whole-element box (confirm).
- [ ] `TextFirstLine` maps the flat caret; `TextLineNumbering` maps a selection.
- [ ] `copy_document` of an endless `ListNode` ends.
- [ ] A version made with Ctrl+Shift+S has its author and time.
- [ ] The natural notation takes the most derived type; `_SYNTAX_PAIRS`.
- [ ] `GraphToGraphics` and the `GraphLayoutToGraphics` export.
- [x] The web backend waits for input and can be woken; `test_web_backend()`
      is its first test. `cac149c8`.
- [x] `test_package_graph()` passes: its table of domain edges follows the
      `Project.toml` files. `7c3530bb`.
- [ ] `OdbcAdapter` catalog calls honour their `database` argument.

### Step 5: tests, dead code, comments

- [ ] `test_video()` runs its layering guard; the process atoms are in the catalog.
- [ ] Dead code: `SelectTabOperation`, the unused fields and functions.
- [ ] The stale comments and docstrings of section 7 of the survey plan.

### Step 6: close

- [ ] The suites of the changed packages pass, against a baseline of `main`.
- [ ] Land on `main`, and move this plan to `plan/done/`.

## 5. Decisions

- **Fix agents run one at a time.** They share the warm session, and a
  restart by one would break the runs of another.
- **A printer context with no fault policy counts as the strict policy.**
  `PAR-REPORT-NEVER-THROWS` asks that a barrier that a test can reach catches
  nothing by default. The editor loop puts its own policy into the context, and
  it drops the printed projection when the policy changes.
- **A tool call runs on the editor task, and the frame waits for it.** The
  in-window assistant and an MCP client then see the same tool. The first
  description search of a build can hold the frame for up to 30 s; a read-only
  flag for each tool would lift that. A fault in a streamed part goes to the
  fault log, and the turn goes on. An operation that is posted after the last
  frame is dropped when the loop ends; a pending call runs then, so no caller
  waits forever.
- **The MCP server starts after `on_start`.** A listing at request time needs a
  hook that the MCP library does not have.
- **A SQL statement ends at `;` or at the end of the text.** Extra text after a
  statement raises an error now; before, it was ignored. A SELECT in a
  `SqlStatementList` prints its `;`.

## 6. Facts found on the way

- New faults from group A1, not in the survey: `SELECT a + 1 FROM t` reads as
  `SELECT a`; `SELECT 1` prints an empty `FROM`; the SQL tokenizer raises
  `StringIndexError` on non-ASCII text; a JSON `\u` with non-hex digits raises
  `ArgumentError` and not the parser error. The last two go into step 4.
- New faults from group A2: a string edit writes a `String` into a number field
  that holds `nothing`, so `5` typed into a cleared number gives `"5"`; a
  `JsonNumber` inside a container gets a `ReplaceStringRangeOperation`, not the
  retype. `test_message_log` fails 4 of 8 on `main`: it checks the log before
  a feed drains it. All three go into step 4.
- New faults from group A4: the MCP library replaces the global logger when it
  starts, so with `--mcp` the message log gets no more records;
  `EvaluateDraftTurnOperation` (Alt+Return) has no guard while a turn streams;
  the layer numbers of `agent.md`, `editor.md` and `SEALING.md` disagree, and
  the `AgentModule` docstring names a missing `AgentServer.jl`. Two failures
  of `test_assistant_mvp` (lines 677 and 721) expect the normalised source
  that `_eval_code` no longer returns; they were hidden behind errors before.
- New faults from group A5: a press on a control does not move the focus to it;
  `WidgetText` and `WidgetTextarea` with a plain string are read only but Tab
  stops on them; the accordion draws its titles and bodies as strings;
  `WidgetList` and `WidgetSpinBox` take the arrow keys with any modifier, so
  Alt+arrow never reaches the selection walk; the checkbox and the switch
  toggle on any mouse button; `plan/tentative/evaluate-operation-document-arg.md`
  still names `SelectTabOperation`.
- `test_catalog_coverage` fails on `main` for 28 types (Assistant, Process,
  Pane, FaultLog and others). It is not caused by this work.
