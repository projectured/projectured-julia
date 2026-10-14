# Measure a stop for a computed cell

Decision 10 says that propagation follows the writes: a computed cell that
computes the value that it had still makes every reader below it compute again.
A write already has a stop: a write of plain data that is `===` to the value of
a cell with no computation invalidates nothing. This plan measures the same stop
at the end of a computation, so that the owner can decide whether the engine
does it always, does it for the cells that ask for it, or does not do it.

The plan changes nothing on `main`. The engine of the experiment lives on the
branch `cell-stop-experiment`, and the branch does not land.

## The engine of the experiment

`ReactiveCell.jl` gets a run-time switch, `:none` or `:always`. With `:none`
the engine does what it does now. With `:always`:

1. **A write** marks the direct readers of the written cell invalid, and every
   cell below them "maybe invalid", a fifth state.
2. **A read of a "maybe invalid" cell** first brings its dependencies up to
   date, in the order that the last run read them. If a dependency computes a
   new value, the cell computes. If none does, the cell becomes valid with no
   computation.
3. **A computed cell that computes** compares the new value with the old one by
   the test of a write: plain data (`isbits`, `String`, `Symbol`) that is
   `===`. If the value is new, or is not plain data, or the computation failed,
   the cell marks its direct readers invalid.
4. `set_cell_computation!`, `invalidate_cell!` and a write to a computed cell
   still make the direct readers invalid.
5. `dependencies` keeps the order of the first read: a `Vector`, with a `Set`
   beside it when the vector passes 16 entries. The order keeps a check from
   computing a dependency that the new run does not read, such as `a` in
   `flag[] ? a[] : b[]` after `flag` changes.
6. An exception in a dependency during a check makes the reader compute, so the
   computation of the reader can catch it, as it can now.
7. Two new counters: `:checks`, a "maybe invalid" cell brought up to date, and
   `:stops`, a computation that gave the value that it had.

`is_cell_valid` answers `false` for a "maybe invalid" cell. The SDL backend and
`ListNode` ask it, so the paint and the lazy lists see the new state.

## The scenarios

Each scenario runs on a headless window, with the walk of the paint, and counts
each step after the first.

- **S1. Typing in a text.** 100 keys in a text file in a tab.
- **S2. Typing in a structure.** 100 keys in a string value of a JSON document.
- **S3. Caret moves.** 100 arrow keys in the same JSON document.
- **S4. The roster.** A key in X1, a save in X1 that the filter sees, the edits
  of one file of 200 that change, and a change of one call in X4.
- **S5. A change of everything.** The width of the window changes, so every
  line breaks again. The stop saves little here, and the checks cost the most.
- **S6. A scroll.** 100 steps of the wheel in a long document.

## Steps

- [x] **1. The engine of the experiment.** The changes above, on the branch,
  with tests of the cell layer for the new rules: a check does not compute a
  dependency behind a condition; an exception in a check reaches the
  computation of the reader; a cycle still throws `CellCycleException`; a write
  of a computed cell still reaches the readers. Check: with `:none`, the counts
  of S1 to S6 are the counts of `main`.
  - Done 2026-10-14. The branch is based on `roster-table-cost`, so that it
    measures the code that the owner asked for. The check compares with the
    counter environment of that branch, which has the engine of `main`.
  - A failed cell stays failed in a write with the stop, so that its next value
    counts as new: a reader that caught its exception must compute again even
    when the value is the one from before the failure.
  - `test_cell_stop` (21 tests) passes. `test_cell`, `test_untracked_cell`,
    `test_cell_fault_scope` and `test_cell_example` pass in both modes.
  - With `:none`, every scenario computes as many cells as with the engine of
    `main`. The median of the marks of S4d differs by 2 (480.5 against 478.5);
    a reader that the collector has not freed yet counts as a mark.
  - S5 and S6 first measured nothing. With a window, the output of the editor
    is a screen, and the walk must read the content of each window. A table in
    a tab does not scroll, because a tab gives its content a free height, so
    S6 is a table of 300 rows in a `WidgetScrollPane` of a fixed size.
- [x] **2. The counts.** S1 to S6, `:none` and `:always`, for each step: the
  computations, the checks, the stops, the reads and the marks. And for
  `:always`, the places of the code where the stops occur, which say what a
  stop for the cells that ask for it would give.
  - Done 2026-10-14. The medians for each step, `:none` / `:always`:

    | | computes | checks | stops | reads |
    |---|---|---|---|---|
    | S1 a key in a text file | 16 / 16 | 0 / 4 | 0 / 5 | 1833 / 1833 |
    | S2 a key in a JSON string | 81 / 33 | 0 / 52 | 0 / 23 | 19447 / 19327 |
    | S3 a caret move in JSON | 4 / 4 | 0 / 3 | 0 / 0 | 26387 / 26387 |
    | S4a X1, a key in a file | 24 / 18 | 0 / 12 | 0 / 6 | 3923 / 3910 |
    | S4b X1, a save that the filter sees | 2208 / 2212 | 0 / 23 | 0 / 4 | 52830 / 53057 |
    | S4c 200 rows, the edits of a file change | 2282 / 8 | 0 / 2277 | 0 / 3 | 95072 / 15974 |
    | S4d X4, a change of one call | 744.5 / 749.5 | 0 / 18.5 | 0 / 3 | 33149 / 33360 |
    | S5 the width of the window changes | 116 / 59 | 0 / 85 | 0 / 17 | 2334 / 2096 |
    | S6 a scroll of a table of 300 rows | 13 / 8 | 0 / 8 | 0 / 4 | 40839 / 40831 |

  - A write marks as many cells with the stop as without it: S4c marks 2281
    cells invalid without the stop, and 8 invalid and 2280 maybe invalid with
    it. The stop moves the work from the computations to the checks.
  - The stops occur in the leaf fields of the graphics: the text, `x` and `y`
    of each drawn text run (`TextToGraphics.jl:1162` to `1164`), the place and
    size of the caret (`:489` to `:491`), the width and the height of a canvas
    of a widget (`_reactive_canvas_cell`), and the places of the grid
    (`LayoutToGraphics.jl:1248`, `:1399`). A new list of rows (S4b) and a
    group (S4d) have no stop: their values are not plain data.
- [x] **3. The paint.** The area that the SDL backend paints again for each step
  of S1, S4 and S5, in both modes, with the headless probe of the dirty parts.
  - Done 2026-10-14. The area in pixels that `_compute_dirty_region` gives
    for each step, `:none` / `:always`, over the whole drawn canvas:

    | | painted area |
    |---|---|
    | S1 a key in a text file | 11712 / 11712 |
    | S4a X1, a key in a file | 293792 / 293792 |
    | S4b X1, a save that the filter sees | 1233632 / 1233632 |
    | S4c 200 rows, the edits of a file change | 2792000 / 720 |
    | S4d X4, a change of one call | 335824 / 335824 |
    | S5 the width of the window changes | 1032336 / 1032336 |

  - A "maybe invalid" cell that a check finds valid is not painted again. A
    check of 20 files drew the right value at each step in both modes:
    without the stop the backend painted the tab strip and the whole pane of
    the roster again, and with it only the cell of the value, 33 by 20 pixels.
  - The probe must be as large as the drawn canvas: a probe of 1600 pixels cut
    the pane of the roster off, and measured nothing there.
- [x] **4. The behaviour.** Every suite in a process of its own, in both modes.
  A failure that only one mode has is listed with its cause.
  - Done 2026-10-14, in the counter environment of the branch. 23 suites:
    kernel, platform, the 20 suites of the domains and adapters, and the
    integration suite of `ProjecturedTest`. The suites of the Anthropic, Ollama
    and ACP adapters did not run: they talk to services outside.
  - Every suite but the integration suite has the same counts and the same
    places of failure in both modes. The platform suite has 152598 passes, 2
    failures and 7 broken in both; the Julia suite fails at the same place in
    both.
  - The integration suite of `:none` reached the limit of 90 minutes with no
    summary; the one of `:always` ended after 86 minutes. The machine was not
    idle, so this says nothing about speed. `test_evaluator_duplicate` and
    `test_application`, which hold the failures that only the run of
    `:always` reached, fail at the same seven places in both modes.
  - Every failure of both modes is on the list of the run of `main` of
    2026-10-13: `NavigationTest.jl:180`, `TypeinTest.jl:639`,
    `CatalogCoverageTest.jl:223`, `ConversationParsingTest.jl:48`,
    `ApplicationTest.jl:1066`, `:1077`, `:1114` and `:1462`, and
    `EvaluatorDuplicateTest.jl:36`, `:40` and `:48`.
  - So no test of the repository depends on a computation that runs again
    with the same inputs.
- [x] **5. Memory and time.** The bytes of the live cells after an example is
  built, on `main` and on the branch. The median time of a step of S1 to S6 in
  both modes, with the counters compiled out, on an idle machine. The time
  waits for the word of the owner.
  - Memory, done 2026-10-14: the live bytes after a second build of an editor
    and its steps, with a first build to compile:

    | | `main` | `:none` | `:always` |
    |---|---|---|---|
    | 200 files and a roster, 10 steps | 16.7 MB | 17.2 MB | 17.2 MB |
    | the JSON example, 20 keys | 1.7 MB | 1.8 MB | 1.8 MB |

    The branch costs 3 to 6 percent more, the same in both modes. The field
    `dependency_index` adds 8 bytes to each cell; a final form can keep the
    set out of the struct. A first measure without the warm-up showed 20
    percent: a redefinition of `_note_cell_stop` in the script made Julia
    compile the engine again, and compiled code lives on the heap.
  - Time, done 2026-10-14 on an idle machine, with the word of the owner. The
    plain environment, with no counters, on the cores 28, 30 and 31. A step
    is the event, `run_frame!`, `_compute_dirty_region` and a read of every
    field of every graphic. The first 10 steps compile and are not kept.
    Medians in milliseconds; `main` is the engine of `roster-table-cost`;
    each mode ran three rounds, `main` two clean rounds:

    | | `main` | `:none` | `:always` |
    |---|---|---|---|
    | S1 a key in a text file | 0.39 | 0.39 | 0.41 |
    | S2 a key in a JSON string | 2.02 | 2.16 | 2.09 |
    | S3 a caret move in JSON | 3.7 | 4.0 | 4.2 |
    | S4a X1, a key in a file | 1.74 | 1.75 | 1.75 |
    | S4b X1, a save that the filter sees | 30.2 | 22.3 | 22.7 |
    | S4c 200 rows, the edits of a file change | 44.8 | 41.1 | 14.6 |
    | S4d X4, a change of one call | 12.3 | 10.0 | 9.9 |
    | S5 the width of the window changes | 1.77 | 1.71 | 1.63 |
    | S6 a scroll of a table of 300 rows | 12.9 | 13.1 | 12.8 |

  - The order of the dependencies alone (`:none` against `main`) makes the
    steps over lists faster, S4b by a quarter and S4d by a fifth: a second
    read of a cell in one run no longer scans the readers of the cell and no
    longer hashes into a set. It makes S2 7 percent slower; the scan of up to
    16 dependencies at each new read is the likely cause, and its limit is a
    number to tune. S3 varies by 20 percent from round to round, and its mean
    is twice its median.
  - The stop (`:always` against `:none`) costs 0.02 ms in S1 and saves 26.5 ms
    in S4c, a third of the time. It changes no other median by more than the
    rounds differ.
  - The second round of `main` was disturbed: S1, S4a and S5 were 20 to 30
    percent slower than in its other rounds, so it is not in the table.
- [x] **6. The report.** The data of steps 2 to 5, and a recommendation: always,
  for the cells that ask, or not.
  - Done 2026-10-14. The recommendation is the stop for every computed cell,
    by the rule that a write follows: plain data that is `===` to the value
    that the cell had. The owner agreed with it on 2026-10-14.
  - Why always: the stop changed no result of any suite; it costs at most
    0.02 ms in a step that the measure found; it saves most where a value of
    the screen changes and its size and place stay, which is the case that a
    view across the session meets at each key; and with it the backend paints
    only the cell that changed. An opt-in would need each place to ask, and
    the stops occur in the leaf fields of the graphics, which every view uses.
  - What the final form keeps from the experiment: the fifth state, the check
    in the order of the first read, a failed cell that stays failed, and the
    exception of a dependency that reaches the reader. What it changes: no
    switch, no `_note_cell_stop`, the set of a long list of dependencies out
    of the struct, and a limit of the scan that a measure of S2 sets.
  - The final form changes the sealed `ReactiveCell.jl` on `main`, decision
    10 of `architecture-decisions.md`, and `cell.md`, and the cell layer goes
    through the audit of its seal again. That is a plan of its own.
