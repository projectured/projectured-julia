# A value that a task reads is a cell like any other

Status: PROPOSED, 2026-10-18. No step has started. The owner asked to see the
shape before the work.

## The ask

The owner, 2026-10-18, on the page of a result folder, whose table sorts by
values that each file holds:

- "The editor is both lazy and incremental not just in nature but also in
  principle. [...] whoever needs it, calculates it, and stores back in the right
  place for others to find. If it's not visible, then it's not calculated. If it's
  visible, then it's calculated. If it's sorted then it must be calculated."
- "The only thing I'm not sure about is how do we make this as transparent as
  possible. So it's not like every consumer of every lazy and incremental data has
  to deal with all sorts of weird values. It's like this should be a kernel
  service, producing a lazy part of a celled data structure eventually from some
  background task."

Then, to three questions: "not ready" is a state that goes up through the
computations, and only the drawing says what to show (the owner: "yes"); the
change of a sealed file of the cell layer ("maybe, I want to see the shape
first"); a plan first, with the records of a result folder as the pilot, and
step 3d of the omnet plan C built on it ("yes").

## What the code does now

Six places read a value off the loop, and each one builds the same parts by hand:
the inputs read on the loop, a key of the inputs, a stored value with its key, a
queue or a read state for each editor, a task, and an operation that writes the
answer back.

| The value | Where | Its parts |
| --- | --- | --- |
| The listing of a folder of the Files tab | `FileSystemDirectory` | `state`, `read_count`, `ApplyFolderListingOperation` |
| The configurations of a project | omnet, the project page | the state and the read count of the cache, `ApplyProjectDiscoveryOperation` |
| The details of the runs | omnet, `LegacyIniFileEntry.jl` | `freshness`, `LegacyRunDetailReads`, `ReadRunDetailsOperation`, `ApplyRunDetailsOperation` |
| The listing of a result folder | omnet, `LegacyResultFile.jl` | `state`, `is_reading`, `is_stale`, `ApplyResultListingOperation` |
| The records of the result files | omnet, `LegacyResultFile.jl` | `record_stamp`, `LegacyResultRecordReads`, `ReadResultRecordsOperation`, `ApplyResultRecordsOperation`, `LegacyResultRecords` |
| The values of formulas | `FormulaComputation.jl` | `result_key`, the queue `_FormulaComputer`, `ReplaceFormulaResultOperation` |

Each consumer reads a placeholder while the value is not there: `nothing`, an
empty text, or a state such as `:unread`. A sort of the records sorts the empty
text as if it were a configuration.

The facts of the kernel:

- A reactive cell is valid, invalid, failed, computing, maybe invalid or
  checking (`ReactiveCell.jl`). No state says that a value is still to come.
- A read records its reader before it brings the cell up to date, and a
  computation that throws stops at the first throw. So a computation that stops
  at a value that is not there reads none of the values after it.
- `PAR-PURE-THUNK` accepts a write to a collector outside the graph, which no
  cell depends on.
- `start_document_read!` (the platform) runs one read on a task and posts its
  answer. `BackgroundWork` (the tool layer) runs code of the assistant.

## The model

1. **A background cell** is a reactive cell whose value comes from a task. It
   declares three things: its **inputs**, a computation of cells that the loop
   reads; its **source**, which says what work reads the value and which values
   one task reads together; and its **default**, the value while it has none.
2. **A read never waits, and never fails because a value is still to come.** A
   background cell whose answer belongs to its inputs now answers that answer.
   Else it answers its last answer, or its default when it has none, and it
   records a **demand** at its source, and it is **provisional**.
3. **Provisional is a state of a cell, not a value.** A computation that reads a
   provisional cell is provisional itself. It computes with what it reads, so it
   reads all the values that it needs in one pass, and each of them records its
   demand: a sort over 2,000 records records 1,970 demands in one frame.
4. **The work runs after the frame, off the loop.** After the print of a frame,
   the editor starts the work of each source with demands, on a task, with the
   inputs as values. The work reads no document.
5. **The answer comes back through the inbox.** One operation for each work
   writes the answers into their cells, in a write phase. Each write invalidates
   the readers, as any write does. The next read computes them again, and with
   all their values there, they are no longer provisional.
6. **A cell keeps its answer with the key of its inputs.** A change of an input
   makes the cell provisional again, and it answers its last answer until the new
   one comes. A demand that a task reads already waits for that task.
7. **Only a drawing decides what to show for a provisional part** (QA).

So the rule of the owner holds by itself: a value that no computation reads is
not read; a value that a visible part reads is read; a sort reads every value
that it sorts by; the answer is stored in its cell, where every other reader
finds it.

## An example: the records of a result folder

The names are proposals. A folder with 2,000 result files, as documents:

```julia
# One source for each folder: one task reads the heads of the demanded files.
records = BackgroundSource(inputs -> [read_run_record(path) for (path, _, _) in inputs])

LegacyResultFileEntry(path = "Sweep-n=0-#0.sca", size = 4096, modified = t1,
    record = make_background_cell(records,
                                  () -> (entry.path, entry.size, entry.modified);
                                  default = EMPTY_RUN_RECORD))
```

Over time, when a person opens the page of the folder, sorts it, and a run writes
a file again:

| When | What happens | The record cells | What the page shows |
| --- | --- | --- | --- |
| The page opens | 30 rows read the record of their entry | 30 answer the default, provisional; 30 demands | 30 rows, the record columns not filled yet |
| After the frame | one task reads 30 heads | | |
| The answer | one operation writes 30 answers | 30 final | the 30 rows with their values |
| A sort by configuration | the sort reads 2,000 records | 1,970 answer the default, provisional; 1,970 demands | the last order, until the sort is final (QA) |
| After the frame | one task reads 1,970 heads | | |
| The answer | one operation writes 1,970 answers | all final | the sorted rows |
| A run writes `Sweep-n=0-#0.sca` again | the listing gives a new size | that cell is provisional, and answers its last record | the file stays under its run |

What goes in the pilot: `record_stamp`, `LegacyResultRecordReads`,
`ask_result_records!`, `ReadResultRecordsOperation`, `ApplyResultRecordsOperation`,
the acquire of a file entry, and `LegacyResultRecords`, because a run reads the
records of its folder through its files and so demands them.

What stays: the holders, for a thing with a lifetime, such as the watch of a
folder while a part shows it. A watch is no value.

## Where the code goes

| File | Sealed | What changes |
| --- | --- | --- |
| `kernel/cell/ReactiveCell.jl` | no | the provisional flag of a cell; a read spreads it to its reader; a computation clears it at its start and keeps it when it read a provisional cell; the stop of a computation that gives the same plain value compares the flag too; `is_cell_provisional` |
| `kernel/cell/CellInterface.jl` | no | the contract of `is_cell_provisional` for every kind of cell; a value kind is never provisional |
| `kernel/cell/CellComputation.jl` | yes | no change |
| `kernel/cell/CellModule.jl` | yes | one export line for the new names of the cell layer, or no change (QC) |
| a new file of the editor layer | no | `BackgroundSource`, `make_background_cell`, the demands of a frame, the start of the works, the operation that writes the answers, and `wait_for_cell` |
| `kernel/editor/EditorLoop.jl` | no | after the print of a frame, the start of the works with demands |
| the projection layer | no | the print of a part that is provisional (QA) |

A provisional cell is a valid cell, so the states of invalidation and
`PAR-MONOTONE-INVALIDATION` do not change. The record of a demand is a write to a
collector outside the graph, as the carve-out of `PAR-PURE-THUNK` allows. The
answer enters by the inbox (`PAR-STORE-THEN-DRAIN`), and only the editor task
writes the cells (`PAR-SINGLE-WRITER`).

## Decisions

1. Option B of plan C step 3d (the owner, 2026-10-18): a value is read when a
   consumer needs it, and stored where the others find it.
2. "Not ready" is a state that goes up through the computations, and only the
   drawing decides what to show (the owner: "yes").
3. This plan comes first, with the records of a result folder as the pilot, and
   plan C step 3d is built on it (the owner: "yes").

## Questions

- **QA. What a drawing shows while its part is provisional.** My proposal: the
  last output of the part that was not provisional, and its provisional output
  when it has none. So a label shows its default, such as an empty text, and a
  table that sorts keeps its last order until the sort is final.
- **QB. A read outside a computation**, by a script, a verb or a test. My
  proposal: it answers as in a computation, the last answer or the default, and
  it records the demand; `wait_for_cell(c)` waits for the final value, off the
  editor task.
- **QC. The sealed `CellModule.jl`.** My proposal: one export line for
  `is_cell_provisional`, with the permission of the owner. The other way is to
  reach the name as `CellModule.is_cell_provisional` from the layers above.

## Steps

Each step is one or more commits with its tests, in a worktree, with a check of
`SEALING.md` before each edit of a kernel file. Mark each step done here.

1. [ ] **The provisional state in the cell layer.** Tests: `test_cell()`: a read
   spreads the flag, a computation clears it, the stop compares it. A measure of
   the hottest path: the count of reads and the time of a frame of a large example
   before and after, and the size of a cell.
2. [ ] **The background cell and its source in the editor layer.** Tests with a
   headless editor: a read answers the default and is provisional; the work runs
   after the frame; the answer makes the cell final; a change of an input makes it
   provisional with its last answer; 1,970 demands of one frame are one work;
   `wait_for_cell` (QB).
3. [ ] **The drawing of a provisional part** (QA). Tests: the print tests of a
   label and of a table that sorts.
4. [ ] **The pilot in omnet:** the record of a result file entry is a background
   cell, and the parts that the table of the example lists go. Tests:
   `test_result_folder()` and `test_result_file_document()`.
5. [ ] **The guides:** `cell.md`, `editor.md`, `architecture-invariants.md` (the
   carve-out of `PAR-PURE-THUNK` and the stop rule) and `concepts.md`; the plan
   moves to `plan/done/`.

## Not in this plan

The other five reads of the table move one at a time after the pilot, each in a
plan of its own. The watches of folders and files stay with the holders. Plan C
step 3d, the page of a result folder, is built on step 4, in the omnet plan C.
