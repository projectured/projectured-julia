# A finished task leaves no files behind

> **Kind:** maintenance · **Status:** a plan, 2026-11-11; steps 1–5 done on the branch
> `no-files-behind` of projectured-julia, omnet-team, omnet-julia and PackageCompiler.jl ·
> **Covers:** the agent rules in `~/.claude/CLAUDE.md`, the omnet-team workflow and the memory
> notes; `workspace/bin/bounded-run`; two settings of the machine; omnet-julia; PackageCompiler.jl;
> projectured-julia · **Not in this plan:** opp_repl, which another agent changes.

On 2026-11-11 the disk was full: 115 MB free of 1.8 TB. A search found the files that tasks,
tests and tools leave after they end. This plan changes the sources of the files that matter
most, so that the files go away without a person. It does not cover every source.

## 1. The goal

1. When the work of a plan lands on `main`, its worktree, its private depot and its merged branch
   go away in the same step.
2. A copy of a project for a repro run, and a task folder in `/var/tmp`, go away at the end of the
   task. If a task keeps one, its final report names the folder and the reason.
3. `bounded-run` removes old job folders by itself.
4. `perf` and the Julia compile cache stop their growth without a bound.
5. The omnet-julia campaign tests, the reactive compiler and the assistant pictures leave nothing in
   `/tmp` or in `~/.cache`.

## 2. What exists (checked 2026-11-11)

| Fact | Where |
| --- | --- |
| A rule makes a worktree for each plan. A worktree goes away only in "Land the work", which starts when the human lands the work. Work that never lands keeps its worktree. There are 35 worktrees of projectured-julia and omnet-julia; 9 have no commit after 2026-10-21. | `~/.claude/CLAUDE.md:16`, `:20`; `omnet-team/workflow.md:68`, `:98-104` |
| A memory note tells a worktree run to use `/var/tmp/<branch>-depot` as its first depot. No rule removes the depot. There are 11 such depots, 0.03–1.2 GB each. | memory `worktrees-share-compile-cache-use-private-depot.md` |
| A memory note tells a repro run to copy the project first. It has no step that removes the copy. A plain copy takes `results/`, `tests/*/work` and `.git/worktrees`. `/var/tmp/every-kind-inet-cpp` is such a copy: 13 GB, 9.5 GB of it results. | memory `repro-never-runs-tasks-in-real-project.md`, `copied-repo-shows-original-worktrees.md` |
| `/tmp` is a RAM disk of 31 GB, so large task folders go to `/var/tmp`. No rule removes them. Task folders from before 2026-11-01 use 15 GB there, without the depots and the copy above. | memory `tmp-is-a-ram-disk.md` |
| `bounded-run` makes a job folder for each job and never removes it. `clean --older` exists, but nothing calls it. A plain `clean` is forbidden, because it removes the fresh jobs of other sessions. There are 870 job folders. | `workspace/bin/bounded-run:65`, `:685`, `:892`; memory `bounded-run-tool.md:49-51` |
| `perf record` copies each binary that it profiles into `~/.debug` (7.4 GB). No `~/.perfconfig` exists. | `~/.debug` |
| Julia keeps up to 10 cache files for each package and each Julia version. `~/.julia/compiled` is 46 GB; `ProjecturedPlatform` alone has 9 files, 3 GB. `bounded-run` passes every `JULIA_*` variable to a job. | `~/.julia/compiled/v1.13`; `bounded-run:78` |
| `campaign_test_project` makes a stub project in a new `mktempdir()` for each call. The tests call it at 30 places, directly or through `campaign_test_session`. Julia removes such a folder only at a normal exit of the process, so a killed test process keeps every folder it made. Of the 290 `/tmp/jl_*` folders of 2026-11-11, about 72 are these stub projects; 78 more come from `test/ide/AssistantSessionTest.jl` and 18 from a third writer. | omnet-julia `example/ide/CampaignFixture.jl:92`, `:121`; `test/ide/Campaign*Test.jl`, `TestVerbsTest.jl:13`, `LegacyPartPageTest.jl:140`, `:184` |
| The reactive compiler server precompiles the trace whose path its caller sends. It writes the statements that did not resolve to `<trace>.unresolved` beside the trace. The founding of a reactive app names its trace `jl_*-trace.jl` and moves the trace into the store, but not the listing: `/tmp` holds 30 listings and 2 traces, up to 460 KB each (step 5 found the founding). | julia-reactive-compiler `stdlib/ReactiveCompiler/src/child.jl:941-945`; PackageCompiler.jl `src/reactive.jl:218`, `:249` |
| The assistant writes a new PNG to `~/.cache/projectured/pictures` for each picture, and nothing deletes old ones. There are 160 files. | projectured-julia `source/platform/assistant/AssistantPicture.jl:97-110` |

## 3. Decisions

These are my proposals. They are approved with the plan.

- **D1. The depot stays in `/var/tmp`, under the name of its worktree.** The name changes from
  `/var/tmp/<branch>-depot` to `/var/tmp/<worktree folder name>-depot`. The step that removes the
  worktree removes the depot of the same name. *Why not a depot inside the worktree:* Pkg installs
  packages into the first depot, so the worktree would then hold `.jl` files that are not its own.
  The tools that walk the source tree, such as `julia-rename.jl` and the naming guard, would read them.
- **D2. A worktree of work that never lands is reported, not removed.** The final report of a task
  lists each worktree that the task made or worked in and that has no commit for 7 days, and no
  other worktree (the owner narrowed the rule in `~/.claude/CLAUDE.md` on 2026-11-12). Only the
  human decides that work is abandoned.
- **D3. `bounded-run start` removes the jobs that ended more than 7 days ago.** It removes no
  running job and no job that ended in the last 7 days, so the jobs of another session stay.
- **D4. `JULIA_MAX_NUM_PRECOMPILE_FILES=4`, set in `~/.profile`.** This keeps main and three
  other states of each package. The cost is a new compile when you switch between more than four
  states of the same package on the same depot. The private depots of D1 hold most worktree states,
  so this cost is rare.
- **D5. A test owns the folder of its stub project.** `campaign_test_project(root)` takes the folder,
  and each test makes it with `mktempdir() do root … end`. The folder goes away when the test ends,
  also when a later test fails. This does not depend on how the process ends.
- **D6. Assistant pictures older than 30 days are deleted** when a new picture is written.

## 4. Steps

Each step names its repository. A step in a folder that has no git repository gets no commit.
Instead, its change is recorded here.

1. [x] **The rules for the end of a task** (no git: `~/.claude/CLAUDE.md`, memory; git: omnet-team).
   **Done 2026-11-11.**
   - `~/.claude/CLAUDE.md`, section "Plans": when the work lands on `main`, remove in the same step
     its worktree, its depot (D1) and its merged branch. The final report lists each worktree that
     has no commit for 7 days, and does not remove it (D2). A new section "Files a task makes":
     at the end of a task, delete each folder that it made in `/var/tmp` and each copy of a
     project, or name it and the reason in the final report.
   - omnet-team `workflow.md` §4 names the depot (D1) and adds the same rule for task files and
     the report of D2. §6 step 3 removes the depot with the worktree and the branch. Commit
     `571e4f6` on the branch `no-files-behind` of omnet-team.
   - Memory: `worktrees-share-compile-cache-use-private-depot.md` uses the D1 name and its
     reason. `repro-never-runs-tasks-in-real-project.md` puts a large copy in
     `/var/tmp/<task>-<project>` and gives the copy command below. The wrong note
     `var-tmp-holds-main-repo-of-tsnspec.md` is replaced by `copied-repo-shows-original-worktrees.md`.
   - Check: the changed lines agree with D1 and D2. The `rsync` patterns were tested on a small
     tree in the scratchpad: the copy had no `results/`, no `tests/*/work` and no
     `.git/worktrees`, and kept `src/work/`.

   Found in the work:
   - **The removal follows the landing, not the move of the plan to `plan/done/`.** A plan moves to
     `plan/done/` on its branch, before the human lands it. A removal at that time would take the
     worktree away from the fixes that the human can still ask for. omnet-team §6 already removes
     the worktree at the landing.
   - **The copy keeps `out/`.** The copy then runs the build of the original and needs no new
     build. `inet-cpp/src/libINET_dbg.so` (0.9 GB) is a hard link to the file in `out/`, so the
     command is `rsync -aH --exclude=results/ --exclude='/tests/*/work/' --exclude=/.git/worktrees/`.
     A copy without `-H` would hold the library twice.
2. [x] **`bounded-run` removes old jobs** (no git: `workspace/bin/bounded-run`). **Done 2026-11-11.**
   - `remove_ended_jobs(jobs, older)` holds the loop that `command_clean` had, and `clean` keeps
     its output. `command_start` calls it with `OLD_JOB_DAYS = 7` before the room check, so a start
     that has no room also removes old jobs. An `OSError` of the removal prints one line to stderr
     and does not stop the start. A removal prints its count to stderr; stdout of `start` stays the
     same. The header text of the tool says the rule.
   - `bounded-run-tool.md` says that each `start` removes the old jobs of every session.
   - The copy before the change: the scratchpad file `bounded-run.before-step-2` of this session.
   - Check: `bounded-run selftest` passes 17 of 17. The new case writes a job that ended 8 days ago
     and one that ended 6 days ago: a start removes the first and keeps the second. On the real
     folder a start takes 0.13 s with 780 jobs.

   Found in the work: on 2026-11-11 no job of the 780 in `/var/tmp/bounded-run` (221 MB) ended
   more than 7 days ago, so the first start removed nothing. With about 800 jobs in a week, the
   folder stays near this size.
3. [x] **Two settings of the machine** (no git). **Done 2026-11-11.**
   - `perf config record.build-id=no-cache` wrote `~/.perfconfig`. The two `perf record` lines in
     the memory notes (`jll-library-const-bakes-build-path.md`, `memory-regions-branch-series.md`)
     now have `-N`.
   - `~/.profile` exports `JULIA_MAX_NUM_PRECOMPILE_FILES=4` (D4), outside the block that juliaup
     manages.
   - Check: `perf config record.build-id` prints `no-cache`, and the `perf` program holds the key
     `record.build-id` and the value `no-cache`. A login shell has the variable. A Julia 1.13.1 job
     that `bounded-run` started from a login shell prints `Base.MAX_NUM_PRECOMPILE_FILES[] == 4`.

   Found in the work:
   - **The `perf` setting could not be tested with a recording.** `perf_event_paranoid` is 4, so
     this user can open no event, and no file in `~/.debug` changed after October. The setting takes
     effect at the next recording. The local manual gives one more way: `buildid.dir = /dev/null`.
   - **The limit stops the growth, but it does not make a cache smaller.** When Julia writes a new
     cache file and the package has the limit or more, it evicts the one oldest file
     (`base/loading.jl:3436`). A package that has 9 files keeps 9. On 2026-11-11 a one-time trim to
     the 4 newest files would free 24 GB: 8.7 GB in 539 packages of `v1.12` and 15.4 GB in 625
     packages of `v1.13`.
   - **The variable reaches a process that a new login starts.** Sessions that run now do not have
     it, and neither do their `bounded-run` jobs. VS Code reads the login environment when it starts.
4. [x] **omnet-julia: the campaign tests remove their stub projects.** **Done 2026-11-11**, commit
   `4ef6f3cb7` on the branch `no-files-behind` of omnet-julia.
   - `campaign_test_project(root)` takes an empty folder, and `campaign_test_session` takes its
     `project` with no default (D5). The helpers `_make_task_verbs_project`,
     `_make_test_verbs_project` and `_project_verbs_run_window` take `root` and pass it on. The 18
     calls in 13 test files make their folders with `mktempdir() do … end`; a test with two
     projects makes two folders. No project lives longer than one test function.
   - Check: `test_campaign_window()` and `test_project_verbs()`, on the merged Julia with the depot
     `/var/tmp/omnet-julia-no-files-behind-depot` (D1), in a capped scope with `unshare -rn`. Main:
     584 passed, 6 failed. After: 584 passed and the same 6 failed (`CampaignControlTest.jl:141`,
     `CampaignDuplicateTest.jl:56`, `CampaignLoopTest.jl:159`, `:244`, `PaneProgramTest.jl:227`,
     `:340`). With a private `TMPDIR`, 0 stub projects were left before the exit, and 4 other
     folders that the fixture does not make.

   Found in the work:
   - **A normal exit removes the folders; a kill keeps them all.** A Julia process that ended
     normally left no `mktempdir()` folder. So a killed test process keeps every folder that it
     made since its start, which explains the bursts of 2026-11-11.
   - **A count in the shared `/tmp` is not a check.** Tests of another session wrote 121 stub
     folders into `/tmp` during the run, and the first count took them in. A check of the folders
     of one process sets a private `TMPDIR`.
   - **`bounded-run` can not run `unshare -rn`.** A service of the user manager gets no user
     namespace under `kernel.apparmor_restrict_unprivileged_userns = 1`. A scope of
     `systemd-run --user --scope` keeps the AppArmor label of its caller and can. The memory note of
     `bounded-run` says this.
5. [x] **PackageCompiler.jl: the founding takes the listing with the trace.** **Done 2026-11-12**,
   commit `dd96ca2f` on the branch `no-files-behind` of PackageCompiler.jl, from `reactive`.
   - The writer is not julia-reactive-compiler. `materialize_app` in `src/reactive.jl` names the
     founding trace `tempname() * "-trace.jl"`. Its harness runs `rc_precompile_trace` on it, which
     writes `<trace>.unresolved` beside it, and the founding moved only the trace into the store. A
     rebuild already reads the trace of the store (`{store}/trace.jl`), so it leaks nothing.
   - The founding makes one `mktempdir()` folder for the trace, the object archive and the harness
     script, and a `try … finally` removes it. The listing moves with the trace into the store; a
     founding with no listing removes an old listing of the store.
   - The omnet-team workflow has the narrower report rule of D2 too (omnet-team `a8b6d7a`).
   - Check: a founding of a copy of HazardApp (`m6_hazard`) with one statement that does not
     resolve, with the reactive Julia, a private `TMPDIR`, through `bounded-run` with an 8 GB cap.
     Branch `reactive`: the store holds `trace.jl`, and `jl_…-trace.jl.unresolved` stays in the
     temporary folder after the exit. The change: the store holds `trace.jl` and
     `trace.jl.unresolved`, and no listing stays. Each founding took about 70 s, peak 6.6–6.9 GB.

   Found in the work:
   - **A founding that fails left its trace and harness script in `/tmp`** (two of each on
     2026-11-11 and 2026-11-12). The `finally` now removes them, and the object archive too.
   - **A HazardApp founding needs about 7 GB**, so a cap of 8 GB fits and 6 GB does not.
6. [ ] **projectured-julia: old assistant pictures go away.**
   - In `_make_picture_filename`, delete `picture-*.png` files older than 30 days (D6).
   - Add a test that writes two pictures, one 31 days old and one new. After a new picture is
     written, only the new files remain.
   - Check: the new test, and the test file of the assistant picture.

## 5. Not in this plan

- The C++ `results/` folders and `inet-cpp/tests/unit/work`, which opp_repl makes.
- `SerializationTest.jl` calls `tempname()` 22 times and removes no file. `/tmp` is cleared after
  10 days and at a restart.
- Fixed `/tmp` paths in omnet-julia `tool/trim-routing/*.sh`, and the staging folder of a
  distribution that a failed build keeps.
- The `<app>.object` folders. The builder keeps them on purpose for a relink.
- A one-time trim of `~/.julia/compiled` to the 4 newest files of each package (24 GB, step 3).
- 214 coverage files `*.cov` (10 MB) of 2026-11-01 in the source tree of `julia-merged-next`.
- The stub folders of `test/ide/AssistantSessionTest.jl` (78 on 2026-11-11) and of the third
  writer (18), and the 4 other plain `mktempdir()` folders of the campaign suites (step 4).
- The folder `jl_packagecompiler_*` of each build, from `mktempdir(; cleanup=false)` at
  PackageCompiler.jl `src/PackageCompiler.jl:717`, which is upstream code: 133 empty folders in
  `/tmp` on 2026-11-12 (step 5).
