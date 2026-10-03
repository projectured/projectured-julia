# AutoPrecompile: one package image for the packages that a session loads

## 1. Goal

The README of `Projectured.jl` tells a user to write:

```
julia> using Projectured, DataFrames, SimpleDirectMediaLayer
julia> display_in_editor(DataFrame(n = 1:100_000, square = (1:100_000) .^ 2))
```

The first session is slow, and every later session is slow too. Each session
compiles the whole path of `display_in_editor` again, because Julia keeps code
that it compiles while a program runs only for that process.

The goal: a session that loads the same packages a second time compiles almost
nothing for the paths that a recording covers. The first `display_in_editor` of
that session is fast. Any package can take part, not only the packages of
ProjecturEd.

## 2. Facts (2026-10-03)

- No released package has a workload. The workload of `ProjecturedREPL` replays
  the recorded statements, and the release leaves `ProjecturedREPL` out
  (`PROJECTURED_RELEASE_EXCLUSIONS`). The binary builder has a workload of its own.
- The recording of the repository has 15403 statements from 105 examples
  (commit `078bf9b56`). A replay of all of them took 312 s in a process with two
  threads. The image of `ProjecturedREPL` at `:recorded` was 217 MB for 12760
  statements (`plan/done/recorded-precompile-workload.md`).
- A recorded workload works when the package that replays it loads last.
  Measured in the repl leaves: a first click of 5.98 s became 0.21 s, and the
  first click on the json example became 475 ms from 2650 ms.
- Code that a session compiles with `precompile` at run time does not persist.
  `plan/done/precompile-workloads.md` measured that a warm-up at startup only
  moves the wait, and every session pays it again. So AutoPrecompile must compile
  into a package image, not into the session.
- Julia's loader (`manifest_deps_get` in `base/loading.jl`, Julia 1.13): a
  package in a directory on `LOAD_PATH` takes its dependencies from the `[deps]`
  of its own `Project.toml`, and Julia finds them through the whole load path.
  `compilecache` gives the load path of the session to the process that writes
  the image. So a package that AutoPrecompile generates in a folder of its own can
  depend on `DataFrames` from the environment of the user. Step 2 confirmed it.
- AutoIntegrations loads the integrations from its package callback. So a
  callback of AutoPrecompile sees the set of loaded packages grow during one
  `using` line: the set with `ProjecturedSDL`, then the set with
  `ProjecturedDataFrames` too. The full set comes last.
- A callback must do nothing while `Base.package_locks` holds a package
  (`plan/pending/auto-integrations.md`, decision 9.3), and a load from `__init__`
  stops with `ConcurrencyViolationError`.
- DataFrames depends on `PrecompileTools` (1.3.4 in `environment/all`).
- No package of the General registry does what AutoPrecompile does (step 1).

## 3. The design

### 3.1 The packages

| Package | `[deps]` | Made by | Loaded by | Released |
| --- | --- | --- | --- | --- |
| `AutoPrecompile` | `TOML`, `UUIDs`, `PrecompileTools`, `Scratch` | its own repository, as AutoIntegrations | the user, with `using AutoPrecompile` | yes, in `ProjecturedRegistry` |
| a leaf | `AutoPrecompile`, `PrecompileTools`, each package of its set | AutoPrecompile, at run time | AutoPrecompile | no |

AutoPrecompile depends on `PrecompileTools` for its leaves: a leaf finds each
dependency only through the environments of the load path, so the manifest of
the user must hold `PrecompileTools`, and the dependency of AutoPrecompile puts
it there.

A leaf is a package that AutoPrecompile writes for one set of packages. Its
precompile replays the statements that apply to that set. Julia stores its image
in `~/.julia/compiled` like the image of any package, so a later session with the
same set loads the image and compiles nothing.

### 3.2 The statement files of a package

- A package takes part when it has a folder `precompile/` at its root.
  AutoPrecompile reads every `.txt` file in that folder.
- One file holds one recorded scenario, for example
  `precompile/readme-data-frame.txt`. A new recording of a scenario replaces
  only its own file.
- A file is plain text, one signature on each line, as `clean_precompile_trace`
  writes them: the text inside `precompile(…)`. A line that starts with `#` is a
  comment.
- AutoPrecompile never `include`s a file. It reads lines. A file that is not a
  statement file does no harm, because the shape check refuses its lines.
- The recording stays a separate task, made as it is made now.

### 3.3 The selection

For the loaded set, AutoPrecompile reads the statement files of each loaded
package, and selects the statements that apply:

1. `Meta.parse` each line.
2. Refuse a line whose expression is not the shape of a signature. The shape is
   `Tuple{…}` and `Type{…}`, dotted names, `var"…"`, `typeof(name)`,
   type parameters, `where` with `<:` bounds, `Vararg`, `Union{…}`, and
   literals. Any other call, macro, assignment or block is refused, so no code of
   a statement file runs.
3. Collect the roots: the first name of each dotted name.
4. Select the line when each root is a loaded top-level module.
5. Remove duplicate lines.

AutoPrecompile reads the files of loaded packages only. So the package that
ships a line also decides when AutoPrecompile reads it: a line in the file of
`ProjecturedSDL` applies only when `ProjecturedSDL` is loaded, even when it
names only `Base`.

The set of a selection is the packages of its roots, without `Base` and `Core`.
The key of a leaf is a hash of the sorted uuids of that set. The name and the
uuid of the leaf come from the key.

### 3.4 The leaf

- AutoPrecompile keeps its leaves in its scratch space (decision 17), and adds
  that directory to the end of `LOAD_PATH`.
- A leaf folder holds its `Project.toml`, its source and a copy of its selected
  statements. The copy keeps the leaf independent of the files of other packages.
- The source imports each package of the set, declares a module
  `StatementScope` of the leaf, binds every loaded module into it, and replays
  the statements inside `@compile_workload`, as `ProjecturedREPL` does. The
  replay code moves from `ProjecturedExample` to AutoPrecompile.

### 3.5 When AutoPrecompile acts

AutoPrecompile adds one callback to `Base.package_callbacks`, as AutoIntegrations
does, with the same guards: nothing in a process that writes a cache file,
nothing while a package loads, no second call while one runs, and a warning
instead of an error.

At each call:

1. AutoPrecompile computes the selection and the key for the loaded set.
2. If the leaf of the key exists and `Base.isprecompiled` says that its image is
   valid, AutoPrecompile loads it with `Base.require`.
3. Else it waits until 10 s pass with no new load. Then it writes the leaf
   folder and starts a build in a separate process, at a low priority. It logs a
   line that names the set, the number of statements and the log file of the
   build, and says that the next session uses the result.
4. AutoPrecompile never loads a leaf whose image is not valid, because `require`
   would build it in the foreground.

A session that ends before the 10 s pass starts the build as it ends, in a
detached process that outlives it, so that a short script gets a leaf too.

One `using` line ends well within the 10 s, and AutoIntegrations loads its
integrations inside that line. So a set that is not complete starts no build. A
person who types the next `using` within 10 s starts no build for the smaller
set either. Julia's pidfile lock stops two sessions that build the same leaf at
the same time.

The build process loads the whole set a second time, so it needs about as much
memory as the session while it runs. The README leaf took 41 s to build (step 2).

### 3.6 Disk space

- A limit on the total size of the leaves, 2 GB by default. The user can change
  it in `LocalPreferences.toml`, table `[AutoPrecompile]`, as for
  AutoIntegrations.
- AutoPrecompile records when a session last loaded each leaf. When the limit is
  reached, it first removes the folder and the images of the leaf that a session
  loaded longest ago.
- When it builds a leaf again, it removes the old image of that leaf, because
  Julia keeps the old one on disk.

A README leaf is 57 MB (step 2), so 2 GB holds about 35 of them.

### 3.7 The statements of ProjecturEd

The recorder of ProjecturEd splits each recording by owner, and writes the parts
into the `precompile/` folders of the packages in the repository:

- A line goes to each ProjecturEd package that it names and that no other
  ProjecturEd package that it names depends on. A JSON line goes to
  `ProjecturedJSON`. A line that names only the platform and the kernel goes to
  `ProjecturedPlatform`.
- A line that names no ProjecturEd package goes to the packages of the scenario
  that no other package of the scenario depends on. In the README scenario these
  are `ProjecturedSDL` and `ProjecturedDataFrames`.

The spread of the two recordings that exist (2026-10-03), counted by the
ProjecturEd packages that a line names, keeping only those that no other named
one depends on:

| | lines | one such package | two or more | none |
| --- | ---: | ---: | ---: | ---: |
| the list of the repository | 15403 | 14721 | 133 | 549 |
| the README recording | 2344 | 2104 | 1 | 239 |

In the README recording, the one package is `ProjecturedPlatform` for 1692
lines, `ProjecturedKernel` for 186, `ProjecturedDataFrames` for 128 and
`ProjecturedSDL` for 98.

## 4. Decisions

The owner, 2026-10-03, on the review of the first version:

1. The first session is slow. That is not a problem if AutoPrecompile logs what
   it does, so that the user sees it.
2. The key of a leaf is the set that its selected statements name. One leaf for
   each set.
3. AutoPrecompile checks `Base.isprecompiled` and builds a stale leaf in the
   background, never in the foreground.
4. AutoPrecompile limits the disk space of its leaves and removes old ones.
5. AutoPrecompile accepts only the shape of a signature and runs no other
   expression.
6. The statement files are plain text, one signature on each line, at a fixed
   path in the package folder.
7. One file for all Julia versions. A signature that does not match is skipped,
   and the recording is made again from time to time, as now.
8. A package records its statements again when its author wants. Stale entries
   are skipped and do no harm.
9. AutoPrecompile does nothing in a process that writes a cache file, and it
   loads a leaf from the package callback, never from `__init__`.
10. A leaf depends on `PrecompileTools` and replays inside `@compile_workload`.

Also from the owner: the recording is a separate task, made as now, and the
statements of ProjecturEd are part of the repository.

The owner, 2026-10-03, later:

11. The user loads AutoPrecompile with `using AutoPrecompile`. `Projectured`
    does not load it.
12. The name is `AutoPrecompile`, in the family of AutoIntegrations.
13. The statement files are the `.txt` files in the folder `precompile/` at the
    root of a package, one file for each recorded scenario (section 3.2).
14. `ProjecturedPlatform` does not ship the statements of other packages. The
    recorder of ProjecturEd splits each recording by owner (section 3.7).
15. A build starts after 10 s with no new load, in a separate process at a low
    priority (section 3.5).
16. The leaves have a limit of 2 GB in total by default, with a setting, and the
    leaf loaded longest ago goes first (section 3.6).
17. The leaves live in the scratch space of AutoPrecompile, which `Scratch.jl`
    gives (`~/.julia/scratchspaces/<uuid of AutoPrecompile>/`), so that `Pkg.gc`
    removes them when AutoPrecompile is no longer installed. AutoPrecompile
    depends on `Scratch`.
18. The load of a valid leaf writes no log line, because it is fast. The build
    writes the lines.

## 5. Steps

Each step is a commit. Mark it here when it is done.

1. **Done — search.** Look in the General registry for a package that does this
   already. Report before step 3.

   Done 2026-10-03: the names of the local General registry, and the web. No
   package does all of it: watch the loads of a session, select recorded
   statements by the loaded set, and build one package image for that set. The
   closest tools:
   - `AutoSysimages` (petvana/AutoSysimages.jl) records statements while a
     person works and builds one system image for each project, with a command.
     It is not driven by the loads of a session and reads no file that a package
     ships.
   - `SnoopCompile` turns traces into `precompile` lines that the author of a
     package puts into that package.
   - `PrecompileTools` caches what a workload runs, in the image of the package
     that holds the workload. AutoPrecompile uses it inside each leaf.
   - `CompileTraces` replays a `--trace-compile` file in the running session
     only.
   - `PackageCompiler` builds a system image for a list of packages that a
     person gives, ahead of time.

   Not read: `PrecompileSignatures`, `PrecompileAfterUpdate`,
   `PrecompileMacro`, `CompileBot`. The names `AutoPrecompile`,
   `JointPrecompile`, `RecordedPrecompile` and `PrecompileTraces` were free.
2. **Done — experiment, no package changes.** In `/var/tmp`, write by hand the
   leaf that AutoPrecompile would make for the set of the README, from the
   recording of the repository. Put it in a directory environment, build it, and
   count the methods that the first `display_in_editor(df)` compiles in a new
   session, with the leaf and without it (`--trace-compile`, counted lines).
   Report the count, the build time and the size of the image. Wall-clock times
   of a session need an idle machine and the owner's approval.

   Done 2026-10-03 on `main` at `9b7be97be`, Julia 1.13, in a scratch
   environment with the five packages of the README (`/var/tmp/x-experiment/`).
   Two leaves, written as section 3.4 says: `XLeafRepo` from the recording of
   the repository, and `XLeafReadme` from a trace of the README scenario itself.

   | | statements | build | image | load | first display | close |
   | --- | ---: | ---: | ---: | ---: | ---: | ---: |
   | no leaf | — | — | — | — | 2010 | 312 |
   | `XLeafRepo` | 7575 of 15403 | 86.4 s | 110 MB | 0.31 s | 470 | 7 |
   | `XLeafReadme` | 2344 of 2344 | 40.5 s | 57 MB | 0.20 s | 106 | 0 |

   "First display" counts the methods compiled from `display_in_editor(df)`
   through its first 8 s; "close" counts `close_display_editor!()`.

   What it shows:
   - A leaf in a directory at the end of `JULIA_LOAD_PATH` builds and loads. Its
     dependencies resolve through the environment of the user, `PrecompileTools`
     too, which is only in the manifest there (through DataFrames). The fact of
     section 2 holds.
   - Every statement of both leaves compiled; none was skipped.
   - The recording of the repository drives no data frame, so `XLeafRepo` leaves
     the DataFrames path to the session. ProjecturEd must record the scenarios of
     its README too (step 7).
   - Of the 106 methods left with `XLeafReadme`, 71 are key and gesture paths
     (`recognize(::ChordRecognition, …, ::KeyDown, …)`) that the window received
     in this run and not in the recorded one. 35 are small `Base` methods that the
     leaf holds and the session compiled again; the cause is not known.
   - A marker function that returns a constant leaves no line in the trace,
     because Julia runs it without compiling it. A marker must return a value of
     run time, such as `time()`.
3. **Done — the repository of AutoPrecompile**, as `auto-integrations`, in the
   sibling folder `auto-precompile`: `Project.toml`, `src`, `test`, `README.md`,
   the licence.

   Done 2026-10-03, commit `688a8e2` on `main` of the new repository. The owner
   created `projectured/AutoPrecompile.jl` on GitHub, private, and pushed it the
   same day; the first CI run passed. The uuid is
   `b272d1c7-21da-44b4-9d4d-f64941f33c6f`. As in `auto-integrations`: the MIT
   licence, the CI workflow on Julia 1.12 and the newest release, `julia = "1.12"`,
   and no manifest in Git. The package has no dependencies yet; each step adds
   the ones that its code uses. The module and the README say that this version
   does nothing when it loads, and the test checks that it adds no package
   callback. `Pkg.test()`: 1 of 1 passes.
4. **Done — the selection**: read the files, parse, the shape check, the roots,
   the key. Tests with lines that pass and lines that are refused.

   Done 2026-10-03, commit `78421c3`, landed on `main` of `auto-precompile` and
   pushed at the owner's word; the CI run passed. `Pkg.test()`: 40 of 40 pass.
   What was found and chosen:
   - The 17747 lines of the two recordings of ProjecturEd hold few forms: each is
     a `Tuple{…}`, the heads are `curly`, `.`, `where`, `<:`, `tuple` and `call`,
     the only call is `typeof`, and the only literals are integers and symbols.
     The shape check allows those, and also `Bool`, `Char`, float and string
     literals, `>:`, and `Lb<:T<:Ub`, which a trace of another package can
     hold. Anything else is refused, for example a call, a macro, an assignment,
     a block, an interpolation, a quoted expression or an array.
   - No line of the 17747 is refused. For the set of the README, the selection
     gives the same lines as the experiment of step 2: 7575 of the list of the
     repository and 2344 of 2344 of the README recording.
   - AutoPrecompile reads the statement files of every loaded package that has a
     uuid, in the folder that `pkgdir` gives. A root resolves by name among the
     loaded packages; a name that two loaded packages share is left out, so a
     line that names it is not selected.
   - The uuid of a leaf is `uuid5` of the sorted uuids of its set, with the uuid
     of AutoPrecompile as the namespace, and its name is `AutoPrecompileLeaf_`
     and the first 16 hex digits. A test pins two values, because a key that
     changes would leave every leaf behind.
   - The package gets the dependency `UUIDs`. `Project.toml` still says 0.1.0;
     the next registration needs a new number.
5. **Done — the leaf**: write it, wait 10 s, build it in the background with a
   log, load it. Tests with scratch packages, as the tests of AutoIntegrations.

   Done 2026-10-03, commit `cb53863`, landed on `main` of `auto-precompile` and
   pushed at the owner's word. `Pkg.test()`: 59 of 59 pass. What was found and chosen:
   - The build runs `Base.compilecache` of the leaf in a detached process, with
     `JULIA_LOAD_PATH` set to the expanded load path of the session (the folder
     of the leaves included) and `JULIA_DEPOT_PATH` to its depots, under
     `nice -n 10` where `nice` exists. A `FileWatching` pidfile lock in the
     leaf folder lets one process build a leaf at a time; the next one finds the
     image valid. Its output goes to `build.log` in the leaf folder. The session
     logs when the build starts, and when it ends: ready, or failed with the
     path of the log.
   - A session that ends before the 10 s pass starts the build as it ends
     (`atexit`), because a short script would else never get a leaf. Section
     3.5 says so.
   - Each loaded package's statements are read and parsed once in a session,
     because the callback runs after each load.
   - The leaf files are written under another name and renamed, so that a build
     in another session never reads half a file.
   - The leaf imports its set, holds `include_dependency` on its
     `statements.txt`, and calls `AutoPrecompile._replay_statements!` inside
     `@compile_workload`. The replay checks the shape of each line again before
     it evaluates it, because the file in the scratch space can change.
   - `AutoPrecompile._BUILD_WAIT` holds the wait, so that a test can shorten it.
   - The dependencies `PrecompileTools` and `Scratch` are added, with the
     compat `"1"`.
   - A fault of the tests: an empty entry at the end of `JULIA_DEPOT_PATH`
     adds the default depots without the depot of the user, so a scratch process
     saw no registry and no installed package. The tests of AutoIntegrations use
     only the standard library and do not see it. The tests name the depots of
     their own process instead.
   - The tests, each a new process in a scratch environment: the first session
     builds and logs; a later one loads the leaf, logs nothing and does not
     compile the replayed method, while a session without AutoPrecompile does;
     a changed statement file builds again; a package with no statements builds
     nothing; a line that calls `rm` is never evaluated; a short session starts
     its build as it ends, and the build finishes after it.
6. **Done — disk space**: the limit, the setting and the cleanup.

   Done 2026-10-03, commit `ba2da6a`, landed on `main` of `auto-precompile` and
   pushed at the owner's word. `Pkg.test()`: 83 of 83 pass. What was found and chosen:
   - The setting is `disk_limit_mb`, a whole number of megabytes, in the table
     `[AutoPrecompile]` of `LocalPreferences.toml`. AutoPrecompile reads it with
     `Base.get_preferences`, which works because the user adds AutoPrecompile by
     name (decision 11); AutoIntegrations reads the file itself only because the
     user never adds it. Another value gives a warning and the default, 2048.
   - The size of a leaf is its folder and its images for each Julia version in
     the first depot. A removal takes all of them.
   - A leaf records the time of its last load as the text of its file `loaded`,
     so that a test can write any time; a leaf with no such file counts from the
     time of its statement file.
   - A removal never takes a leaf that this session loaded, the leaf that it
     builds, or a leaf whose `build.pid` is younger than an hour.
   - The cleanup runs before each build and after each build that succeeds.
   - Under its pidfile lock, a build removes the old images of its leaf for its
     Julia version before it compiles. The test plants a stale image and checks
     that the rebuild removed it, because a rebuild with the same flags writes
     the same file name and would pass without the removal.
7. **Done — ProjecturEd**: the recorder writes text, records the README
   scenarios, and splits each recording by owner into the `precompile/` folders
   of the packages (section 3.7). `ProjecturedREPL` reads the text files. The
   release copies the `precompile/` folder of each package, and the README says
   what AutoPrecompile does.

   Done 2026-10-03, one commit for each part: `fd42a55ac`, `03fa7d716`,
   `92e0aefd1`, `fd5ce2dca`, `1905fffea`, landed on `main` of projectured-julia
   at the owner's word. What was found and chosen:
   - The worktree is a sibling folder of the main checkout, not one under
     `.claude/worktrees/`, because `environment/all` and `package/Projectured`
     find AutoIntegrations at `../../../auto-integrations` (plan of
     AutoIntegrations, 9.7). Julia reused the package images of the main
     checkout, because it checks the sources by content: the first build of the
     worktree took 2 minutes.
   - `ProjecturedExample` keeps `record_precompile_statements(driver, output)`
     and the Julia list, because `OmnetRepl` and `InetRepl` call it. It gets
     `trace_precompile_statements`, which answers the cleaned lines of a run.
   - The split lives in `ProjecturedREPL` (`source/tool/repl/ReplStatementFiles.jl`),
     because only this repository knows its packages. The dependency graph comes
     from the `Project.toml` files of `package/`, so `ProjecturedREPL` depends on
     `TOML`. `PRECOMPILE_RECORDINGS` names each recording, its driver and its
     environment; `record_precompile_statements(recording)` runs one.
   - "The packages of a recording" in section 3.7 are the packages that its lines
     name. In the recording "examples", the 549 lines that name no package of the
     repository go to `ProjecturedTest`; in "readme-data-frame" they go to
     `ProjecturedDataFrames` and `ProjecturedSDL`.
   - Part 1 wrote the list of the repository as the recording "examples": 47
     files, 15536 lines for 15403 statements, because 133 lines name two packages
     that do not depend on each other. `ProjecturedPlatform` keeps 6617 lines.
   - Part 2: `PRECOMPILE_STATEMENTS` is each line of each statement file, with
     each file and each statement folder as an `include_dependency`. It holds the
     same 15403 lines as the old list. At `:recorded` the leaf built in 211 s, and
     a replay compiled 15403 and skipped none.
   - Part 3: `environment/readme-data-frame` holds the five packages of the
     README, with a tracked manifest as `environment/all` and `environment/build`
     have. The driver `tool/precompile/readme-data-frame.jl` sends real SDL events
     to the largest window that SDL knows, with each field of an event set by
     name, as the SDL tests do; an event with window id 0 maps to no window. 2577
     lines: `ProjecturedPlatform` 1676, `ProjecturedDataFrames` 372,
     `ProjecturedSDL` 346, `ProjecturedKernel` 183. The files hold paths of the
     wheel, the button and the keys; none of `F2` opening a cell, so the click at
     the middle of the window selected no cell.
   - Part 4: the release copies `package/<Name>/precompile/` beside `ext/`.
   - Part 5: the front page of the release repository gets the section "Faster
     sessions".
   - Tests: `test_package_release()` 244 of 244; `test_package_graph()`,
     `test_export_collisions()` and `test_naming()` together 368 of 368.
   - Open for the owner: `ProjecturedPlatform` also ships the 6617 lines of
     "examples", so the leaf of the README set holds them too. In step 2 a leaf
     of 7575 lines took 86 s and 110 MB, against 41 s and 57 MB for the README
     lines alone.
8. **Measure the README scenario**: the count of compiled methods in the second
   session, and the times if the owner approves.
9. **Release**: the owner registers AutoPrecompile in `ProjecturedRegistry`.

   Version 0.1.0, the version of step 3 that does nothing, is registered
   2026-10-03 at the owner's word: commit `fcbf66b` in the clone
   `~/.julia/registries/ProjecturedRegistry`, made with LocalRegistry.jl from
   `@localregistry` as for AutoIntegrations, tree `4c5c951b…` of `688a8e2`. The
   owner pushed it the same day. So
   the first version that works needs a new number, for example 0.2.0.

## 6. Open questions

None at the moment.
