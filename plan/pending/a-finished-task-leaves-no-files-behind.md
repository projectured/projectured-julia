# A finished task leaves no files behind

> **Kind:** maintenance · **Status:** a plan, 2026-11-11; step 1 done on the branch
> `no-files-behind` of projectured-julia and omnet-team · **Covers:** the agent
> rules in `~/.claude/CLAUDE.md`, the omnet-team workflow and the memory notes;
> `workspace/bin/bounded-run`; two settings of the machine; omnet-julia; julia-reactive-compiler;
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
| `campaign_test_project` makes a stub project in a new `mktempdir()` for each call. The tests call it at 30 places, directly or through `campaign_test_session`. Julia removes such a folder only at a normal exit of the process. 165 of the 290 `/tmp/jl_*` folders of 2026-11-11 are these stub projects. | omnet-julia `example/ide/CampaignFixture.jl:92`, `:121`; `test/ide/Campaign*Test.jl`, `TestVerbsTest.jl:13`, `LegacyPartPageTest.jl:140`, `:184` |
| The reactive compiler server precompiles the trace whose path its caller sends. It writes the statements that did not resolve to `<trace>.unresolved` beside the trace. The caller removes the trace, but not the listing: `/tmp` holds 30 listings and 2 traces, up to 460 KB each. The code that names the trace `jl_*-trace.jl` was not found in the first search. | julia-reactive-compiler `stdlib/ReactiveCompiler/src/server.jl:184`, `child.jl:941-945` |
| The assistant writes a new PNG to `~/.cache/projectured/pictures` for each picture, and nothing deletes old ones. There are 160 files. | projectured-julia `source/platform/assistant/AssistantPicture.jl:97-110` |

## 3. Decisions

These are my proposals. They are approved with the plan.

- **D1. The depot stays in `/var/tmp`, under the name of its worktree.** The name changes from
  `/var/tmp/<branch>-depot` to `/var/tmp/<worktree folder name>-depot`. The step that removes the
  worktree removes the depot of the same name. *Why not a depot inside the worktree:* Pkg installs
  packages into the first depot, so the worktree would then hold `.jl` files that are not its own.
  The tools that walk the source tree, such as `julia-rename.jl` and the naming guard, would read them.
- **D2. A worktree of work that never lands is reported, not removed.** The final report of a task
  lists each worktree that has no commit for 7 days. Only the human decides that work is abandoned.
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
2. [ ] **`bounded-run` removes old jobs** (no git: `workspace/bin/bounded-run`).
   - At the start of `command_start`, call the code of `command_clean` with `older` set to 7 days (D3).
   - In `bounded-run-tool.md`, write that `start` does this.
   - Check: `bounded-run selftest` passes. Then a `start` of a short job leaves no folder of a job
     that ended more than 7 days ago.
3. [ ] **Two settings of the machine** (no git).
   - Run `perf config record.build-id=no-cache` once, and change the two `perf record` lines in the
     memory notes to `perf record -N`.
   - Set `JULIA_MAX_NUM_PRECOMPILE_FILES=4` in `~/.profile` (D4).
   - Check: `perf config record.build-id` prints `no-cache`. A new login shell has the variable.
4. [ ] **omnet-julia: the campaign tests remove their stub projects.**
   - Apply D5 to `CampaignFixture.jl` and to each caller.
   - Check: count the `/tmp/jl_*` folders. Then run the campaign tests of `test/ide/` and count again.
     The count must be the same. The tests pass with the same counts as before.
5. [ ] **julia-reactive-compiler: the caller of the server removes the listing with the trace.**
   - Find the code that makes the `jl_*-trace.jl` path and sends it to `server.jl:184`. In that
     code, remove `<trace>.unresolved` where it removes the trace.
   - Check: one reactive rebuild leaves no new `*.unresolved` file in `/tmp`.
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
