# A catalog of what each part could say

Status: CATALOG, 2026-10-21. Wave 1 is implemented by
[a-part-says-what-it-holds.md](../done/a-part-says-what-it-holds.md) (see its "As
built" notes for what each part says and what it left out), and item 2 of "What
stands in the way" by
[a-file-says-what-the-pointer-is-on.md](../done/a-file-says-what-the-pointer-is-on.md).
The rest of wave 2 and wave 3 are deferred. The user, 2026-10-22: "the rest of
the waves are deferred for now".

## The ask

The user, 2026-10-21, after the plan
[a-tooltip-is-a-framed-note.md](../done/a-tooltip-is-a-framed-note.md) landed:
"check which of the explorer items have tooltips and which would make sense? what
other stuff could have a useful tooltip? let's make a catalog"

## How to read the catalog

A row names a part, what its tooltip says now, what a `TooltipNote` should say,
where the data is, and two marks:

- **Value**: H (a person needs it often, or cannot find it elsewhere), M, L.
- **Effort**:
  - S: the data is on hand, and the change is in one place.
  - M: it needs a small mechanism or a small data change first (see "What
    stands in the way").
  - L: it needs a parser, a new data path or a design decision.

"Note" means the pieces of a `TooltipNote`: title, keys, code, text, facts,
hint. The facts were found by three read-only searches on `main` `3200dffe7`
(projectured-julia) and `2b3ca573` (omnet-julia), and the main claims were
checked by hand.

## What stands in the way

These are the mechanisms and the data that many rows need. Each is one design
decision, not one per row.

1. **A row says only its decoration.** A tree row and a tab show
   `make_decoration_note(decoration)`: the condition words and
   `decoration.tooltip`. Almost no type sets `decoration.tooltip`, so a plain
   file, a section, a log or a tool says nothing. A type gives a note by
   setting `decoration.tooltip`. The decoration is built for each row at each
   print, so its note must read stored values only: a file size or a time that
   needs a disk read must come from a stored stamp, never from `filesize` or
   `mtime` in the decoration.
2. **A binding of a document sees only the node.** Done by
   [a-file-says-what-the-pointer-is-on.md](../done/a-file-says-what-the-pointer-is-on.md):
   the container says it from its own mouse target, with no new mechanism. `make_tooltip_binding`
   gets the document, not its path or its parent. A JSON path, an XML
   namespace, the degree of a graph vertex and the callee of a Julia call need
   the `source` path that `OpenTooltipOperation` carries, or a binding on the
   parent.
3. **A cut table cell shows nothing.** A cell of a sized column clips its text
   (`cell_policy = :clip`, `WidgetDocument.jl:2853`), and a dwell on it answers
   nothing. One answer in the widget table, "the full value and the column",
   serves the roster, task, assistant, workflow, pivot and omnet result tables.
4. **The syntax layer takes no dwell.** `SyntaxToText.jl` has no `MouseDwell`
   reader, so a fold marker and a folded "…" say nothing in every text domain.
5. **The tab strip answers the tab note over its icons.** A dwell on the close,
   duplicate or new-tab icon goes out to the tab label
   (`_read_tabbed_pane_outward`, `WidgetToGraphics.jl:5114`), so the note of
   the tab covers the icon that the pointer is on.
6. **Lines drawn as text have no document.** The message, gesture and fault
   logs and the help lists are lines of plain structs, so a line can not carry
   a binding.
7. **Strings where a widget is needed.** The status bar segments, the omnet
   result frame cells, the resolved parameter rows and other omnet rows are
   strings, so they can not hold a tooltip.
8. **Missing data.**
   - The message log keeps only the level and the text; `handle_message` drops
     the module, the file and the line (`MessageLogCapture.jl:40-44`).
   - A gesture log entry has no time.
   - A palette row that is "(not now)" has no reason: a binding has only
     `applicable(...) -> Bool`.
   - omnet-julia: the NED `tt=` tag is not parsed, a submodule `@display` is
     skipped (`NedNetworkBuilder.jl:1510`), NED doc comments are dropped by the
     grammar, there is no catalog of the configuration options, an edge of the
     topology carries no channel, and a message has no kind or length.

## The Explorer

### Rows

| Part | Now | Note should say | Data | Value | Effort |
| --- | --- | --- | --- | --- | --- |
| File, not read | nothing (icon only) | title: name; facts: Path, Size, Modified; hint: "A press shows it. A Ctrl+press opens a tab." | `file.pathname`; size and time from a stored stamp (`_get_file_stamp`, `FileChangeStore.jl:422`) | H | M (stamp, item 1) |
| File, read | condition words only (unsaved, read only, changed on disk) | the same facts, and Lines, Format | `get_filename`, the file content | H | M |
| Folder (`FileSystemDirectory`, `WorkspaceFolder`) | "running" or the failure; a good folder says nothing | facts: Path, Entries ("not read yet" before a read); hint: "Right reads it and opens it." | `folder.pathname`, `length(folder.elements)`, `folder.state` | H | S |
| Section (Explorer root, Evaluators, Dashboards, Editor, Settings, Help, a section of the user) | nothing | facts: Entries; keys: Rename (F2), Add (Insert), Move (Ctrl+Shift+Up/Down) | `length(section.entries)`, `find_bound_keys(Explorer, …)` | M | S |
| Task (`TaskDocument`) | condition words; the reason when there is one | title: the task line; facts: State, Result, Started, Duration, Position, Process, Memory; text: the reason | `get_current_task_execution(doc)` fields, `format_task_parameters` | H | S |
| Closed task group | "stopped" | its stored summary: kind, counts, time | `group.summary` | M | S |
| Search (`ExplorerSearch`) | one word: stopped, running, done | text: what it looks for; facts: Matches, Waiting, Depth and limit, Started, Took | `search.result`, `search.text`, `search.depth`, `search.limit` | M | S |
| Assistant | condition words; every untitled assistant reads "Assistant" | title: `compute_assistant_overview_title`; facts: Model, Backend, Context used, Prompts, Started, Working for, Session | `a.model`, `a.backend`, `describe_agent_usage`, `compute_prompt_count`, `find_assistant_start_time`, `compute_assistant_busy_time` | H | S |
| Subagent (`AgentWork`) | the state word | facts: Tokens, Tool calls, Duration, Last tool, Stop reason | `AgentWork` fields | M | S |
| Conversation turn and part | "running" only | turn: role, Started, Duration, Parts, Stop reason; part: the first line in full | `ConversationTurn` fields | M | S |
| Tool call (`EvaluatorForm`) | running, failed | facts: Tool, State, Duration | `form.tool_name`, `form.is_running`, `form.is_error` | M | S |
| Permission or question request | "waits for you: 1" | hint: "Answer it on its page." | `request.title` | M | S |
| Dashboard | nothing (the count is a pill) | facts: Cards; key: Add a card (Insert) | `length(dashboard.cards)` | L | S |
| Dashboard card | nothing | the note of its content: its decoration note | `make_decoration_note` of `card.content` | M | S |
| Message, gesture, fault, MCP and background work logs | nothing, or the fault count | text: what it shows (the toolbar texts of `WindowChrome.jl`); facts: Kept, Capacity, Errors, Faults | `log.count`, `log.capacity`, `length(log.entries)` | M | S |
| Frame statistics, frame times, selection inspector, settings, appearance, help pages | nothing | one sentence of what each shows | the toolbar texts | L | S |
| System process | nothing; the label packs pid, command, load, memory | code: the full command; facts: Folder, State, Threads, Started | `process.command` and fields | H | S |

### Controls

| Part | Now | Note should say | Value | Effort |
| --- | --- | --- | --- | --- |
| Filter field | nothing (placeholder "Filter") | text: "Show the rows whose label holds these words."; key: Ctrl+F; hint: "Return searches below the selected row. Escape clears." | H | S |
| Kinds item (funnel) | a plain sentence | title: "Kinds"; facts: the kinds now shown | M | S |
| Add item (+) | a note with Insert | add the kinds that it offers as a fact | L | S |
| Row menu and add menu items | nothing | short texts, and the keys of Rename, Remove, Move from the `@gestures` table | M | S |
| Section page card and its links | nothing | the decoration note of the entry | M | S |

## The rest of projectured-julia

### The window frame

| Part | Now | Note should say | Value | Effort |
| --- | --- | --- | --- | --- |
| Tab close, duplicate and new-tab icons | the note of the tab, over the icon | title: Close tab, Duplicate tab, New tab; the key; for close, "Unsaved edits" when there are | H | M (item 5) |
| File tab | condition words | facts: Path in full (the label shortens it), Size, Modified, Format | H | M (item 1) |
| Assistant tab | condition words | the facts of the assistant row | H | S |
| Log tabs, Tasks tab, background work, roster, work plan | a pill such as "3/5" that nothing explains | text: what the pill counts | M | S |
| Status bar segments | nothing; the bar takes no dwell | the selection in full, with its node type | M | M (item 7) |
| Split divider, scroll bar thumb | nothing | "Drag to resize"; "Line 120 of 4000" | L | M |

### Tables

| Part | Now | Note should say | Value | Effort |
| --- | --- | --- | --- | --- |
| A cut cell of any `WidgetTable` | nothing | title: the column; text: the full value | H | M (item 3) |
| Task table row | one text for the whole table | per row: the task line, state, elapsed, result, reason | H | M |
| Assistants table: context, started, work badge, "›" | nothing | `describe_agent_usage`; the full date; what the state means; "Show this assistant below." | H | S |
| Pivot cell | nothing | full value; measure and aggregate; row and column keys; rows aggregated | H | M |
| Pivot zone badge | nothing | column, distinct values, order, limit; hint: drag or key to move | H | S |
| Workflow catalog "file", journal "time" and "text" | nothing | full path; ISO time; full text | M | M (item 3) |
| Data frame header | nothing (the sort glyph has a note) | element type, missing values, distinct values | M | S |
| Frame statistics: a slow frame, the Pause toggle | nothing | "Slow: 14.2 ms, over 2x the median 5.1 ms"; what Pause keeps | M | S |

### Controls with a glyph and no tooltip

27 controls show a glyph and say nothing. Each needs a sentence and, where
bound, a key.

| Part | Where | Note should say | Value | Effort |
| --- | --- | --- | --- | --- |
| Appearance "−", "+", "‹", "›", Step, Fix, Reset (16 sites) | `AppearanceToWidget.jl:250-602` | the setting, its value now and the next value: "Text size 120 %: 10 % smaller" | H | S |
| Appearance color swatch | `AppearanceToWidget.jl:467, 488, 605` | role, `#rrggbbaa`, default | M | S |
| Filter chip "×" and the ".*" toggle | `NaturalArrangement.jl:169, 178`; `WidgetDocument.jl:970` | "Remove this filter: …"; "Match as a regular expression" | H | S |
| System process Interrupt and Stop | `SystemProcessToWidget.jl:23-24` | "Send SIGINT, as Ctrl+C does."; "Send SIGTERM: ask the program to end." | H | S |
| Task stream find "‹" "›" | `TaskStream.jl:144-145` | "Previous match", "Next match", "3 of 17" | M | S |
| Tasks list Close, Stop, Run unexpected again | `TaskGroupToWidget.jl:1017-1022` | Close: "Its tasks and their output are gone."; Run again: how many | H | S |
| Agent options Model, Effort, Mode and their values | `AssistantToWidget.jl:415-471` | `option.description` and `value.description`, which arrive and are not shown | H | S |
| Evaluator check boxes | `EvaluatorToWidget.jl:214-227` | one sentence each | M | S |
| Settings controls | `SettingsToWidget.jl:155-171` | facts: Default, Range, "takes effect at the next start" | M | S |

### Text domains and documents

| Part | Note should say | Value | Effort |
| --- | --- | --- | --- |
| Fold marker and folded "…", in every text domain | "Fold" or "Unfold", the count of children, the key | H | M (item 4) |
| Julia call | the signature and docstring of the callee, with `_make_julia_function_note` | H | M (item 2) |
| Formula cell | code: the formula; facts: Type, Computing | H | S |
| Sequence chart event and arrow | time, lane, kind, label, delay (the hover state exists) | H | M |
| JSON and YAML key and value | path, type, count | M | M (item 2) |
| XML element | attributes, children, namespace | M | M (item 2) |
| Chart legend and point | "A press hides this series", samples; x and y | M | M |
| Graph vertex, FSM state and transition, workflow state | degree; transitions; next state | M | M (item 2) |
| Markdown heading | the anchor `#slug`, the level | M | S |
| Math symbol | name and how to type it | M | S |

### Logs and lists

| Part | Note should say | Value | Effort |
| --- | --- | --- | --- |
| Message log line | time; source: module, file:line | H | L (items 6, 8) |
| Fault log line | full message, site, origin, count | M | M (item 6) |
| MCP call line | full date and time, exact duration | M | S |
| Palette row "(not now)" | why it is off | M | L (item 8) |
| Document type list, projection list | the full docstring, the fields, the file extension | M | M (item 6) |

## omnet-julia

### Tree rows

| Part | Now | Note should say | Data | Value | Effort |
| --- | --- | --- | --- | --- | --- |
| Project | a failure sentence only | facts: Root, OMNeT++ version, Built modes, INI files, Configurations, Runs, Fingerprints, Baselines; hint: why "not built" | `read_project_facts` (`LegacySimulationProjectPage.jl:89`) | H | S |
| Configuration | counts, "N runs" | facts: Runs, Limits, Flags (bounded, abstract, emulation), Expected result, Description, Extends | `LegacySimulationConfiguration`; `IniConfiguration.sections` | H | S |
| Run | the reason of the last task | title: "NAME #n"; facts: Iteration variables, Repetition, Last result vs expected, Elapsed | `format_run_iteration_variables`, `find_run_task` | H | S |
| Runner | the match line | facts: Configurations, Runs, Kind, Mode, Jobs; text: which filter emptied the match | `compute_runner_match` | H | S |
| Result file | icon only | facts: Size, Modified, Kind, Run, Configuration, Iteration variables, Read failure | `LegacyResultFileEntry` (size and time are stored) | H | S |
| Result run, result folder | the newest file time; a failure | facts: Configuration, Run, Files, Written; Path, Files, State | `LegacyResultRunEntry`, `LegacyResultFolder` | M | S |
| INI file, NED file, NED package, NED type | a failure only | configurations and runs; types by kind; kind, extends, parameters, gates | the entry fields | M | S |
| Fingerprint store, statistical baseline | a count | facts: Entries, Path, Written; text: what read only means | the store fields | M | S |

### The simulation

| Part | Now | Note should say | Value | Effort |
| --- | --- | --- | --- | --- |
| Module on the canvas | nothing; the node does not know its module | title: full name; facts: Path, NED type, Id, Gates, Parameters, Status; the `tt=` text first | H | L (module identity, `tt=` parser) |
| Connection line | nothing; an edge is a bare index pair | facts: Delay, Datarate, Channel type | H | L (edge data) |
| Next / In / At lines | nothing | Next: event number, time, delta; In: path and id; At: the stop point | H | S |
| Resolved parameter row | nothing (a string) | facts: Value, Unit, Default or fixed, Type, the rule that set it | H | M (item 7, rule source) |
| Configuration form row | a label when it matches nothing | operator (`=` fixed, `?=` default), value kind, why unused | M | S |
| Status bar, execution readout | nothing | run state, events scheduled, stop reason | M | M (item 7) |
| Dashboard captions (Ev/simsec, Mean FES, Lag) | nothing | what each measures | M | S |
| Message in flight | nothing | name, from, to, sent, arrives | M | M |
| Pause point, Panes, Run-until buttons | nothing | the notes of the transport buttons | M | S |

### Results and tests

| Part | Now | Note should say | Value | Effort |
| --- | --- | --- | --- | --- |
| Scalar, vector, statistic rows of a result file | nothing | full module path and name, exact value, unit, `title`; vector: count, min, max, mean, times; statistic: count, mean, deviation, bins | H | S |
| Result frame cell (rounded, or "N values") | nothing | the exact value; the first values and the length | H | M (item 7) |
| Frame column headers (`sumweights`, `mintime`, `binmin`, …) | nothing | what each column means, the unit | M | S |
| Scalar comparison columns and verdicts | nothing | the three errors and the threshold; what FAIL and ERROR mean | H | S |
| Fingerprint test row, mismatch | the reason only | facts: Calculated, Expected, Ingredients in words, Limit | H | S |
| Fingerprint store columns | nothing | the legend of the ingredient letters (`e` event number, `t` time, …) | H | S |
| Smoke, statistical, update tasks | the reason only | what the test does; that an update rewrites the store | M | S |
| Build step and make task | the reason only | code: the command; facts: Folder, Exit code, First error line | M | S |
| Runner filter boxes, settings, flags, kind toggle, Run button | nothing | "A regular expression over the configuration name."; what each kind starts; how many tasks Run starts, or why it can not | H | S |

### The INI and NED editors

| Part | Note should say | Value | Effort |
| --- | --- | --- | --- |
| `[Config X]` heading, `extends =` | the chain `X → Base → General`, runs, abstract | H | S |
| `${n=1,2,5..10 step 3}` | the values, their count, how they multiply runs | H | S |
| Parameter key `**.host[*].iaTime` | the sites it matches, or "matches nothing" | H | M (needs a built network) |
| Configuration option key (`sim-time-limit`, …) | type, default, unit, documentation | H | L (option catalog) |
| NED parameter, gate, connection, `@display` | type, unit, default or fixed, doc comment; the decoded tags | M | L (doc comments, display parser) |

## Waves

The recommendation is mine.

1. **Data on hand (Effort S, Value H).** The Explorer rows of a file name and a
   folder, a task, an assistant and a system process; the Explorer filter
   field; the Appearance buttons, the filter chips, the ".*" toggle, the
   process signals, the Tasks list buttons and the agent options; the formula
   cell and the pivot badges; in omnet-julia, the project, configuration, run,
   Runner and result file rows, the Next / In / At lines, the result file rows,
   the fingerprint and statistical test notes, the Runner form, the INI section
   chain and the iteration variables. About 35 parts, each a few lines.
2. **One mechanism each (Effort M).** A cut table cell (item 3), the fold marker
   (item 4), the tab strip icons (item 5), a stored file stamp for size and time
   (item 1), the `source` path for a binding (item 2), and widgets in place of
   strings for omnet rows (item 7).
3. **Parsers and new data (Effort L).** The module on the canvas with `tt=`, the
   channel on a connection, NED doc comments, the option catalog, the source of
   a log message, and the reason of a palette row.

## Open questions

1. Which waves go into the next plan.
2. For item 1: may a file row show its size and time from the file watcher's
   stamp, or does it show only what the file page has read?
3. For item 2: does a binding get the `source` path, or does the parent
   document answer for its child?
