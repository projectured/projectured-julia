# The first key in a name buffer is compiled ahead of time

## Why

A person opens a tab with `Ctrl+T`, presses Insert on the placeholder, and types
a name into the `DocumentInsertion` buffer. The first key waits a long time. The
keys after it do not wait.

Counted on 2026-09-22 in a `:recorded` session, with `--trace-compile`, on the
headless application window:

| key | method instances compiled |
| --- | ---: |
| `Ctrl+T` | 106 |
| Insert | 200 |
| `e`, the first key of "evaluator" | 338 |
| each of the other eight keys | 0 |
| Enter, which commits `EvaluatorToplevel` | 69 |

257 of the 338 are `insertable(::Type{T})`, one for each document type in each
loaded module. The first key calls `name_completion`, which calls
`get_insertion_candidates(Document)`. That function probes every concrete
subtype of `Document`, and `insertable` specializes on the type, so each probe
compiles its own method instance with the zero-argument constructor of the type
inside it.

The recording driver never presses Insert. Its examples do not hold a
placeholder with the cursor on it, so the trace never sees these compiles, and
the recorded list does not hold them.

## Design

- `warm_application()` gets the sequence that the person used: `Ctrl+T`, Insert,
  "evaluator" one key at a time, and Enter. The binary runs `warm_application()`
  in its `@compile_workload`, so the binary gets the sequence too.
- `warm_application()` answers the application document, or `nothing` when the
  warm-up failed. The test "the warm-up of a build" asserts that the tab with
  the focus holds an `EvaluatorToplevel`. The warm-up swallows each failure, so
  without this assertion a warm-up that stops short of the name buffer passes.
- The recording driver calls `warm_application()` after
  `precompile_workload()`. The sequence is then written once and used by the
  binary and by the recording.
- The list is recorded again, at `:none`, as `package-rules.md` says.
- The `:live` level does not change. `precompile_workload()` is shared with the
  leaves of the other repositories, and the request was about the recording.

## Steps

1. [x] The warm-up types into a name buffer, the test asserts it, and the driver
   runs the warm-up.
2. [x] Record the list again at `:none`. The driver drove 105 examples, and
   none refused. The list holds 11314 statements, against 11975 in the list it
   replaces. All 338 statements of the first key are in it; the old list held 2
   of them. Of the 9246 statements dropped, 7681 no longer resolve. Of the 1565
   that still resolve, about 1100 are `DocumentWalk` closures and
   `search_documents` methods. `precompile_atom_walks` compiled them, and
   commit `30ab2d63` deleted it after the last recording. So the new run did not
   lose coverage.
3. [x] Count the compiles again at `:recorded`, with the same headless script:

   | key | before | after |
   | --- | ---: | ---: |
   | `Ctrl+T` | 106 | 6 |
   | Insert | 200 | 5 |
   | `e`, the first key | 338 | 1 |
   | each of the other eight keys | 0 | 0 |
   | Enter | 69 | 1 |

   What remains is small `Base` methods. These are counts, not times: no timing
   measurement was taken.
4. [x] `documentation/package/repl/repl.md` says that the driver runs the
   warm-up.

## Decisions found during the work

- The application document is wrapped by the window. The test reaches the pane
  tree with `get_wrapped_document`, as the other cases in `ApplicationTest.jl`
  do.
- The recording was made in the worktree environment. A cache slot belongs to
  the environment, so the build at `:none` did not touch the `:recorded` image
  of the main checkout.

## Not in this change

- `get_insertion_candidates` runs `insertable(T)` before the cheap
  `_is_layout_variant(T)` in its filter. So each `MFoo` layout variant compiles
  its probe and is then dropped. The cheap checks first would halve the probes
  that a new, unrecorded type costs.
- In a `jp` session, the fixture types of the test packages
  (`ProjecturedKernelTest.ContractPair`, `ProjecturedTest.TestWindow`, …) are
  candidates of the name buffer, because `ProjecturedRepl` loads
  `ProjecturedTest`.
