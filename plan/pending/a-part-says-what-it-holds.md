# A part says what it holds

Status: IN PROGRESS, 2026-10-21, on the branch `part-notes`, in the worktree
`projectured-julia-part-notes`. Not landed on `main`. The user, 2026-10-21: "yes,
let's go". Wave 1 of
[a-catalog-of-what-each-part-could-say.md](a-catalog-of-what-each-part-could-say.md).

## The ask

The user, 2026-10-21, after the catalog: "write the plan and give me the
questions", for wave 1: the parts whose data is on hand, in projectured-julia and
omnet-julia.

## The problem

The facts at projectured-julia `main` `3200dffe7` and omnet-julia `main`
`2b3ca573`. The catalog gives the file and the line of each part.

1. **Most Explorer rows say nothing.** A row says `make_decoration_note`: the
   condition words and `decoration.tooltip`. Only a task group and a folder that
   failed set `decoration.tooltip`. A file, a healthy folder, a section, a log, a
   tool and a system process say nothing; a task, an assistant and a search say
   one word.
2. **Every untitled assistant reads "Assistant".** `get_document_title(::Assistant)`
   answers the constant `ASSISTANT_TITLE` when `agent_title` is empty, and the
   row label is that title.
3. **27 controls show a glyph and say nothing**: the Appearance "−", "+", "‹",
   "›", Step, Fix and Reset; a filter chip "×"; the ".*" toggle; the process
   Interrupt and Stop; the find "‹" "›" of a task stream; and others.
4. **Data arrives and is not shown**: the descriptions of the agent options
   (Model, Effort, Mode), `describe_agent_usage` in the assistants table, the
   default and the range of a setting.
5. **omnet-julia rows say a failure or nothing**, while each holds its data: the
   project (`read_project_facts`), a configuration, a run, the Runner, a result
   file (its size and time are stored), the NED entries, the stores.
6. **A row note built in the decoration costs on each change.** `_make_tree_node`
   builds the whole row in the computation of the node, and that computation
   reads the decoration. A fact that changes often, such as the position of a
   running task or the memory of a process, would rebuild the row at each
   change, although nobody reads the note until the pointer rests on it.

## The decision

The user answered the three questions on 2026-10-21: "1: yes", "2: agreed",
"3: yes".

- **A note is made when the pointer rests** (question 1: yes). A `tooltip` of a
  widget, a `PaneTabTitle` and `decoration.tooltip` may be a function with no
  argument that makes the note. The dwell calls it; `make_decoration_note` keeps
  the conditions and calls it then. So a row reads its facts only when a person
  asks, and a fact that changes often rebuilds nothing.
- **Facts, not gestures, on a row.** A row of the Explorer does not repeat the
  press, the double press and the Ctrl+press in a hint: they are the same on
  each row, and the gesture help lists them. A hint stays for a part with a
  gesture of its own.
- **Stored values only.** A note reads what a document holds. A file row shows
  its path, its format and, when it is read, its lines; not its size or its
  time, which need a disk read and wait for the stored file stamp of wave 2
  (question 2: agreed).
- **An untitled assistant has its overview title as its label** (question 3:
  yes). `get_document_title(::Assistant)` answers
  `compute_assistant_overview_title` when `agent_title` is empty, so two
  assistants no longer look the same, and the row matches its note.

## Steps

The steps are fixed. Each step is one commit. projectured-julia lands first,
because the omnet-julia steps use the function form of step 1.

1. [ ] **The note made at the dwell.** `_as_tooltip_document` calls a function;
   `make_decoration_note` answers a function when `decoration.tooltip` is one;
   the tree row and the tab call it at the dwell. Test: `test_widget_tooltip()`,
   `test_document_decoration()`, `test_widget_tree()`, and a check that a fact
   that changes does not rebuild the row.
2. [ ] **The Explorer rows of the platform.** Each gives a note through its
   decoration:
   - a file: its name, the path, the format, and the lines when it is read;
   - a folder: the path, the entries, or "not read yet";
   - a section: the entries; the keys of Rename and Add;
   - a task: the task line, the state, the result, the start, the duration,
     the position, the process and its memory, the reason, and
     `format_task_details` as the text;
   - a closed task group: its stored summary;
   - a search: what it looks for, the matches, the waiting nodes, the depth,
     the start and the time it took;
   - an assistant: `compute_assistant_overview_title`, the model, the backend,
     the context used, the prompts, the start, the busy time; and the label of
     an untitled assistant is its overview title;
   - a subagent, a turn, a part, a tool call and a request: their fields;
   - a dashboard and a card: the cards; the note of the content;
   - the logs and the tools: what each shows, and the counts kept, the
     capacity, the errors and the faults;
   - a system process: the full command as code, the folder, the state, the
     threads, the start.
   Test: a new `test_explorer_row_notes()`, and `test_explorer()`.
3. [ ] **The Explorer controls.** The filter field (Ctrl+F from the binding, the
   effect of Return and Escape), the kinds item (the kinds shown), the add item
   (the kinds offered), the items of the row menu and the add menu, the cards of
   a section page. Test: `test_explorer()`.
4. [ ] **The glyph controls.** The Appearance buttons and swatches say the
   setting, its value now and the next value; the filter chip, the ".*" toggle,
   the process signals, the find buttons of a task stream, the Close, Stop and
   Run again of the Tasks list, the agent options with their descriptions, the
   Evaluator check boxes, and the default, the range and "takes effect at the
   next start" of a setting. Test: `test_appearance()`, `test_settings()`, the
   suites of the assistant, task and arrangement slices.
5. [ ] **Tables and cells with data on hand.** The assistants table (context,
   start, work badge, the "›" button), the pivot zone badges, the formula cell
   (the formula as code, the type, "computing"), a Markdown heading (the anchor,
   the level), a math symbol (its name and how to type it), the slow frame and
   the Pause toggle of the frame statistics. Test: the suites of the pivot,
   formula, markdown and math domains, and `test_frame_statistics()`.
6. [ ] **omnet-julia tree rows.** The project, a configuration, a run, the
   Runner, a result file, a result run, a result folder, an INI file, a NED file,
   a NED package, a NED type, the fingerprint store and the statistical
   baseline give a note with their stored facts. Test: the legacy suites that
   build these rows.
7. [ ] **omnet-julia simulation, results and tests.** The Next, In and At lines;
   the configuration form rows (the operator, the value kind, why unused); the
   captions of the engine dashboards; the pause point, panes and run-until
   buttons; the scalar, vector, statistic and parameter rows of a result file;
   the Runner form (the filter boxes are regular expressions, the settings, the
   flags, the task kinds, and how many tasks Run starts or why it can not); and
   `format_task_details` of the fingerprint, statistical and smoke tests (the
   calculated and the expected fingerprint with its ingredients in words; the
   reason of a verdict). Test: `test_simulation_embed_card()`,
   `test_task_group_pane()` and the legacy test suites.
8. [ ] **The documentation and the catalog.** tooltip.md (a note made at the
   dwell), the guides of the slices that changed, and the catalog marks each
   part of wave 1 done.

## Not in this plan

- The six mechanisms of wave 2: a cut table cell, the fold marker, the tab strip
  icons, a stored file stamp, the path for a binding, and widgets in place of
  strings in omnet-julia rows. So no column header, no INI section chain, no
  JSON path and no result frame cell is in this plan.
- The parsers and the data of wave 3: `tt=`, the module on the canvas, the
  channel on a connection, NED doc comments, the option catalog, the source of
  a log message.

## Questions answered

1. May a tooltip be a function that makes the note when the pointer rests? Yes.
2. Does a file row show only its path, or also its size and time for an open
   file? Only the path, the format and the lines.
3. May step 2 also change the label of an untitled assistant from "Assistant" to
   its overview title? Yes.
