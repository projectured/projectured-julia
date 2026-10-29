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

1. [x] **`ProjecturedPrecompile` (D10).** A new package, with its code in
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

   As built (2026-10-29, worktree `projectured-julia-compile-ahead`, branch
   `compile-ahead`):
   - `@compile_ahead workload` in the entry file defines two names in the
     package: `run_package_workload()` and `PRECOMPILE_FAILURE`. A first form
     also defined a module `PrecompileScope` to resolve a recorded call in, as
     the REPL leaf did. Step 2 found that 84 entry files bind each submodule of
     the packages below them under its own name, so a module of one name in each
     package collides there. The compile now puts the module object in place of
     the first name of each dotted name and evaluates the call in the package.
     A package with no workload writes `@compile_ahead`
     alone, so that it still compiles the calls that an application records for
     it. The preferences are read with `Preferences.load_preference(package,
     …)` while the package precompiles, which makes the image depend on them.
   - Both compiles run between `tag_newly_inferred_enable` and
     `tag_newly_inferred_disable` of PrecompileTools, as `@compile_workload`
     does, so the code of other packages stays in the image.
   - A package with no folder `precompile/` depends on the list of its own
     folder, so a first recording builds it again.
   - At `"warning"` the package shows the failure when it loads: the
     `__init__` of the slice reports the packages that loaded before it, and
     a function in `Base.package_callbacks` reports each later one.
   - The recording builds the images in a first process with no trace, and then
     traces the workload in a second one. With a single traced process the
     list held the calls of the build of the images (`precompilepkgs` and the
     like).
   - Fact: `--trace-compile` of Julia 1.13 writes only the entries of a run.
     A call that inference resolves inside an entry, also a dynamic call that
     inference splits over the methods of the function, compiles with the
     entry and is not in the trace. A build that compiles the entry compiles
     those calls again, so a list loses nothing.
   - The recording reads a manifest, so the package also depends on the
     standard library TOML. Decision 10 of `compile-ahead.md` names it; the
     documents of omnet and inet follow in steps 4 and 5.
   - `package-rules.md` moves to step 2, because it describes the entry files
     that step 2 changes.
   - Not run yet: `test_package_graph()`, which needs a build of every image of
     the worktree; step 2 runs it.

   Tests: `test_precompile()` 48 of 48: the layering guard, the trace, the
   list, the graph, the owner of a call, and a probe package at `"none"`,
   `"live"`, a failed workload at each value of `precompile_failure`,
   `"recorded"`, a stale list, an unknown value and a recording. The naming
   guard and the documentation check pass.
2. [x] **projectured: each package uses it.**
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

   Progress (2026-10-29):
   - Done: the 16 domain entry files, the platform, SDL and the data frames call
     `@compile_ahead` with their workloads. 13 packages of the binary with no
     workload call `@compile_ahead` alone (Kernel, Console, PDF, FSM,
     SequenceChart, Process, Database, DBCatalog, Web, Ollama, Anthropic, MCP,
     ACP), so that an application recording can give a call to the lowest
     package that sees its types (D8). The other packages are aggregates,
     tools, leaves, examples and tests.
   - Done: `ProjecturedExample` runs `run_example_workload()`: each example in
     a window of a backend with no device, sent the events of the recording
     driver of today. An example that fails does not stop the others; the
     workload throws at the end and names them. The atom walks stay, because
     the catalog coverage test uses them.
   - Done: the slice `ReplModule`, `tool/precompile/`, the 53 old files, the
     recorder and the replay of `ProjecturedExample` and the atom workload are
     gone. `ProjecturedREPL` keeps its exports only.
   - Done: `test_package_graph()` checks one `@compile_ahead` in an entry file,
     a dependency on `ProjecturedPrecompile`, and no `@compile_workload`.
     `package-rules.md`, `repl.md`, `naming-rules.md`,
     `division-terminology.md`, the new-domain guide and three other documents
     say the new form.
   - Done (the owner accepted this form of D9 on 2026-10-29: "I accept it"):
     `ProjecturedBuild`, a real package and a leaf, holds every package of the
     binary, both backends included, and the workload of the binary
     (`warm_application()`, then the window on SDL). The build still writes the
     small package under `build/app/` with the values of one build (the build
     record, the log level, the usage text, the stand-ins), and that package
     loads `ProjecturedBuild`. So a build that names one backend still carries
     both; `backends` chooses what `--backend` offers.
   - Done (U13): `build_executable` takes `precompile_calls` in place of
     `workload`, and writes it as a preference of each package of the build
     that compiles ahead. The command line takes `--precompile-calls=` in place
     of `--no-workload`. The generated package has no `@compile_workload` and
     no PrecompileTools. The builder depends on `ProjecturedPrecompile` for
     `is_compiling_package`, which the recording uses too.
   - Fact: the example workload drives 132 of 135 examples in 288 s. Three
     fail, each a fault of the product: `json_sorted` writes a `CellVector` of
     the wrong element type (`DeclaredTypeMismatchException`), and
     `filesystem` and `files` read the fields `value` and `elements`, which
     `FileSystemFile` and `Workspace` no longer have. The workload names them.
   - Done: a recording whose workload fails keeps the calls compiled before the
     failure and shows the failure in a warning, as the default of U12 does.
   - Done: the recording (2026-10-29, 27 min, peak 6.7 GiB):
     `record_repository_calls!` wrote `workload.txt` for 21 packages (the
     platform 9626 calls, `ProjecturedExample` 8110, `ProjecturedBuild` 3219,
     each domain 300 to 800) in 1300 s, and `record_application_calls!` wrote
     `projectured.txt` into 27 packages (the platform 1827, the kernel 272) in
     303 s. A package with `@compile_ahead` alone is not recorded by the
     repository scope (`has_package_workload`), and a call of
     `ProjecturedPrecompile` itself goes into no list.
3. [x] **The measurements (U7, U5).** The guards and the measurements of U7 leave
   the test suites and run from one command. The release runs the recording and
   the measurements.

   As built (2026-10-29), projectured:
   - `tool/measure-compile-ahead.jl` runs the measurements of U7: the build time
     and the size of the image of each package, in a depot of its own that
     takes the packages, artifacts and registries of the depot of the process;
     the `using` line, the first frame and its compile part of the session of
     the README, the median of three; the two guards; and, with `--binaries`,
     the build time, the peak memory (`/usr/bin/time`) and the size of the
     binary. `--record` records first. `--root=<checkout>` measures another
     checkout, run with the environment of that checkout, so that step 6 can
     measure `main` before the change with the same command.
   - `test_first_window_compiles_little` and `test_gestures_compile_little`
     leave the default suite of `ProjecturedTest`; they stay exported.
   - The release is a procedure in `release-guide.md`, not one command, so
     "the release runs them" is a step of that procedure: the command with
     `--record --binaries`, and a commit of the changed lists, before the
     landing of the release.
   - `environment/build` and `environment/readme-data-frame` are resolved
     again, because their packages now depend on `ProjecturedPrecompile`.
   Measured (2026-10-29), projectured only, `tool/measure-compile-ahead.jl`
   with no binary, on `main` (`e30ac20d8`) and on this branch:

   | | main | this branch |
   |---|---:|---:|
   | the images of `environment/all` in a new depot | 743 s, 1374 MB | 516 s, 1331 MB |
   | `ProjecturedPlatform` | 198 s, 307 MB | 103 s, 292 MB |
   | `ProjecturedREPL` | 156 s, 306 MB | 16 s, 3 MB |
   | `ProjecturedExample` | 9 s, 2 MB | 87 s, 175 MB |
   | `ProjecturedBuild` | — | 65 s, 94 MB |
   | the `using` line of the README session | 2.09 s | 2.09 s |
   | its first frame (the part that compiles) | 0.89 s (0.69) | 0.96 s (0.76) |
   | the start of the binary: statements (compiled again) | 77 (1) | 73 (6) |
   | 166 gestures: statements (compiled again) | 251 (2) | 310 (80) |
   | gestures over 10 statements | 4 | 4 |

   Facts from the measurement:
   - Two of the three calls that the application recording gave to
     `ProjecturedAnthropic` named `Base.Val{Pkg}`; `Pkg` stands bare there,
     and the owner rule saw only the first names of dotted names. The rule now
     counts a bare name of a package too, and the compile puts a loaded module
     in place of a bare name.
   - The 80 calls compiled again are mostly the save of each format and the
     reads of intents. Each list holds them, and a package that loads later
     makes them invalid. The same gestures on `main` compile about as many calls
     new, not again: Ctrl+S on a book file is 14 new calls on `main` and 13 here,
     10 of them again. A second recording of `ProjecturedBuild` after the
     application lists, `"live"` for `ProjecturedBuild` alone (99 again), and
     `"live"` for every package (92 again) do not change it. The cause is open.
   - `record_application_calls!` records the package of the application again
     at its end, so that its list follows the new lists of the lower packages.
   - The measurement command continues when one measurement fails, and says so.
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

   Decided (the owner, 2026-10-29, "Yes"): the run binaries take way 3.
   `omnet_run` and the twelve sample binaries have no package of their own. A
   sample binary differs from another one only in the model package that ports
   the simple modules of its sample, and each model package has its own
   workload: one configuration of its own sample. The runner has the workload of
   the paths that answer with no model. The build of a run binary only chooses
   `precompile_calls`.

   As built (2026-10-29):
   - `OmnetRunner` and the twelve model packages call `@compile_ahead`. The
     preference `workload` of the runner is now `precompile_calls`, which
     `--build-info` prints; the preference `models` goes, because nothing reads
     it.
   - `Batch.jl`, `asset/precompile/`, `record_workload.jl` and
     `repair_statements.jl` go. The build command takes `--precompile-calls=`
     in place of `--workload=` and `--no-workload`.
   - The trace of a reactive build runs `run_package_workload()` of each package
     of the build that compiles ahead.
   - Fact: Julia 1.13 still prints a value in a type parameter with the names
     of its fields (`Rational{Int64}(num=1, den=1)`), which does not read back.
     Each type of Unitful holds one. `repair_statements.jl` of omnet dropped the
     names; `collect_traced_calls` of `ProjecturedPrecompile` now does it.

   Decided (the owner, 2026-10-29, "Yes"): `omnet_ide` gets a real package,
   `OmnetIdeBuild`, in the form of `ProjecturedBuild`: it holds every package
   of the binary, both backends and the four assistant packages included, and
   the workload of the binary (`warm_omnet_ide()`, then the window on SDL). The
   demo and `omnet_simulate` follow way 3: the old workload of the demo is the
   workload of `OmnetPresentationExample` now, and `omnet_simulate` had none.
   Decision 9 of `compile-ahead.md` says so in projectured and in omnet: an
   application with a workload of its own has a real package; an application
   whose workload is only that of its packages has none.

   As built (2026-10-29, omnet `2489b6e5c`):
   - The tests: the package graph and the name guards pass except two failures
     that `main` has too (`OmnetBench` depends on `OmnetSimulatorExample`, and
     the spelling guard flags `build_omnetpp!`). The runner suite passes 671 of
     673; the two closure errors read `../projectured-julia`, the main checkout,
     which has no `ProjecturedPrecompile` before the landing. Through a layout of
     symbolic links where both sibling names point at the worktrees, the closure
     tests pass 58 of 58, and the build test passes 64 of 67 with the same three
     errors as `main` (no `juliac` in this Julia, and a `PackageCompiler`
     checkout with no `collect_tracked_sources`).
   - The closure of `OmnetIde` counts 36 packages, one more:
     `ProjecturedPrecompile`.
   - A build with no assistant still holds the assistant packages, because
     `OmnetIdeBuild` holds them, as a projectured build with one backend still
     holds both.
   - `environment/all` of omnet gains `OmnetIdeBuild` and `ProjecturedACP`.
   - Each of the twelve sample packages builds its image with the live workload
     in 18 to 22 s.
5. [ ] **inet: each package uses it.**
   - `InetExample` and `InetRunner` call `ProjecturedPrecompile`. The workload
     of the binary moves from `precompile_execution_file` into the workload of
     `InetRunner`.
   - `asset/precompile/`, the recording driver, `InetExample.precompile_workload()`,
     the levels of `InetRepl` and of the build, and the name
     `editor_precompile.jl` go.

   Decided (the owner, 2026-10-29, "I agree with you, option 1"): the inet build
   uses `ProjecturedBuilder`, as the omnet build does. The inet build compiled
   `package/InetRunner` itself, and Julia reads a preference only for a package
   that the project lists directly, so it could not choose `precompile_calls`
   for the packages below `InetRunner`. The builder writes a small package that
   lists each package of the binary. `BuildSpec` becomes a build function, like
   `build_omnet_run_executable`.

   As built (2026-10-29, inet `f2667da`, worktree `inet-julia-compile-ahead`):
   - `InetRunner` runs the old binary workload at its old level `:full` in its
     own `@compile_ahead` (`source/runner/RunnerWorkload.jl`): the command lines
     that answer with no run, the parse of the corpus, a whole run of a small
     network and two configurations of the tutorial. `InetExample` opens and
     forces its catalog page and one header page. `InetRepl` only re-exports.
   - Facts: the strict workload found four faults that the old workload hid in
     a `try`. It imported `iniparse_file`, which omnet no longer has, so each of
     the 329 INI files of the corpus failed to parse; `-c General` names no
     configuration; the small network named two packet elements that nobody
     registers; and `main` answers an exit code, so a failed run said nothing.
     The workload now reads with `parse_ini_file`, runs `[Config Small]`, uses
     `ActivePacketSource` and `PassivePacketSink`, and throws when a run ends
     with another code than 0.
   - `source/tool/build/Build.jl` is `build_inet_executable` over
     `ProjecturedBuilder`, with its own context (the sibling checkouts of omnet
     and projectured), `incremental = false` and a portable processor target by
     default, as the inet build had. The editor build goes: its package
     `InetRunnerEditor` is not written, so no build of it could run, and the
     runner says that the build that draws is not written yet. The front end
     takes `--precompile-calls=`. `InetRunnerTest` and `environment/tool`
     depend on `ProjecturedBuilder` in place of Pkg and Preferences.
   - `BuildContext` of `ProjecturedBuilder` loses its field `statements`, the
     file of statements that PackageCompiler replays: no repository sets it
     now, and it was a second mechanism. omnet passes none any more.
   - Tests: the package graph 39 of 39, the runner command line and run 107 of
     107, and through the layout of symbolic links the build test, the runner
     closure and the package graph 65 of 65. `test_inet()` gives 390 pass, 46
     fail and 34 errors, the same as `main` (an ambiguous `open_page!` between
     `OmnetPresentation` and `ProjecturedAll` in `InetTest`). The builder suite
     of projectured passes 593 of 593.
6. [ ] **The measurement and the end.** Run the measurements of U7 in each
   repository, before step 2 and after step 5, and write both into this plan.
   Remove the section "The code today" from the three design documents.

   Decided (the owner, 2026-10-29, "I accept step 6, yes"): the measurements
   that each repository takes the same way are functions of
   `ProjecturedPrecompile` (`measure_package_images`, `measure_process_median`,
   `measure_binary_build`), and each repository has a small command for its own
   checks.

   As built (2026-10-29):
   - projectured `dfe541a96`: `source/tool/precompile/PrecompileMeasurement.jl`
     and `test_precompile_measurement()`. The command of each repository runs
     in an environment that holds `ProjecturedPrecompile`, and each measurement
     runs in a new process of the environment of the measured checkout, so the
     command measures `main` too.
   - omnet `f62e464f0`: `tool/measure-compile-ahead.jl`: the images, the `using`
     line and the first frame of `OmnetIde`, the guard of `omnet_ide`, and the
     binaries `omnet_ide` and `omnet_run`.
   - inet `0dc46b8`: `source/tool/build/measure-compile-ahead.jl`: the images,
     the `using` line and the first run of `InetRunner` in place of a first
     frame, and the binary `inet-julia`. `.gitignore` named `build/`, which also
     hid `source/tool/build/`; it names `/build/` now.
   - The recordings: omnet 1872 s for the repository and 715 s for `omnet_ide`;
     inet 187 s. The first recording of `OmnetIde` failed under load: the window
     did not draw `DONE` within the 300 s of its step, while four other jobs ran.
     It passed when it ran again, and the lists of `omnet_ide` were recorded
     again after it.
   - Fact: Pkg follows the real path of an environment, so the relative
     `[sources]` of a worktree reach the main checkouts also through a folder of
     symbolic links. That folder serves the static tests only. The
     measurements of the branches run in `/var/tmp/compile-ahead/tree`, a
     detached worktree of each branch with the real name of its repository,
     beside links to the other folders that the `[sources]` reach.
   - The section "The code today" goes from the three design documents
     (projectured `5670e98c4`, omnet `1db23c48b`, inet `1e91ecd`).

   Results without the binaries (2026-10-29, 10:58 to 13:05, Julia 1.13.1, one
   job of 20 GB; another session ran jobs at the same time, a load average of
   about 6 on 32 cores). "main" is the main checkout of each repository, the
   code before step 2; "branch" is the tree of the branches. The outputs are
   in the scratch folder of the session, `measure/<repository>-<main|branch>.txt`.

   The images of `environment/all`, in a depot of its own, the default
   parallel precompile:

   | | main | branch |
   |---|---:|---:|
   | projectured: the wall time, the size | 768.9 s, 1375 MB | 527.4 s, 1330 MB |
   | omnet | 1156.5 s, 1838 MB | 899.2 s, 2093 MB |
   | inet | 706.8 s, 1284 MB | 449.0 s, 1188 MB |
   | `ProjecturedPlatform` (in each of the three) | 202 to 205 s | 107 to 115 s |
   | the other slow images of projectured | `ProjecturedREPL` 159.2 s, `ProjecturedSDL` 84.2 s | `ProjecturedExample` 88.3 s, `ProjecturedBuild` 66.5 s |
   | of omnet | `OmnetRepl` 321.3 s, `OmnetIde` 140.7 s | `OmnetPresentationExample` 136.7 s, `OmnetIde` 66.0 s |
   | of inet | `InetRepl` 177.4 s, `ProjecturedSDL` 78.9 s | `InetExample` 38.1 s, `InetRepl` 27.6 s |

   The sessions from source, each the median of three new processes, in
   seconds (the part that compiles in parentheses):

   | | main | branch |
   |---|---:|---:|
   | projectured, the README: the `using` line | 2.13 | 2.16 |
   | projectured, the README: the first frame | 0.85 (0.69) | 0.99 (0.78) |
   | omnet, `using OmnetIde, ProjecturedSDL` | 11.5 | 11.23 |
   | omnet, the first frame of `run_omnet_ide` | 4.97 (4.2) | 4.96 (4.24) |
   | inet, `using InetRunner` | 7.31 | 7.57 |
   | inet, the first run of `ActiveSourcePassiveSink` | 11.37 (11.33) | 0.17 (0.14) |

   The omnet session loads `OmnetIde`, not `OmnetIdeBuild`, so the workload
   of the window is not in what it loads, on main or on the branch.

   The guards of the binaries. Each image of a binary runs its workload with
   no warning, and each guard has 2 passes and 3 broken, on main and on the
   branch:

   | | main | branch |
   |---|---:|---:|
   | `projectured`: the start (recompiles) | 77 (1) | 72 (6) |
   | `projectured`: 166 gestures, statements (recompiles), over 10 | 251 (2), 4 | 310 (80), 4 |
   | `omnet_ide`: the start (recompiles) | 91 (1) | 87 (3) |
   | `omnet_ide`: 202 gestures, statements (recompiles), over 10 | 247 (1), 8 | 240 (42), 6 |

   **Open: the recompiles of the branch.** The branch compiles again in a
   gesture what the image holds: 80 against 2 in `projectured`, most of them
   in the saves (`Ctrl+S saves SqlFile.sql` 13 statements, 11 of them
   recompiles), and 42 against 1 in `omnet_ide`, most of them in the presses
   and the typing in the tables of results. The cause is not known yet.

   The longest chain of images sets the wall time, not the count of cores: on
   the branch the images of projectured are 995 s of work, 31 s on 32 cores,
   but their longest chain is 283 s (`ProjecturedKernel` → `ProjecturedPlatform`
   → … → `ProjecturedExample` → `ProjecturedTest` → `ProjecturedREPL`), and
   493 s on main. The precompile jobs of this plan used 2.4 to 2.5 cores on
   average.

## Hazards

- A list names closures that the compiler generated, so it goes stale when the
  code changes. U5 and U12 handle that: a person records again, and a list
  fails above 10 %.
- The removed names are exports: `set_workload!`, `get_workload`, `WORKLOAD`,
  `record_precompile_statements`, `replay_precompile_statements` and others. A
  released package that loses an export takes a minor version step.
- omnet and inet load projectured through `[sources]`, so step 2 can break them
  until steps 4 and 5 land. Steps 2, 4 and 5 land together.
