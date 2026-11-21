# Agents work fast

> **Status (2026-11-20): approved, in progress.** The owner asked for this work on 2026-11-20
> and approved the plan the same day ("Good plan"), with the land of `tests-run-fast` together
> with `main-stays-green` in step 1. The owner also asked: "if something else is found along
> the way which can be done better than let me know. We really need to bring down the
> compilation, the testing time because writing code is now negligible to these two".
> 2026-11-21: step 1 lands in projectured-julia, with the work of steps 2 and 5 on the runner
> (A7, A8, A9 without the call of grow, A11). The run of all parts of the land branch took
> 1 h 31 min on 10 cores, with 1 fail (now marked) and no error. omnet-julia follows.

## 1. The purpose

The owner, 2026-11-20: "My goal is to really speed up the work of an other agents. The
compilation of their worktrees should be incremental and reactive, the tests should be fast,
parallel and focused. The memory reserve should be tight." And: "They have to test
unnecessarily, they wait for memory reserve too much, they compile far too long, the tests run
sequentially". The owner stopped the other agents. When this plan is done, each agent rebases
and continues with the new method.

## 2. Where the time goes

Measured on 2026-11-20 in the worktrees of the plan `main-stays-green`:

- **A new worktree compiles every package first.** A worktree has a private depot, because
  worktrees that share one depot overwrite the compiled files of each other. Its first load of
  the test packages took 703 s and 743 s. With a warm depot it took 18 s.
- **The tests compile again while they run.** In a run of all 765 parts with two workers, the
  parts took 10605 s, and 8623 s of it (81 %) was compile. The run took 1 h 44 min.
- **The memory budget is half of what is free.** `bounded-run` starts a job only when the caps
  of all running jobs and the new cap stay under half of the available memory plus what the
  running jobs use. With 42 GB available that is 21 GB of caps for all agents together: one or
  two runs of the tests at a time. The caps are larger than the use: a run with a cap of
  14 GB peaked at 12.2 GB, and jobs with caps of 10 to 12 GB peaked at 7 to 8 GB. A run of mine
  waited about two hours for room, twice in one evening.
- **A run gets 4 of 32 cores.** The rule of the machine puts each run of tests on the cores 24
  to 27, and one agent runs one job at a time.
- **Agents run `main` beside each branch.** `main` has unmarked failures, so an agent can not
  tell its own failures from those of `main` without a second run.

What exists, and is not on `main`:

- The plan `the-tests-run-fast` (approved, stopped by the owner): a suite is a table of parts;
  `tool/run-tests.jl` runs the parts in parallel worker processes, each with a time and a
  memory limit; `test_changed` runs the parts that a change reaches; a fast and a slow level;
  a record of each part. Its branch is `tests-run-fast` in both repositories.
- The plan `main-stays-green` (approved, in progress): each check of `main` passes or has a
  marker with its reason, and the rule that keeps it so. Its branch `main-stays-green` starts
  on a merge with `tests-run-fast`.
- The plan `the-tests-start-from-a-compiled-image` (written, not approved).
- The reactive compiler of the merged Julia: a founding image (about 27 minutes, 26 GB peak),
  then a rebuild of the changed code in 9 to 12 s. It serves the binaries now.

## 3. Decisions

Each decision is proposed by the assistant. The owner approved them with the plan on
2026-11-20.

- **A1. The runner and green main land first, together** (proposed by the assistant). The
  branches `tests-run-fast` and `main-stays-green` land in both repositories as one step: they
  give parallel workers, focused runs and a `main` with no unmarked failure. The two faults of
  the filter that the run of `main-stays-green` found are fixed on `main-stays-green`.
- **A2. A cap is the measured peak and a margin** (proposed by the assistant). The runner
  writes the peak of each part into its record. The memory limit of a worker comes from the
  record of the part (the peak plus 25 %, at least 2 GB), and the cap of a run is the sum of
  the limits of its workers and 1 GB for the supervisor.
- **A3. The budget is what is free, less a reserve** (proposed by the assistant). `bounded-run`
  starts a job when the caps of the running jobs and the new cap stay under the available
  memory plus what the running jobs use, less a reserve of 6 GB. A cap is a hard limit of the
  kernel for its job, so the sum of the caps can not grow past the budget. Rejected: no caps,
  because one job can then take the memory of all.
- **A4. Cores are a budget too** (proposed by the assistant). `bounded-run start` takes
  `--cores N` and gives the job N free cores of a pool (the cores 16 to 31 less the isolated
  ones), as it gives memory. The runner starts one worker for each two cores. Rejected: the
  fixed lane of 4 cores for all agents.
- **A5. A worktree compiles only what changed** (proposed by the assistant). A seed depot holds
  the compiled files of `main` for each Julia that the agents use, and a job that lands on
  `main` brings it up to date. A worktree gets its own depot as a copy of the seed by hard
  links, and its Julia runs in `bwrap` with the worktree bound at the path of the main
  checkout. So the compiled files of `main` stay valid for each package whose files did not
  change, and only the changed packages and the packages above them compile. The same binding
  lets omnet-julia run against a worktree of projectured-julia with no special environment.
  Step 3 measures this first; if it does not hold, the step stops and the owner decides.
- **A7. A worker loads only the package of its parts** (proposed by the assistant on 2026-11-20
  after the plan; the owner: "If we can bring down the memory consumption then we can run more
  workers and speed up the cycle"). Now each worker loads every test package of the run, so
  each holds the memory of all, and some checks fail beside packages that they do not need. The
  runner groups the parts by the package that defines them, and a worker loads that package
  only; when its parts are done, it ends, and a new worker takes the next package. The runner
  starts a worker when its memory, from the record of its package, fits in the memory of the
  run, so the count of workers follows the memory and the cores. Step 2 does it.
- **A8. The cycle runs in a session that stays open** (proposed by the assistant on 2026-11-20
  after the owner: "Ultimately the goal is to change the code, compile quickly what's changed,
  test what's necessary, repeat while utilizing the most resources dynamically without
  risking oom killing. It's ok to do more comprehensive testing when landing. The cycle must be
  way faster."). A package image holds a whole package, so a change in the kernel or the
  platform compiles every image above it again. A worker that stays open with Revise takes a
  changed function in seconds and compiles only what a test calls. So the cycle is a session of
  the runner (`--stay`): a request applies the changed files with Revise and runs the fast
  parts that the change reaches. A worker keeps one package (A7) and stays warm between
  requests; when another package needs its memory, the worker that waited the longest ends.
- **A9. The memory is used to the full, with no OOM of the run** (proposed by the assistant,
  2026-11-20). The runner reads the cap and the use of its own job, and starts a worker when
  its estimate fits. A worker has the highest OOM score of the job, so a worker that passes
  the cap is the one that the kernel ends, and its part runs again. `bounded-run grow NAME SIZE`
  raises the cap of a running job when the budget has room.
- **A10. The images compile in the background** (proposed by the assistant, 2026-11-20). After a
  request, the session compiles the images of the changed packages with the free cores, so a
  new worker loads fresh images and does not compile them first.
- **A11. The parts of a change come from a map of what each part runs** (proposed by the
  assistant, approved by the owner on 2026-11-20: "Agreed"). `test_changed` chooses by files
  and folders now: a changed file of a package reaches the tests of each package that depends
  on it, so a change in one widget file reaches most tests. A run of `main` with code coverage
  writes, for each part, the lines that it executes: a worker clears the coverage data of
  Julia before a part and writes it after the part (`jl_clear_coverage_data`,
  `jl_write_coverage_data`; checked in Julia 1.13.1 on 2026-11-20). The map belongs to its
  commit, as a record does. A branch takes the diff against its base: each part that executed
  a changed line runs, and each part of a changed test file. A change that runs at load and
  not in a part (a `struct`, a `const`, a macro, a signature, a new method) and a new file
  keep the rule of today, so nothing is missed. The map of `main` comes from a run of its own
  after each land, in the background, and merges a few runs, so a line that a part runs only
  at some times is in it.
- **A6. A worker of the tests starts from a compiled image** (proposed by the assistant). This
  is the plan `the-tests-start-from-a-compiled-image`, which moves into this plan as step 4:
  first the measure of what an image saves, then the questions of its design to the owner,
  then the workers start from the image. The reactive compiler is the first candidate, as the
  owner asked in that plan.

## 4. Steps

Do the work in the worktrees of `main-stays-green` and in the copy of `bounded-run`. Make one
commit for each step in a repository. Run each Julia process with `bounded-run`.

- [ ] 1. **The runner and green main land (A1).** Fix the two filter faults. Finish the check of
  `main-stays-green` in projectured-julia, and the list and the marks of omnet-julia. Land and
  push `tests-run-fast` and `main-stays-green` in both repositories. **Done when:** both are on
  `main` and pushed, and a run of all parts on `main` has no unmarked `Fail` or `Error`.
- [ ] 2. **Tight memory and more cores (A2, A3, A4, A7).** Change `bounded-run` and the runner.
  Run `bounded-run selftest`. **Done when:** a run of all parts of projectured-julia with the
  caps of its record and 8 workers on 16 cores is green, and its time and its peak are in this
  plan.
- [ ] 3. **A worktree compiles only what changed (A5).** Measure first: a new worktree with a
  change in one domain, its first load with the seed and the binding, against a new private
  depot. Then the seed, its update after a land, and a helper that makes a worktree with its
  depot and the command that runs Julia in it. **Done when:** the first load of a new worktree
  with a change in one domain takes less than 2 minutes.
- [ ] 4. **The tests start from a compiled image (A6).** The steps of the plan
  `the-tests-start-from-a-compiled-image`. **Done when:** the compile is less than 30 % of the
  time of the parts in a run of all parts, or the owner decides on another goal at its
  questions.
- [ ] 5. **The cycle (A8, A9, A10, A11).** The session keeps a worker for each package, the
  runner starts workers by the memory of its job, `bounded-run grow`, the compile in the
  background, and the map of what each part runs. Measure the cycle: an edit in one slice of the platform, then the result of the
  fast parts that it reaches, in a worktree of step 3. **Done when:** that cycle takes less than
  a tenth of a run of the platform suite from a new worktree today, and its number is in this
  plan.
- [ ] 6. **The rule of the agents.** Write into both `CLAUDE.md` files and the testing guide:
  make a worktree with the helper of step 3; after a change, run `test_changed(level = :fast)`;
  before a land, run all parts with the caps of the record; give a job the cores and the
  memory that its record names. Tell the owner the line that each agent needs to rebase and
  continue. **Done when:** the texts say it, and the owner has the line.

## 5. What the work found

- **Step 2, the budget (2026-11-20).** `bounded-run` now starts a job when the available
  memory holds what the running jobs can still take up to their caps, the new cap and a reserve
  of 6 GiB, and `--cores N` holds N cores of a pool (default 8-12,14-27) and pins the job to
  them. Its selftest passes, 19 of 19. Right after the change, three jobs of 14, 11 and 10 GB of
  cap ran at the same time, where the old budget allowed one; an omnet-julia run that had waited
  started at once.
- **Step 2, a worker loads only the package of its parts (A7).** The list of a part gives the
  package that defines its function and its name, and the worker command `call` runs it with
  that package only. A part whose function is a closure runs by its place in the suite, as
  before. The tests of the runner pass, 70 of 70, with two new testsets.
- **Step 3, the measure (2026-11-20, `using ProjecturedJSONTest`, Julia 1.13.1).** A seed depot
  compiled at the path of the main checkout: 318 s, peak 6.5 GB. A new worktree of the same
  commit, mounted at that path in `bwrap`, with a hard-link copy of the seed: 5.2 s, peak
  0.5 GB. The same with a change in one file of the JSON domain: 92.8 s, peak 1.1 GB. So a new
  checkout keeps the compiled files valid, and only the changed package and the packages above
  it compile.
- **Step 3, the path.** A worktree mounted over the main checkout hides the `.git` folder of
  main, which the `.git` file of a worktree names, so `git` in the sandbox fails. So the helper
  mounts both the seed build and each worktree at one neutral path of each repository, and the
  main checkout stays where it is.
- **Step 3, the helper (2026-11-21).** `workspace/bin/julia-worktree`: `seed` compiles the
  environments of the main checkouts at the neutral paths of `~/.cache/julia-work` into
  `~/.cache/julia-seed/<julia>` (the first seed: 542 s for projectured-julia and 657 s for
  omnet-julia, 2.4 GB, peak 13.2 GB with 3 tasks); `new` and `depot` make a worktree and its
  depot as a hard-link copy of the seed; `run WORKTREE [--with WORKTREE]... -- COMMAND` runs
  the command in `bwrap` with each repository at its neutral path, so `git` and the relative
  paths of the environments work there.
- **Step 2, the lister.** The first worker of a run took 11 GB to load the 27 test packages of
  omnet-julia, and stopped at its cap. The lister now takes a new worker for each package of
  the command line.
- **Step 5, the session (A8) and the map (A11) are in the runner.** A session keeps a warm
  worker for each package; the worker that waited the longest ends when a new worker needs
  memory or a place. `--coverage FOLDER` writes the lines of each part and `FOLDER/map.tsv`;
  `--changed BASE --coverage-map PATH` runs each part that executed a changed line, by the
  name of the function for a changed signature or a new method, and the rule of the folders
  for what runs at load and for a new file. The tests of the runner pass, 75 of 75.
- **omnet-julia on the new method (2026-11-21).** All 28 suites of omnet-julia, 268 parts, ran in
  60 minutes with two workers of 4 threads on 8 cores, per-package workers, the depot from the
  seed, and the worktree of step 2 mounted as projectured-julia; peak 12.4 GB. Before, the run of
  `test_presentation` alone did not end in 4 hours, and a first worker that loaded all 27 test
  packages stopped at an 11 GB cap. The time limit of a part stops three parts at 10 minutes
  (`test_presentation_atoms`, `test_campaign_walk`, `test_ide_gestures_compile_little`), and one
  part passes 8 GB in a worker of its own (`test_simulation_window_graphics`).
- **A name that hides a function of Base** was the cause of two faults of the filter of
  `tests-run-fast` and of one of mine: a keyword `only` or `count` hides `Base.only` or
  `Base.count` in its function. A guard of the naming rules could find it.
- **Found along the way:** the recorded call list of `ProjecturedJulia` is stale (539 of 3186
  calls no longer resolve), so that package compiles more at each load; step 4 records it again.

## 6. Not in this plan

- A change of the reactive compiler itself, beyond what step 4 needs.
- The fixes of the faults that the markers of `main-stays-green` name.
