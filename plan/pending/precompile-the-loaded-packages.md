# X: one package image for the packages that a session loads

`X` is a working name. The name is an open question (section 6).

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
  moves the wait, and every session pays it again. So X must compile into a
  package image, not into the session.
- Julia's loader (`manifest_deps_get` in `base/loading.jl`, Julia 1.13): a
  package in a directory on `LOAD_PATH` takes its dependencies from the `[deps]`
  of its own `Project.toml`, and Julia finds them through the whole load path.
  `compilecache` gives the load path of the session to the process that writes
  the image. So a package that X generates in a folder of its own can depend on
  `DataFrames` from the environment of the user. This is read from the source and
  not yet tested (step 2).
- AutoIntegrations loads the integrations from its package callback. So a
  callback of X sees the set of loaded packages grow during one `using` line: the
  set with `ProjecturedSDL`, then the set with `ProjecturedDataFrames` too. The
  full set comes last.
- A callback must do nothing while `Base.package_locks` holds a package
  (`plan/pending/auto-integrations.md`, decision 9.3), and a load from `__init__`
  stops with `ConcurrencyViolationError`.
- DataFrames depends on `PrecompileTools` (1.3.4 in `environment/all`).

## 3. The design

### 3.1 The packages

| Package | `[deps]` | Made by | Released |
| --- | --- | --- | --- |
| `X` | `TOML`, `UUIDs`, `PrecompileTools` | its own repository, as AutoIntegrations | yes, in `ProjecturedRegistry` |
| a leaf of X | `X`, `PrecompileTools`, each package of its set | X, at run time | no |

X depends on `PrecompileTools` for its leaves: a leaf finds each dependency
only through the environments of the load path, so the manifest of the user must
hold `PrecompileTools`, and the dependency of X puts it there.

A leaf is a package that X writes for one set of packages. Its precompile
replays the statements that apply to that set. Julia stores its image in
`~/.julia/compiled` like the image of any package, so a later session with the
same set loads the image and compiles nothing.

### 3.2 The statement file of a package

- A package takes part when its folder holds a statement file at a fixed path
  (open question: the path and the name).
- The file is plain text, one signature on each line, as `clean_precompile_trace`
  writes them: the text inside `precompile(…)`. A line that starts with `#` is a
  comment.
- X never `include`s the file. It reads lines.
- The recording stays a separate task, made as it is made now. The statements of
  ProjecturEd stay in the repository. The recorder writes the text format, and
  `ProjecturedREPL` reads the same file.

### 3.3 The selection

For the loaded set, X reads the statement file of each loaded package that has
one, and selects the statements that apply:

1. `Meta.parse` each line.
2. Refuse a line whose expression is not the shape of a signature. The shape is
   `Tuple{…}` and `Type{…}`, dotted names, `var"…"`, `typeof(name)`,
   type parameters, `where` with `<:` bounds, `Vararg`, `Union{…}`, and
   literals. Any other call, macro, assignment or block is refused, so no code of
   a statement file runs.
3. Collect the roots: the first name of each dotted name.
4. Select the line when each root is a loaded top-level module.

The set of a selection is the packages of its roots, without `Base` and `Core`.
The key of a leaf is a hash of the sorted uuids of that set. The name and the
uuid of the leaf come from the key.

### 3.4 The leaf

- X keeps its leaves in a directory of the first depot, for example
  `~/.julia/x/leaves/`, and adds that directory to the end of `LOAD_PATH`.
- A leaf folder holds its `Project.toml`, its source and a copy of its selected
  statements. The copy keeps the leaf independent of the files of other packages.
- The source declares a module `StatementScope` of the leaf, binds every loaded
  module into it, and replays the statements inside `@compile_workload`, as
  `ProjecturedREPL` does. The replay code moves from `ProjecturedExample` to X.

### 3.5 When X acts

X adds one callback to `Base.package_callbacks`, as AutoIntegrations does, with
the same guards: nothing in a process that writes a cache file, nothing while a
package loads, no second call while one runs, and a warning instead of an error.

At each call:

1. X computes the selection and the key for the loaded set.
2. If the leaf of the key exists and `Base.isprecompiled` says that its image is
   valid, X loads it with `Base.require`.
3. Else X writes the leaf folder and starts a build in a separate process in the
   background. It logs a line that names the set, the number of statements and
   the log file of the build, and says that the next session uses the result.
4. X never loads a leaf whose image is not valid, because `require` would build
   it in the foreground.

One `using` line passes through sets that are not complete. A leaf of such a set
is never built, because X starts a build only after a short time with no new
load (open question: how long). Julia's pidfile lock stops two sessions that
build the same leaf at the same time.

### 3.6 Disk space

An image can be some hundred MB. X keeps a limit on the number of leaves (open
question: the number), records when a session last loaded each one, and removes
the folder and the compiled images of the leaf that was used longest ago.

## 4. Decisions

The owner, 2026-10-03, on the review of the first version:

1. The first session is slow. That is not a problem if X logs what it does, so
   that the user sees it.
2. The key of a leaf is the set that its selected statements name. One leaf for
   each set.
3. X checks `Base.isprecompiled` and builds a stale leaf in the background, never
   in the foreground.
4. X limits the disk space of its leaves and removes old ones.
5. X accepts only the shape of a signature and runs no other expression.
6. The statement file is plain text, one signature on each line, at a fixed path
   in the package folder.
7. One file for all Julia versions. A signature that does not match is skipped,
   and the recording is made again from time to time, as now.
8. A package records its statements again when its author wants. Stale entries
   are skipped and do no harm.
9. X does nothing in a process that writes a cache file, and it loads a leaf from
   the package callback, never from `__init__`.
10. A leaf depends on `PrecompileTools` and replays inside `@compile_workload`.

Also from the owner: the recording is a separate task, made as now, and the
statements of ProjecturEd are part of the repository.

## 5. Steps

Each step is a commit. Mark it here when it is done.

1. **Search.** Look in the General registry for a package that does this
   already. Report before step 3.
2. **Experiment, no package changes.** In `/var/tmp`, write by hand the leaf
   that X would make for the set of the README, from the recording of the
   repository. Put it in a directory environment, build it, and count the methods
   that the first `display_in_editor(df)` compiles in a new session, with the leaf
   and without it (`--trace-compile`, counted lines). Report the count, the build
   time and the size of the image. Wall-clock times of a session need an idle
   machine and the owner's approval.
3. **The repository of X**, as `auto-integrations`: `Project.toml`, `src`,
   `test`, `README.md`, the licence.
4. **The selection**: parse, the shape check, the roots, the key. Tests with
   lines that pass and lines that are refused.
5. **The leaf**: write it, build it in the background with a log, load it.
   Tests with scratch packages, as the tests of AutoIntegrations.
6. **Disk space**: the limit and the cleanup.
7. **ProjecturEd**: the recorder writes text, `ProjecturedREPL` reads text, a
   released package ships the file (`PROJECTURED_PACKAGE_ASSETS`), and the
   README says what X does.
8. **Measure the README scenario**: the count of compiled methods in the second
   session, and the times if the owner approves.
9. **Release**: the owner registers X in `ProjecturedRegistry`.

## 6. Open questions

- The name of X.
- Who loads X. My proposal: `Projectured` loads it, as it loads
  AutoIntegrations, and a user who names each package writes `using X`.
- The path and the name of the statement file in a package folder.
- Which released package of ProjecturEd ships the file of the repository. My
  proposal: `ProjecturedPlatform`, because every package of ProjecturEd loads it,
  and X selects from the file by the loaded set.
- How long X waits after the last load before it starts a build.
- How many leaves X keeps.
- Whether the load of a valid leaf writes a log line. My proposal: no line,
  because it is fast; the build writes lines.
