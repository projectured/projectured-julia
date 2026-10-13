# Views across the documents of a session: the options

> **Kind:** plan · **Status:** pending; the API of section 6 is agreed (2026-10-13), the steps of section 9 are not started, the options of the engine are not chosen. Written 2026-10-12, updated 2026-10-13. · **Stands on:** [cell.md](../../documentation/package/kernel/cell.md), [architecture-decisions.md](../../documentation/design/architecture-decisions.md), [cheap-reactive-cells.md](cheap-reactive-cells.md), [filter-sort-and-find-any-table.md](filter-sort-and-find-any-table.md), [pending-edits-and-file-changes.md](pending-edits-and-file-changes.md), [back-and-forward-between-a-definition-and-its-uses.md](back-and-forward-between-a-definition-and-its-uses.md)

## 1. The request

The owner, 2026-10-12: in projectured-julia and in omnet-julia, a
cross-cutting view is often useful. Examples:

- all the external tasks that run;
- all the assistants in use;
- all the files with edits;
- the same lists with a filter: the files in one folder, the tasks that run
  fingerprint tests.

A view can be a table widget or another display. The editor can make such a
view from normal reactive documents, and the interface then stays consistent.
The editor must not become slow or stop to answer.

The second message of the owner puts the question at the cell layer. The cell
layer gives a reactive data structure, and a view can be a part of it. The
trade-off is between memory, time and consistency. The documents, which are
the value layer, must stay as independent as possible of the layer that
records the dependencies and runs the invalidation and the recomputation.

The third message of the owner corrects the costs of section 2.3:

- A view can be lazy and incremental. Its cost depends on how the view
  computes, what is on the screen, and what changed.
- When the invalidation is small, the computation is small too. A move of the
  cursor is a change of the selection through the whole pipeline, and it
  changes very little of the graphics. This works today.
- A view that reads the cells of another editor is not a concern now.

The owner answered the three questions on 2026-10-13. Section 8 has the
answers. Then the owner asked for more examples (section 5), and for an API
that lets the assistant build such views on demand (section 6).

On 2026-10-13 the owner agreed to the API of section 6: "Roster is fine, the
five mechanism are agreed", and asked for the steps in this plan (section 9).

**The options of the engine (section 4) are not chosen.** The steps build the
API with no change in the engine, and step 7 measures. A later plan extends
the engine if the measurement asks for it.

## 2. What exists now

### 2.1 Four patterns that give the rows of a list

| Pattern | Example | Where the rows come from | Cost of one change |
|---|---|---|---|
| Reactive query | `AssistantList` ([AssistantList.jl:40](../../source/platform/assistant/AssistantList.jl#L40)) | A computed cell over `collect_pane_tab_contents`, which reads only the structure of the panes | All rows compute again when a tab opens or closes. An edit inside an assistant costs nothing. |
| Session list | `TaskGroupList` ([TaskGroupList.jl:18](../../source/platform/task/TaskGroupList.jl#L18)) | The producer calls `add_task_group!` | O(1) for each event |
| Feed | `TaskFeed`, `FileChangeFeed`, `MessageLogFeed`, `McpLogFeed` | The producer writes a store with a lock. The editor drains it into shadow cells, at most four times a second ([TaskFeed.jl:87](../../source/platform/task/TaskFeed.jl#L87)). | A limit for each frame. A feed with no data asks for no frame. |
| Walk on demand | `search_documents` | One walk of the object graph | O(session) for each walk, and no cost between the walks |

The arrangement (filter, sort, find) is a projection over any collection.
`FilteringProjection` runs the predicate on every row when the source changes
([Filtering.jl:41](../../source/platform/projection/generic/Filtering.jl#L41)).

### 2.2 The facts of the cell engine that set the cost

The engine is in [ReactiveCell.jl](../../source/kernel/cell/ReactiveCell.jl).

- **A read records two entries.** A read inside a computation adds a weak
  reference to the `dependents` of the cell that it reads, and an entry to the
  `dependencies` set of the reader.
- **A write marks, and a read computes.** A write marks all transitive readers
  out of date at once. The walk stops at a reader that is out of date already,
  so the second write in a frame costs O(1) for a reader that the first write
  reached.
- **A run records its edges again.** Before a computation runs again,
  `_detach_upstream!` removes all its old edges, and the run records them
  again. A computation that reads N cells pays O(N) for its edges at each run,
  and then its own work.
- **Propagation follows the writes, not the values** (decision 10 of
  [architecture-decisions.md](../../documentation/design/architecture-decisions.md)).
  A computation that gives the same value still invalidates its readers.
- **The computing stack belongs to one task.** Only the editor task writes a
  document that a running editor shows (`PAR-STORE-THEN-DRAIN`). Each window
  runs its editor on its own task, and that task can be pinned to its own
  thread ([EditorLoop.jl:404](../../source/kernel/editor/EditorLoop.jl#L404)).
- **A reactive `CellVector` holds one cell for each element**, inside one cell
  for its structure. A write of an element reaches only the readers of that
  element. A write of a field inside an element document does not go through
  the vector.
- **One schema gives many kinds and layouts.** `@document` makes the cell kinds
  `ReactiveCell`, `MutableCell`, `ImmutableCell` and `UntrackedCell`, and the
  native layout `MFoo`. `copy_document(K, doc)` changes the kind.
  `sync_document!` copies a document into a reactive shadow, and writes only
  the cells that changed.
- **The editor knows if a cell has a reader.** `has_dependent_cells(c)` answers
  it. The editor uses it to tick the clock only while something reads the time
  ([Feeds.jl:45](../../source/kernel/editor/Feeds.jl#L45)).
- **The order of a frame** is `drain_feeds!`, then the read and evaluate
  stages, then the print stage
  ([EditorLoop.jl:65](../../source/kernel/editor/EditorLoop.jl#L65)).
- **The performance counters** count `:reads`, `:computes`, `:invalidations`
  and `:writes` in each frame, in a build that compiles them in. The write path
  calls `@count_performance :writes`, which finds a store that the frame binds
  to its task.

### 2.3 The costs of a cross-cutting view

The engine is lazy and incremental now. A change costs what it invalidates,
and then what the screen reads of that. So the cost of a view depends on the
form of each step of its computation:

- **A step for each element** makes one row from one item, as a map does. A
  change of one item costs one row, and a row that is not on the screen does
  not compute.
- **A step over the structure** finds the items: the walk of the pane tree, the
  tabs and the layers of each tab. It reads only the structure, so a change of
  the structure runs it again, and an edit inside a document does not.
  `AssistantList` is this step.
- **An aggregate step** makes one value from many inputs: a filter, a sort, a
  count, a group, the list of the kept rows. One computation reads all its
  inputs, so the change of one input runs all of it again.

Two costs come from the aggregate step:

- **P1, the time of an aggregate step.** A run reads all N inputs. Most of them
  are up to date, so each read is short, but the run is O(N). Laziness helps a
  filter only up to the last row on the screen. A sort and a count need all
  inputs.
- **P2, the memory of the dependencies.** The aggregate holds one edge for each
  input, and each run removes and records all of them again. A step for each
  element holds one cell for each element.

A small invalidation that does not reach an aggregate is no cost: a move of
the cursor shows it. A view that reads the cells of another editor is not in
this plan.

## 3. Options at the level of the editor

These options are from the first answer of 2026-10-12. Each option says where
the rows come from.

| | Option | Consistency | Cost |
|---|---|---|---|
| E1 | Reactive query over index cells of one window, as `AssistantList` does | Exact, in the same frame | O(index) for a change of structure |
| E2 | Session list that the producers write when a thing starts or ends, as `TaskGroupList` is | Exact only when every start and end writes it. A missed end leaks an entry. | O(1) for each event |
| E3 | Feed with sampled shadows, as `TaskFeed` is | Late by at most one interval | A limit for each frame |
| E4 | Fold over the stream of applied operations | Exact. It needs a start state and an answer for undo. | O(1) for each operation |
| E5 | General session store and a feed for each window: E2 and E3 together, the general form of `TaskFeedStore` | Late by at most one interval | A limit for each frame. The query can run off the editor task, because the records are values. |
| E6 | Incremental collections in the kernel | Exact | O(changed elements). Section 4 has the forms of it (R7, R8). |
| E7 | Snapshot on demand, from `search_documents` | Old until a refresh | No cost between refreshes |

**The place of a filter.** A filter can go in the view: the arrangement holds
the conditions as a document, and `FilteringProjection` applies them, in
O(rows) for each change. A filter can also go in the source: the store keeps
an index by a key, such as the folder of a file or the kind of a task, and
sends only the records that match.

**Guards for every option.**

- A source does no work while no view shows its rows (the check of
  `has_dependent_cells`, as for the clock).
- A source syncs at most once in an interval (`TaskFeed`: 0.25 s).
- A sync goes by key and version, and writes only the cells that changed. A
  sync with no change paints nothing.
- The table prints only the visible rows.

## 4. Options at the cell layer

### 4.1 The four axes

Each option at the cell layer is one choice on each of four axes.

| Axis | Choices |
|---|---|
| The form of a dependency | an edge for each cell read (now) · one edge for a group · an edge with a filter · a subscription to one field of one type · an entry in a journal of writes · a version number to compare · no edge |
| What a write does | marks the readers (now) · marks the readers when a filter passes · adds an entry to a journal · increments a version · nothing |
| What a read does | computes all again (now) · patches the old value with the changes · computes in slices over many frames · gives the old value |
| Freshness | exact at each read · exact at the print of the frame · late by at most one interval · old until a refresh |

The spectrum of the owner on these axes:

- **Fine-grained:** an edge for each read, a write marks, a read computes all,
  exact at each read.
- **Coarse-grained and functional:** no edge, a write does nothing, each read
  computes all from the whole document graph, exact at each read.
- **Materialized, with a refresh on demand:** no edge, a write does nothing, a
  read gives the old value, old until a refresh.
- **Intermediate:** the views look at the changes at the cell layer and patch
  their materialized data: a journal, a filter or a group edge, a read
  patches, exact at the print of the frame.
- **Other forms of the dependency graph:** a group edge, a filter, a field
  subscription, a version.

### 4.2 The options

**R1 — An edge for each cell read (now).** The view is a computed cell, and its
computation reads every cell that it needs.

- Memory: two entries for each cell read.
- Time: a write reaches the view once in a frame. A step for each element and
  a step over the structure cost what changed. An aggregate step computes all,
  O(N), and records N edges again.
- Consistency: exact at each read.
- Change: none.
- Fixes: nothing of P1 and P2. It is good when the view has no large aggregate
  step.

**R2 — A function with no tracking.** The view is a function of the document
graph. It reads with `peek` or inside `run_untracked`, or it is an
`UntrackedCell`, which computes at each read and records no reader.

- Memory: none between reads.
- Time: O(N) at each read.
- Consistency: exact at each read. But nothing tells the screen to read again,
  so a pane that shows the view becomes old. A trigger must come from outside:
  a key, a timer, or R3.
- Change: none. `UntrackedCell` and `run_untracked` exist.
- Fixes: P2, because there is no edge. P1 is worse: each read is O(N).
- Fits: a tool call of the assistant or of an MCP client, a command, a test.

**R3 — A materialized view with a refresh.** The view keeps its last result in
value cells, its rows. A refresh runs the function of R2, and syncs the result
into the rows by key, so a refresh with no change writes no cell. The trigger
is a command, an interval while the view is on the screen (the check of
`has_dependent_cells`), a quiet editor, or a budget of time in each frame.

- Memory: the result.
- Time: O(N) for each refresh. The rate limit or the budget keeps each frame
  short.
- Consistency: old between refreshes. The view can show its age.
- Change: none. A feed or a timer of the editor gives the trigger.
- Fixes: P2. P1 has a limit of time for each frame, but each refresh is O(N).

**R4 — A group edge.** One edge stands for many cells. A write of any member of
the group marks the readers of the group. The owner's example: cell A depends
on all cells of a `CellVector`, and lists none of them. Three forms of the
membership:

- *A static edge.* The group is a value cell, and each member lists it in its
  `dependents`. A cell with no computation does not remove its edges when it is
  read, so the engine keeps such an edge now. The change is a public call that
  adds and removes a static edge.
- *The container.* `CellVector` marks its group at each write of an element
  and at each change of its structure. A write of a field inside an element
  document does not go through the vector, so this form covers only the slots.
- *A scope at creation.* A cell keeps the group of the scope that made it, as a
  `Computation` keeps its fault scope. This needs one more field in every
  cell, and every operation that makes cells must run in the right scope.

A fourth form is one tracking unit for each document object, lever L4 of
[cheap-reactive-cells.md](cheap-reactive-cells.md). It changes the layout of
the documents.

- Memory: one edge for the reader. The static form keeps one entry in each
  member.
- Time: a read of the view computes all, O(N), but records one edge, not N.
- Consistency: exact.
- Change: small, in the engine (static form) or in `CellVector` (container
  form).
- Fixes: P2, and the work of the edges in P1. The view does not know which
  member changed, so the O(N) run of the aggregate stays.

**R5 — An edge with a filter.** An edge carries a predicate over the write: the
cell, the old value and the new value. The write asks the predicate before it
marks the reader. Example: the view of the files with edits depends on the
fields of the file documents, and its filter passes only a write of the state
of the edits. A key press writes text cells, and the filter stops it.

- Memory: one predicate for each edge, or one for each group with R4.
- Time: one call of the predicate for each write of a watched cell. It runs in
  the write, so it must be pure, short, and read no cell.
- Consistency: exact, when the predicate is right. A wrong predicate gives an
  old view: the same kind of bug as an impure computation.
- Change: in the walk of a write, the hottest path after the read. An edge
  with no filter must cost nothing more.
- Limit: only the first step of the walk has values. Further steps mark
  computed cells, which have no new value yet.
- Note: a filter that compares the old and the new value is a local exception
  to decision 10.
- Fixes: P1 for a write that can not change the aggregate: the aggregate does
  not run.

**R6 — A subscription to one field of one type.** A view subscribes to every
write of one field of one document type, wherever the documents are: for
example `(FileDocument, :modified)` or `(TaskExecution, :status)`. It is like a
trigger on one column of a database table.

- How a cell knows its type and field: the `@document` macro makes the cell, so
  it can give the cell a tag with its owner and its field. Either every cell
  gets the tag, or only the fields that the schema marks.
- A subscription sees only later writes. The view needs a first walk (R2) for
  the start state.
- Memory: one tag in every cell, or a mark in the schema.
- Time: one lookup for each write.
- Consistency: exact.
- Change: the macro and the engine.
- Fixes: P2, and P1 with the owner in the tag.
- Cost to independence: the tag grows every cell, or the schema names the
  observation.

**R7 — A journal of writes, and a view that patches itself.** This is the
general form of the intermediate solution of the owner. While at least one
view listens, each write of a value cell adds an entry to a journal of the
editor. After the evaluate stage and before the print stage, each view reads
the entries since its last position and patches its rows. A view finds the
row of a written cell in its own index, which maps a cell to a row key. Its
first walk makes the index, and it updates the index when a write changes a
structure.

- Memory: the index of the view, on its side, and the journal of one frame. The
  cells hold nothing more.
- Time: for each write, one check, and one entry while a view listens. For each
  frame, O(writes) lookups and the work of the rows that changed.
- Consistency: exact at the print of the frame. The patch must run between the
  evaluate stage and the print stage. At the point of `drain_feeds!`, it paints
  one frame late.
- Change: the write path of the engine, and one step in the frame. The journal
  is a collector outside the reactive graph, bound to the task of the frame, as
  the store of the performance counters is.
- Limit: the journal lists the writes of value cells. A computed value has no
  write, so a view reads a computed value through a cell of its row (R1 or R8).
- Undo is a set of writes, so the journal sees it with no special case.
- Fixes: P1, P2.

**R8 — Collection operators with one cell for each element.** The view is a
chain of operators over `CellVector`: map (one computed cell for each element),
filter (one predicate cell for each element), sort (one key cell for each
element), and concatenation (the documents of all panes). After a change of
the structure of the source, an operator matches the old and the new elements
by identity, and keeps the cells of the elements that stay.

- Memory: one cell for each element in each operator.
- Time: a change of one element computes its own cells again. The cell that
  puts the rows together reads N cells that are up to date: O(N), with a small
  constant, plus N edges.
- Consistency: exact.
- Change: none in the engine. The operators go in the collection slice of the
  platform.
- Fixes: P1 in part: the predicate runs for one row only. The assembly stays
  O(N). R4 removes its edge work, and R7 removes the O(N).

**R9 — Versions in place of marks.** A write increments a number of its group
and does not walk. A view keeps the number that it saw at its last refresh, and
skips each group whose number did not change. `TaskExecution` has such a
number in its native layout now.

- Memory: one number for each group.
- Time: O(1) for each write with flat groups, O(depth) with nested groups.
  A refresh costs O(changed groups).
- Consistency: as R3.
- Change: a group for each member, as in R4. A document does not know its
  parent, and a document can sit in two places, so nested groups are hard.
- Fixes: P1 for R3: a refresh does only the work of the groups that changed.

**R10 — Early cutoff.** A computed cell that gives the same value as before does
not count as a change for its readers. Example: the state of the edits of a
file computes again at each key press, and stays `true`. With a cutoff, the
view does not compute again.

- How: a mark becomes "possibly out of date". At the read, the engine checks
  each dependency first, and computes only when one of them really changed.
  This is the form of the Salsa and Adapton libraries.
- Memory: the old value, and a number for each cell that has a cutoff.
- Time: a check of the dependencies at each read.
- Consistency: exact.
- Change: a second algorithm of invalidation in the engine. Decision 10
  rejected this for the whole engine. An opt-in kind of cell is possible.
- Fixes: P1 for a computed input that gives the same value: the aggregate does
  not run.

### 4.3 Comparison

| | Memory | Each write | Each read or refresh | Freshness | Change | Fixes |
|---|---|---|---|---|---|---|
| R1 edge for each read | 2 entries for each cell read | O(1) after the first | what changed; O(N) and N edges at an aggregate | exact | none | — |
| R2 function, no tracking | none | nothing | O(N) at each read | exact, but no repaint | none | P2 |
| R3 materialized, refresh | the result | nothing | O(N) for each refresh | old ≤ interval | none | P2 |
| R4 group edge | 1 edge for the reader | O(1) | O(N), 1 edge | exact | small, engine or vector | P2, edges of P1 |
| R5 filtered edge | 1 predicate | 1 predicate call | fewer runs | exact | engine, write walk | P1 when a write can not change the aggregate |
| R6 field subscription | a tag in each cell | 1 lookup | first walk, then O(changes) | exact | macro and engine | P1, P2 |
| R7 journal and patch | index of the view | 1 check, 1 entry | O(writes) for each frame | exact at print | engine write path, frame step | P1, P2 |
| R8 collection operators | 1 cell for each element | O(1) | changed rows, O(N) assembly | exact | platform only | P1 in part |
| R9 versions | 1 number for each group | O(1) or O(depth) | O(changed groups) | old ≤ interval | groups in the engine | P1 for R3 |
| R10 early cutoff | old value for each cell | as now | check of the dependencies | exact | second algorithm | P1 when an input keeps its value |

### 4.4 How the options combine

The options are not exclusive.

- R4 and R5 together are the example of the owner: one edge to all cells of a
  `CellVector`, and a filter that runs at each write.
- R3 and R9 together give a refresh that skips the groups with no change.
- R7 and R8 together give operators that take their changes from the journal,
  so a change costs O(changed rows), with no O(N) assembly.
- R2, R3 and R7 are one path for one view function: first called at each read,
  then kept, then patched.

The three examples of the request:

- **Files with edits, in one folder:** R8 over the tabs, with a cell in each
  row for the state of the edits. The filter by folder and by state is the
  aggregate step.
- **Tasks that run fingerprint tests:** the rows come as values from a feed (E3
  or E5). The cell layer adds only R8 for the filter.
- **Assistants:** `AssistantList` (E1) is this view now. It has no aggregate
  step until a filter or a sort comes on it.

### 4.5 What keeps the documents independent

| Change | Options |
|---|---|
| No change in the documents or in the engine | R1, R2, R3, R8 |
| A change in the engine only | R4 (static form), R5, R7 (index on the side of the view), R9, R10 |
| A change in every cell, or in the schema | R6, R4 with a scope at creation, R4 with one unit for each object |

The question under this table: who picks the strategy of tracking?

- **The observer picks.** The view picks on its own side, and the engine gives
  one general hook: R5, R7, R9. The documents and their producers know nothing
  of the view. The precedent is the store of the performance counters: a
  collector outside the reactive graph, which the write path finds through the
  task of the frame.
- **The producer picks.** A document picks a cell kind or a layout
  (`@document [Kind]`), as it does now. A cross-cutting view can not pick the
  kind of the cells that other documents made. So this works only for data
  that the view owns, or that is made for it, such as a session store (E5).

### 4.6 The rules that each option must keep

- `PAR-PURE-THUNK`: a filter (R5), a patch (R7) and a view function (R2, R3)
  are pure functions of what they read.
- `PAR-NO-WRITE-IN-THUNK`: a journal is a collector outside the graph, as the
  fault store and the counter store are. No computation reads it.
- `PAR-STORE-THEN-DRAIN`: data from outside the editor task comes in through
  a store and a drain.
- `PAR-PER-EDITOR-STATE`: a journal, a group or a version counter belongs to
  one editor, or is bound to the task of its frame. It is never a constant of a
  module.
- Decision 1, laziness: a view that nothing shows does no work. While no view
  listens, a write costs at most one check.
- Decision 10: R5 with a compare of values, and R10, are local exceptions. Each
  must be opt-in for each edge or each cell, and cost nothing where it is not
  used.
- Monotone invalidation: R5 decides from the write alone. It never leaves a
  reader marked in part.

## 5. Examples

### 5.1 What each example says

- **Items:** what the rows are made from, and where those items live: in the
  cells of documents, in a store of values, in a native layout with a reactive
  shadow, or on disk.
- **N:** how many items the view looks at.
- **Changes:** what changes the items, and how often.
- **Steps:** the aggregate steps of the view. A map for each row is always
  there and is not listed.
- **Edits:** what a person does through a row. A projectional editor maps an
  edit of a row back to the source of the row.

### 5.2 Examples in projectured-julia

| | View | Items | N | Changes | Steps | Edits |
|---|---|---|---|---|---|---|
| X1 | Files with edits in one folder (the first view to measure) | The file documents of the tabs | 10–200 | The state of the edits, at a key press | Filter by folder and state, sort by name | Save, Revert |
| X2 | The count of open documents of each type ("4 JSON, 3 Julia") | The layers of the tabs | 10–100 | A tab opens or closes | Group, count | — |
| X3 | Assistants, their state, and the tokens that each used | `AssistantList` | 1–20 | Each streamed token | Sum of tokens, filter "waits for the person" | Show, Stop |
| X4 | Uses of one function in all open Julia files | The syntax nodes of each file | 10⁴–10⁵ | A key press in any file | Filter by name, group by file | Jump to a use, rename all uses |
| X5 | Faults of the session, grouped by origin | The fault store of the editor | up to 10³ | In bursts | Group, count, newest first | Retry, Clear |
| X6 | Log lines of one level and one source | The `MessageLog` document | 10³–10⁵ | New lines only, many in a frame | Filter, the newest k | — |
| X7 | The undo steps of all documents, newest first | The history of each document | 10²–10⁴ | Each edit | Merge by time, the newest k | Undo to a step |
| X8 | The 20 slowest frames, and the mean time of each stage | `FrameMeasurementStore`, a ring of 1000 frames, not cells | 10³ | Each frame adds one and drops one | The first k, a mean | — |
| X9 | Settings that differ from their default | The settings documents, and the defaults | 10² | Rare | A join of two sources | Reset a row to its default |

### 5.3 Examples in omnet-julia

| | View | Items | N | Changes | Steps | Edits |
|---|---|---|---|---|---|---|
| X10 | Tasks that run fingerprint tests, with the count of passes and failures in each campaign | `TaskFeedStore`, values with shadows | 1–10³ | Sampled four times a second | Filter by kind, group by campaign, count | Stop, Run again |
| X11 | Fingerprints whose last result differs from `fingerprint.json` | The file of the store, with pending edits, and the results of the tasks | 10²–10⁴ | A task ends, or the file changes | A join of two sources | Accept the new value into the store |
| X12 | Modules of a running simulation whose state passes a test, for example the queues longer than 5 | The native layout of the simulation, synced into a shadow with `sync_document!`, as the engine dashboards do | 10²–10⁵ | In bursts, at each sync | Filter, sort by length, the first k | Set one parameter on all the modules of the view |
| X13 | Messages in flight to one destination, by arrival time | The event heap of the engine, a native layout. No such view exists now. | 10³–10⁶ | 10⁵–10⁶ events a second, seen only at a sync | Filter, the first k by time | — |
| X14 | The mean of one accumulator over all runs of a study, one row for each design, with its width | The results of many executions, some of them still running | 10–10³ runs | A run ends, or a running accumulator moves | Group by design, mean and width | — |
| X15 | Results of one configuration in a result store | A store on disk, larger than memory | 10⁶ and more | A run writes a result | A query of the store | — |
| X16 | The parameters that the INI files and the NED defaults set, with the file that sets each | The content of many files, open or not | 10³–10⁴ | An edit of a file, or a change on disk | Filter by a pattern, group by parameter, two files that set one parameter | Change a value; the edit goes to the right file |

### 5.4 What the examples add to the costs

The examples show forms of change and of aggregate that section 2.3 does not
name. Each form has a cheaper path than a full run of the aggregate:

- **New items only** (X5, X6). The change is the new items. A filter tests
  only them, and the newest k are at the end.
- **A window** (X8). One item comes in, and one goes out. A mean keeps a
  running sum.
- **A partition** (X4, X7, X14, X16). One aggregate for each document, and one
  combination over the k parts. A change in one document runs one part and the
  O(k) combination. R1 and R8 can do this now, with no change in the engine.
- **A join of two sources** (X9, X11, X16). A row needs a key in both sources.
- **The first k rows** (X6, X7, X8, X12, X13). The screen shows k rows.
  Laziness helps only when the order has an index, such as a heap or a sorted
  tree.
- **Bursts at a sync** (X10, X12, X13). `sync_document!` writes only the cells
  that changed, so the set of the changes is exact and small. A journal (R7)
  gets that set as it is.
- **A high rate in one row** (X3). The cell of the row takes the rate, and the
  aggregate runs at most once in a frame.
- **Data larger than memory** (X15). No option at the cell layer fits. The
  view is a query of the store, one page at a time.
- **Edits through the view** (X1, X4, X9, X11, X12, X16). A row must keep the
  identity of its source: the source cell, or a reference to it.
  `FilteringProjection` shares the cells of its input now. A materialized copy
  (R2, R3) must keep a reference in each row, or a person can not edit
  through it.

Four examples cover most of these forms: X1 (the first view to measure), X4 (a
partition over the content of documents), X6 (new items only) and X12 (bursts
at a sync, a large N, and one edit for many rows).

## 6. An API to build a view on demand

### 6.1 What the API must do

The owner, 2026-10-13: the final plan has an API that lets the assistant build
views such as the examples, on demand. The API need not cover every
combination. It must make the useful combinations easy to make and to hook
in.

The API follows the conventions that the editor has now:

- **A description is a small document, not a closure.** The arrangement does
  this already (`ArrangementFilter`, `ArrangementSort`). So a view is saved,
  copied and undone like any document, and a person and the assistant edit it
  in the same way.
- **The assistant writes Julia** through `execute_julia_code`, and it can call
  only the names that `make_application_api` declares.
- **A verb edits through an operation**, as the interface does, so that undo,
  the log and the fault barrier see the edit.
- **A verb answers `Text`** that the model can read in the same round.
- **The strategy of the engine is not a part of the API.** Section 6.6 says
  which option of section 4 does the work of each part. An option can change
  later, and no view, no saved file and no call of the assistant changes.

### 6.2 The shape of a view

A view is a `Roster`: the items of a **source**, one row for each item, the
**columns** of each row, and the **steps** of an arrangement.

```
Roster
  source:     TabDocuments(FileDocument)          where the items come from
  columns:    ["name", "folder", "has_edits"]     a path inside an item, or a facet
  arrangement entries at the rows:
      filter  "has_edits" == true, "folder" contains "source/kernel"
      sort    "name"
```

- **A source** is a small document that says where the items come from.
  Section 6.3 lists the first kinds.
- **A key** names a value of an item, as in `filter_collection!` now: a path of
  fields, such as `"status"` or `"address.city"`, or a **facet**. A facet is a
  named value that the slice of the item type computes, such as `"folder"` or
  `"has_edits"` of a file document. A facet and a path have the same form. A
  facet must not have the name of a field.
- **The steps** are the kinds of the arrangement: filter and sort, which exist,
  and two new kinds that its plan names already as later kinds: a group with
  aggregates, and the first k items.
- **A row** keeps the identity of its item. A path column shares the cell of the
  item, so an edit of the row goes to the item through the readers. A facet
  column can not take an edit, unless its slice gives an operation for it. The
  context menu of a row is the context menu of its item, so the verbs of the
  item type (Save, Revert, Stop) work in a row with no new code.
- **A tab that a file keeps** saves the source, the columns and the
  arrangement. It does not save the rows, as `AssistantList` does now.

### 6.3 The first sources

| Source | The items | Parts | Examples |
|---|---|---|---|
| `TabDocuments(type)` | The documents of `type` that the tabs of the window show | One part for each tab | X1, X2, X3 |
| `ItemsWithin(source, type)` | The documents of `type` inside each item of `source` | One part for each item of `source` | X4, X7 |
| `StoreRecords(name)` | The records of a session store, through its feed: `:tasks`, `:faults`, `:log`, `:mcp_log`, `:frames` | One part | X5, X6, X8, X10 |
| `CollectionItems(collection)` | The items of a collection inside a document, given by a `Reference` | One part | X14 |

A row of `ItemsWithin` has the key `within`: the item of the outer source that
holds its item. So `"within.name"` is the name of the file of a call in X4. The
store `:tasks` is the tasks within the groups of the session task list, so a
row of it has `within`, its group.

A part is the unit of the work that finds the items. A change in one tab or in
one file finds the items of that part again, and then joins the parts. In the
first set, the steps of the arrangement run over all rows: a row that did not
change is a cell that is up to date, so its read is short. An aggregate for
each part is one of the later options (section 5.4, "a partition").

Not in the first set: a join of two sources (X9, X11), the files that no tab
holds (X16 in part), a store that is larger than memory (X15), a sample of a
native layout that has no shadow (X13), and the state of the modules of a
running simulation (X12), because no shadow holds it now: `ModuleTreeView`
reads the native model.

### 6.4 The verbs of the assistant

```julia
# Make a roster and show it in a tab. The keywords are a short form of the
# arrangement: they make the same entries as the chips and as filter_collection!.
show_roster!(source; title, columns,
             filter = [], sort = [], group = [], aggregates = [], first = nothing,
             editor = get_evaluation_editor()) -> ReferencedDocument

# The same roster, as a document, and not shown.
make_roster(source; columns, filter, sort, group, aggregates, first) -> Roster

# What the assistant reads before it writes a roster.
list_roster_sources() -> Text          # each source kind and store name, with an example
list_item_facets(type) -> Text         # the facets of an item type, and what each says

# New verbs of the arrangement, for any collection, as filter_collection! is.
group_collection!(collection, keys...; aggregates = [:count]) -> Text
limit_collection!(collection, count) -> Text

# One edit of every row that the roster shows, as one step of undo.
edit_shown_items!(collection, key => value) -> Text
```

- The keywords `filter` and `sort` take what `filter_collection!` and
  `sort_collection!` take.
- `group` takes keys. `aggregates` takes `:count`, or `key => :sum`, `:mean`,
  `:minimum` or `:maximum`. A slice can add an aggregate, for example the
  width of a mean in omnet-julia.
- `first` takes a count. It keeps the first rows after the sort.
- `show_roster!` answers the roster in its tab as a `ReferencedDocument`, the
  handle that the verbs of the arrangement take. Its `show` prints the title,
  the count of rows ("12 of 180"), the columns and the first 20 rows, so the
  model can check the roster in the round that made it.
- After `show_roster!`, the roster is a collection in a tab. The assistant
  changes it with `filter_collection!`, `sort_collection!` and the two new
  verbs, and a person changes it with the chips.
- `edit_shown_items!` makes one `CompoundOperation` with the operation of each
  row. It is the edit of X12: one parameter set on all the modules of the
  view.

### 6.5 The examples in the API

```julia
# X1: files with edits in one folder
show_roster!(TabDocuments(FileDocument); title = "Files with edits",
             columns = ["name", "folder", "has_edits"],
             filter = ["has_edits" => ==(true), "folder" => contains("source/kernel")],
             sort = ["name"])

# X2: the count of open documents of each type
show_roster!(TabDocuments(Document); title = "Open documents",
             columns = ["type"], group = ["type"], aggregates = [:count])

# X3: assistants, the most tokens first
show_roster!(TabDocuments(Assistant); title = "Assistants",
             columns = ["title", "state", "tokens"], sort = ["tokens" => :descending])

# X4: the uses of one function in all open Julia files, by file
show_roster!(ItemsWithin(TabDocuments(FileDocument), JuliaCall); title = "Uses of drain_feeds!",
             columns = ["callee", "within.name"],
             filter = ["callee" => ==("drain_feeds!")], group = ["within.name"], aggregates = [:count])

# X6: the newest 100 errors of the log
show_roster!(StoreRecords(:log); title = "Errors",
             columns = ["time", "source", "text"],
             filter = ["level" => ==(:error)], sort = ["time" => :descending], first = 100)

# X10 (omnet-julia): fingerprint tasks, counted by campaign and state
show_roster!(StoreRecords(:tasks); title = "Fingerprint tests",
             columns = ["name", "within.title", "status"],
             filter = ["kind" => ==(:fingerprint)],
             group = ["within.title", "status"], aggregates = [:count])

# X12 (omnet-julia): the 20 longest queues, and then one edit of all of them.
# Not in the first set: no shadow holds the state of the modules now.
roster = show_roster!(CollectionItems(queues); title = "Long queues",
                      columns = ["path", "length", "capacity"],
                      filter = ["length" => >(5)], sort = ["length" => :descending], first = 20)
edit_shown_items!(roster, "capacity" => 10)
```

The facets in these examples (`"folder"`, `"has_edits"`, `"type"`, `"state"`,
`"tokens"`, `"callee"`, `"kind"`) are proposals. Each one comes from
the slice of its item type. `queues` in X12 stands for a `Reference` to the
collection of the queue modules in the shadow of the simulation.

### 6.6 How a slice hooks in, and what the engine does

A slice adds to the API with methods of five generics, and with no change in
the roster slice:

```julia
# A source kind: the type of its items, and its items in parts.
get_roster_item_type(source) -> Type
make_roster_parts(source, context) -> the parts, each a reactive collection of items

# A store that offers its records as a source, under a name.
register_roster_source!(name, make_source)

# A facet of an item type: its name and what it says, its value, and an edit of it.
get_item_facets(::Type{T}) -> Vector{Pair{String,String}}
compute_item_facet(item::T, ::Val{name}) -> value                # pure: it reads cells only
make_item_facet_operation(item::T, ::Val{name}, value) -> Operation or nothing

# A step kind: as the arrangement does now.
make_arrangement_projection(description) -> Projection
```

A source that needs the window, such as `TabDocuments`, gets the pane tree
through `context` when the window shows the roster, as
`link_assistant_list!` links the assistant list now. No document holds the
editor.

Behind the API, the engine does the work of each part as follows:

| Part | Now, with no change in the engine | Later, with the engine extended, and no change in the API |
|---|---|---|
| A row | One computed cell for each facet column (R8). A path column shares the cell of the item. | — |
| A part of a source | One cell for the items of each part, and one cell that joins the parts | R7 patches the part |
| Filter, sort, first k | The stages of the arrangement keep index vectors over all rows. One predicate cell for each row (R8). | A stage for each part, R4 for the edges of the assembly, R7 for O(changed) |
| Group and aggregates | One run over all rows | An aggregate for each part, R7 |
| A store source | Its feed, at most one frame late (answer 1 of section 8) | — |
| A roster that no tab shows | No work: laziness, and the feed checks `has_dependent_cells` | — |

### 6.7 New mechanisms, agreed by the owner (2026-10-13)

1. The `Roster` document, and a new slice of the platform that holds it. The
   name is free in both repositories, and it says "a list of all the members
   of a kind". `View` names about forty types now, and "catalog" names the atom
   catalog test.
2. The four source kinds, and `register_roster_source!`.
3. Facets: `get_item_facets`, `compute_item_facet` and
   `make_item_facet_operation`.
4. Two new kinds of the arrangement: a group with aggregates, and the first k
   items, with `group_collection!` and `limit_collection!`.
5. `edit_shown_items!`.

The roster slice loads after `natural`, so it can use `arrangement`, `screen`
and `widget`. The slices that own the sources and the item types load after
it: `assistant`, `pane`, `fault`, `fileformat`, `undo`, `log`, `statistics`,
`mcplog` and `task`. So each of them adds its own source kind, store or facets,
and the roster slice names none of them.

## 7. Recommendation of the assistant (not a decision)

Build the API of section 6 first. It fixes the surface that the assistant, a
person and a saved file use. The options of the engine stay behind it.

Then try the options in the order of their cost:

1. **R8 and R3, with the check of `has_dependent_cells`.** No change in the
   engine. Measure the aggregate steps with the performance counters on a real
   session: for example 50 open files and 20 tasks, and typing in one file
   while a filtered and sorted view is open.
2. **R4 in the static form**, if the measurement shows that the edges of the
   O(N) assembly cost the most. It is a small change in the engine.
3. **R7**, if many views need exact rows at O(changed). It is the general form
   of the intermediate solution, and it keeps the documents independent. It is
   the largest change: the write path of the engine. After answer 1 of section
   8, it needs no new step in the frame.

Not recommended now: R6, because it grows every cell or the schema must name
the observation; R10, because it is a second algorithm of invalidation, against
decision 10 for the whole engine. R5 and R10 help only an aggregate that a
write reaches but can not change.

## 8. The answers of the owner (2026-10-13)

1. **Freshness.** "One refresh interval is at most 30 ms, that's fine for cross
   cutting views (but it's not for text type-in)." So:
   - The text that a person types stays exact in the same frame.
   - R3 and R9 are acceptable when their interval is at most one frame.
   - R7 can patch in a feed at the point of `drain_feeds!`, one frame late, if
     the journal asks for the next frame at once. It needs no new step between
     the evaluate stage and the print stage.
2. **The engine.** "We can extend the engine." R4, R5, R7 and R9 are open on
   the same footing as the options that change nothing.
3. **The first view to measure.** "Probably yes" to "files with edits in one
   folder" (X1).

## 9. Steps

Do the work in a worktree, on the branch `roster`, off `main`. Make one commit
for each step. Mark each step done here, and write here what the step finds.
The branch lands on `main` only with the word of the owner.

For each step, run the narrowest test: the test files of the step, through
`ProjecturedPlatformTest`. Do not run `test_all()`.

- [x] **1. The roster slice, its document and its generics.** Done 2026-10-14.
  - Add the slice `source/platform/roster/`, module `RosterModule`, after
    `natural` in `ProjecturedPlatform.jl`. Add it to the layering guard of the
    platform.
  - `Roster(source, columns, title)`. The rows compute from the parts of the
    source: one cell for the items of each part, and one cell that joins the
    parts. A row holds its item, and one computed cell for each facet column
    (R8).
  - The generics of section 6.6: `get_roster_item_type`, `make_roster_parts`,
    `register_roster_source!`, `get_item_facets`, `compute_item_facet` and
    `make_item_facet_operation`.
  - A key reads a facet when the item type has one of that name, and else a
    path through `get_arrangement_value`. A facet with the name of a field of
    its type is an error.
  - The sources `CollectionItems` and `ItemsWithin`, with the key `within`.
  - Tests in `test/platform/roster/`: the rows of `CollectionItems` over a list
    of JSON objects; a write of one item makes only its own row out of date;
    the parts of `ItemsWithin` and the key `within`; a facet key and a path
    key.
  - **What the step found and decided:**
    - The generic `make_roster_parts` is two generics, `collect_roster_parts(source,
      link)` and `collect_roster_items(source, link, part)`. The roster keeps the
      cell of each part itself, by the identity of the part, so a source holds no
      cache and stays a plain value. The naming law gives `collect_`: they gather
      from several places.
    - A source is a plain immutable struct, not a `@document`. It is data, so a
      file and the assistant can still write it.
    - `rows` is one `CellVector{RosterRow}` that keeps its identity. Its elements
      compute from the parts. The roster keeps the slot of the row of each item,
      so a row that stays keeps its cells. An item that two parts give is one
      row.
    - `link` is a field of the roster: the document of the window, which
      `link_roster!` sets. A roster with no link has no rows.
    - The roster is opaque to the walk of the documents (`is_walk_opaque`), as
      `AssistantList` is: its rows are the items of other places.
    - The arrangement gets a public generic, `find_arrangement_key_value(item,
      key)`, in place of a private helper. A row answers a key through the value
      cell of its column, or through `compute_roster_value`.
    - `PickingProjection` keeps the element type of a `CellVector`. So the picked
      rows of a filter or a sort are a `CellVector{RosterRow}`, which the natural
      renderer prints as a roster table.
    - `RosterToGraphics` prints `rows` through the recursion at the path `rows`.
      So an arrangement entry at `rows` works as at any collection, with no
      code of the roster for it.
    - **A widget table could not print inside an arrangement.** Inside an
      arrangement, every part prints through the arranged dispatch, also the
      panes and the grids that a table prints. The table reads fields of those
      IO maps, such as `content_iomap`, and the `ReferenceDispatchingIoMap` did
      not pass them on. The fault barrier states the law that a wrapper IO map
      keeps: a parent reads the IO map of the part through it, as if it were not
      there. So `ReferenceDispatchingIoMap` is now a plain struct, as
      `FaultCatchingIoMap` is, and passes an unknown property on to its inner
      IO map. It also answers `get_content_iomap`.
    - A facet is declared on the name of a type, such as `_RosterRun`, but an
      item of a `@document` type has a type with parameters. So
      `collect_item_facets` asks each type of the chain and the name of each.
    - The cell layer renamed its names on `main` while this plan was written:
      `is_cell_up_to_date` is `is_cell_valid`, and `run_untracked` is
      `run_without_cell_tracking`. Section 2.2 keeps the old words.

- [x] **2. The table of a roster, and an edit through a row.** Done 2026-10-14.
  - `RosterToWidget` prints the rows as a `WidgetTable`: a header with the
    column keys, and one row for each item. It uses the widget table as it is
    now. A roster of more than about 1000 rows waits for the lazy rows of step
    5 of [filter-sort-and-find-any-table.md](filter-sort-and-find-any-table.md).
  - A path column shares the cell of the item, and an edit goes to the item
    through the readers, as an operation. A facet column takes an edit only
    through `make_item_facet_operation`.
  - The context menu of a row is the context menu of its item.
  - A file that keeps a tab with a roster saves its source, its columns, its
    title and its arrangement, and no row.
  - Tests with a real `Editor`: an edit in a row changes the item and is one
    step of undo; the context menu of a row; a save and a read of a tab that
    shows a roster.
  - **What the step found and decided:**
    - The printer of the rows is `RosterRowsToWidget`, which step 1 made, and
      the natural renderer prints a `CellVector{RosterRow}` with it.
    - A cell whose value is a document shows that document, the same object as
      in its item, so its own reader edits it. In the test, a key in a cell
      writes the item and adds one entry to the undo list. A cell whose value is
      not a document is a label: no widget writes a field of a target as text
      now, so such a cell takes no key. A press on it selects the item of the
      row, so the context menu is the menu of the item.
    - A file keeps the source, the columns and the title of a roster
      (`pred_arguments`), and the three sources of the slice say that a file may
      build them (`is_pred_constructible`).
    - **A file can not keep an arrangement now**, of a roster or of any other
      document: an entry holds a `Reference`, and the pred notation can not
      write a kernel `Reference`. A `CollectionItems` with a `Reference` can not
      be saved for the same reason. This is outside this plan.
    - A bare name in a file is the name of a type that a file may build, and a
      name that starts with `_`, as a test fixture has, is not one.

- [x] **3. Two new kinds of the arrangement.** Done 2026-10-14.
  - `ArrangementGroup(keys, aggregates)` and `ArrangementFirst(count)`, each
    with its `make_arrangement_projection` method and its chips in the bar.
  - A group gives one row for each group: its keys and its aggregates. A group
    row takes no edit. The aggregates are `:count`, `:sum`, `:mean`, `:minimum`
    and `:maximum`. A slice adds an aggregate with a method of one generic.
  - `group_collection!`, `limit_collection!`, and their `make_…_operation`
    forms, as `filter_collection!` has.
  - Tests beside the tests of the arrangement: each kind on a plain collection
    and on a roster, its chips, and its verb.
  - **What the step found and decided:**
    - A group is a stage of its own, `GroupingProjection`, in a new fragment
      `Grouping.jl`. Its output is a `CellVector{ArrangementGroupRow}`. A row of
      a group holds the names of its columns, its values and the indices of its
      items (`members`). A key of a row is the name of a column, so a sort and
      the first items after a group act on the rows, such as `"count" =>
      :descending`. The aggregate is the generic `compute_arrangement_aggregate`.
    - The first items are a pick, as a filter is.
    - The bar shows a group and the first items each as one chip, so the × of
      the chip takes the whole description away.
    - The words of a place with a group count the groups: `2 groups of 3 items:
      by status: count, mean of delay`. `compute_shown_rows` stops at a group,
      because a group shows groups and not items.
    - The natural renderer prints the rows of a group as a table,
      `ArrangementGroupRowsToWidget`. The natural slice may not use the focus
      slice, so the table of a group does not follow the selection.
    - The widget slice has a new constructor, `WidgetTable(headers::CellVector,
      cells::CellVector)`, for a table that follows computed headers and rows.
      The roster table uses it too.
    - With no key, `group_collection!` takes the group away; with no count,
      `limit_collection!` takes the first items away.

- [x] **4. The sources of the window and of the stores.** Done 2026-10-14.
  - `TabDocuments(type)` in the slice `pane`, one part for each tab. The window
    links it to its pane tree when it shows the roster, as
    `link_assistant_list!` does.
  - `StoreRecords(name)` in the roster slice, and one registration in each
    slice that owns a store:
    - `:faults`: the entries of the `FaultLog` of the window;
    - `:log`: the entries of the `MessageLog`;
    - `:mcp_log`: the entries of the `McpLog`;
    - `:tasks`: the `TaskDocument`s within the groups of the session task list;
    - `:frames`: one row for each frame of the `FrameMeasurementStore`. A feed
      copies the ring into rows at most once in a frame, and only while a
      roster shows them.
  - Tests: each source gives the items of its store; a store that no roster
    shows asks for no frame.
  - **What the step found and decided:**
    - `TabDocuments` finds the pane tree in the document of the window, the link,
      as `show_document!` finds it: the content of the first window, looked
      through the layers that wrap it. A tab gives the first layer of its
      content that is of the type, from the outside inward.
    - Each of the five stores is a document of the session now: `FaultLog`,
      `MessageLog`, `McpLog`, the `TaskGroupList` and `FrameTimeSeries`. So
      `StoreRecords` reads each one as a collection, and no store needed a new
      feed. Each slice registers its store in the `__init__` that it has.
    - `:tasks` is a private source of the task slice: one part for each group of
      the session list, and each task with its group as `within`.
    - `:frames` is a private source of the statistics slice: one row for each
      frame of the session series, a named tuple of the number of the frame and
      the time of each measurement. The part reads `names` of the series, which
      is the probe of `FrameStatisticsFeed` for a view. So the series flushes
      while a roster shows its frames, and only then, with no new feed.
    - An entry of the message log holds `level` and `message` only. So X6 shows
      those columns, and a filter of a source needs a facet in step 5.

- [ ] **5. The facets of the first examples.**
  - `FileDocument`: `"name"`, `"folder"` and `"has_edits"`. A file document
    has no such state now: the file change store compares a hash of the whole
    text. So a save and a load record the newest entry of the undo list in a
    cell, and `"has_edits"` compares it with the newest entry now. A key press
    then prints no text of the file.
  - `Document`: `"type"`.
  - `Assistant`: `"title"`, `"state"` and `"tokens"`. A facet whose value the
    assistant does not hold now is left out, and this plan records it.
  - `JuliaCall`: `"callee"`.
  - The entries of the stores of step 4 use path keys where they have the
    field.
  - Tests: each facet; and X1 in a real `Editor`: a key press in a file makes
    its row show `has_edits`, and a save clears it.

- [ ] **6. The verbs of the assistant.**
  - `make_roster`, `show_roster!`, `list_roster_sources`, `list_item_facets`
    and `edit_shown_items!`, in a file of verbs, as `ArrangementProgram.jl`
    holds the verbs of the arrangement.
  - `show_roster!` answers a `ReferencedDocument`. Its `show` prints the
    title, the count of rows, the columns and the first 20 rows.
  - `edit_shown_items!` makes one `CompoundOperation`, one step of undo.
  - Declare the verbs, the four sources and the two verbs of step 3 in
    `make_application_api`, and add the vocabulary to the text of
    `APPLICATION_SYSTEM`.
  - Tests: each example of section 6.5 that is in the first set runs as it is
    written and answers its summary; `edit_shown_items!` on a roster of a JSON
    array is one step of undo.
  - The fast loop of the assistant (`tool/assistant/rehearsal.jl`) with three
    requests in plain words, for X1, X2 and X6. Record here how many rounds the
    model used for each. Check the free memory before a local model runs.

- [ ] **7. Measure X1 and X4, and record the counts here.**
  - Compile the performance counters in, with the preference
    `performance_counters`.
  - X1: 50 file tabs, the roster on the screen, 100 key presses in one file.
    Record `:reads`, `:computes`, `:invalidations` and `:writes` for each key
    press.
  - X4: the same, with the roster of the calls in the open files of
    `source/kernel/`.
  - Record counts, not times. A time needs an idle machine and the word of the
    owner.
  - The counts decide if a later plan adds a stage for each part, R4 or R7.

- [ ] **8. The documentation.**
  - `documentation/package/platform/roster/roster.md`: the design document of
    the slice, and its line in the index of the package documents.
  - A section "A list across the session" in
    [view-your-data-guide.md](../../documentation/guide/view-your-data-guide.md).
  - `test_documentation()` passes.

- [ ] **9. omnet-julia: X10.**
  - Start this step after the branch lands on `main`. A change of
    projectured-julia in a worktree is not visible to omnet-julia before that.
  - The facet `"kind"` of a task of a legacy runner (a smoke test, a
    fingerprint test, an update of the fingerprints), in the slice `campaign`.
  - If the API list of the IDE window does not include
    `make_application_api`, it declares the roster verbs.
  - A test in omnet-julia runs X10 as section 6.5 writes it.

## Not in this plan

A view that reads the cells of another editor (the owner, 2026-10-12: not a
concern now), a view across processes (the worker processes of omnet-julia),
the sources that section 6.3 leaves out of the first set, and the extensions of
the engine (a stage for each part, R4, R7), which a later plan adds if step 7
asks for them.
