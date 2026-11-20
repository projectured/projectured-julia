# The tests run fast

> **Status (2026-11-20): proposed.** The owner asked for this plan on 2026-11-20. No step is
> done. The plan waits for the approval of the owner. The work covers projectured-julia and
> omnet-julia.

## 1. The purpose

The owner, 2026-11-20: "running the projectured and omnet tests take a lot of time, we should
work on making it faster." The owner named three ways:

- "move large tests into separate functions so they can be called separately"
- "add filters for large test groups of the same kind to allow focusing on specific parts"
- "support running the tests in parallel to better utilize CPU cores"

The assistant gave six more ways. The owner said: "yes, write the plan with all nine ideas".
The table gives each idea and the step of this plan that does it.

| Idea | Step |
|---|---|
| I1. Large tests in separate functions (owner) | 1, 6 |
| I2. Filters for large groups of the same kind (owner) | 3 |
| I3. Parallel runs (owner) | 5 |
| I4. A record of the time and the memory of each test function | 2 |
| I5. One process that stays open between two edits | 10 |
| I6. Only the tests of what changed | 8 |
| I7. No extra run of main beside a run of a branch | 9 |
| I8. A time limit for each test function | 4 |
| I9. A fast level and a slow level | 7 |

The owner also asked: "Idea 3: parallel tests could be run in the same image using multiple
threads, can that save memory and load time?" Section 3 gives the answer.

## 2. What exists

These facts come from the logs of earlier runs in `/var/tmp/bounded-run`, from the notes of
earlier sessions, and from [testing-guide.md](../../documentation/guide/testing-guide.md).

- **Suites and parts.** A suite is a function that calls other test functions, its parts.
  `test_platform()` calls 261 parts, `test_kernel()` calls 81, and `test_all()` calls 35
  suites (on `main` at `ae590420c`). Each part is a function, for example `test_text()`.
  omnet-julia runs every suite in one process from `test/runtests.jl`.
- **One call compiles all parts first.** `test_platform()` names each part in its body. Julia
  compiles the suite and every part that it names before the first test starts. On 2026-10-14
  (`main` at `3f8f96ea7`) this compile reached 7.9 GB in three minutes and printed nothing.
  The same parts, called one at a time through a lookup of their names, peaked at 2.9 GB.
- **The time of a run.** Four runs of `test_platform()` in a new worktree in November took 29
  to 32 minutes, with a peak of 13.2 to 13.8 GiB. The testset of the suite took 14 to 17
  minutes of that time. The rest is precompile, load, and the compile of the one call.
- **The load.** The load of `ProjecturedTest` takes about 8 s and holds about 0.75 GB
  (testing guide, 2026-09-25). A small suite, for example `test_json()`, takes 61 to 66 s
  with a peak of 1.0 to 1.6 GB.
- **Runs of main.** 145 of the 1049 jobs in `/var/tmp/bounded-run` are runs of a base commit
  beside a run of a branch. A branch run must be compared with main, because main has
  failures that are not marked. `test_platform()` has 15 of them now (commit `7c05bfa0e`).
- **Hangs and memory.** An omnet run of `test_presentation` reached its 2-hour bound and
  printed no result. An omnet run of `test_ide` reached its 12 GB cap after 44 minutes. In
  both cases the results of all parts of the run were lost.
- **The machine.** 32 CPUs, shared with other sessions. Suites run on the four cores 24 to
  27. The caps of all running jobs must stay under half of the available memory. On
  2026-11-20 that half was about 16 GB.
- **Helpers that exist.**
  - `catalog(; domain = :json)` filters the generated examples by the name
    `domain/name/variant`.
  - The convention for a known failure: `@test_broken` with a `# @broken: <reason>` line
    (testing guide, "Marking known-failing tests").
  - The section "The time and the memory of each part" of the testing guide: a measurement
    by hand, one process for each part.
  - `bounded-run` (outside the repositories) caps the memory and the time of one job.

## 3. Threads in one process

**The answer: a little, and not enough for the risk now.** Parallel worker processes give
more, after step 1.

What threads in one process save:

- **The load.** Each extra worker process loads the packages again: about 8 s and 0.75 GB. A
  thread does not.
- **The compile while the tests run.** Each process compiles the same code paths again. In one
  process, each path compiles one time. The size of this cost is not known. Step 2 records it.

What threads do not save:

- **The precompile.** The package images are on disk, in the depot. All processes that use the
  depot read them. Only the first run after a change precompiles.
- **The test memory.** The large peaks are the memory of the tests and the compile of the one
  call, not the loaded code. In one process, the peaks of parts that run at the same time add
  up as in separate processes. One garbage collector serves all threads, and a full collection
  stops all of them.

What stops threads in this code now:

1. The check of cell writes is for the whole process
   ([CellWriterCheck.jl:33](../../source/kernel/cell/CellWriterCheck.jl#L33)). While one test
   runs an editor loop, a cell write from the task of another test counts as a foreign write.
   20 test files start an editor loop.
2. 14 test files change `ENV` or call `cd`. Both are values of the process.
3. Some caches are a `Dict` with no lock, for example `_TTF_CACHE`
   ([TrueType.jl:54](../../source/platform/style/TrueType.jl#L54)) and `_PALETTES`
   ([Palette.jl:111](../../source/platform/style/Palette.jl#L111)). Two tasks that write one
   `Dict` at the same time can break it.
4. 24 test files use SDL. The video state of SDL is a value of the process.
5. A test already fails when other test packages share its process: on 2026-10-30
   `test_kernel()` failed one check with three more test packages loaded, and passed alone.
6. The workers of the omnet parallel engine spin and never yield. They take the threads that
   other tests need.
7. A hang, a crash, or the memory cap in one part ends all parts of the process.

The test framework itself is not an obstacle: the `Test` package of Julia 1.13 keeps the
current testset in a `ScopedValue` and locks the list of results.

With parts in a table (step 1), one process of `test_platform` needs about 3 GB, not 14 GB. Then
four worker processes fit in the memory budget and use the four cores of the suite lane.

## 4. Decisions

Each decision is proposed by the assistant. It counts as approved when the owner approves the
plan.

- **P1. A suite is a table of parts** (proposed by the assistant). The suite file holds a
  constant vector of the part functions, for example `const PLATFORM_PARTS = [test_collection,
  test_table_interface, …]`. `test_platform(; keywords...)` calls the runner with that table.
  The runner calls each part through the table, so Julia compiles a part only when it runs. An
  entry can also be a suite, which the runner opens into its parts. An entry can carry
  settings: `test_catalog => (limit = Minute(20), level = :slow)`. Rejected: a runner that
  reads the calls from the text of the suite file. The text is not a value of the program, and
  a comment or a line break makes the read wrong.
- **P2. The runner lives in `ProjecturedKernelTest`** (proposed by the assistant). It uses only
  `Base`, `Dates`, and `Test`. The test packages of both repositories depend on it already, or
  get it as a test dependency. Rejected: a copy in each repository.
- **P3. The record is one line for each part, in a file of tab-separated values** (proposed by
  the assistant). The columns: repository, commit, suite, part, pass, fail, error, broken,
  result (`done`, `timeout`, `memory`, `crash`), time, compile time, garbage collection time,
  allocated bytes, live bytes after a full collection, and the peak resident memory of the
  process. The runner also prints one line when each part ends, because a nested testset
  prints its summary only at the end. Rejected: a JSON record, because a JSON writer needs a
  package.
- **P4. One filter keyword, `only`, and its opposite, `skip`** (proposed by the assistant). Each
  takes a `String` (a part of the name) or a `Regex`. A suite filters the names of its parts. A
  walk over the examples filters the names of its examples, `domain/name/variant`, as
  `catalog` does. Rejected: one keyword for each kind of group.
- **P5. Parallel runs use worker processes, not threads** (proposed by the assistant), for the
  reasons of section 3. Rejected: threads in one process.
- **P6. A supervisor starts the workers** (proposed by the assistant). It is a script,
  `tool/run-tests.jl`, that loads no package, so it needs little memory and starts at once. It
  sends the name of the next part to a worker on the standard input of the worker. The worker
  sends the line of the record back on its standard output. The worker function,
  `run_test_worker()`, is in `ProjecturedKernelTest`. Rejected: a supervisor that loads the
  test packages, because a fault in a part then ends the supervisor too.
- **P7. A time limit for each part** (proposed by the assistant). The default is 10 minutes. An
  entry of the table can give its own limit. At the limit, the worker prints the stacks of all
  tasks. Then the supervisor records `timeout`, stops the worker, and starts a new worker for
  the next part. A worker that the memory cap stops gets the result `memory` in the same way.
- **P8. Two levels** (proposed by the assistant). Each entry is `:fast` unless the table marks it
  `:slow`. The keyword `level = :fast` runs only the fast parts. The default, `level = :all`,
  keeps the meaning of `test_platform()` as it is now. The tests on GitHub run all parts.
- **P9. The parts of what changed** (proposed by the assistant). `test_changed(; base =
  "main")` reads the changed files from `git diff --name-only`. A part belongs to the folder of
  the file that defines it (`functionloc`). A change in `source/<layer>/<slice>` selects the
  parts in `test/<layer>/<slice>` and the parts of every slice above it, from
  `PLATFORM_SLICE_EDGES`. A change in the kernel selects all parts. A changed test file
  selects its own parts. In omnet-julia, a change in a package selects the parts of its test
  package and of the test packages above it.
- **P10. No extra run of main** (proposed by the assistant). Each known failure of main gets the
  marker of the convention that exists. Then an unmarked `Fail` or `Error` on a branch is a
  regression, and no run of main is needed to see it. The supervisor also keeps the record of
  each run of a commit of main in `~/.cache/projectured-test-records/<repository>/<commit>.tsv`.
  `compare_records(a, b)` prints the parts whose counts changed. Rejected: a folder in
  `/var/tmp`, because the end of a task removes the folders that it made there.
- **P11. A worker that stays open** (proposed by the assistant). `tool/run-tests.jl --stay
  <folder>` keeps one worker open. The worker loads `Revise` when the environment has it. For
  each request file in `<folder>/requests`, it calls `revise()`, runs the parts, writes the
  record and the log into `<folder>/results`, and writes a `.done` file. `tool/run-tests.jl
  --send <folder> <suite> only=<filter>` writes a request and waits for its `.done` file under
  a bound. When `revise()` reports an error, for example after a change of a struct, the
  worker stops and the supervisor starts a new one. A person in the REPL needs none of this:
  after steps 1 and 3, `test_platform(only = "widget")` runs again in the same REPL with no new
  load.

## 5. Steps

Do the work in the worktrees `projectured-julia-tests-run-fast` and `omnet-julia-tests-run-fast`,
on the branch `tests-run-fast`. Make one commit for each step. Run every Julia process with
`bounded-run`.

- [ ] 1. **A suite is a table of parts (P1, P2, I1).** Add the runner `run_parts` to
  `ProjecturedKernelTest`. Change each suite of projectured-julia to a table: `test_kernel`,
  `test_platform`, each domain, backend, and adapter suite, and `test_all`. In omnet-julia,
  change each suite, and change `test/runtests.jl` to one call of the runner with the table of
  the suites. **Done when:** each suite gives the same counts of pass, fail, error, and broken
  as on its base commit, and `test_platform()` passes under a 6 GB cap.
- [ ] 2. **The record of each part (P3, I4).** The runner writes the record when the keyword
  `record = <path>` is given. It prints the 10 slowest parts at the end. Add a section on the
  record to the testing guide. Replace the measurement by hand there. **Done when:** a run of
  `test_platform(record = …)` writes one line for each of its parts, and the counts of the file
  agree with the testset.
- [ ] 3. **A filter by name (P4, I2).** Add `only` and `skip` to the runner, so every suite
  takes them. Add them to each walk over the examples: `test_printers`, `test_readers`,
  `test_repls`, `test_position_navigations`, `test_typeins`, `test_click_roundtrips`,
  `test_catalog`, and the walks of the domains and of omnet-julia. **Done when:**
  `test_platform(only = "widget")` runs only the parts whose name has `widget`, and
  `test_printers(only = "json/")` walks only the JSON examples.
- [ ] 4. **Workers and a time limit (P6, P7, I8).** Write `tool/run-tests.jl` and
  `run_test_worker()`. The supervisor runs the parts in one worker, in the order of the table.
  It gives the summary of all parts at the end. **Done when:** a test part that sleeps longer
  than its limit gets `timeout` with the stacks in the log, and the parts after it run.
- [ ] 5. **Parallel workers (P5, I3).** The supervisor starts `workers = N` workers. N is at
  most the number of CPUs that the supervisor can use, divided by two. The supervisor first
  loads the packages in one worker, so that only one process precompiles. Then it starts the
  others. Each worker gets `--heap-size-hint` from the keyword `memory`. An entry of the table
  can be `alone`, for example the omnet engine tests that need `-t 4`. The supervisor runs
  such a part when no other part runs. **Done when:** a run of `test_platform` with three
  workers gives the same counts as the run of step 1.
- [ ] 6. **Split the slow parts (I1).** Use the record of step 2. Split each part that takes
  more than 60 s at the boundaries of its top-level testsets, into functions in the table. A
  walk over the examples gets one entry for each domain, which calls the walk with the filter
  of step 3. **Done when:** no part of the record takes more than 60 s, except the parts that
  have no testset boundary. The plan names those parts.
- [ ] 7. **Two levels (P8, I9).** Mark the slow parts in the tables, from the record. The
  walks over all examples, the click walk, and the omnet presentation tests are slow. **Done
  when:** `test_platform(level = :fast)` runs only the fast parts, and the testing guide and
  the two `CLAUDE.md` files say which level to run after a change and before a land.
- [ ] 8. **The parts of what changed (P9, I6).** Add `test_changed` to both repositories, and
  `--changed` to the supervisor. **Done when:** a change in one file of
  `source/platform/widget` selects the parts of the widget slice and of the slices above it,
  and a change in the kernel selects all parts.
- [ ] 9. **No extra run of main (P10, I7).** Mark the 15 known failures of `test_platform` and
  the known failures of omnet-julia, each with its reason. Add the store of the records of
  main and `compare_records`. **Done when:** a run of main has no unmarked failure, and a
  branch run is compared with the stored record of its base commit.
- [ ] 10. **A worker that stays open (P11, I5).** Add `--stay` and `--send` to the supervisor.
  **Done when:** a test file that changes after the start of the worker runs in its new form,
  with no new load, and a change of a struct starts a new worker.

## 6. Rule of runs and measurements

- Every Julia process of this plan runs with `bounded-run`.
- No part reaches a model. The suites of Ollama, Anthropic, and OpenRouter stay out of every
  table that runs by default. A run over many suites runs in `bwrap --unshare-net`.
- A time from the record is not a measurement for a report. A time to report needs the word of
  the owner and the A B A order in the lane `taskset -c 28,30,31`. The compile time, the count
  of collections, and the allocated bytes do not depend on the load of the machine.

## 7. Not in this plan

- Threads in one process (section 3). If the record of step 2 shows that the compile while the
  tests run is a large part of the time, a new plan can look at threads again.
- The fixed waits in the tests: 159 calls of `sleep` in projectured-julia and 93 in omnet-julia.
- The causes of the omnet hang and of the memory cap of `test_ide`. This plan only limits their
  cost.
- A faster precompile in a new worktree.
