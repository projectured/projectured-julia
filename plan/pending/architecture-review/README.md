# The review of the architecture, area by area

The owner asked on 2026-11-15 for a review of the whole project:

> I'm looking for ways to improve the overall architecture. Find parts which could be
> implemented in a simpler, more consistent, more future proof, more generic way. I'm not
> looking for implementing new features which do not exist yet. Apply the first principles
> of the project.

This folder holds that work: this index and 16 reports, one for each area. The review
changed no file of the repository. It ran no Julia.

- **Commit:** `3a9b4fae4` on main, 2026-11-15.
- **Totals:** 144 findings. After the check: 20 of high value, 59 of medium value, 64 of low
  value, 1 refuted.
- **The main result:** most findings have one of 19 causes. Each cause is one job that the
  code does in more than one way. The 19 causes are the themes below, and they are the real
  list of this review.

## How the review ran

1. The lead read the first principles (`documentation/design/concepts.md`,
   `architecture-decisions.md`, the `PAR-…` rules) and divided the code into 14 areas and 2
   subjects that go across all areas (concurrency, extension points).
2. Sixteen reviewers each read one area. Each one made an inventory first: a table of each
   mechanism that does the same job, with a matrix of what each one can do. A finding comes
   from a difference in that table. Each report holds its inventory.
3. Sixteen checkers each got one report, with the task to refute it. A checker opened each
   cited line, counted again, searched the plans and the design documents for a reason, and
   tested if the proposal keeps each feature. Each finding has a line **Check:** with the
   result. A checker corrected a wrong fact where it stands.
4. The lead checked the central facts of the top themes in the code (the two forms of the
   reader, the projections that hold a projection, the two tables of a file format, the
   branches on the list type, the database reads, the disk reads of the task stream), and
   compared each theme with the recorded decisions of the owner.

The results of the check: 16 confirmed, 69 confirmed with corrections, 53 weakened, 4 covered
by a plan, 1 refuted, 1 against a decision of the owner.

A finding has one kind:

| Kind | Meaning | Count |
| --- | --- | ---: |
| several-ways | One feature is implemented in N ways that do not combine. | 57 |
| repeated-by-hand | Each domain, widget or package repeats what one general mechanism could give. | 38 |
| partial-feature | A feature works only in some contexts. | 17 |
| redundant | A concept is dead, or it overlaps another one. | 12 |
| special-case | A special path exists where the general rule could serve. | 9 |
| wrong-place | A thing is in a slice where it blocks reuse. | 6 |
| complicated-api | An API has more parts than its features need. | 5 |

## The themes

Each theme names its findings. The report of the area has the inventory, the code example
and the full proposal of each finding. "Value" is the value after the check.

### T1. A projection has one form of reader

Findings: KM-1. Value: high. Effort: large.

- **Today:** `read_intent` has two forms. The form `read_intent(projection, iomap, payload)`
  is the older one. The form `read_intent(projection, recursion, change::Intent, iomap)` is
  the one that the kernel text asks for: "do not write a 3-arg method in new code"
  ([ProjectionInterface.jl:220](../../../source/kernel/projection/ProjectionInterface.jl#L220)).
  Of 441 definitions, about 360 have the older form. A bridge in the kernel joins the two
  forms, and 43 methods exist only to pass from one form to the other.
- **What it costs:** the older form follows no route. An operation whose route names a place
  below the input gets no answer there. A label and a description of a change are lost in
  each projection that has only the older form.
- **Proposal:** one form. The work of the default method becomes plain helper functions that
  a reader calls.
- **From the check:** `ClaimedGesture` can not go with the bridge, because it asks another
  question. No plan removes the older form: `unify-projection-api-parameter-names.md`
  changes parameter names only. omnet-julia and inet-julia must follow.

### T2. A wrapper projection is written once, in the algebra

Findings: KM-2, II-4, AS-3, and part of LS-1. Value: high. Effort: large.

- **Today:** 18 files outside `source/platform/projection/` have a projection with a field
  `inner` that holds another projection. Each one repeats an IO map type, a printer that
  passes the output on, two reference maps and a reader that delegates. There are two
  families. About 9 wrap the same input (Escape quits, focus cycling, drag tracking, gesture
  tracking, the help, the palette, the overlays). About 8 wrap a state document around a
  field `content` (undo, settings, appearance, versioning, clipboard, file to content).
- **The decision that applies:** on 2026-10-08 the owner said that only a higher-order
  projection of the algebra holds a projection. The rule is in no rule document, and
  `higher-order-projections.md` counts four decorators outside the algebra folder as
  higher-order. So the owner must say if a wrapper is a projection of the algebra.
- **Proposal:** two higher-order projections in the algebra, one for each family. Each one
  takes its child from the recursion. A wrapper gives only its own keys and one function
  over the answer of the child.
- **What starts to work:** each wrapper follows a route (the reader of
  `VersioningToAnyProjection` does not today). The rule for a path through the field of a
  view is written once (today three times). About 17 IO map types go.
- **From the check:** add no new "behavior value". The dispatch on the state document, which
  the clipboard and the undo use, fits.

### T3. One reader gives an event to a child of a container

Findings: WS-1, LS-2. Value: high. Effort: large.

- **Today:** five readers in the layout slice and fourteen readers of widget containers each
  decide which events go to a child. Each one passes a different set. The stack layout
  passes no button down, no button up and no rest of the pointer. The list forms pass no
  leave and no Tab walk. The title pane passes three kinds of event.
- **What it costs:** a click, a key, Tab and the hover work in one container and not in the
  next. The find bar that lies over a text is a live case.
- **Proposal:** one function that reads an event for the children of a container. A
  container reads its own parts first (a divider, a tab strip, a scroll bar) and then calls
  it.
- **Plans near it:** `a-click-reaches-the-innermost-part-in-every-view.md` and
  `tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md` repair the result
  container by container. This theme is the general rule under both.

### T4. A command has one declaration, and each key is a row of a table

Findings: II-1, II-2, WS-2, DD-6, TD-7. Value: high. Effort: large.

- **Today:** the kernel has gesture tables (`@gestures`): a row has a gesture, a text and an
  operation, and the help (F1), the command palette and the assistant read the rows. 44
  tables exist, one of them in the widget slice. The readers of the widgets and five
  wrappers test keys by hand instead: 25 `@gesture_case` blocks and 84 lines that test
  `.key`. The zoom keys of a plot and the build keys of math are in readers too.
- **What it costs:** the help, the palette and the assistant do not see those keys. A
  command such as "close the tab" has three declarations (the key rule, the tab menu, the
  File menu), and the text of the description joins them.
- **Proposal:** the table is the one declaration. A rule takes the place that it acts at. A
  reader finds the part and calls the table. A menu is made from the rows.
- **From the check:** the keys of a tree and of a table need the IO map, so they belong in
  the gesture table of the projection, and `describe_commands` must read that table too. The
  proposal removes `collect_part_commands`, which the owner accepted on 2026-10-21, so it
  needs the word of the owner.

### T5. A vector and a lazy list answer one protocol

Findings: CO-2, LS-4, CO-5, TS-8. Value: high. Effort: large. Needs decisions of the owner.

- **Today:** `CellVector` (a vector of cells) and `ListNode` (a lazy linked list) have
  different calls for the index, the count and the walk. 119 branches `isa ListNode` are in
  26 files. The table widget, the tree widget, the row, the column and the grid each have a
  second printer for a list. The features differ: the drag of a column edge and the header
  levels work with one form only, and the list forms of the layouts have no ring, no
  backward map, no baseline and no span.
- **Proposal:** a small protocol that both types answer (the count or `nothing`, the node at
  a place, a walk from a head). A view is written once. What needs a count is a policy.
- **Decisions that limit it:** D9 of `a-layout-paints-only-what-the-screen-shows.md`
  approved two printers for a layout. The memory of a lazy list is an open question of the
  owner (2026-11-13). The checker recommends a first step that needs no decision: share the
  abilities over one entry, and keep two printers.

### T6. A file format and the view of a type have one declaration each

Findings: XS-1, XS-2, AS-2, TD-4, DD-8, TD-10. Value: high. Effort: medium to large.

- **Today, a file format:** YAML declares its format to the natural slice
  (`register_natural_domain!`, `register_natural_parser!`), to the serialization slice
  (`register_file_document_type!` two times), with three methods on its file type, and a
  seed method. A tab reads a file through the first table and saves through the second. The
  copies drifted: the last line break, `.markdown` has no parser, and one YAML document gets
  `.yaml` from one function and `.yml` from another.
- **Today, the view of a type:** the general renderer builds its table from 33 methods of
  `make_graphics_projection`, 30 factories that `__init__` registers, 12 rung rows and a
  closed widget table. Five of the ten diagram and data domains have no row.
- **The decision that applies:** C1 of `packages-compose-by-seams.md` says "Seams only. No
  registry table, no `__init__` registration". C7 says "A later plan moves the other eight
  natural register functions to seams." That later plan does not exist.
- **Proposal:** write that plan. One method for each question, on the file type or on the
  document type. `emit_text` gets one default, the print of the content.
- **From the check:** use methods, add no register function and no macro. Keep the shared
  build of a factory (one `MathConfig` for 21 rows).

### T7. Outside state enters in one way

Findings: DD-1, WL-2, CC-7, CC-3, and part of CC-2. Value: high. Effort: medium.

- **The rule that applies:** a printer and a computation read no disk. Outside state enters
  by an acquire on a task. The git domain follows it with background cells.
- **Today, against the rule:** the ODBC adapter runs the catalog queries and the `SELECT`
  inside computations that a print reads
  ([DatabaseInstanceToDbCatalog.jl:35](../../../source/adapter/odbc/DatabaseInstanceToDbCatalog.jl#L35),
  [SqlToCellTable.jl:24](../../../source/adapter/odbc/SqlToCellTable.jl#L24)), so a slow
  server stops the frames. The stream page of a task calls `isfile`, `filesize` and `open`
  from its printer ([TaskStream.jl:24](../../../source/platform/task/TaskStream.jl#L24)).
  A function series of a chart calls user code in the print. The debugger of a process
  model needs its host to call `sync_process_debug!`, which has no caller outside the tests.
- **Today, repeated:** four documents of outside state each build a count of reads, an
  operation that compares the count, a watch and a receive method.
- **Proposal:** each domain uses the shape of git. One function makes a background cell ask
  again. One watch function serves a file and a folder.
- **From the check:** a period on a background cell (for a value that is sampled) is a new
  input of the kernel, so it needs the word of the owner. A formula stays as decision D8 of
  the owner says. The stream page gets its window one frame later.

### T8. A growing list of records has one store, one feed and one page

Findings: WL-1, II-6, WL-5, WL-6, CO-1, CO-3, TS-3, WL-8. Value: medium, in sum high.

- **Today:** `MessageLogStore` and `McpLogStore` are the same code two times, and they
  drifted: only one reports the items that it missed. `GestureLogOverlay` and
  `FaultLogOverlay` are one projection two times. The message log, the gesture log and the
  fault log use three copies of one printer. Six pages repeat "a line of counts over a
  table" with the same grid, the same two path maps and the same repair in the reader, and
  the page of the workflows omits one repair. Seven documents hold the filter, the sort and
  the head of their table. A read-only text of many lines reaches the screen in four ways.
- **Proposal:** one bounded store of records that the editor owns, with one feed. One page
  projection for a table that a document holds. One read-only view of lines from the text
  slice.
- **From the check:** the MCP log keeps its look (the code and the answer of each call). No
  store is a constant of the process. A view document for the table waits for
  `views-compose-as-content-composes.md`. The stream of a task waits for the decision on
  lazy text lines.

### T9. A place shows a document through one slot, and one function finds its tab

Findings: AS-1, AS-5, DD-3, XS-7. Value: high for AS-1, medium for the rest.

- **Today:** the navigator, the card of a dashboard and the row of a file each write by hand
  the slot that makes, holds and drops the view of a document. A tab has no slot, so
  `open_pane!(file)` shows the bare file with no scroll and no band, and the caller must
  write `open_pane!(make_file_view(file))`. "Find the tab that shows it, else open it" has
  four openers and three searches, with seven functions that walk the layers of a tab.
- **Proposal:** one slot type with three functions, used by the tab, the card, the page and
  the row. One function that walks the layers and one that finds or opens.
- **From the check:** AS-1 belongs with the deferred plan of what a holder holds (question
  Q10 of the tab plan).

### T10. The assistant has one runner of a tool call and one shape of a turn

Findings: AI-1, AI-2, AI-3, AI-5, AI-7, XS-4. Value: high for AI-1 and AI-2.

- **Today:** the loop of the kernel and the MCP server each run a tool with about 60 lines
  for the same eleven duties, and they differ in six. A tool answers a `String`; the code
  finds a failure by the word "Error" in the text. The assistant has two drivers of a turn,
  and nine lines test the literal `:acp`. The transcript chooses the body of a part
  by 27 type tests in one projection. Five places make a form from an evaluation.
- **Proposal:** a typed result of a tool (content, value, failure) and one function
  `run_tool_call!` for both clients. Both drivers report with the same event types, and the
  platform has one applier.
- **From the check:** the wide text test of the loop is on purpose, so the owner chooses the
  rule for a failure. A picture for a model in the process is a new ability, not a part of
  this theme.

### T11. A text edit has one form on its way back

Findings: TS-1, TS-2. Value: high for TS-1. Effort: large.

- **Today:** a key makes an edit of a flat range. `_lower_unless_line_edit` changes it into
  an edit of one run, but not when it holds a line break. Both forms go back through the
  stages. Of 33 readers, 5 read only the second form. The fold, the filter and the highlight
  pass a flat edit on with no map. Seven places build the lines of a plain string and the
  maps to its field by hand.
- **Proposal:** one form, the flat range. Each stage maps the range. One projection of the
  text slice for "the string at this field is a text".
- **From the check:** the cost of a key must stay at log N. Two operation types stay.

### T12. The projection template covers what the domains write by hand

Findings: TD-2, TD-1, TD-3, TD-8, KM-4. Value: high for TD-1 and TD-2.

- **TD-2 (small effort):** the template can not wrap each element of a list. So four list
  rules are written by hand with a printer, two maps and three readers (YAML, book,
  Markdown, RST: about 390 lines), and a pending plan adds a fifth. One more form,
  `collection(:field; each = …)`, removes them.
- **TD-1:** the buffer that takes the typed characters of a new element exists in three
  forms, and Markdown, RST, book, math and formula print a fixed label in its place. This is
  the cause of "type-in of single characters does not work the same way in every domain" in
  `concepts.md`.
- **TD-3:** the builder of a template does not see the printer context, so Markdown, RST and
  formula each carry an inherited value in their own way.
- **TD-8:** an escape is one function in the printer and another in the parser, and a caret
  in an escaped value maps by the plain offset.
- **KM-4:** the template engine has seven wirings of a node with limits between them; one
  list of slots serves all.
- **From the check:** the keys of the insertion buffer must stay where the declared type of
  the place is known.

### T13. One stage makes a graph from a domain

Findings: DD-2, DD-4. Value: high for DD-2. Effort: medium.

- **Today:** the FSM, the process and the research map each build the graph, its highlight
  cells and its reference maps by hand. Each one makes all vertex objects again after a
  change, and the graph stage keys the pins and the kept corners by the vertex object. So a
  place that a person dragged does not survive an edit.
- **Proposal:** one stage in the graph domain. A domain gives its nodes, its links and its
  highlight. The stage keeps one vertex for each node.
- **From the check:** the FSM and the process are near copies. The research map joins after
  DD-4 (its outline walks the whole tree in one computation, against
  `PAR-DELEGATE-ONE-LEVEL`).

### T14. Graphics has one walk of a canvas and one search for what changed

Findings: BE-3, BE-1, LS-6, LS-5. Value: high for BE-3.

- **Today:** the search for what changed since the last paint is 1,943 lines in
  `SdlBackend.jl` that call no SDL function. The web backend has a second search, and the
  offscreen renderer makes a false window record to use the first. The walk of the elements
  of a canvas is written in the hit test, the pointer shape, the SDL paint and the web
  backend. The primitive kinds are `isa` chains in five places. The build of a row and of a
  column are mirror copies of 114 and 120 lines.
- **Proposal:** the search and the walk move to the graphics slice. A primitive kind gets a
  method of `get_element_box`, `is_point_on_element` and `draw_element`. The axis becomes a
  value.
- **From the check:** the owner deferred the web part of the walk on 2026-11-05 (D11). Three
  rules of the SDL software renderer stay in the SDL file.

### T15. A widget field takes a value, a cell or a function by one rule

Findings: WS-5, CO-8, WS-4. Value: medium.

- **Today:** 46 widget constructors are written by hand and take plain values only, though
  the constructor that `@document` makes takes a cell. So eight projections pass all 25
  cells of a `WidgetTable` by position, and about 190 places write
  `set_cell_computation!(getfield(widget, :field), f)`. The value of a control has two ways
  to bind and five names (`content`, `checked`, `pressed`, `selected`, `value`).
- **Proposal:** one rule for each field of each widget, and one name for the value slot.
- **From the check:** the value slot prints only under one dispatch table today, so that
  must become general first.

### T16. The reference layer gives the path helpers and one list of children

Findings: RS-4, RS-7, RS-3, RS-8. Value: medium.

- **Today:** "the rest of a path below a prefix" is 13 private copies; 164 places in 82
  files do path arithmetic by hand. Three functions list the child documents of a node under
  three rule sets. Two walkers give an output tree its paths. The clipboard has two wrapper
  documents and the only two mutable projections.
- **Proposal:** four functions in the reference layer; one list of children under a
  `DocumentWalk`; one clipboard document.

### T17. A test drives the real loop, and the list of packages has one source

Findings: PB-1, PB-2, PB-3, PB-4, PB-5. Value: high for PB-1.

- **Today:** eight drivers give scripted input to an editor. 198 of 676 test files call
  `read_intent` themselves, and 52 stand-in editor types exist, so a test does not exercise
  what a person gets. The list of the packages is written by hand in about twelve places:
  `test_all()` calls 28 of 39 suites, and CI has no job for three test packages. 88 entry
  files repeat one loop.
- **Proposal:** one script type and one runner over the real frame, for each backend. The
  aggregates and CI take the list from the folder.
- **From the check:** `kernel-audit-fixes.md` (L23-5, L23-4, L22-31) already covers the
  playback part.

### T18. The settings and the appearance are one mechanism

Findings: LS-1, AS-8. Value: medium. Effort: large.

- **Today:** `@theme` and `@settings`, two wrapper documents, two projections that differ in
  one call, two operations, two TOML encoders and two form tabs do one job two times.
- **From the check:** decision D16 of `editor-settings.md` keeps two selection models. The
  gain is about 300 lines.

### T19. An operation tree has one generic walk

Findings: KM-3. Value: medium.

- **Today:** 38 functions have a method for a compound operation and 22 for a wrapper
  operation. A type says how it travels in one of five ways.
- **From the check:** the walk holds. The proposed default, "an operation with no
  registration travels as it is", is against decision L13-8 of the owner and must not be
  done.

## Small removals

These are cheap. The text of each one is what stays after the check:

- WS-8: the component slice (76 lines) has no user in the three repositories. It is the
  first step of `component-document.md`, which is stale since 2026-08-12. A removal drops
  that plan, so the owner decides.
- CO-10: `CellMatrix` has no user in the three repositories. The type is exported and
  documented, so the owner decides.
- KM-6: `FilteringProjection` is a second implementation of the stage that the arrangement
  slice uses. The sort and the reverse have a reason and stay.
- II-7: two older tooltip mechanisms have only two examples and one test as users. A removal
  loses the tooltip of the gallery that follows the selection.
- PB-7: `warm_file_editor` is dead in the three repositories.
- TS-10: `TextFirstLine` and two fields of `SyntaxLeaf` have no user (about 100 lines).
- LS-9, LS-10, AS-9, RS-6, TS-9: small copies.

## Proposals that did not pass

The check removed these, or a recorded decision is against them. They are in the reports
with the reason.

| ID | Proposal | Why it did not pass |
| --- | --- | --- |
| KM-7 | Move seven kernel seams that only `CellVector` uses | Refuted: the seams keep the rule that the kernel holds no concrete document. |
| AS-7 | List the tools of a window from the trait | Against decision R3 of `plan/done/the-toolbar-opens-the-tools.md`: the shell names the tools. |
| II-3 | One operation for each popup window | The four ways are recorded design (D5 of the popup plan). A smaller part in the window manager stays. |
| BE-2 | Move the window policy out of the SDL backend | Three recorded decisions make the backend the writer. |
| RS-1 | One chain for the selection and the mouse target | The owner chose two chains on 2026-09-29. |
| CC-1 | The inbox as the one door of a stream | `communication-anatomy.md` gives a stream to a feed (approved 2026-10-21). |
| LS-4 | One printer for a layout and its list form | D9 approved two printers. See T5 for what stays. |
| WS-3 | A control answers a typed operation | `plan/done/one-action-one-operation.md` chose one type. |
| TS-5, TS-6, BE-7, BE-9 | (four findings) | A pending plan covers each one. |

## Defects seen on the way

The review did not search for defects. These came up in a check, and each one has its place
in a report:

- CI runs no job for `ProjecturedACPTest`, `ProjecturedPivotTest` and
  `ProjecturedPrecompileTest`; `test_all()` calls 28 of 39 suites (packages-build-test).
- `YamlString("true")` prints with no quotes, and the parser reads it back as a boolean
  (text-domains).
- `AgentEventQueue` takes no wake, so an event that the ACP adapter puts between two prompts
  waits for the next frame of another cause (concurrency).
- The process tree of the explorer is never sampled; only `show_system_process_tree!` puts a
  tree into the feed (concurrency, CC-3).
- The reader of `WindowManagingProjection` changes the screen document, against
  `PAR-READER-IS-PURE` (input-interaction).
- An edit of a line break below a closed fold reaches the syntax stage with no map
  (text-syntax).
- `make_document_seed` has a method for four of the eight text formats, so a new `.yaml`,
  `.md` or `.rst` file has no seed (extension-seams-api).
- `SqlToCellTable` builds a chain of projections inside its print (diagram-data-domains).
- `plan/pending/an-insert-moves-the-paths-after-it.md` is out of date against the code
  (reference-selection).
- `documentation/package/backend/web/web.md:90` describes one shared key table; the code has
  two (backends).

## An order, proposed by the lead

This order is a recommendation. No part of it is decided.

1. **No decision needed, small:** TD-2, CO-8, AS-5, the page helper of WL-6, RS-4, the two
   log stores of II-6, the small removals, the CI rows.
2. **A decision exists, the work follows it:** T6 (the later plan of C7), T2 (the rule of
   2026-10-08), T7 (the acquire rule), T1 (the kernel text already forbids the older form).
3. **The general rule under plans that are pending:** T3 before the click plan and the Tab
   plan go on; T4 before `key-chords-from-bindings.md`.
4. **Needs answers of the owner first:** T5 (lists), T9 (what a holder holds), T10 (the rule
   for a failed tool), T8 (the view document of a table), T12 (TD-1).

## The areas

### The kernel model: cells, documents, projections, IO maps, operations

Report: [kernel-model.md](kernel-model.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| KM-1 | The reader has two signatures, and most methods use the one that the rules call obsolete | several-ways | high | large | confirmed-with-corrections |
| KM-2 | A projection that wraps one other projection has no shared base | repeated-by-hand | medium | medium | confirmed-with-corrections |
| KM-3 | An operation tree has no generic walk, and five ways to say how it travels | repeated-by-hand | medium | medium | weakened |
| KM-4 | The template engine has seven shapes of node, with limits between them | several-ways | medium | medium | confirmed-with-corrections |
| KM-5 | Choosing one inner projection is implemented four times | several-ways | low | small | weakened |
| KM-6 | The generic sort, filter and reverse are a second implementation of a stage that the product uses | redundant | low | small | weakened |
| KM-7 | The kernel has seven seams whose only registrant is CellVector | wrong-place | none | medium | refuted |
| KM-8 | The parts of a value are listed by several walks, each with its own rules | several-ways | low | large | weakened |
| KM-9 | The reflected view of a running object draws its own tree beside the tree slice | several-ways | low | medium | weakened |

### References, selection, focus, clipboard, links

Report: [reference-selection.md](reference-selection.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| RS-1 | One chain for every kind of path | several-ways | medium | large | confirmed-with-corrections |
| RS-2 | A place in a text has one path form | several-ways | medium | large | weakened |
| RS-3 | One call gives an output tree its paths | several-ways | medium | medium | confirmed-with-corrections |
| RS-4 | The reference layer gives the path arithmetic that each slice rewrites | repeated-by-hand | medium | medium | confirmed |
| RS-5 | A step says whether it reaches a part or names a place | special-case | low | medium | weakened |
| RS-6 | A row of a columnar document is the element step | redundant | low | small | confirmed-with-corrections |
| RS-7 | The child documents of a node have one list | several-ways | medium | medium | confirmed-with-corrections |
| RS-8 | One clipboard document that holds a list | partial-feature | medium | medium | confirmed |

### Input: events, gestures, bindings, popups, drag, hover, the frame loop

Report: [input-interaction.md](input-interaction.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| II-1 | A command is declared up to three times, and a text joins the copies | several-ways | high | medium | confirmed-with-corrections |
| II-2 | Most keys of the widgets and of the wrappers are outside the table that F1, the palette and the assistant read | partial-feature | high | large | confirmed-with-corrections |
| II-3 | A popup window opens in four ways, and each way has its own part of the features | several-ways | medium | large | weakened |
| II-4 | A wrapper around the content is written by hand each time, and three wrappers exist for one key each | repeated-by-hand | medium | medium | confirmed-with-corrections |
| II-5 | The small move that turns a press into a drag is written four times | repeated-by-hand | low | small | confirmed-with-corrections |
| II-6 | A log of the session is built by hand for each log | repeated-by-hand | medium | medium | confirmed-with-corrections |
| II-7 | Two older tooltip mechanisms are left beside the one that the editor uses | redundant | low | small | confirmed-with-corrections |

### The widget set

Report: [widget-set.md](widget-set.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| WS-1 | Each widget container has a reader of its own for the same job | repeated-by-hand | high | large | confirmed-with-corrections |
| WS-2 | The gestures of a control are code in its reader, not rows of its gesture table | several-ways | medium | medium | confirmed-with-corrections |
| WS-3 | A control says what a press does in five ways, and a typed operation needs a closure | several-ways | medium | medium | weakened |
| WS-4 | The value of a control is bound in two ways and held in five shapes | several-ways | medium | medium | confirmed-with-corrections |
| WS-5 | The widget constructors are written by hand and take plain values only | complicated-api | medium | medium | confirmed-with-corrections |
| WS-6 | Each printer assembles the frame of its widget by hand | repeated-by-hand | low | large | weakened |
| WS-7 | A view that builds widgets is written by hand; the builder engine makes syntax only | partial-feature | low | large | weakened |
| WS-8 | The component slice is a concept with no user | redundant | low | small | confirmed |
| WS-9 | The widget slice holds operations and seams of other slices | wrong-place | low | small | weakened |

### Layout, style, theme, appearance, graphics

Report: [layout-style.md](layout-style.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| LS-1 | The appearance and the settings are one mechanism written twice | several-ways | medium | large | confirmed-with-corrections |
| LS-2 | Five readers route an event to a placed child, each with another set of abilities | several-ways | high | medium | confirmed-with-corrections |
| LS-3 | The size protocol holds in three of the nine layouts | partial-feature | medium | medium | weakened |
| LS-4 | Each layout has a second printer for a lazy list, and the grid a third | several-ways | medium | large | weakened |
| LS-5 | The axis is not a value, so each rule of a stack is written for the width and again for the height | repeated-by-hand | medium | medium | confirmed-with-corrections |
| LS-6 | Each consumer of a canvas repeats the walk of its elements and the case over the primitive kinds | repeated-by-hand | medium | medium | confirmed-with-corrections |
| LS-7 | A colour and a font come from a shared role, a length does not | several-ways | low | medium | weakened |
| LS-8 | A style of one document over its theme has three unrelated shapes | several-ways | low | medium | weakened |
| LS-9 | Two colours and one constant enter beside the chain | special-case | low | small | confirmed |
| LS-10 | The screen slice restates three things that exist elsewhere | complicated-api | low | small | confirmed-with-corrections |

### Text, syntax tree, natural notation, text entry

Report: [text-syntax.md](text-syntax.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| TS-1 | A text edit and a caret travel back in more than one form | several-ways | high | large | confirmed-with-corrections |
| TS-2 | A plain string shown as an editable text is built again in each place | repeated-by-hand | medium | medium | confirmed-with-corrections |
| TS-3 | A read-only text of many lines reaches the screen in four ways beside the text domain | several-ways | medium | medium | confirmed-with-corrections |
| TS-4 | The view of code is a chain that each package assembles by hand | repeated-by-hand | low | medium | confirmed-with-corrections |
| TS-5 | Coloured ranges of a text have three shapes and two splitters | several-ways | low | medium | covered-by-plan |
| TS-6 | The natural notation keeps eight process-global tables beside the seam that replaces them | several-ways | low | medium | covered-by-plan |
| TS-7 | Find and filter of a text are a second mechanism, and no product view uses it | redundant | low | medium | weakened |
| TS-8 | A text whose lines are a lazy list is a second, weaker path | partial-feature | low | large | weakened |
| TS-9 | The wrap and the cut of a drawn string repeat the word wrap, and find line starts by search | several-ways | low | small | confirmed |
| TS-10 | Concepts of the area that no code uses | redundant | low | small | weakened |

### Collections: lists, tables, trees, rosters, arrangement

Report: [collections.md](collections.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| CO-1 | Seven content documents hold the filter, the sort and the head of their table | repeated-by-hand | medium | large | weakened |
| CO-2 | A list has two types with no shared protocol, so each view that can be lazy is written twice | several-ways | high | large | confirmed-with-corrections |
| CO-3 | Lists of records are still drawn by hand beside the roster | several-ways | medium | medium | weakened |
| CO-4 | Four projections print a tree, each with its own children and its own open nodes | several-ways | low | medium | weakened |
| CO-5 | Each owner of a lazy table converts the move of its head by hand | repeated-by-hand | medium | medium | confirmed-with-corrections |
| CO-6 | The filter of a tree is a second tree of copied rows | partial-feature | medium | medium | weakened |
| CO-7 | A row with named columns has three types, and a column is read in three ways | several-ways | low | medium | weakened |
| CO-8 | A live table is built with a constructor of 25 positional cells | complicated-api | medium | small | confirmed-with-corrections |
| CO-9 | The stores of a roster are a table of the process, beside the session documents | special-case | low | small | weakened |
| CO-10 | CellMatrix has no user | redundant | low | small | confirmed-with-corrections |

### The application: panes, files, persistence, undo, settings, explorer, navigator

Report: [application-shell.md](application-shell.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| AS-1 | A place shows a document through a view: three hand-written slots, and a tab has none | repeated-by-hand | high | medium | confirmed |
| AS-2 | The text format of a domain is declared to two registries and three tables | several-ways | medium | medium | confirmed-with-corrections |
| AS-3 | Each window wrapper writes the same transparent projection by hand, in two styles | repeated-by-hand | high | large | confirmed-with-corrections |
| AS-4 | The editor's file document is made in three ways, with two wrap parameters | several-ways | low | medium | weakened |
| AS-5 | "Find the tab that shows it, else open it" is written five times, with six walkers | several-ways | medium | small | confirmed-with-corrections |
| AS-6 | Two mechanisms keep a window for the next start, and they treat its files in two ways | several-ways | low | medium | weakened |
| AS-7 | The tools of a window are listed by hand in three places, beside the trait that lists them | special-case | low | small | against-owner-decision |
| AS-8 | Settings and appearance are two stores of one shape, with two TOML encoders | several-ways | low | medium | confirmed |
| AS-9 | Two small redundant parts: copied workspace rows and an empty wrapper layer | redundant | low | small | confirmed-with-corrections |

### Running work and logs: tasks, processes, background work, feeds, log views

Report: [work-and-logs.md](work-and-logs.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| WL-1 | A growing list of records has seven hand-made views; only one log uses the generic table | several-ways | medium | large | confirmed-with-corrections |
| WL-2 | The stream page of a task reads the disk in its printer and has its own window, find, filter and follow | special-case | high | medium | confirmed-with-corrections |
| WL-3 | A program that runs has two implementations: task execution and terminal | several-ways | low | medium | weakened |
| WL-4 | Running background work is recorded only for background cells; four callers keep private tables | partial-feature | low | medium | weakened |
| WL-5 | Each feed builds its store, its pacing and its gate again | repeated-by-hand | medium | medium | confirmed-with-corrections |
| WL-6 | The page "a line of counts over a held table" is written six times | repeated-by-hand | medium | small | confirmed |
| WL-7 | Each running kind maps its status to icon and condition by hand; the Tasks pane reads state from the decoration | repeated-by-hand | low | small | weakened |
| WL-8 | Eleven session documents repeat the same methods | repeated-by-hand | low | small | confirmed |
| WL-9 | The debugger of a process model brings its state in outside the feed mechanism | partial-feature | low | small | confirmed-with-corrections |

### The assistant: tool set, models, agents, conversation, MCP and ACP

Report: [assistant-stack.md](assistant-stack.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| AI-1 | A tool call has two runners, and its result has no type | several-ways | high | medium | confirmed-with-corrections |
| AI-2 | A turn has two drivers that share the conversation and little else | several-ways | high | large | confirmed-with-corrections |
| AI-3 | The transcript draws seven kinds of part inside one projection | special-case | medium | medium | confirmed-with-corrections |
| AI-4 | The session of an agent has one shape at the root and another for a subagent | special-case | low | large | weakened |
| AI-5 | An evaluation becomes a form in five places | repeated-by-hand | medium | small | confirmed-with-corrections |
| AI-6 | A person sends a message by the draft, and a test sends it by another field | redundant | low | small | confirmed-with-corrections |
| AI-7 | The assistant has two views with two sets of maps, and the card has no controls | partial-feature | medium | medium | confirmed |
| AI-8 | The search models reach a tool set in three ways, one as a side effect of a turn | partial-feature | medium | small | confirmed-with-corrections |
| AI-9 | The provider adapters repeat the stream skeleton, the tool schema and the JSON conversion | repeated-by-hand | low | medium | weakened |
| AI-10 | State of one editor sits in tables of the process, beside the slot an editor has for it | wrong-place | low | small | confirmed-with-corrections |

### The text-like domains: JSON, XML, YAML, SQL, Julia, Markdown, RST, math, formula, book

Report: [text-domains.md](text-domains.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| TD-1 | The insertion buffer is built three ways, and half of the domains have only a label | several-ways | high | medium | confirmed-with-corrections |
| TD-2 | The template can not wrap each element of a list, so four list rules are written by hand | special-case | high | small | confirmed-with-corrections |
| TD-3 | A value that a subtree inherits is carried in three ways, one for each domain that needed it | several-ways | medium | medium | confirmed-with-corrections |
| TD-4 | A format is declared in two registries and four methods, and a tab reads through one and writes through the other | several-ways | medium | medium | confirmed |
| TD-5 | The parts of a prose page are written once for each prose domain | repeated-by-hand | medium | medium | confirmed-with-corrections |
| TD-6 | JSON and YAML are one data model kept as two domains | redundant | low | medium | weakened |
| TD-7 | The structural keys of math live in the reader of one view | wrong-place | medium | small | confirmed-with-corrections |
| TD-8 | An escape is two unrelated functions, and the edit of an escaped value maps by plain offset | partial-feature | medium | medium | confirmed |
| TD-9 | The code view of a file is assembled by hand for each file type that has it | partial-feature | low | small | confirmed-with-corrections |
| TD-10 | A domain says how it draws in two tables, and their order decides which view a tab shows | several-ways | low | medium | weakened |

### The diagram and data domains: chart, sequence chart, graph, FSM, workflow, git, process, research, database

Report: [diagram-data-domains.md](diagram-data-domains.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| DD-1 | Outside state enters in three ways, and the database is read on the loop | several-ways | high | medium | confirmed |
| DD-2 | The stage from a domain to a graph is written three times, and none keeps its vertices | repeated-by-hand | high | medium | confirmed-with-corrections |
| DD-3 | A view document is made in two ways; the diagram domains copy the second way four times | several-ways | medium | medium | confirmed-with-corrections |
| DD-4 | The outline of a workflow and of a study walks its whole tree in one computation | special-case | medium | large | confirmed |
| DD-5 | The chart and the sequence chart write one plot interaction twice | repeated-by-hand | low | medium | weakened |
| DD-6 | The view gestures of a plot and of a graph are in readers, so nothing can list them | partial-feature | medium | small | confirmed |
| DD-7 | Each domain writes its own plumbing for a verb, and workflow and research keep two code paths | repeated-by-hand | low | medium | weakened |
| DD-8 | Five of the ten domains have no view in the general renderer | partial-feature | medium | small | confirmed-with-corrections |
| DD-9 | The catalog draws its tree by its own projections, and the database domain holds a table model that nothing uses | several-ways | low | medium | weakened |
| DD-10 | The default layout engine is one slot of the process | wrong-place | low | small | confirmed |

### The backends: SDL, web, PDF, video, console

Report: [backends.md](backends.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| BE-1 | The walk of a canvas has no one home, and only the SDL backend draws just what is in view | partial-feature | medium | large | confirmed-with-corrections |
| BE-2 | The SDL backend holds the policy of the windows, and it writes the screen document while it paints | wrong-place | medium | large | weakened |
| BE-3 | The search for what changed since the last paint is written twice, and its home is the SDL file | several-ways | high | large | confirmed-with-corrections |
| BE-4 | Each painter decides again what a primitive means | repeated-by-hand | low | large | weakened |
| BE-5 | Each backend translates and queues its input by its own rules | several-ways | medium | medium | weakened |
| BE-6 | A service of the desktop has no one shape | several-ways | medium | medium | weakened |
| BE-7 | Output to a file has six shapes | several-ways | low | medium | covered-by-plan |
| BE-8 | The rule of a held frame is written three times | repeated-by-hand | low | medium | weakened |
| BE-9 | The device layer carries one value that is used | redundant | low | small | covered-by-plan |

### Packages, environments, build, tests, examples, tools

Report: [packages-build-test.md](packages-build-test.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| PB-1 | An editor is driven by scripted input in eight ways, and most tests imitate the loop by hand | several-ways | high | large | confirmed-with-corrections |
| PB-2 | The list of the packages is written by hand in about twelve places, and the copies have drifted | repeated-by-hand | medium | medium | confirmed-with-corrections |
| PB-3 | An example is declared in up to six places, and its sweeps are chosen by lists of names | several-ways | medium | medium | confirmed-with-corrections |
| PB-4 | The entry file of a package repeats one loop in 88 files, and a guard demands two workload lines that the method table knows | repeated-by-hand | medium | medium | confirmed-with-corrections |
| PB-5 | A test is registered three times by hand, and the contract tests of a domain are copies | repeated-by-hand | medium | medium | weakened |
| PB-6 | The static guards share a shape but no code | several-ways | low | medium | weakened |
| PB-7 | Parts of earlier compile-ahead and file-editor schemes are still exported | redundant | low | small | weakened |

### Cross-cut: tasks, timers, processes, watchers, and how their data reaches the editor loop

Report: [concurrency.md](concurrency.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| CC-1 | A stream has three doors to the loop, and one stream keeps its order by hand | several-ways | medium | large | weakened |
| CC-2 | A value that is read off the loop is built six ways | several-ways | medium | medium | weakened |
| CC-3 | A value that is sampled at an interval has no general form | partial-feature | medium | medium | confirmed-with-corrections |
| CC-4 | A child process is run five ways | several-ways | low | medium | confirmed-with-corrections |
| CC-5 | A task of an editor is started by hand at about 40 places, and no list holds the running work | repeated-by-hand | low | medium | weakened |
| CC-6 | The feed layer gives a contract and no store | repeated-by-hand | low | small | confirmed-with-corrections |
| CC-7 | A document of outside state repeats five parts | repeated-by-hand | medium | medium | confirmed-with-corrections |
| CC-8 | Each verb repeats the door, and each verb with an edit repeats it twice | repeated-by-hand | low | medium | confirmed-with-corrections |

### Cross-cut: extension points, registries, factory seams, and the shape of the public API

Report: [extension-seams-api.md](extension-seams-api.md)

| ID | Finding | Kind | Value | Effort | Check |
| --- | --- | --- | --- | --- | --- |
| XS-1 | The row of a type in the renderer is declared in five forms | several-ways | high | large | confirmed-with-corrections |
| XS-2 | A file format is declared twice, under three keys | several-ways | high | medium | confirmed-with-corrections |
| XS-3 | Five more registries are filled at load, and two of them came after the decision for seams | several-ways | low | medium | weakened |
| XS-4 | A model adapter is an open seam in the kernel and a closed list in the application | partial-feature | medium | small | confirmed-with-corrections |
| XS-5 | Ten functions read a method table as a list, each written by hand | repeated-by-hand | low | small | confirmed-with-corrections |
| XS-6 | A session document of an editor is declared in up to five places | repeated-by-hand | low | medium | weakened |
| XS-7 | Four show verbs repeat make, place and find again, because show_document! answers nothing | complicated-api | low | small | weakened |
| XS-8 | The printer of one widget has no factory, so six views search the whole widget table for it | complicated-api | low | small | weakened |
| XS-9 | A verb of the assistant is a group of up to six methods written by hand | repeated-by-hand | low | medium | weakened |
