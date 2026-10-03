# REPL

> **Kind:** design · **Status:** current · **Stands on:** [package-rules.md](../../../rule/package-rules.md)

`ProjecturedREPL` is the leaf that a person loads to work: one `using` gives the editor, the examples, the SDL backend and the tests, with their code compiled ahead of time. It holds the one `@compile_workload` of the source tree. This document says how the workload level is chosen, how the recording is made and replayed, and where the traps are.

## How it works

### The leaf

A package image keeps its compiled code only when nothing depends on the package and nothing loads after it. [package-rules.md](../../../rule/package-rules.md#why-the-leaf-matters) explains why, with the measurement. So the workload is here, and in no package below.

`ProjecturedREPL` depends on `Projectured`, `ProjecturedExample`, `ProjecturedSDL` and `ProjecturedTest`, and on `PrecompileTools` and `Preferences` for the workload. A loop over `names(module)` exports again every name that the four export, so no list of names needs care. `test_export_collisions()` checks that two of the four do not export one name with two bindings, which would make the name ambiguous. `Revise` is not a dependency: it must load before the packages that it tracks, so the session alias loads it first.

### The workload level

`WORKLOAD` is read with `@load_preference("workload", "recorded")` at module scope. Julia records a preference read at module scope as a dependency of the precompile cache, so a change of the level builds the image again. An environment variable does not do that, and the old image would keep the old level with no sign.

| Level | What the build compiles |
| --- | --- |
| `:none` | nothing, for a day of work on the kernel |
| `:recorded` | `PRECOMPILE_STATEMENTS`, the lines of the statement files of the packages, the default |
| `:live` | what `ProjecturedExample.precompile_workload()` runs |

`set_workload!(level)` writes the preference; the next start of Julia builds with it. `get_workload()` returns the level of the running image, and it warns when the stored preference differs, because then the session was not started again.

`:recorded` is the default because it is the only level that compiles the reader. The workload prints the atomic documents and parses their text, but it sends no gesture, so no reader runs. A recording holds what a driven editor had to compile, the reader included. `@setup_workload` builds the atoms outside `@compile_workload`, so the compiled region holds the chain and not the construction of the documents.

### The recording

`record_precompile_statements()` runs the driver of the recording `"examples"`, `tool/precompile/recording-driver.jl`, in a new Julia process under `--trace-compile`, because that is a flag of the command line. `PRECOMPILE_RECORDINGS` names each recording, its driver and its environment. `ProjecturedExample` then drops every statement that names `Main` or does not parse, and sorts the rest. `split_precompile_statements` gives each line to each package that it names and that no other package that it names depends on, and a line that names no package of the repository to the packages of the recording that no other one depends on. `write_precompile_statement_files` writes them into `package/<Name>/precompile/<recording>.txt`. Those files are generated; do not edit them.

`PRECOMPILE_STATEMENTS` is each line of each statement file, read while the leaf precompiles; a changed, added or removed file builds the leaf again. A released package carries its statement files, and AutoPrecompile reads them in the session of a user.

The driver runs three things:

1. `precompile_workload()`, so the recording holds everything that `:live` compiles.
2. `warm_application()`, the warm-up of the binary. It types a name into the name buffer of a new tab, and the first key compiles a method for every document type that the buffer can make.
3. Every registered example, in one SDL window. The driver sends each one a fixed list of events: pointer motion, a left and a right press, a scroll each way, the arrow keys, Tab, Home, End, Backspace, Delete and two characters. One event of each kind is enough, because the value of a key is a run-time value. An example that throws is counted and skipped.

The recording needs a display. The SDL backend needs an accelerated renderer, and the dummy video driver has none.

### The replay

`replay_precompile_statements()` binds every loaded module into `StatementScope`, an empty module of this package, and resolves each statement there before it calls `precompile`. A statement that names nothing any more is skipped, so the list can be older than the code. The build warns when more than a tenth of the list was skipped, which is the sign to record again. The same call at the prompt shows what the list is worth with no rebuild.

## How it fits

The code is the slice `ReplModule`, in `source/tool/repl/`; the package entry re-exports what four packages export and the names of the slice. Nothing depends on `ProjecturedREPL`, and nothing may load after it. The session alias runs `julia --project=environment/all -i -e 'using Revise, ProjecturedREPL'`; the alias is outside this repository. The shared machinery of the recording and the replay is in `ProjecturedExample`, so a downstream leaf calls the same code with its own driver and its own list. A built binary is the other leaf: its generated app package holds its own `@compile_workload`, which runs `warm_application()`; see [builder.md](../builder/builder.md).

## Design decisions

- **The level is a preference.** A change then builds the image again. See [plan/done/recorded-precompile-workload.md](../../../../plan/done/recorded-precompile-workload.md).
- **The default replays a recording.** A workload compiles only what somebody wrote down to run, and nobody wrote a read. A recording compiles what an editor that is driven had to compile.
- **A statement resolves in a module of this package.** `StatementScope` holds the bindings. A binding in the module of a dependency would be one build that writes into the image of another package.
- **A stale statement is skipped, not an error.** The list stays usable while the code moves, and the skip count is the signal to record again.
- **The recording is a step that a person runs, not a build step.** Nobody waits for it, so it can open a real window and take its time.
- **The machinery is shared.** The driver and the list belong to the leaf. The code that records and replays is written once, in `ProjecturedExample`.

## Usage

```julia
using Revise, ProjecturedREPL         # what the session alias runs
get_workload()                        # the level of this image
set_workload!(:none)                  # then start Julia again
replay_precompile_statements()        # what the list is worth, with no rebuild
record_precompile_statements()        # record "examples" again; needs a display
```

- Examples: none of its own. The recording drives every registered example.
- Test: `test_export_collisions()` in `test/projectured/ExportCollisionTest.jl`. No `test/repl/` exists, and no test runs the driver. `test_sdl_keysym()` in `test/backend/sdl/backend/KeysymTest.jl` reads the driver and checks that SDL reports each key that it presses.

## Limits

- Record at `:none` only. A `:recorded` image already holds the old list, so those methods never compile, never reach the trace and drop out of the new list. [package-rules.md](../../../rule/package-rules.md#the-session) gives the steps and the check of a new list.
- A recording replaces the list and does not merge with it.
- The driver needs a display, so no automatic run checks that it still works.
