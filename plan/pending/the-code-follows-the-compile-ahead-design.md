# The code follows the compile-ahead design

Status: pending. Written 2026-10-29. Not started; the owner starts each step.

Applies to projectured-julia, omnet-julia and inet-julia.

## The ask

The owner, 2026-10-29: "commit and continue", after the design
`documentation/design/compile-ahead.md` was complete. The design is in each of
the three repositories. This plan moves the code of the three repositories to
it. U1 to U14 and Decisions 1 to 10 are the ones of that document.

## What changes

| Today | After this plan | From |
|---|---|---|
| Each package with a workload runs it in a plain `@compile_workload` at each build | Each package calls `ProjecturedPrecompile`, which reads `precompile_calls` and `precompile_failure` | U4, U12, D6, D10 |
| One recording of every example, split into 53 files `examples.txt` and `readme-data-frame.txt` | Each package records its own workload into `precompile/workload.txt`; an application records into `precompile/<application>.txt` | D1, D3, D4, D8 |
| The REPL leaves have the levels `:none`, `:recorded` and `:live`, and replay one list | The REPL packages have no levels and no workload | D2 |
| omnet and inet keep their lists in `asset/precompile/` | Each package of omnet and inet keeps its own lists | D4, D5 |
| The build writes the package of each application again at each build | Each application has a real package under version control | D9 |
| The binary builds of omnet and inet have the levels `:none`, `:minimal`, `:demo` and `:full` | The build of a binary chooses `precompile_calls` for its packages | U13 |
| A failed workload writes a warning into a build output that nobody sees | The failure shows when the session or the binary starts, or it stops the build | U12 |
| The guards of the binaries run in the test suites | The measurements run when a person starts them, and before each release | U7 |
| `OmnetSimulator` calls `precompile` by hand | It has a workload, as each package has | U10 |

## Steps

Each step is one or more commits in a worktree of each repository that it
changes. Mark a step here when it is done.

1. [ ] **`ProjecturedPrecompile` (D10).** A new package, with its code in
   `source/tool/precompile/`:
   - The call that the entry file of a package makes. It reads the two
     preferences of that package, so that a change of a preference builds the
     image again. At `"none"` it does nothing. At `"recorded"` it compiles each
     file in `precompile/` of the package. At `"live"` it runs the workload of
     the package.
   - The failure (U12): at `"error"` the build stops. At `"warning"` the image
     stores the failure, and the package shows it when it loads. At `"silent"`
     nothing shows. A list fails when more than 10 % of its lines no longer
     resolve.
   - The recording (U5, D7, D8): one package, all packages of a repository, or
     one application. It runs in a new process with `precompile_calls =
     "none"` for the packages that it records, with no display (U14), and it
     writes the files of D4.
   - The check of U14: it compares a recording with no display with one with a
     display.
   - Its tests, its design document in `documentation/package/`, and its place
     in `package-rules.md`.
2. [ ] **projectured: each package uses it.**
   - Each entry file with a workload calls `ProjecturedPrecompile`.
   - `ProjecturedExample` gets a workload that opens each example and sends it
     the events of the recording driver of today (D2).
   - The application `projectured` gets a real package (D9), and the builder
     uses it and chooses `precompile_calls` for its packages (U13).
   - The recording of each package and of the application writes the new
     files. The 53 old files, `ReplStatementFiles.jl`, the recorder and the
     replay of `ProjecturedExample`, `tool/precompile/`,
     `ProjecturedExample.precompile_workload()` and the levels of
     `ProjecturedREPL` go.
   - `package-rules.md`, `repl.md` and `builder.md` say the new form.
3. [ ] **The measurements (U7, U5).** The guards and the measurements of U7 leave
   the test suites and run from one command. The release runs the recording and
   the measurements.
4. [ ] **omnet: each package uses it.**
   - `OmnetIde`, `OmnetLegacyFormat`, `OmnetLegacyResultPresentation`,
     `OmnetPresentationExample` and `OmnetSimulator` call
     `ProjecturedPrecompile`. `OmnetSimulator` gets a workload in place of its
     `precompile` call.
   - `omnet_ide`, `omnet_run`, `routing` and the demo get real packages (D9).
     Their builds choose `precompile_calls` (U13).
   - `asset/precompile/`, `tool/record_precompile.jl`,
     `tool/record_workload.jl`, `tool/repair_statements.jl`, the replay in
     `Batch.jl`, the levels of `Batch.jl` and of `OmnetRepl` go.
   - The reactive build keeps its own trace, because the build chooses how the
     binary is produced (U13).
5. [ ] **inet: each package uses it.**
   - `InetExample` and `InetRunner` call `ProjecturedPrecompile`. The workload
     of the binary moves from `precompile_execution_file` into the workload of
     `InetRunner`.
   - `asset/precompile/`, the recording driver, `InetExample.precompile_workload()`,
     the levels of `InetRepl` and of the build, and the name
     `editor_precompile.jl` go.
6. [ ] **The measurement and the end.** Run the measurements of U7 in each
   repository, before step 2 and after step 5, and write both into this plan.
   Remove the section "The code today" from the three design documents.

## Hazards

- A list names closures that the compiler generated, so it goes stale when the
  code changes. U5 and U12 handle that: a person records again, and a list
  fails above 10 %.
- The removed names are exports: `set_workload!`, `get_workload`, `WORKLOAD`,
  `record_precompile_statements`, `replay_precompile_statements` and others. A
  released package that loses an export takes a minor version step.
- omnet and inet load projectured through `[sources]`, so step 2 can break them
  until steps 4 and 5 land. Steps 2, 4 and 5 land together.
