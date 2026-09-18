# REPL

> **Kind:** reference · **Status:** current · **Stands on:** [package-rules.md](../../rule/package-rules.md)

The workload a session compiles ahead of time, and the recording that drives
it: `WORKLOAD`, `set_workload!` / `get_workload`, and
`replay_precompile_statements`. This is the file-level detail behind
`ProjecturedRepl`, the leaf a person loads to work; what a leaf is and why
compiled code survives only there is in
[package-rules.md](../../rule/package-rules.md#why-the-leaf-matters).

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/repl/Repl.jl` | `WORKLOAD`, `set_workload!`, `get_workload`, `replay_precompile_statements`, `record_precompile_statements`, and the `@compile_workload` block |
| `source/repl/record/driver.jl` | the script `record_precompile_statements` runs under `--trace-compile` to produce the recording |

## The workload

`WORKLOAD` is a `Preferences.jl` preference, read once at module scope so
that changing it invalidates the precompile cache — an environment variable
would not, and a stale image would keep the old setting silently. It takes
one of three levels:

| level | what the build does |
| --- | --- |
| `:none` | nothing; for a day spent editing the kernel |
| `:recorded` | replays `PRECOMPILE_STATEMENTS`, a checked-in list — the default |
| `:live` | runs `ProjecturedExample.precompile_workload()` |

`:recorded` is the default because it is the only level that compiles the
*reader*: a recording covers what a person actually did, while `:live`
compiles only what `precompile_workload()` thought to call. Measured
downstream, the read half of a first click is 4.4 ms under `:recorded` and
528 ms under `:live`, the same cost as no workload at all.
`set_workload!(level)` writes the preference and takes effect on the next
build; `get_workload()` reads the level this session was built with, and
warns when it differs from the stored preference, since a preference change
needs a restart to take effect.

## The recording

`source/repl/record/driver.jl` is not run by a build. A person runs
`record_precompile_statements()`, which opens a real SDL window — the shim
needs a display, since SDL asks for an accelerated renderer the dummy video
driver does not offer — drives every example the way a reader drives it
(the mouse, the arrow keys, Tab, Home, End, Backspace, Delete, Enter, and two
character keys), and writes down every method instance Julia had to compile
under `--trace-compile`. The list this produces is checked in at
`asset/precompile/PrecompileStatements.jl` and replayed by
`replay_precompile_statements()`, either inside `@compile_workload` during a
build or at the prompt to see what the list is worth without a rebuild. The
list goes stale gracefully as the code moves — a statement that no longer
names anything is skipped — which is why it must be re-recorded once the
example set changes enough to be worth it.

## How it fits

`ProjecturedRepl` is the leaf: it depends on `Projectured`, `ProjecturedExample`,
`ProjecturedSdl` and `ProjecturedTest`, and re-exports everything the four
name, so `using Revise, ProjecturedRepl` gives a session `run_example`,
`test_all`, `SdlBackend` and every document and projection constructor in
one line — the `jp` alias in `~/.bashrc` runs exactly that. `@compile_workload`
appears here and nowhere else in the tree, because a package image keeps its
compiled code only when nothing loads after it.

## What a reader must know before changing this

There is no `test/repl/` folder and no `example/repl/`; `record/driver.jl`
is the one script that exercises this slice, and it needs a display to run.
`test_export_collisions()` (`test/projectured/ExportCollisionTest.jl`) is
the guard that keeps the four re-exported packages from naming the same
symbol with two different bindings. A change to which example set the
workload compiles must be checked against `PRECOMPILE_STATEMENTS`: a
`:live` build is only allowed to replace the checked-in recording when its
own compiled set is a superset of it.
