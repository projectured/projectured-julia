# A value that a task reads is a cell like any other

Status: ACCEPTED, 2026-10-18 (the owner: "Yes, looks good"). No step has
started.

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
7. **A background cell whose inputs are provisional records no demand.** It
   answers its last answer, or its default, and it waits until its inputs are
   final, so a work never runs on values that are still to come.
8. **Only a drawing decides what to show for a provisional part** (decision 4, QA).

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
| A sort by configuration | the sort reads 2,000 records | 1,970 answer the default, provisional; 1,970 demands | the last order, until the sort is final (decision 4, QA) |
| After the frame | one task reads 1,970 heads | | |
| The answer | one operation writes 1,970 answers | all final | the sorted rows |
| A run writes `Sweep-n=0-#0.sca` again | the listing gives a new size | that cell is provisional, and answers its last record | the file stays under its run |

What goes in the pilot: `record_stamp`, `LegacyResultRecordReads`,
`ask_result_records!`, `ReadResultRecordsOperation`, `ApplyResultRecordsOperation`,
the acquire of a file entry, and `LegacyResultRecords`, because a run reads the
records of its folder through its files and so demands them.

What stays: the holders, for a thing with a lifetime, such as the watch of a
folder while a part shows it. A watch is no value.

## An example: a sort on a task

A sort that takes a cell vector, gives a cell vector, and orders the items on a
task, for a collection whose sort takes long:

```julia
function make_sorted_cell_vector(items::CellVector, key)
    # The work of one demand orders its keys. It reads no document.
    source = BackgroundSource(demands -> [sortperm(keys) for (keys,) in demands])
    # The inputs, read on the loop: the key of each item, as a value. A key that
    # is provisional makes the inputs provisional, and the order then records no
    # demand until every key is final.
    order = make_background_cell(source, () -> (Any[key(item) for item in items],);
                                 default = Int[])
    sorted = CellVector()
    set_cell_computation!(getfield(sorted, :elements), () -> begin
        n = length(items)
        rows = order[]               # the order of the keys now, the last order, or none
        length(rows) == n || (rows = collect(1:n))   # an order of other items is no order of these
        Cell[Cell(items[i]) for i in rows]
    end)
    sorted
end
```

`sorted` is provisional while `order` is, because it reads it, and the table
that draws `sorted` keeps its last rows that were not provisional (decision 4, QA). For the
2,000 files of a result folder, sorted by configuration:

| When | The records | `order` | `sorted` |
| --- | --- | --- | --- |
| The sort starts | 1,970 answer the default, provisional, and record demands | its inputs are provisional: no demand, the default, provisional | the own order, provisional |
| After the frame | one task reads 1,970 heads | | |
| The answers | final | its inputs are final, and it has no answer for them: a demand, provisional | provisional |
| After the frame | | one task orders the 2,000 keys | |
| The order | | final | final: the sorted rows |
| A run writes a file again | that record answers its last value, provisional | its inputs are provisional: its last order, provisional | the last order, provisional |
| The new record | final | a new demand only if the keys changed | final |

A sort that is fast needs no task. The arrangement keeps its cell `rows` as it is
today (`compute_sort_rows` in `Picking.jl`): it reads the keys, so it is
provisional while a key is, and it computes again when the keys come. That is
the pilot.

## Where the code goes

| File | Sealed | What changes |
| --- | --- | --- |
| `kernel/cell/ReactiveCell.jl` | no | the provisional flag of a cell; a read spreads it to its reader; a computation clears it at its start and keeps it when it read a provisional cell; the stop of a computation that gives the same plain value compares the flag too; `is_cell_provisional` |
| `kernel/cell/CellInterface.jl` | no | the contract of `is_cell_provisional` for every kind of cell; a value kind is never provisional |
| `kernel/cell/CellComputation.jl` | yes | no change |
| `kernel/cell/CellModule.jl` | yes | one export line for the new names of the cell layer, and no other change (decision 4, QC) |
| a new file of the editor layer | no | `BackgroundSource`, `make_background_cell`, the demands of a frame, the start of the works, the operation that writes the answers, and `wait_for_cell` |
| `kernel/editor/EditorLoop.jl` | no | after the print of a frame, the start of the works with demands |
| the projection layer | no | the print of a part that is provisional (decision 4, QA) |

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
4. The owner accepted the plan with the three proposals (2026-10-18, after the
   example of a sort on a task):
   - **QA.** A drawing of a provisional part shows the last output of the part
     that was not provisional, and its provisional output when it has none. So a
     label shows its default, such as an empty text, and a table that sorts keeps
     its last order until the sort is final.
   - **QB.** A read outside a computation, by a script, a verb or a test, answers
     as in a computation, the last answer or the default, and records the demand;
     `wait_for_cell(c)` waits for the final value, off the editor task.
   - **QC.** The sealed `CellModule.jl` gets one export line for the new names of
     the cell layer, such as `is_cell_provisional`, and no other change. This is
     the permission of the owner for that line.
5. A search of the documents has a parameter for background work (the owner,
   2026-10-18: "Both options make sense and the user may need one or the other
   depending on the circumstances. A search in a potentially large data should be
   bounded by default but the user should be able to override. So these are
   parameters, depth of search, do background work, number of items to find,
   etc."). By default a search starts no background work; `background = true`
   waits for the values that it reads. The depth is `maxdepth`, which exists. A
   bound on the count of matches is not in this plan.

## Steps

Each step is one or more commits with its tests, in a worktree, with a check of
`SEALING.md` before each edit of a kernel file. Mark each step done here.

1. [x] **The provisional state in the cell layer.** Done. Tests: `test_cell()`: a read
   spreads the flag, a computation clears it, the stop compares it. A measure of
   the hottest path: the count of reads and the time of a frame of a large example
   before and after, and the size of a cell.

   What the work found and decided:

   - The flag is a field `is_provisional::Bool` beside `state`. It fits in the
     padding, so a cell stays 40 bytes.
   - A computation marks itself with `mark_computation_provisional!()`, which
     throws an `ArgumentError` outside a computation. A computation that fails is
     final, and so is a write and a new computation before its first run.
   - `is_cell_provisional(c)` records a dependency on `c` and brings it up to
     date, and it does not make its reader provisional.
   - A read that records no reader (`peek`, `run_without_cell_tracking`, the
     untracked kind) takes no part.
   - The fallback `is_cell_provisional(::AbstractCell) = false` stands in
     `ReactiveCell.jl`, because the fallbacks of `CellDefaults.jl` are sealed.
   - The one export line of `CellModule.jl` exports `is_cell_provisional` and
     `mark_computation_provisional!`.
   - After a review: a failure that a provisional value caused is provisional. A
     failed run keeps the flag that its reads gave it, and a read that throws
     still makes its reader provisional, in the slow path of the read, so a
     computation that catches the failure is provisional too. A computation whose
     first attempt fails in an older world keeps the flag of both attempts, as it
     keeps the cells that both read; the next change clears it.
   - The measure, 2026-10-18, main against the branch, alternate processes on the
     same cores: a cell stays 40 bytes and allocates the same. A read of a valid
     cell is +0.3% to +0.6%, inside the noise. A chain of 1,000 computed cells is
     +1.3%, about 3 ns for each computation, slower in 20 of 20 pairs. A fan-out
     to 1,000 readers is +1.7%, slower in 15 of 20 pairs. A fresh print of a JSON
     array of 200 objects is +0.6% (348.7 ms against 346.7 ms), inside the spread
     of 3% between processes of one tree, and a reprint after one write is noise.
     The scripts are in `/var/tmp/explorer-pages/perf/`.
2. [x] **The background cell and its source in the editor layer.** Done. Tests with a
   headless editor: a read answers the default and is provisional; the work runs
   after the frame; the answer makes the cell final; a change of an input makes it
   provisional with its last answer; 1,970 demands of one frame are one work;
   `wait_for_cell` (decision 4, QB).

   What the work found and decided:

   - The file is `kernel/editor/BackgroundCells.jl`. A background cell is a
     `Cell` whose computation reads a computed cell of its inputs and a hidden
     cell of its last answer, which only the write of an answer changes. So the
     engine of step 1 needs no other change.
   - The demands of an editor are a session document, `BackgroundDemands`, and
     not a field of the editor. A computation finds it through the editor of the
     evaluation, because a code unit computes on a task of its own. A demand wakes
     the editor, so a frame follows and starts the work.
   - The frame starts the work after its print (`start_background_cell_work!`),
     and so does the loop after its first print. A held frame prints no document,
     so a demand of a code unit starts at the next frame after the unit.
   - The tool layer has `start_background_work` for the code of the assistant, so
     the start of a frame is `start_background_cell_work!`.
   - `wait_for_cell` on the task that owns the documents, or with no loop, first
     makes each provisional cell below the cell invalid, because a provisional
     cell that a read computed before is valid and records no new demand. Its
     collector records each demand again, also one that a task of the editor
     computes already, because that answer would come through the inbox, which
     nothing drains while the call waits.
   - A work that throws is the answer of each cell of its batch, and so is a work
     that answers another count of values; a read of such a cell throws it.
   - After a review: every demand gets an answer, also from a work that throws at
     a stop or answers no vector, so no cell waits forever. An answer to a demand
     older than the one of the answer that the cell holds is dropped. The work gets
     a copy of the inputs, and runs through `start_background_work`. A source is
     one object, and opaque to a walk of the documents. `wait_for_cell` on the
     task that owns the documents throws at once when nothing below the cell asks.
   - A review and the explorer session found that a demand that comes from one
     computation run is lost when that run happens where no editor is in scope,
     such as the first print of `make_editor` or a read at the REPL, because the
     cache never repeats the run; and that a walk of the documents would ask for
     every value that it passes. What changed, following the rule of the owner
     ("if it's visible, then it's calculated"):
     - A provisional cell computes again at each read by a computation (the cell
       layer), so a background value asks wherever a computation uses it, also
       when it computed before where it asked nobody. `is_computation_running()`
       is the third name of the export line of `CellModule.jl`.
     - The first print of `make_editor` runs with its editor as the editor of the
       evaluation.
     - A walk of the documents (`walk_document`, so `search_documents` and
       `search_references`) has the keyword `background`, decision 5: by default
       it starts no background work and takes each value as it is; with
       `background = true` it waits for the final value of each provisional cell
       that it reads (`complete_walked_cell`, which the editor answers).
     - `wait_for_cell` is `wait_for_cell!`, because it writes cells, and a
       computation can not call it. It reads the cell through a computation, so
       the cells below ask again.
   - A fact for later (the explorer session): the quick filter of the explorer is
     a computation that reads the label of every row that the tree read, so it
     asks for each background value that those labels read, also of the rows that
     it hides; no label of a tree row reads a background cell today. A decoration
     must keep to stored state, because the count of a roster reads the decoration
     of each counted item.
3. [x] **The drawing of a provisional part** Done. (decision 4, QA). Tests: the print tests of a
   label and of a table that sorts.

   What the work found and decided:

   - A background cell answers its last answer while it is provisional, so a
     part that reads it shows its last value already, and a label needs nothing:
     it shows its default only while its value never came.
   - The case that needs more is a computation over values that came at different
     times, such as a sort: its order over defaults is wrong. So the projection
     layer has `make_final_holding_cell(compute; is_usable)`
     (`ProvisionalOutput.jl`): a cell that answers its last final value while it
     is provisional, as long as `is_usable` accepts it.
   - The picking stage of the arrangement (`Picking.jl`), which every filter and
     sort of a collection goes through, keeps its last final rows while a value
     that they read is provisional, as long as each row names an item of the
     input. So a table keeps its order until its sort is final.
   - Not built: one rule for every part of every print. A part applies the
     helper where its output must not jump.
4. [x] **The pilot in omnet:** Done. the record of a result file entry is a background
   cell, and the parts that the table of the example lists go. Tests:
   `test_result_folder()` and `test_result_file_document()`.

   What the work found and decided (omnet branch `background-records`):

   - The record of a file entry is a background cell over the path, the size and
     the time of its file, with the empty record as its default. Each result
     folder holds one `BackgroundSource`, so one task for each folder and frame
     reads the records that the frame asked for.
   - Gone: the stamp of a record, the reads for each editor, the ask, the read
     and the apply operation of the records, the acquire of a file entry, and
     `LegacyResultRecords`.
   - A run holds its result folder, through `find_run_result_folder`, which was
     `find_run_result_records`, so the folder reads its listing and watches it.
     The files of the run read the index of the folder, which reads every record,
     so a run in view asks for all the records of its folder.
   - `read_result_folder` reads every record at once, in one batch on the calling
     task, with `wait_for_cell!`.
   - The label of a file in a tree reads no record, so a quick filter of the
     explorer asks for none.
5. [ ] **The guides:** `cell.md`, `editor.md`, `architecture-invariants.md` (the
   carve-out of `PAR-PURE-THUNK` and the stop rule) and `concepts.md`; the plan
   moves to `plan/done/`.

## Not in this plan

The other five reads of the table move one at a time after the pilot, each in a
plan of its own. The watches of folders and files stay with the holders. Plan C
step 3d, the page of a result folder, is built on step 4, in the omnet plan C.
