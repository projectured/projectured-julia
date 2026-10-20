# A launcher shows its slow work

Status: DONE, 2026-10-20. Q1 decided by the owner on 2026-10-20.

## The ask

The owner, 2026-10-20: `bin/omnet_ide --help`, run the first time, "shows nothing
about what's going on": it installs packages and compiles for a long time, "so the
user doesn't know what's up". "We don't want to always log everything but when
something happens that takes a lot of time then it would be desirable for the user
to see by default."

## What exists

- **Seven launchers hide the output of their first step:** `bin/projectured` in
  projectured, and `bin/omnet_ide`, `bin/omnet_campaign_ui`, `bin/omnet_run`,
  `bin/omnet_simulate`, `bin/omnet_demo` and `bin/omnet_legacy_sample` in omnet.
  Each runs one Julia process over `environment/build` with its error output sent
  to a temporary file (`2>"$problem"`), and shows the file only when the step
  fails. Then it starts the program with `exec julia --project=<app> -e "using <App>; …"`.
- **That first step does the slow work.** It adds the General registry when none
  is there, resolves and installs `environment/build`, loads the builder (which
  compiles it when it is stale), and writes the package of the program
  (`build_*_executable(; compile = false, resolve = true)`). The last part calls
  `resolve_app_project` (`source/tool/builder/Executable.jl`), which resolves and
  installs the package of the program at every start; the install compiles every
  package of the program, because the automatic precompile of the package manager
  is on.
- **The package manager already shows progress** (each package, a count, and the
  time). What it prints when its output is no terminal is not measured yet (step 1).
  All of it goes into the temporary file today.
- A start that has nothing to install or compile still takes a few seconds for
  the resolve, and prints nothing.

## The model

1. **A launcher holds the output of its first step for ten seconds** (see step 1).
   When the step ends within them, nothing is shown, as today: a normal start stays quiet.
2. **When the step runs longer, the launcher says why the wait comes,** in one line,
   such as "Preparing the packages of the IDE: after an install or an update, the
   first start installs and compiles them, which takes some minutes." From then on
   the output of the step goes to the terminal as it comes, starting with what was
   held, so a person sees which package installs or compiles.
3. **A step that fails shows its output, as today,** also within the two seconds.
4. **One function holds it.** The builder library (`ProjecturedBuilder`, which
   `OmnetBuilder` uses) gives the function that runs the work of the first step
   under this rule, and each of the seven launchers calls it. A launcher script
   keeps only what makes the builder loadable.

## Steps

1. [x] **Measure the first start.** On a cache made stale by a change of one source
   file of the platform, run `bin/omnet_ide --help` with the output shown: the time
   of each part (the build environment, the builder, the resolve, the compile, the
   load of the program), and what the package manager prints to a terminal and to
   a pipe. Record it here. Done, on 2026-10-20 with Julia 1.13.1, `bin/omnet_ide`:
   - **A normal start spends 4.4 to 4.9 seconds in the first step**, with nothing
     to install or compile: about 1 second for the resolve of the build
     environment and 3.2 seconds for the resolve and the install of the package
     of the program. **So the gate holds ten seconds, not two.** A gate of two
     seconds would show the line at every start. The decision of the owner, the
     time, stays; the number moved with the measurement.
   - A start after a landing in projectured compiled 21 packages: 150 seconds in
     the first step (145 for the compile). A fresh worktree of projectured took
     132 seconds for `bin/projectured --help`.
   - To a pipe, the package manager prints "Precompiling packages..." and one line
     for each package as it finishes, such as `47.7 s ✓ ProjecturedPlatform`.
     When a manifest is new, it first lists each package that it adds (about 180
     lines). The builder logs a few `@info` blocks, and the compile workload of the
     IDE logs some warnings of its own.
2. [x] **The function and `bin/projectured`** (projectured): the function in the
   builder library, with its line of explanation, and `bin/projectured` calls it.
   Tests: a step that ends within the time shows nothing; a slow step shows the
   line and all of its output; a step that fails shows its output. Done:
   `run_with_slow_output(work; notice, after = 10.0)` in
   `source/tool/builder/LauncherOutput.jl`, a fragment of `BuilderModule` that
   uses only Base. A launcher includes it alone, in a module of its own
   (`Module()`), because the builder is not loadable before the first step, and a
   `using ProjecturedBuilder` later in `Main` would meet the same name there. The
   gate redirects the error output to a pipe, so the workers of the precompile
   write into it too, and the logs go through a `SimpleLogger` on that pipe. The
   script needs no temporary file: a failure shows on the terminal, and the empty
   answer ends the script. Tested: `test_launcher_output()` (three cases, each in a
   process of its own); `bin/projectured --help` in a fresh worktree showed the
   line after ten seconds and each package live, and a second start showed only
   the help.
3. [x] **The six omnet launchers** (omnet) call it. Test: `bin/omnet_ide --help` on a
   stale cache shows the line and the progress, and on a fresh cache shows only the
   help. Done: each script finds the file at
   `$root/../projectured-julia/source/tool/builder/LauncherOutput.jl`, where the
   `[sources]` of `OmnetBuilder` find the projectured builder, so projectured lands
   first. Tested with a copy of the script that names the file of the worktree:
   `omnet_ide --help` in a fresh worktree showed the line at 11 seconds and the
   help at 155, and a second start showed only the help (15 seconds in all);
   `omnet_legacy_sample routing --help` too, for the scripts that pass arguments.
4. [x] **The guides:** the build guide of projectured (omnet has no build guide,
   and its launchers carry the note in their own comments); the plan moves to
   `plan/done/`.

## Questions for the owner

- **Q1. What decides that the work is shown? Decided (the owner, 2026-10-20: "agreed"): (a), the time.**
  (a) The time. The
  output shows when the step runs longer than two seconds, so every slow part
  shows, also one that nobody foresaw, and a quick start stays quiet; a person
  waits two seconds before the first line. (b) A check before the work: the
  launcher asks whether packages are missing or not compiled for this Julia, and
  shows the output only then. The line comes at once, but a slow part that the
  check does not foresee, such as a slow resolve, stays silent.

## Not in this plan

- A start that skips the resolve when nothing changed, which would make a normal
  start faster: the resolve is there because a manifest goes stale in a way that
  the install alone does not see (`resolve_app_project`).
- The load of the program after the first step, which takes a few seconds with no
  output on a cold start.
