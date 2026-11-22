# The tests start from a compiled image

> **Status (2026-11-22): steps 1 to 4 done; step 5 not started; the land waits for the owner.** The plan is step 4 of agents-work-fast (A6, approved
> with that plan on 2026-11-20): first the measure, then the questions of the design to the
> owner, then the workers start from the image. Before: written, not approved for implementation. The owner asked for this
> plan on 2026-11-20, with the measurement of step 1 as its first step ("yes"). The split of
> the slow parts, step 6 of [the-tests-run-fast.md](../done/the-tests-run-fast.md), moved here as
> step 5. The design of the image (step 3) starts with the questions to the owner, because an
> image of the tests is a new use of compiling ahead.

## 1. The purpose

The record of a whole run of the tests (plan `the-tests-run-fast`, 2026-11-20, two workers)
shows that the compile takes most of the time: 141 min of the 166 min of the parts that ended,
85 %. The owner, 2026-11-20: "We already have the reactive Julia compiler server written by
another agent, can't we use that? And if compilation speeds up then perhaps parallel execution
becomes important again".

The goal: a worker of the tests starts from an image that holds the compiled code of the
tests, so a part compiles only what the image can not hold. When the compile is small, more
workers and the split of the slow parts shorten the run.

## 2. What exists

- **The compile of the parts.** The record of the whole run gives the time and the compile of
  each part. Some sums by suite:

  | Suite | Parts | Time | Compile |
  |---|---|---|---|
  | integration | 68 | 4989 s | 83 % |
  | ProjecturedPlatform | 254 | 1941 s | 91 % |
  | ProjecturedKernel | 84 | 468 s | 83 % |
  | ProjecturedJSON | 23 | 128 s | 93 % |

  `test_export_collisions` took 1497 s, all of it compile. `test_printers` took 73 s, 64 s of it
  compile. A worker already keeps the code that an earlier part of the same worker compiled.
- **Some compile stays with any image.** Some tests evaluate code or make new modules while they
  run, for example the fixtures of the runner itself (`include_string` into a new `Module`). An
  image can not hold that code. Its share is not known.
- **The package images.** A precompile in a new worktree takes about 12 min. A change of the
  platform rebuilds 99 package images (279 s), and a change of the kernel 112. No test package
  records its calls: the test packages have no `precompile/` folder. An image records the
  absolute paths of its sources, so each new worktree builds again.
- **The reactive compiler.** It is the branch `reactive-compiler` of the Julia fork, and it is in
  the merged fork `julia-merged-next` (the juliaup channel `merged`). A first build of an image
  (a founding) of the projectured editor took 27.5 min and 25.9 GB; that of the omnet IDE took
  39.5 to 41.8 min and up to 28.7 GB. That is above the memory budget of `bounded-run`; the
  owner allowed it once with `systemd-run` and a cap of 32 GB. After an edit, a rebuild adds an
  overlay to the image in 9 to 12 s. A server with more than one thread is not safe, but a
  worker that starts from the image needs no server.
- **The compile-ahead design.** [compile-ahead.md](../../documentation/design/compile-ahead.md)
  holds the requirements of the owner (U1 to U14) for each way to compile ahead. A package
  chooses with the preference `precompile_calls` (`"none"`, `"recorded"` or `"live"`), and the
  build of a binary chooses how the binary is made (U13). It names no image of the tests.
- **The Julia of the tests.** A worktree runs the release 1.13.1. Only the main checkouts run the
  merged fork.

## 3. Steps

Do the work in a worktree of its own, on a branch of its own. Run every Julia process with
`bounded-run`, on the cores 24 to 27. Make one commit for each step.

- [x] 1. **What an image can save.** Run each of three samples two times in one worker, with a
  record for each run: `test_kernel`, `test_json`, and `test_printers`. The compile of the second
  run is the share that an image can not remove. **Done when:** this plan gives, for each sample,
  the compile of the first and of the second run, and the share that an image can save.
- [x] 2. **One image of one sample.** Record the calls that the sample with the largest share
  compiles (`--trace-compile`). Build an image of the test packages of that sample from the
  record. Run the sample from the image. **Done when:** this plan gives the compile, the start
  time and the peak memory of a worker from the image, and the time and the memory of the build
  of the image, beside the same numbers without the image.
- [x] 3. **The design, with the answers of the owner.** Give the owner the facts of steps 1
  and 2, and ask the questions that decide how the tests get their image, one at a time, the
  goals first. **Done when:** the owner answered each question, and the answers are in this
  plan and in `compile-ahead.md`. If the owner stops the plan here, it moves to `plan/done`
  with the result of the measurement.
- [x] 4. **The workers start from the image.** Build the image as step 3 decides it, and let
  `tool/run-tests.jl` start each worker from it. **Done when:** a run of all parts from the image
  gives the same counts as a run without it, and the compile of the record is no larger than
  step 1 says.
- [ ] 5. **More workers, and the split of the slow parts.** The supervisor chooses the count of
  workers from the memory of a worker from the image. Split each part that takes more than 60 s
  at the boundaries of its top-level testsets, into functions in the table. A walk over the
  examples gets one entry for each domain, which calls the walk with the filter `only`. **Done
  when:** no part of the record takes more than 60 s, except the parts that have no testset
  boundary, which this plan names, and the plan gives the time of a run of all parts.

### What the work found

- **Step 1 (2026-11-21, Julia 1.13.1, a worktree of `julia-worktree`, the cores 28, 30 and 31,
  one process for each sample, each sample two times).**

  | Sample | First run | Its compile | Second run | Its compile | An image can save |
  |---|---|---|---|---|---|
  | `test_kernel`, 84 parts | 367.4 s | 247.3 s | 143.7 s | 13.6 s | 234 s, 64 % |
  | `test_json`, 23 parts | 124.1 s | 116.6 s | 6.2 s | 0.0 s | 117 s, 94 % |
  | `test_printers`, 1 part | 202.4 s | 195.8 s | 3.0 s | 0.0 s | 196 s, 97 % |

  Of the second run of `test_kernel`, 104 s is `test_supervised_runs`, whose workers are
  processes of their own. So the code of the tests compiles again in each new process, and the
  package images hold almost none of it. `test_meaning_search` fails 6 checks in a second run
  in the same process: the stores of its toy models stay from the first run.

- **Step 2 (2026-11-21, the same lane).** A trace of one run of `test_json` holds 5,411 calls.
  A throwaway package that depends on `ProjecturedJSONTest` compiles each call of the trace at
  its precompile, so its package image holds the code (the form of Decision 2 of
  `compile-ahead.md`: recorded calls in a package image). All 5,411 calls compiled. Each run is
  a new process, in the order without, with, without:

  | | Without the image | With the image |
  |---|---|---|
  | Time of the 23 parts | 118.3 s, 118.0 s | 7.4 s |
  | Compile in the parts | 111.1 s, 110.8 s | 0.5 s |
  | Load before the parts | 4.8 s | 5.1 s |
  | Peak of the job | 1.2 GB | 0.87 GB |

  The build of the image took 162 s with a peak of 3.0 GB, and the image is 84 MB. So a run of
  the sample takes 13 s in place of 124 s.

- **A slow part, for question 2 (2026-11-21).** The same throwaway image for `test_printers`,
  the walk of the printer over every example and a slow part: 6,043 calls (12 did not
  compile), a build of 279 s with a peak of 5.0 GB, and an image of 147 MB. A walk repeats the
  same code over many examples, so a slow part makes the list not much longer than a package
  of fast parts. The CI run on `main` a63b22235 is green.

- **Step 4, the recording and the build (2026-11-21).** `tool/record-test-calls.jl --jobs 3`
  recorded the 40 test packages in 2 h 46 min on 10 cores, peak 27.6 GB: 102 MB of lists, of
  which `ProjecturedTest` holds 73,674 calls (94 min to record) and `ProjecturedPlatformTest`
  46,616 (31 min). Most lists are small: 37 packages have fewer than 5,000 calls.
  - The image of `ProjecturedPlatformTest` with its list is 988 MB, against 89 MB without; it
    took about 20 minutes to build (the three recordings that waited for it took 1,343-1,447 s,
    where the others took 36-145 s).
  - The image of `ProjecturedTest` with its list did not build: its compile ran 37 minutes
    alone and the kernel ended it at the cap of 24 GB (one OOM kill). `Pkg.precompile` gave no
    error for it.
  - The image of `ProjecturedJSONTest` (3,542 calls after its dependencies recorded) builds in
    about 2 minutes and makes its parts take 7.6 s in place of 118 s.

### The answers of the owner (step 3)

- **Q1. Where the compiled code of the tests lives.** The owner, 2026-11-21: "Agreed" to the
  recommendation: each test package keeps the recorded calls of its own parts in its own
  `precompile/workload.txt`, the mechanism of `compile-ahead.md`, in place of one system image
  of all test packages (about 30 minutes and 26 GB to build). Written as Decision 11 of
  `compile-ahead.md`, with its consequence: a call of a lower package stays in the list of the
  test package, so Decision 8 does not apply to the tests.
- **Q2. Which parts a test package records.** The owner, 2026-11-21: "Yes" to the
  recommendation: all of its parts, fast and slow. The build of the largest list, that of
  `ProjecturedTest` with the 68 integration parts, is measured in the first step of the work;
  if it takes too long, the owner can limit it to the fast parts.
- **Q3. When a test package records again.** The owner, 2026-11-21: "Yes" to the
  recommendation: as U5 says (by hand, and before each release), and after each land, a job in
  the background records again each test package whose files the land changed.

- **Q4. The two large lists.** The owner, 2026-11-21: "Agreed" to the recommendation:
  `ProjecturedPlatformTest` and `ProjecturedTest` record only their fast parts. If the image of
  one of them still takes more than about 5 minutes or 8 GB to build, that package gets no list,
  and its parts compile while they run, as before.
- **Q4, the result.** The fast parts of `ProjecturedPlatformTest` record 42,064 calls, only
  10 % fewer than all of its parts (46,616), and its image with them did not build in a cap of
  20 GB (two OOM kills). So it has no list. The list of all parts of `ProjecturedTest` is gone
  too, because its image does not build; the list of its fast parts is recorded again next.
  The lists of the other test packages were recorded while the image of
  `ProjecturedPlatformTest` held its list, so they lack the calls that it held; they record
  again after `ProjecturedTest`.
- **Q4, the umbrella.** The new recording of the 39 test packages took 57 min, peak 11.1 GB,
  68 MB of lists; the fast parts of `ProjecturedTest` record 24,650 calls. The build of all test
  images then took 9 min 46 s, peak 16.8 GB. The image of `ProjecturedTest` alone did not build
  in a cap of 10 GB (one OOM kill after 5 min 39 s), so it has no list either.
- **Step 4, the run of all parts from the images (2026-11-22).** 38 test packages with their
  lists, `ProjecturedPlatformTest` and `ProjecturedTest` with none, 10 cores, `--workers auto`:
  39 min 16 s, where the land run of `main` before took 1 h 05 min. The time of the parts went
  from 12,396 s to 8,809 s, and their compile from 10,659 s to 6,814 s. The domain test
  packages gain most (the parts of `test_json` 259 s to 10 s, of the kernel 417 s to 133 s);
  the integration suite and the platform suite keep their compile, because they have no list.
  The counts of each part are those of `main`, except two parts that ended with `memory`: a
  worker of `ProjecturedTest` loads each test package, and their larger images add about 2.2 GB
  to it (the peak of `test_printers` went from 2.86 GB to 5.05 GB), so `test_application` and
  `test_window_frame_guards`, which peaked at 5.3 GB, passed the largest memory of a worker,
  6 GB. The default of `--memory` is now 8 GB.
- **Step 4, done.** The counts of each part are those of `main`, with the default of 8 GB the
  two parts pass too. The compile of the samples of step 1 is no larger than the second runs of
  step 1 gave: `test_kernel` 10 s (13.6 s), `test_json` 2 s (0 s). `test_printers` keeps its
  compile, because `ProjecturedTest` has no list by the rule of Q4.
- **Step 4, omnet-julia against the branch (2026-11-22).** The omnet manifest, which is not in
  git, needs a resolve: `ProjecturedKernelTest` depends on `ProjecturedPrecompile` now. After
  it, the 265 fast parts of omnet-julia gave 1 fail, `test_express_greying`; it failed six times
  of six also against projectured `main`, so it is a fault of `main`: a check 0.2 s after the
  start of a run came before the session worked on a quiet machine. The test now waits for
  the working run, with a bound of 30 s, and passes three times of three.
- **The land checks (2026-11-22, the branch rebased on `main` 560543542).** All 765 parts:
  40 min 27 s, every part done, 0 error, 2 fails in `test_exports`, which come from `main`: the
  builder commits of another session give "BuilderModule.jl:51: the names are not in the order
  that Distribution.jl defines them", and the CI run on 560543542 failed in its static guards;
  that session fixes it. The fast parts of omnet-julia against the branch, with the fix of
  `test_express_greying`: 265 parts, 0 fail, 0 error, 47 min.
- **A note of the owner (2026-11-21):** "when the incremental reactive compiler is ready to be
  used, I think the compilation will speed up for testing as well." A rebuild of the reactive
  compiler adds an overlay to an image in 9 to 12 s, so it can make the image of a test package
  follow a change below it without the rebuild of the whole image.

- **The reactive compiler, first measure (2026-11-21, the owner: "Yes").** The replay gate of
  `julia-merged-next` (`contrib/reactive-compiler/tool/gate_replay.sh`), with `PACKAGE =
  ProjecturedPlatformTest` and its 46,616 recorded calls as the statements, on a branch with
  three edits of one body line of the platform after the founding commit. The founding of the
  image did not end: the kernel ended it at the cap of 28 GB after 38 min 44 s, with a peak of
  28.9 GB. So a founding with this list needs more than the budget of `bounded-run`.
- **The reactive compiler, second measure (the owner: "Agreed" to measure with
  `ProjecturedJSONTest`).** The founding commit is the one where `ProjecturedPlatformTest` has
  no list, and the statements are the 3,542 calls of `ProjecturedJSONTest`. The founding did not
  end either: the kernel ended it at the cap of 18 GB after 26 min, in the step "compiling
  incremental system image", which compiles the whole stack in one process with no package
  images. So each founding that holds the platform needs more than 18 GB, as the founding of
  the IDE needed about 28 GB. A third run with a cap of 32 GB waits for room in the budget.

## 4. Rule of runs and measurements

- Every Julia process of this plan runs with `bounded-run`. A build above its budget needs the
  word of the owner first.
- No part reaches a model. A run over many suites runs in `bwrap --unshare-net`.
- A time to report needs the A B A order in the lane `taskset -c 28,30,31`.

## 5. Not in this plan

- Threads in one process. Workers that start from one image share its code already.
- An image of the omnet-julia tests. It can follow the same design after this plan.
