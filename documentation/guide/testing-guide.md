# Testing in the REPL

> **Kind:** procedure · **For:** developer · **Status:** current · **Stands on:** [package-rules.md](../rule/package-rules.md)

The test suite is a DAG of **test packages** that parallels the main
package DAG (see [plan/done/test-package-split.md](../../plan/done/test-package-split.md)):

```
main:     ProjecturedKernel ← ProjecturedPlatform ← the 18 domains ← Projectured ← {Example, Sdl, …}
tests:    ProjecturedKernelTest ← ProjecturedPlatformTest ← the 18 domain test packages ← ProjecturedTest
```

- [package/kernel/test](../../package/ProjecturedKernelTest/src/ProjecturedKernelTest.jl) —
  kernel unit tests + the **shared generic drivers** (`test_printer`,
  `test_reader`, `test_repl`, the navigation explorers, `_walk!`) + the shared
  static `check_layering` guard. Aggregator: `test_kernel()`.
- [package/platform/test](../../package/ProjecturedPlatformTest/src/ProjecturedPlatformTest.jl) —
  the unit tests of every one of the thirty-eight slices of the platform: the
  collection and copying tests, the ground-truth selection enumerators, the
  syntax, text, graphics and layout documents, the text, graphics and widget
  projections, and the type-in and click-roundtrip drivers. Aggregator:
  `test_platform()`.
- `package/<domain>/test` — one test package per domain, holding the suites
  whose fixtures are that domain's documents: its parser, its `*ToSyntax`
  projections, its editor tests. Aggregator: `test_json()`, `test_sql()`,
  `test_xml()`, … Each also runs its package's layering guard
  (`test_json_layering()`, …).
- The console, PDF and web backends and the MCP adapter each have their own
  test package: [ProjecturedConsoleTest](../../package/ProjecturedConsoleTest)
  (`test_console()`), [ProjecturedPDFTest](../../package/ProjecturedPDFTest)
  (`test_pdf()`), [ProjecturedWebTest](../../package/ProjecturedWebTest)
  (`test_web()`) and [ProjecturedMCPTest](../../package/ProjecturedMCPTest)
  (`test_mcp()`). Each runs its package's layering guard, and its fixture is a
  JSON document where it needs one. A test that reads the whole surface of the
  application stays in the umbrella.
- The **opt-in** main packages each have their own test package, so a suite
  that needs a native backend lives with the backend it exercises (not in the
  umbrella): [package/sdl/test](../../package/ProjecturedSDLTest) (`test_sdl()` — DirtyRect,
  write_image), [package/tulip/test](../../package/ProjecturedTulipTest) (`test_tulip()` —
  the LP constraint solver), [package/video/test](../../package/ProjecturedVideoTest)
  (`test_video()` — record_video), and [package/odbc/test](../../package/ProjecturedODBCTest)
  (`test_odbc()` — the live-DB adapter + DbCatalog suites). Each one names the
  packages it uses, so it runs in its own environment, and it precompiles only
  where the native dependency (SDL2 / Adaptagrams / FFMPEG / ODBC) is installed.
  [package/ollama/test](../../package/ProjecturedOllamaTest) follows the same
  shape (`test_ollama()` — request/stream translation, a meaning-vector suite
  against a stand-in server, and two live-server tests that skip themselves
  when no Ollama server answers), but gates on a reachable server rather than
  a native library.
  [package/acp/test](../../package/ProjecturedACPTest) (`test_acp()` — the
  translation of the updates of an agent, the connection against a fake agent
  in the test process, the transport with a small child agent, and the start of
  the built-in agent) needs no network, no Node.js, no `claude` and no sign-in.
  [package/languageserver/test](../../package/ProjecturedLanguageServerTest)
  (`test_languageserver()` — the connection and the semantic tokens against a
  language server in the test process, a source file in a headless editor, and
  three tests with `clangd`, which skip themselves when it is not installed).
- [package/projectured/test](../../package/ProjecturedTest/src/ProjecturedTest.jl) — the umbrella:
  the genuinely **cross-package** suites. Two kinds live here: the sweeps over
  the interleaved `examples` / `catalog` aggregate (`ExampleSweeps`,
  `ExampleTest`, `CatalogTest`, `RecursionContract`, `MouseClick`,
  `PrinterLocality`, `test_domain_examples()`), and every suite whose **fixture
  names several domains** — `ConstructTest` (JSON, YAML and XML), the table,
  dragging, insertion, gesture, serializer and MCP suites, and the Console and
  Pdf backend tests. It `using`s every test package so `test_all()` still
  orchestrates the whole suite, and re-exports their entry points so
  `using ProjecturedTest` alone gives you `test_json()` as well as `test_all()`.

The examples follow the same split (`package/kernel/example` — the `Example`
harness core; `package/platform/example` / `package/domain/example` — the
per-package example sets with `platform_examples` / `domain_examples` registry
subsets; the
opt-in example packages — `package/odbc/example`, `package/tulip/example`,
`package/adaptagrams/example`, and `package/sdl/example` (the `LiveExample`
window/record timelines) — hold the examples that need a native dependency; the
`ProjecturedExample` umbrella keeps the `Example` registry, the gallery, the
file editor and the cross-domain compositions — a registry that names every
domain belongs to none of them). Each test package depends on its example
package: the `Example`-typed driver overloads live beside the drivers.
`test_platform()` sweeps its own package's examples; the concrete-domain sweep is
`test_domain_examples()` at the umbrella.

Each test package only depends on the main package it tests (plus the packages
below it), so every per-package suite runs without SDL, ODBC, or any other
opt-in dependency installed.

Every top-level function is *callable directly from the REPL*. There is no
hidden runner: anything `test_all` does is something you can do one piece
at a time.

```sh
cd projectured
julia --project=environment/all
```

```julia
julia> using ProjecturedAll, ProjecturedExample, ProjecturedTest
```

`ProjecturedAll` gives the names of every package in one namespace, as the
test packages and the example packages use them.

## The top-level entry point

```julia
julia> test_all()
```

Runs everything: the per-package suites (`test_kernel()`, `test_platform()`,
and one `test_<domain>()` per domain — each includes its package's static
layered-architecture guard) followed by the umbrella integration tests
(printers, readers, selections, REPL-loop tests, the MCP tool tests, and the
mouse-click / click-round-trip sweeps — see
[test/ProjecturedTest.jl](../../package/ProjecturedTest/src/ProjecturedTest.jl)).

`test_all` is a suite: a table of the per-package suites, which it runs in
sequence. Pick the one you need and skip the rest. `test_integration()`
runs the umbrella integration tests alone, and `test_repository()` the tests of
the umbrella that read this repository (the package graph). The builder has its
own test package, `ProjecturedBuilderTest` (`test_builder()`).
[The time and the memory of each part](#the-time-and-the-memory-of-each-part)
gives what each of them costs.

## A suite is a table of parts

A suite is a value of the type `TestSuite`: the name of its testset and a table
of its parts, in the order they run. A part is a function with no argument that
runs tests. An entry of the table can also be another suite, which runs as a
testset inside the testset of the suite. Call the suite to run it:

```julia
const test_json = TestSuite("ProjecturedJSON", [
    test_json_layering,
    test_json_parser,
    test_json_document,
])

julia> test_json()
```

The runner calls each part through the table, at run time, so Julia compiles a
part only when it runs. A function that names each of its parts in its body
makes Julia compile all of them before the first test runs. For
`test_platform`, that compile alone needs more than 8 GB.

Each part runs in a testset of its own, with the name of the part. So a part that
throws records an error, and the parts after it still run.

To add a test, write its function and add the function to the table of the
suite of its folder. A test that takes an argument becomes a part through a
function with no argument and a name:

```julia
TestPart(() -> test_part_click(text_example); name = "test_part_click(text_example)")
```

The runner is in
[test/kernel/runner/SuiteRunner.jl](../../test/kernel/runner/SuiteRunner.jl),
in `ProjecturedKernelTest`, so every test package can use it.

### A filter by name

Every suite takes the keywords `only` and `skip`. Each is a `String`, which
matches a name that holds it, or a `Regex`. `only` chooses the parts whose name,
or the name of a suite that holds them, matches it. `skip` leaves out each part
and each suite whose name matches it:

```julia
julia> test_platform(only = "widget")             # the parts with "widget" in their name
julia> test_all(only = "ProjecturedJSON")          # the whole suite of JSON, inside test_all
julia> test_kernel(skip = r"^test_(agent|llm)")    # the kernel without the agent and model parts
```

A walk over the examples takes the same keywords, and matches the names of its
examples: `test_printers(only = "json")` walks the examples whose name holds
`json`, and `test_catalog(only = "json/")` the JSON atoms of the catalog. A new
walk filters its list with `select_by_name(examples; only, skip)`.

Each part has a level, `:fast` or `:slow`. A slow part has
`TestPart(test_printers; level = :slow)` in its table. `test_platform(level = :fast)`
leaves the slow parts out, `level = :slow` runs only them, and the default,
`level = :all`, runs both. The supervisor takes `--level fast`.

The slow parts are those that took more than 60 s in the record of a whole run:
the walks over every example and over the catalog, the click walks, the workloads
of a window, and a few large suites. After a change, run the narrowest test, then
`test_changed(level = :fast)`. Before a land, run all the parts: `test_all`, the tests that
read this repository, and the suites of the CI that `test_all` does not call. Run them in
`bwrap --unshare-net`, so that no part reaches a model:

```bash
julia --project=environment/all tool/run-tests.jl --workers 2 --record /var/tmp/all.tsv \
    ProjecturedTest test_all ProjecturedTest test_repository \
    ProjecturedOpenRouterTest test_openrouter ProjecturedConsoleTest test_console \
    ProjecturedPDFTest test_pdf ProjecturedWebTest test_web ProjecturedMCPTest test_mcp \
    ProjecturedSDLTest test_sdl ProjecturedTulipTest test_tulip ProjecturedVideoTest test_video \
    ProjecturedODBCTest test_odbc ProjecturedBuilderTest test_builder
```

`main` is green: this run gives no unmarked `Fail` and no `Error` there, and each part
ends with the result `done`. So the land of a branch needs the same.

### Worker processes and a time limit

`tool/run-tests.jl` runs the parts of one or more suites in worker processes.
The script loads no package; each worker loads the test packages and runs one
part at a time:

```bash
julia --project=environment/all tool/run-tests.jl ProjecturedPlatformTest test_platform
julia --project=environment/all tool/run-tests.jl --only widget --record /var/tmp/w.tsv \
    ProjecturedPlatformTest test_platform
```

Each part gets a time limit: the `limit` of its entry, such as
`TestPart(test_catalog; limit = 20 * 60)`, or else the `--limit` of the run, 600 s
by default. At the limit, the worker prints its stacks, the supervisor stops it,
records the result `timeout`, and starts a new worker for the next part. A worker
over its `--memory` stops. A worker grows with each part that it runs, so its part
runs once more in a new worker, and a second stop gives it the result `memory`. A
worker that ends during a part gives the part the result `crash`. So a part that hangs costs its limit, and no result of
another part is lost. At the end, the supervisor prints a summary, the parts
that did not pass, and the ten slowest parts. Its exit code is 0 when each part
ended and passed. `--help` gives the options.

`--workers N` runs N workers at the same time, each on the next part of the
queue. The first worker loads the packages and lists the parts before the
others start, so only one process precompiles. N is at most the CPUs that the
supervisor may use, divided by the `--threads` of a worker; under
`taskset -c 24-27` with `--threads 2`, that is two. Each worker gets
`--heap-size-hint` from `--memory`, so the memory of the run is about N times
`--memory`. A part that needs the machine to itself, such as a test that
measures time or one that needs every thread, has `is_alone = true` in its entry:
it waits until no other part runs, and no part starts beside it.

### The memory of the workers

A worker loads only the test package that defines its parts, so a worker of a small
package stays small. When the parts of a package are done, its worker ends, and a new
worker takes the next package. With `--workers auto`, the count of the workers follows
the CPUs and the memory of the run:

- `--memory-from PATH` gives each worker 1.25 times the peak of the parts of its package
  in the record `PATH`, at least 1.5 GB and at most `--memory`. `--memory-from auto` takes
  the peaks from the stored records of `main` (see "The stored records of main").
- The memory of the run is the cap of the cgroup of the supervisor less 1 GB, or
  `--memory-total SIZE`. A new worker starts when its memory fits beside the workers that
  run, or when no other worker runs.
- A worker has the highest OOM score of its process tree. So when the run passes its cap,
  the kernel stops a worker and not the supervisor, and the part runs again.
- When the environment names a job whose cap can grow (`BOUNDED_RUN_JOB` and
  `BOUNDED_RUN_BIN`), and a worker does not fit, the supervisor asks that tool for the
  memory that it lacks.

### The parts of what changed

`test_changed()` runs the parts of `test_all` that the changes since `main`
reach: the committed changes of the branch, the changes that are not committed,
and the new files. `test_changed(base = "HEAD~3")` takes another base, and the
supervisor takes `--changed main`:

- a changed test file reaches its own parts;
- a changed file of a package reaches the tests of the package and of each
  package of the repository that uses it, by the `[deps]` of the `Project.toml`
  files, so a change of the kernel reaches every package;
- inside the platform, a changed file of a slice reaches the tests of the slice
  and of the slices that use it, by `PLATFORM_SLICE_EDGES`, in place of all the
  tests of the platform.

It prints the changed files and the test folders that they reach. It is a quick
check after a change. Run the whole suites before a land.

The supervisor chooses more narrowly when a map of what each part runs is stored. A
run with `--coverage FOLDER` writes, for each part, the lines that it executes, and at
the end the map `FOLDER/map.tsv`. The map of a commit of `main` is stored in
`~/.cache/projectured-test-coverage/<repository>/<the first 12 characters of the
commit>/map.tsv`, or under the folder that `PROJECTURED_TEST_COVERAGE_STORE` names.
With `--changed BASE`, the supervisor takes the stored map of the newest commit at or
before the fork from `BASE`, and runs:

- each part that executed a changed line;
- for a changed signature or docstring, and for a new method, each part that executed a
  method of that name;
- for a changed test file, a new file, and a change outside a function, such as a
  `struct` or a `const`, the parts of the folders of the changes, as above.

The changes then count from the commit of the map, so an older map chooses more parts.
When no map is stored, the folders of the changes choose the parts. `--coverage-map
PATH` takes another map, and `--coverage-map none` the folders only.

### The stored records of main

After a run, the supervisor stores its records when the run is of one commit with
no change that is not committed: in
`~/.cache/projectured-test-records/<repository>/<commit>.tsv`, or under the folder
that `PROJECTURED_TEST_RECORDS` names. A later run of the same commit replaces the
records of the parts that it runs again. So the record of the run before a land is
the record of `main` when the land moves `main` to that commit. A run of a branch is
then compared with the stored record of the commit where the branch left `main`. The supervisor
prints each part whose result or counts changed, and each new part. So a run of
a branch needs no run of `main` beside it, when a run of that commit of `main`
stored its record. `compare_records(base, other)` of `test/kernel/runner/TestSupervisor.jl`
compares two record files; `include` that file in the REPL to call it.

### A session that stays open

`--stay FOLDER` keeps the workers open. Each worker loads Revise first when the
environment has it, so after an edit a run needs no new load:

```bash
julia --project=environment/all tool/run-tests.jl --stay /var/tmp/my-session &
julia --project=environment/all tool/run-tests.jl --send /var/tmp/my-session \
    --only widget ProjecturedPlatformTest test_platform
julia --project=environment/all tool/run-tests.jl --send /var/tmp/my-session --stop
```

`--send` writes the other arguments as a request into `FOLDER/requests`, waits
for its end, prints its output, and gives its exit code. Before each request,
each worker applies the changes of the files with Revise. When Revise can not
apply a change, that worker stops and a new one starts, which loads the files
again; `--restart` in a request starts new workers in any case. The output, the
record and the exit code of a request stay in `FOLDER/results`.

The session keeps a worker for each package, so the next request of the same
package needs no load. When a new worker needs memory or a place, the worker that
waited the longest ends. A request takes `--memory-from` and `--coverage-map` from the
session when it gives none.

In the REPL, Revise does the same for a person: `test_platform(only = "widget")`
runs again after an edit, with no new load.

### The compiled code of the tests

The code of the tests compiles again in each new process, and most of the time of a
part is that compile: a run of `test_json` took 118 s, of which 111 s was compile.
So each test package records the calls that its parts compile into
`precompile/workload.txt` in its folder, and its package image holds them
([compile-ahead.md](../design/compile-ahead.md), Decision 11). Its workload, which
`@compile_ahead` at the end of its entry file names, is all of its parts. With its
recorded calls, the parts of `test_json` take 7.6 s, of which 0.3 s is compile.

`tool/record-test-calls.jl` records the given test packages, or each test package
whose files changed since a commit, each after the test packages that it depends on:

```bash
julia --project=environment/all tool/record-test-calls.jl ProjecturedJSONTest
julia --project=environment/all tool/record-test-calls.jl --changed main --list
```

A list records again as U5 of that design says, and after each land that changes
the files of its package. A stale list does not change the result of a test: a call
that it does not hold compiles while the part runs, and a list of which more than
10 % no longer resolves gives a warning when its package loads.

## Per-package tests

| Function | What it covers |
|---|---|
| `test_kernel()` | The whole kernel suite: `test_cell()`, `test_document_contract()`, `test_reference_builder()`, `test_gesture_binding()`, …, plus the kernel layering guard. |
| `test_platform()` | `test_collection()`, `test_syntax()`, `test_text()`, `test_graphics()`, `test_syntax_to_text()`, `test_text_to_graphics()`, the widget projection suites, the layering guard of every slice of the platform, and the package's example printer sweep (`test_platform_examples()`). |
| `test_json()` … `test_yaml()` | One per domain package: that domain's documents, parser and projections, plus its layering guard. The bare name is the package aggregator; a single file's suite carries a more specific name (`test_json_document()`, `test_graph_projection()`). `test_database()` is the domain aggregator like the rest; the ODBC live-connection suite is the separate `test_odbc_database*` family (`test_odbc_database()`, `test_odbc_database_connection()`, `test_odbc_database_no_db()`). |
| `test_domain_examples()` | A printer sweep over every concrete-domain example. Umbrella, because the registry it walks names all eighteen. |
| `test_text_gutter()`, `test_text_folding()` | The gutter of a block of lines and its alignment, and the text folds: a closed fold hides its lines after its first, the numbers count the hidden lines because `TextLineNumbering` stands before `TextFolding` in the chain, and a click on a triangle of a syntax node toggles the node (in `ProjecturedPlatformTest`). The example `syntax_folding` is that chain on syntax with `text_folds`, so the example sweeps walk it. |
| `test_help()` | the help slice's suite: the layering guard, the docstring description, and the two lists and the page that the Help menu opens. |
| `test_cell()` | The reactive cell primitive (in `ProjecturedKernelTest`; run inside `test_kernel()` or standalone). |
| `test_cell_struct()` | The `@cell_struct` transparent-Cell struct codegen that `@document`/`@iomap`/`@projection` build on (in `ProjecturedKernelTest`; run inside `test_kernel()` or standalone). |
| `test_cell_struct_plan()` | The `CellStructPlan` parse and the positional constructors, called on expressions (in `ProjecturedKernelTest`; run inside `test_kernel()` or standalone). |
| `test_documents()` | The umbrella-only document suites (`test_constraint_solver()` — Tulip, `test_serialization()` — example fixtures). |
| `test_projections()` | The umbrella-only projection suites (example/editor/SDL-coupled: tooltip, hover, dragging, write_image, …). |
| `test_printers()` | Runs `test_printer` over every entry in `examples`. |
| `test_text_runs_hold_no_break()` | Walks the document, the stage outputs and the IO maps of every entry in `examples`, and rejects a `TextString` that holds a `'\n'`: a break is the start of a line. |
| `test_text_blocks_hold_only_lines()` | Walks the same, and rejects an element of a `TextBlock` that is no `TextLine`: a text is a block of lines. |
| `test_readers()` | Runs `test_reader` over every example. |
| `test_position_navigations()` | Runs `test_position_navigation` (position/caret BFS, no-error sweep) over every example. |
| `test_position_navigations_complete()` | Over a curated subset, additionally asserts navigation reaches every position enumerated from the document (`collect_position_selections`). |
| `test_tree_navigations_complete()` | Same idea for whole-element/structural selections (`collect_tree_selections`); curated to the native syntax tree. |
| `test_repls()` | Runs `test_repl` (full read-eval-print loop) over every example. |
| `test_text_navigation_invariants_all()` | Runs `test_text_navigation_invariants` (walk the cursor end to end, rightwards from Ctrl+Home and leftwards from Ctrl+End, and cross-check the two walks) over every example with a text pipeline. |
| `test_typeins()` | Runs `test_typein` (type a character at every cursor position of every string and check the edit) over the supported field-addressed examples. About three minutes. |
| `test_mcp_tools()`, `test_mcp_resources()` | MCP server tools and resources. |
| `test_mouse_clicks()` | Mouse-click round-tripping. Run by `test_all`. |
| `test_catalog()` | Runs printer/reader/repl (+ position-navigation on `:graphics`) over the **generated** atomic-example catalog — see below. Run by `test_all`. |

`test_kernel()` also runs the tool, llm and agent suites under
[test/kernel/tool/](../../test/kernel/tool/DeclaredApiTest.jl) (the declared API a model
may call, search by name/pattern/description, and `execute_julia_code!`),
[test/kernel/llm/LlmDefaultsTest.jl](../../test/kernel/llm/LlmDefaultsTest.jl) (the
fallbacks of the provider contract) and
[test/kernel/agent/AgentDefaultsTest.jl](../../test/kernel/agent/AgentDefaultsTest.jl) (the
inbound agent-server seam) with
[AgentLoopTest.jl](../../test/kernel/agent/AgentLoopTest.jl) (the agent loop) — this
table does not name them individually.

## The time and the memory of each part

`test_all()` calls 82 parts. Two runs on 2026-09-25 measured each part alone, in
a process of its own, so the peak memory of a process is the peak of one part.
The table gives each part that took more than 60 s or more than 1.5 GB in one of
the two runs. Each other part took less than 60 s and less than 1.5 GB.

| Part | Time | Peak memory | Allocated |
|---|---|---|---|
| `test_catalog()` | 556–666 s | 1.6 GB | 46 GB |
| `test_position_navigations()` | 379–392 s | 1.4 GB | 368 GB |
| `test_platform()` | 250–365 s | 4.3 GB | 20 GB |
| `test_typeins()` | 175–212 s | 1.0 GB | 231 GB |
| `test_application()` | 158–174 s | 2.2 GB | 18 GB |
| `test_text_navigation_invariants_all()` | 128–150 s | 1.1 GB | 72 GB |
| `test_repls()` | 129–149 s | 1.2 GB | 20 GB |
| `test_natural_renders_every_atom()` | 110–146 s | 1.2 GB | 14 GB |
| `test_natural_round_trips_every_atom()` | 80–117 s | 1.1 GB | 9 GB |
| `test_evaluator_toplevel()` | 58–101 s | 1.8 GB | 6 GB |
| `test_kernel()` | 91–99 s | 2.5 GB | 8 GB |
| `test_click_roundtrips()` | 90–99 s | 1.1 GB | 45 GB |
| `test_readers()` | 88–95 s | 1.1 GB | 9 GB |
| `test_tree_navigations()` | 90–93 s | 1.2 GB | 12 GB |
| `test_domain_examples()` | 83–93 s | 1.2 GB | 10 GB |
| `test_printers()` | 83–86 s | 1.2 GB | 9 GB |
| `test_sql()` | 74–82 s | 1.7 GB | 7 GB |
| `test_mouse_clicks()` | 71–72 s | 1.1 GB | 7 GB |
| `test_projections()` | 59–63 s | 1.5 GB | 6 GB |
| `test_chart()` | 40–45 s | 1.9 GB | 4 GB |
| `test_graph()` | 34–38 s | 1.7 GB | 3 GB |

- **Time.** The sum over the 82 parts was 72 and 70 minutes. The load of
  `ProjecturedTest` takes about 8 s in each process, so about 11 minutes of the
  sum is load. The first process after a change of the source also precompiles
  the changed packages, which adds up to two minutes.
- **Memory.** Each peak includes about 0.75 GB for the loaded packages. No part
  needed more than 4.5 GB, so a cap of 8 GB on each process is enough.
- **Allocation.** `test_position_navigations()` and `test_typeins()` allocate the
  most, and spend 43 s and 28 s in garbage collection. Their objects are short
  lived, so their peak stays under 1.5 GB.
- **Noise.** Other work ran on the machine, with a load average from 2 to 24 on
  32 CPUs. The time of a part changed by up to 43 % between the two runs. The
  peak memory changed by at most 220 MB.

### The record of each part

The runner measures each part that it runs. When a part ends, it prints one line
with the counts and the times of the part. At the end of the outermost suite, it
prints the ten slowest parts:

```
  part ProjecturedPlatform/test_text: 412 pass, 0 fail, 0 error, 0 broken, 3.2 s, compile 1.1 s
```

To keep the numbers, give a record file. The runner adds one line for each part
to it, as tab-separated values:

```julia
julia> test_platform(record = "/var/tmp/platform.tsv")
julia> records = read_part_records("/var/tmp/platform.tsv")
```

The columns are the fields of `PartRecord`, in the order of
`PART_RECORD_COLUMNS`:

| Column | What it holds |
|---|---|
| `repository`, `commit` | The checkout of the first part, and its commit, with a `+` when the tree has changes that are not committed. |
| `suite`, `part` | The path of the suites that hold the part, such as `Projectured/ProjecturedPlatform`, and the name of the part. |
| `pass`, `fail`, `error`, `broken` | The counts of the part. |
| `result` | `done` for a part that ended. |
| `seconds`, `compile_seconds`, `gc_seconds` | The time of the part, the time of the compile while it ran, and the time of the garbage collection. |
| `allocated_bytes` | The memory that the part allocated. |
| `live_bytes`, `peak_bytes` | The memory that the last garbage collection kept, and the peak resident memory of the process so far. |

The times depend on the load of the machine. The compile time, the garbage
collection time and the allocated bytes depend much less on it.

## The generated example catalog

Alongside the hand-authored `examples` registry there is a **generated catalog** of
atomic examples (`ProjecturedExample.catalog()`), built to give broad, cheap coverage of
every domain's projections. Its *documents* are hand-authored — one meaningful instance
per document type: the atomic **leaves** (a JSON scalar, a primitive, …) and a minimal
non-empty **compound** for each node type (`JsonArray(JsonNumber(1))`,
`JsonObject("a" => JsonString("x"))`), in each domain's `example/document/*.jl` file,
registered as an `AtomicDocument(:domain, "name", make_document)`. Its *projections* are
**discovered**: for each atomic document the catalog finds the trivial single-step
projection, then a projection to `:text`, then one to `:graphics` (via a small set of
whole-tree bridges), and emits one `Example` per reachable variant. A compound's syntax
variant uses the domain's whole-tree **dispatching** projection (a bare node projection
has no recursion to project its children), not the trivial single-step leaf.

Each entry is a plain `Example` whose `name` is a hierarchical **`domain/name/variant`**
path — the name doubles as the filter:

```julia
julia> catalog()                                  # every generated Example (~315)
julia> catalog(; domain = :json)                  # one domain
julia> catalog(; document = "string")             # one document across domains
julia> catalog(; terminal = :graphics)            # everything runnable on screen
julia> catalog(; only_runnable = true)            # :text (console) + :graphics (screen)
julia> run_example(only(catalog(; domain=:json, document="null", terminal=:graphics)))
```

The `variant` is the projection's terminal domain, and it sets *which tests apply*:
`:syntax` runs printer/reader/repl; `:text` / `:graphics` also add position-navigation
(caret geometry needs the graphics layer, so navigation routes to `:graphics`). Run the
whole thing, or any slice, with `test_catalog`:

```julia
julia> test_catalog()                             # all applicable testers over the catalog
julia> test_catalog(; domain = :julia)            # just one domain
julia> test_catalog(; testers = (test_printer,))  # just one tester
```

A domain is included once its leaf projections are **bidirectional and navigable**. The
catalog covers every domain that has a registered `AtomicDocument` — run
`catalog(; domain = :formula)`, or any domain symbol, to see one — plus the platform's
atoms (primitive, collection, graphics, layout, syntax, text, widget), including the
opaque display leaves (their introduced-text carets collapse to a
bounded `proj(p, …)` position, navigable but non-editable) and the self-modifying
`*Nothing` / `*Insertion` documents (whose syntax variant uses the domain's dispatching
projection, since a bare leaf can't reproject a type swap). It covers a minimal non-empty
**compound** for *every* node type too — the whole document grammar of each domain (json
array/object/object_entry, all the julia AST nodes, all the sql clause/statement nodes, the
markdown blocks/inlines, …) — so every projection is exercised, not just the leaves.
`process` is the one domain with no generated atoms; its examples are hand-authored instead.

**No document type is skipped.** A node whose projection still has a bug stays in the catalog
with its failure recorded `@test_broken` — the failure is *information* (a real bug to fix),
keyed on its signature so a *different* failure still surfaces as an unmarked `Fail` (a
regression). The open bugs are `grep "@catalog-broken"` in
[CatalogTest.jl](../../test/projectured/projection/CatalogTest.jl). See
`plan/**/catalog-{deferred,compound,all}-*.md` for how the atoms were added.

**A new printer brings its atom.** A change that adds a `print_document` method for a
document type with no atom also adds the atom: a function that makes one instance that a
test can use, and its `AtomicDocument` row. The catalog is a test instrument, not a thing
that a person sees, so a part of a page and a document of a process get an atom too; the
atom of a task comes from a step that has not run, so a test starts no process. A printer
of a cell layout of a document counts for that document. `test_catalog_coverage` finds a
printer with no atom and fails for the change that adds it. Only a type that no test can
make goes on its list `_NO_ATOM`, with the reason. A projection that a test defines for
its own fixture is no stage of the catalog.

**The atoms of another package.** `catalog(atoms; natural = false, …)` takes any list of
atoms, such as those of another repository, and gives their projections by the same
search. With `natural = true`, each atom also gets the variant `domain/name/natural`: the
projection that an editor makes for the document when it gets none
(`make_document_projection`), the one that the app uses. A view that prints widgets reaches
the screen only through it. The testers run on any list of examples with
`test_catalog_examples(examples; testers, marks)` of `ProjecturedPlatformTest`, where
`marks` names the known failures of each kind of tester by the name of an example, and
the guard runs on any list of atoms with `test_atom_coverage(atoms; roots, no_atom)`,
where `roots` names the modules whose printers the atoms cover, such as `("Omnet",)`.
`test_catalog()` and `test_catalog_coverage()` call them with the atoms and the known
failures of this repository.

```julia
julia> examples = catalog(atoms; natural = true)
julia> test_catalog_examples(examples; testers = (CATALOG_TESTERS..., test_part_click))
julia> test_atom_coverage(atoms; roots = ("Omnet",), no_atom = Set{String}())
```

## A test that checks the root of a built editor

`build_editor` applies the wrappers that are on by default, and the platform has
three: `tabs`, `appearance` and `settings`. Each puts a document around the root.
A test that checks the root document after `build_editor`, or the depth of a
selection path, turns them off: `tabs = false, appearance = false,
settings = false`. A keyword that is off and that no loaded package declares is
ignored, so a test of the kernel alone can pass them too.

With the `settings` wrapper on and no `Settings` given, the settings read the
values of the editor and of its backend when the editor starts, so a test that
gives `build_editor` a `fault_policy`, or a backend its keywords, keeps them.

## Testing a single example

Each example-level test is also defined for a single `Example` or a labelled
`(document, projection)` pair:

```julia
julia> test_printer(json_example)
julia> test_reader(json_example)
julia> test_position_navigation(json_example)                 # no-error position BFS
julia> test_position_navigation(json_example; check_reaches_all=true)  # + reaches every enumerated position
julia> test_repl(json_example)
julia> test_typein(json_example)                               # every caret of every string
julia> test_typein(json_example; positions=:ends)              # just the boundary carets + one interior
julia> test_text_navigation_invariants(json_example)                  # end-to-end cursor walk, both directions

julia> ex = widget_example;
julia> test_printer("widget", ex.document, ex.projection)
```

`test_text_navigation_invariants` is the linear counterpart to `test_position_navigation`'s
BFS: it walks a single cursor from one end of the text to the other and back, so a
direction that skips a caret or stalls partway is caught. Several examples are known
to fail the leftward walk; the sweep marks those `@test_broken`, but a bare
single-example call does not. Pass `broken=get_navigation_broken(example.name)` to see one
example exactly as the sweep does:

```julia
julia> test_text_navigation_invariants(json_example; broken=get_navigation_broken("json"))
julia> test_text_navigation_invariants(json_example; directions=(:left,))   # one walk, while debugging
```

`test_example(ex)` bundles printer + reader + repl + text-navigation + typein
for one example — useful when you have just added a new domain and want a single
command to exercise it.

Each example-level test emits **one `@test` per unit verified** rather than a
single `isempty(errors)` assertion, so the pass count reflects the work done:
`test_printer` asserts once per forced reactive cell, `test_reader`/`test_repl`
once per event, `test_position_navigation` once per reachable selection state, and
`test_typein` once per cursor position of every string. A failing unit names the
offending cell/event/state/reference in a `@warn`.

## What each generic driver checks

The tables above say *what each driver runs on*; this section says *what it
actually asserts*. Every entry is the same four fields — **Seed** (the starting
state and what, if anything, it enumerates), **Drive** (how it exercises the
editor), **Asserts** (the invariant, at the `@test`-per-unit granularity from the
section above), and **A failure means** (how to read a red result). All of these
are example-driven: the single-example call and the `examples`/`catalog` sweep run
the identical algorithm.

### Print-based drivers

**`test_printer`** — the projected output evaluates without error.
- **Seed:** `print_document(projection, document)` once → an iomap.
- **Drive:** `_walk!` reflexively descends every field of the iomap (`fieldnames`/`getfield`), follows every `Vector`, and forces every reactive `Cell` with `c[]`; cycles are broken by `objectid`, and the walk is capped at depth 100 / 500 000 nodes.
- **Asserts:** one `@test` per forced `Cell` (and per `getfield`) — that forcing it does not throw. Hitting the depth/node cap is reported as `@info`, not a failure (lazy/large documents don't fail the test).
- **A failure means:** a cell in the projected output errors when evaluated, or a field is unreadable — a broken printer or iomap.

**`test_reader`** — every gesture is handled without crashing.
- **Seed:** clear the selection, print once → iomap.
- **Drive:** fire every event in `_ALL_READER_EVENTS` (every key symbol × {ctrl on/off}, key repeats, `KeyUp`, printable `KeyPress`; mouse down/up/press/move/scroll at sample coordinates) through `read_intent(projection, nothing, Intent(event), iomap)`.
- **Asserts:** one `@test` per event — that `read_intent` *returns* (any value, `nothing` included) rather than throwing. It does **not** inspect the intent's content — only that no event makes the reader blow up. A `broken` predicate can mark known-failing events `@test_broken`.
- **A failure means:** some gesture throws inside the reader.

**`test_repl`** — the full read→eval→reprint loop is stable under every gesture.
- **Seed:** clear the selection, print once → iomap.
- **Drive:** for each event, run the whole cycle: `read_intent` → if the op is non-`nothing`, `evaluate_operation` on a stand-in `_ReplEditor` (which picks up whole-document swaps) → re-`print_document` → `_walk!` the new output. The iomap threads forward into the next event exactly as the real editor loop does.
- **Asserts:** one `@test` per event — the entire read→evaluate→reprint→walk cycle completes without throwing and every cell in the reprinted output forces cleanly.
- **A failure means:** an operation fails to apply, or leaves the document in a state that can't be re-projected or forced: a reader, operation or printer mismatch. This check is strictly stronger than `test_reader`.

### Navigation drivers

The two BFS drivers share one engine (`explore_selections` / `test_navigation`); they differ only in the **seed gesture** and **nav-key set** they're preset with, and in the ground-truth enumerator used for the coverage check.

**`test_position_navigation`** — caret navigation is closed and (optionally) complete.
- **Seed:** fire `Ctrl+Home`; the first selection is the resulting `ReplaceSelectionOperation.path`.
- **Drive:** BFS over selection states. At each state: set the selection, reprint, `_walk!`; then try each `POSITION_NAVIGATION_KEYS` gesture (arrows, Home/End, Ctrl+arrows, Ctrl+Home/End) via `read_intent`, enqueuing every new target path (deduped modulo type checkpoints via `strip_reference_types`) not yet visited.
- **Asserts:** one `@test` per reachable state (its reprint + walk don't throw), plus `@test state_count > 0`. With `check_reaches_all=true`: additionally one `@test` per selection enumerated by `collect_position_selections(document)` asserting it was reached (subset check: *enumerated ⊆ reachable*), plus `@test !isempty(enumerated)`.
- **A failure means:** a navigation gesture throws, a reached state can't be reprinted, or, in completeness mode, navigation can't reach a caret the document actually has. The last case is the caret motion stuck or leaking.

**`test_tree_navigation`** — the same, for whole-element (∅) structural selections.
- **Seed:** `Ctrl+Alt+Home`, which selects the root ∅.
- **Drive:** identical BFS, but with the `TREE_NAVIGATION_KEYS` (Alt+arrow) structural moves.
- **Asserts:** same shape (one `@test` per reachable whole-element state; `state_count > 0`; optional *enumerated ⊆ reachable*), against `collect_tree_selections` — or a projection-aware enumerator for domains whose document is not a native syntax tree (e.g. JSON passes `collect_json_tree_selections`, mirroring `JsonToSyntax`'s decomposition).
- **A failure means:** structural navigation throws or can't reach an enumerated node.

**`test_text_navigation_invariants`** — linear cursor walks are chains and agree both ways. This is the *linear* counterpart to the position-navigation BFS: a BFS proves reachability but hides a direction that skips or stalls; this catches it.
- **Seed / Drive:** two walks. **Right:** seed `Ctrl+Home`, step `:right`. **Left:** seed `Ctrl+End`, step `:left`. Each fires its seed, then repeats its step — reprinting between moves — until the reader declines the step (edge of text), the step is a fixed point (edge), or it lands on an already-visited state (cycle).
- **Asserts:** *per direction* — the walk ran without error, `terminated` on its own (not by exhausting `max_steps`), never revisited a state (`cycle === nothing`, i.e. it is a chain), and moved at least once (`length(paths) > 1`). *Cross-direction* — both walks visit the same caret count (`:same_length`), the right walk ends where `Ctrl+End` lands, and the left walk ends where `Ctrl+Home` lands. Exact caret-*sequence* equality is deliberately **not** asserted: at a line boundary the same logical caret renders in two places and the two directions canonicalize to different ones.
- **A failure means:** a direction skips a caret, stalls partway, loops, or the two directions disagree on caret count / endpoints — a directional asymmetry invisible to the BFS.

### Editing drivers

**`test_typein`** — typing and deleting at every caret lands the right string and caret.
- **Seed:** collect every string reference reachable in the document.
- **Drive:** for each string, at each character boundary `0…n` (policy `:all` / `:ends` / `:first`), run three edits in order — **insert** (`KeyPress`), **backspace** (`KeyDown(:backspace)`), **delete** (`KeyDown(:delete)`). Each edit sets the cursor at the boundary, drives the event through the reader, evaluates it, then restores the string to pristine before the next edit (so each edit starts from the same string).
- **Asserts:** per `(string, position, edit)` — the caret **renders** in the Graphics image; the resulting string equals the expected edited string; and the post-edit caret is where it belongs (insert → `k+1`, backspace → `k−1`, delete → `k`). At a declined boundary (backspace at `0`, delete at `n`) the reader must produce **no** edit, and the walk asserts that decline without evaluating anything. A string that can't be restored ends that target (the rest of the document walk continues).
- **A failure means:** an edit at some caret produces the wrong string or wrong caret, a character lands in neighbouring chrome (the boundary carets `0`/`n` are what catch this), or the caret fails to render.

**Structural insert-by-typing** — turning a *nothing* placeholder into a real document.
- **Today:** `test_document_insertion()` is a *domain-specific* suite (in [DocumentInsertionTest.jl](../../test/projectured/projection/DocumentInsertionTest.jl)), **not** example-driven. It asserts the insert-by-typing machinery directly: the factory/completion functions (`default_factory`, `default_completion`), the reflection-derived insertion names and resolution (`DomainModule.get_insertion_names` / `resolve_insertion`), the completion states (`:empty` / `:invalid` / `:unambiguous` / `:ambiguous`), and that typing a domain name into a `DocumentInsertion` commits the corresponding `document/insertion`.
**Live example construction** — rebuilding a whole document from nothing by typing.
- **`test_construct` / `test_json_construct`** (engine in [ConstructTest.jl](../../test/projectured/editor/ConstructTest.jl); the oracle `compare_content` lives in the kernel test) are the *reachability* counterpart to `test_typein`: seed the domain's empty `*Nothing` placeholder, drive the editor's own gestures to rebuild a target document from scratch, then assert the result equals the target **by content**.
- **Drive:** recurse over the *target's* structure — a leaf is authored by typing its surface (opening delimiter + value; the closing delimiter is projection chrome, so it is not typed), a container by its kind-selecting keystroke (`[`/`{`/digit/`"`/…) followed by navigating to each child slot (programmatic ∅ selection) and recursing. Every keystroke goes through the real `read_intent → evaluate_operation` loop.
- **Asserts:** `compare_content(reached, target)` — a strict recursive content-equality (types compared by name, cells unwrapped, `:selection`/`:ref` skipped) that returns the **first mismatch path** (`.field` / `[i]`), or empty when equal. Strict on scalar type, so `42 ≠ 42.0`.
- **A failure means:** an editor authoring gap (a kind with no gesture recipe), a reader/operation bug (wrong shape or non-inverting leaf), or a located content regression. Covers JSON scalars and arrays today; the cross-domain `test_construct(example::Example)` sweep is still pending (see [plan/pending/live-example-construction.md](../../plan/pending/live-example-construction.md)).

> Two more generic example drivers, out of scope for the list above but built the same way, are documented in [ClickRoundtripTest.jl](../../test/platform/editor/ClickRoundtripTest.jl) and [MouseClickTest.jl](../../test/projectured/editor/MouseClickTest.jl): `test_click_roundtrip` / `test_mouse_click_roundtrip` fire a click at each rendered character cell and assert the resulting selection lands in, or immediately beside, the clicked cell. This is the pointer-side inverse of the caret-rendering that `test_typein` checks.

## The walker helpers (non-`@testset` variants)

When you want errors back as a `Vector{String}` instead of `@test` output —
e.g. you are iterating in the REPL and want to keep going on failure —
every test has a sibling that does the same work without wrapping it in
`@testset`:

| Helper | Location | What it does |
|---|---|---|
| `walk_printer_output(doc, proj)` | [kernel/test PrinterTest.jl](../../test/kernel/editor/PrinterTest.jl) | Calls `print_document`, reflexively walks every field of the resulting iomap, and forces every `Cell` via `c[]`. Returns `(errors, status)`. |
| `walk_reader_events(doc, proj)` | [kernel/test ReaderTest.jl](../../test/kernel/editor/ReaderTest.jl) | Prints once, then fires every key / mouse event in `_ALL_READER_EVENTS` through `read_intent`. Returns `errors::Vector{String}`. |
| `walk_repl_loop(doc, proj)` | [kernel/test ReplTest.jl](../../test/kernel/editor/ReplTest.jl) | The complete read → evaluate → reprint → walk cycle, repeated for every event. The closest thing to driving the real editor headlessly. Returns `errors::Vector{String}`. |
| `explore_selections(doc, proj; nav_keys, seed_gesture)` | [kernel/test NavigationTest.jl](../../test/kernel/editor/NavigationTest.jl) | The generic navigation BFS over reachable selection states, parameterized by gesture set and seed. Returns `(state_count, errors, visited)`. |
| `explore_position_selections(doc, proj[, initial])` / `explore_tree_selections(doc, proj)` | [test/platform/editor/NavigationPresets.jl](../../test/platform/editor/NavigationPresets.jl) | The two presets over `explore_selections`: position (caret) navigation keys and Alt+arrow structural navigation. |
| `collect_position_selections(doc)` / `collect_tree_selections(doc; is_node)` | [base/test SelectionEnumeration.jl](../../test/platform/document/SelectionEnumeration.jl) | Ground-truth selections enumerated directly from the document (all positions/carets / all whole-element nodes), for the completeness suites to check against. |
| `walk_typein(doc, proj; positions=:all)` | [test/platform/editor/TypeinTest.jl](../../test/platform/editor/TypeinTest.jl) | Types a character at every character boundary of every reachable string — undoing each edit so the next boundary starts from the same string — and verifies the cursor renders and the edit lands. The boundary carets (`0` and `n`) are the ones that catch a character landing in the neighbouring chrome. Returns one `(ref, position, length, ok, message)` result per (string, position); `positions=:ends` / `:first` trade coverage for time. |

`walk_printer_output`, `walk_reader_events`, `walk_repl_loop`, and
`explore_position_selections` keep their plain return values for REPL use; each also
takes an optional callback (`oncell` / `onevent` / `onstate`) that the
`test_*` wrappers use to emit one `@test` per unit.

```julia
julia> errors, status = walk_printer_output(json_example.document, json_example.projection);
julia> isempty(errors)
true

julia> result = explore_position_selections(syntax_example.document, syntax_example.projection);
julia> result.state_count, length(result.errors)
```

## The shared reflexive walker

`_walk!` (in
[kernel-test/editor/PrinterTest.jl](../../test/kernel/editor/PrinterTest.jl))
is the workhorse behind every printer-based test. It descends every field
via `fieldnames` / `getfield`, follows every `Vector`, forces every `Cell`,
and uses an `objectid` `Set` to break cycles. New document types are
covered automatically as long as their fields are reachable through the
struct.

If you write a domain that stores state outside of struct fields (e.g. in a
side table), `_walk!` will not see it; either expose it as a field or add a
dedicated test under [domain/test/document/](../../test/projectured/document).

## Validating the recursion contract

The four core projection functions (`print_document`, `read_intent`,
`map_reference_forward`, `map_reference_backward`) must each be **recursive** —
descending into children only by delegating to the child projection's own version
of the same function. That is [the recursion contract](../package/kernel/projection-system.md#the-recursion-contract),
and a load-bearing half of it is that **no fifth recursive function may be
introduced** to do the descent: the four functions are the only interface every
projection implements, so any extra recursive function would break the moment a
pipeline composed a projection that lacks it.

The same constraint binds the *validation*: it is done **externally**, by a harness
that drives the four functions over composed examples, and it must add **no new
per-projection generic function** of its own. The harness reuses the existing
walkers rather than introducing an interface method:

- **Reachability** — enumerate every reference with `collect_position_selections` /
  `collect_tree_selections` and assert `map_reference_forward` returns a non-`nothing`
  image for each. A deeply nested reference can only have an image if the mapper
  delegated all the way down; a flattening mapper drops what it never recursed into.
- **Round-trip** — `map_reference_backward(map_reference_forward(ref))` returns the
  original, a reference to a projection-introduced position included. Round-tripping
  at every level is the signature of lockstep recursion.
- **Printer lockstep** — reuse `_walk!` to reach every iomap; for any iomap carrying
  `child_iomaps`, assert each `child_iomap.output` is object-identical to the
  corresponding child of the parent output (the printer spliced delegated children,
  it did not rebuild the subtree).
- **Composition substitution** — the discriminating check: substitute the projection
  used for one child subtree (via an existing higher-order projection), and assert
  the parent output reflects it. A compliant projection delegates, so the swap takes
  effect; a flattening one ignores `recursion` and the swap is a no-op — the test
  fails. This is what flags `SyntaxToText`.

The harness lives in
[package/projectured/test/editor/RecursionContractTest.jl](../../test/projectured/editor/RecursionContractTest.jl):

| Function | What it does |
|---|---|
| `test_recursion_contract(example)` / `test_recursion_contracts()` | `@testset` running the delegation probe over the curated structural pipelines (`json`, `xml`, `syntax`, `math`). |
| `probe_delegation(doc, proj)` | Re-invokes each node projection with a spy `recursion` and reports `(projection_name, count, delegated, broken)` per node. |
| `walk_reference_roundtrip(doc, proj)` | The reachability + round-trip check, returning findings as a `Vector{String}` for REPL use. |
| `walk_recursion_contract(doc, proj)` | Both checks combined, findings as a `Vector{String}`. |

The asserted check is the **delegation probe** — the discriminating test, which adds
no per-projection generic function (the spy is an ordinary higher-order projection).
Every probed node now delegates: `SyntaxCompoundToText` was the last flattener (reached
transitively by all four examples) and the refactor in
[plan/done/syntaxtotext-delegation.md](../../plan/done/syntaxtotext-delegation.md) converted it to School A, so it is now a plain
`@test`. `test_recursion_contracts()` is opt-in (not yet wired into `test_all`); the
reference round-trip is exposed as the REPL walkers above rather than asserted,
pending calibration on a running editor.

## Scale: does a pane of 20,000 tasks stay a window?

`test_task_group_scale(; task_count = 20_000, jobs = 16)` (`ProjecturedPlatformTest`)
starts a group of `task_count` process tasks and checks P7 of the catalog of
legacy documents: a print of the pane of the group builds only the rows of a
window of 900 pixels, before and after the run, and the drains while the group
runs cost no walk of every task. It starts 20,000 processes in about 25 s, so
`test_platform` does not call it. Run it after a change of the task slice, of
the walk of the part under the pointer, or of a lazy table.

## Memory: does an editor stay flat over a cycle of gestures?

`test_editor_memory_cycle()` (`ProjecturedTest`, a slow part with a limit of 30
minutes) runs one cycle of gestures 60 times in one window of `run_application`,
on a headless backend, with an undo capacity of 10. A cycle inserts and deletes an
element of a list in a tab, opens a new file as the page of the explorer, clicks a
value of it, types a key and saves, waits until the page shows a change on disk,
opens and closes a file in a tab of its own, and opens another page and goes Back.

After cycle 20, 40 and 60 the test takes a report of what holds the memory of the
editor (`compute_held_memory`, [memory.md](../package/platform/memory/memory.md)). A
holder grows when it keeps more than 64 KiB more in each half, about 3.3 KB in
each cycle, and the gain repeats: neither half gains more than four times the
other. It takes only the gain
that the growing holders below it do not explain, so the root takes the growth
that no listed holder explains. The live memory of the process that the editor does
not reach is a line of its own, `(unreached)`, with a margin of 4 MiB, four times
the noise of two reports in a row. Each store that grows on main is an entry of
`_MC_KNOWN_GROWTH`, a part of the path of its holder with its reason. A
growth that an entry names counts as broken, and a growth that no entry names fails,
and so does an entry that names no growth. So a fix of a store removes its entry.

Run it after a change of what a view, a page, a file document or a history keeps.

## Reactivity: does the output follow the input?

`test_reactivity()` sweeps every registered example and asserts the property no
other suite can see:

> Touch a leaf of a projection's input, and something in that projection's own
> output must go invalid.

The bug it catches does not make the output **wrong**, it makes it **stale**.
Nothing errors and no assertion trips; the pixels are simply from a document that
no longer exists. Every other printer test re-prints from scratch, and a re-print
always looks correct, so this shape survives a green suite indefinitely.

It is opt-in and slow — about seven minutes over 103 examples. Do not run it to
check a one-line change; run the narrowest test as usual and leave this to a
broad sweep.

```julia
test_reactivity()                      # the whole sweep
check_reactivity(json_example)         # one example, per-node verdicts
check_structural_reactivity(json_example)   # append an element instead of writing a leaf
```

The unit is an **IoMap node**, not a document leaf, because an IoMap pairs one
projection's input with its output. A failure then names the projection that
froze rather than saying "something in this example went stale".

### The four outcomes

A node is not charged for every write. `map_reference_forward` is asked first,
and the answer determines what a non-reacting write means.

| outcome | meaning |
|---|---|
| **followed** | the surface moved; the node did its job |
| **frozen** | the leaf path maps, so the field is rendered, and nothing moved — a finding |
| **unproven** | only the document path maps; the field may have no reader, so nothing is proven |
| **carried** | the output holds the written cell itself, so the value passes through by reference and the node owes nothing |
| **not shown** | neither path maps; a filtering, searching or focusing projection drops it deliberately |

`SyntaxLeaf.indentation` is the reason `unproven` exists: the field is there, and
`get_indentation` has no method for a leaf, so nothing consults it.
`ChartToChartPlot` is the reason `carried` exists: its output wraps the live
`Chart`, so writing `chart.title` moves nothing there and nothing is stale — the
renderer one stage on reads the same cell.

### What it does not test

- **Reader-side reactivity.** This is printer-only; `test_readers` owns the
  other direction.
- **Correctness of the new value.** Only that something moved.
- **Over-invalidation.** `PrinterLocalityTest.jl` owns that bound, and shares its
  cell collector with this file. Measured across all examples, over-invalidation
  is not a problem: the median write moves 0% of a surface and the worst moves
  35%.

### Trusting the sweep

Three acceptance tests guard the harness itself, because a harness that cannot
fail reports zero whether or not anything is wrong:

- `test_reactivity_property()` — a captured value must be called frozen and a
  re-deriving output must not.
- `test_reactive_surface()` — includes the orphaning case, where a projection
  re-derives its whole output and every cell of the old tree is untouched.
- `test_structural_property()` — children built once into constant cells must be
  called frozen; the same shape as a computation must pass.

`test_verdict_stability(names)` additionally requires that the same leaves
measured forward, forward again and backward give identical counts.

## The layout rules

`test_layout_rules()` (`ProjecturedPlatformTest`, in `test_platform()`) checks
the rules of [layout-rules.md](../rule/layout-rules.md) for every widget type
and every layout type of the platform. It runs in about 16 s, most of which is
compilation, and makes 520 checks.

- Each type has a small sample with no authored size, and a kind on each axis:
  `:rigid`, `:reflowing`, `:scrolls`, `:fills`, `:authored` or `:overlay`. The
  test prints the sample in an exact, a bounded, an "at least" and a free range,
  and checks what it draws by the rule of its kind.
- A guard fails for a concrete type below `WidgetDocument` or `LayoutDocument`
  that has no kind. When you add such a type, add its sample and its kind to
  `_RULES_KINDS` in `test/platform/projection/LayoutRulesTest.jl`, or a reason
  why the type is not placed alone.
- The worked cases of [layout-rules.md](../rule/layout-rules.md) §5 are tests,
  and so is a lazy grid of ten million rows in a scroll area that grows.

Run it after a change of a printer that sizes a widget or a layout, of a scroll
area, or of a stack. Then run `test_dataframes()`. The view of a data frame sizes
its rows by the same rules, and only that suite edits a data frame in its view.

## The static guards

`test/suite/*.jl` holds the guards of the rules that a program can check. Each
reads the repository as text, loads no package, and runs in about a second:

| Function | What it guards |
|---|---|
| `test_tree()` | every top-level folder holds one kind of thing, the rule of [repository-tree.md](../../plan/done/repository-tree.md) §3. |
| `test_naming()` | the mechanical rules of [naming-rules.md](../rule/naming-rules.md): a module name against its file and its slice, an alias no file declares, a banned abbreviation, a test package's entry point, and a definition two files of one module state twice. |
| `test_arguments()` | the rule of three positional arguments of [code-quality-rules.md](../rule/code-quality-rules.md) §4, unless a `# @positional:` marker says why a definition stands over the line. |
| `test_exports()` | the rule of the export block of [code-quality-rules.md](../rule/code-quality-rules.md) §1: one `export` statement per fragment, in the order of the includes. |
| `test_documentation()` | the part of [writing-rules.md](../rule/writing-rules.md) that a program can check: a dead link, an unknown `resource://guide/…`, a document with no header or no summary, and a forbidden phrase. |
| `test_style()` | every font, color and length comes from a theme; see below. |
| `test_kernel_layering()`, `test_platform_layering()`, … | the layering guard of each package; see [Per-package tests](#per-package-tests) below. |

Each is callable alone from the REPL, and `test_all()` runs them first, before
any per-package suite.

### The style guard

`test_style()` is the style guard: a font, a color or a size that a line of
`source/` writes as a literal value, outside a theme, fails. It reads the code
as text and loads nothing, so it also runs standalone, with no environment:

```bash
julia test/suite/style.jl
```

It fails on a line of `source/` that holds:

- a font description, `StyleFont("…`;
- a color of numbers, `StyleColor(0.…`, or a color of the palette by its name
  (a constant that [Color.jl](../../source/platform/style/Color.jl) declares,
  other than `color_transparent` and `color_default`);
- a length with a number other than 0: `Inset(`, `Spacing(`, `Radius(`,
  `LineWidth(`, `ControlSize(` or `IconSize(`.

It skips a `@theme` declaration, a preset of a theme (a function whose name
ends in `_theme`), the palette and the registry of font faces
(`source/platform/style/FontFace.jl`), a docstring, a comment, and an `export`,
`import` or `using` statement.

A line that holds such a value on purpose carries the marker
`# @style: <reason>`, on that line or on the line above it: the content of a document
that its author set, a mark that is not the look of the editor, or a value
that waits for a decision of the owner. A marker on a line of its own covers
every line below it, up to the next blank line, so a table of several values
needs one marker and not one for each line. `STYLE_EXEMPT_FILES` in
`test/suite/style.jl` lists a whole file that is exempt by name, with its
reason — for example, a file whose colors wait on an open question.

## CI

[CI.yml](../../.github/workflows/CI.yml) runs on each push to `main` and on each
pull request, except a push that changes only `plan/`:

- One job runs each static guard, `test/suite/*.jl`, alone. The guards read the
  source as text and load no package, so the job takes seconds.
- One job runs the suite of each test package in its own environment, for
  example `test_json()` in `package/ProjecturedJSONTest`. A suite that uses a
  package that its `Project.toml` does not name fails there, and passes in
  `environment/all`, where AutoIntegration finds every trigger as a direct
  dependency. Two jobs run the umbrella's suite: `test_integration()` and
  `test_repository()`.
- Each job collects the coverage of the files of this repository and sends it
  to Codecov. SDL draws with `SDL_VIDEODRIVER=offscreen`, because the runner
  has no display.

To run one suite as CI runs it:

```bash
julia --project=package/ProjecturedJSONTest \
      -e 'using Pkg; Pkg.instantiate(); using ProjecturedJSONTest; test_json()'
```

## Typical workflows

- **Added a new example.** `test_printer(my_example)`, then
  `test_reader(my_example)`, then `test_position_navigation(my_example)`, then
  `test_repl(my_example)`. Once those pass, the example is automatically
  picked up by `test_printers` / `test_readers` / etc. because they loop
  over the `examples` vector.
- **Changed a projection.** `walk_printer_output` and `walk_repl_loop`
  against the affected example give you a fast failure surface; the latter
  also catches reader/operation mismatches.
- **Changed the kernel/platform/domain source layering.** The per-package
  layering guards (`test_kernel_layering()`, `test_platform_layering()`) parse
  the real `import ..XxxModule` headers and re-check the include order in ~1s.
- **Suspected reactive bug.** `test_cell()` first, then
  `walk_printer_output` (which forces every reachable cell) on the
  affected example.
- **Selection navigation bug.** `explore_position_selections(doc, proj)` returns
  every reachable state; small `state_count` numbers are often the symptom
  of caret motion stuck in place. To check *coverage*, compare against
  `collect_position_selections(doc)` (or use `test_position_navigation(ex; check_reaches_all=true)`).

See [the debugging guide](debugging-guide.md) for the matching REPL helpers
(`run_example`, `print_example`) that let you reproduce a failure
interactively before reaching for the test functions.

## Marking known-failing tests

**Invariant:** every currently-failing assertion is marked with
`@test_broken`. An unmarked `Fail` or `Error` in a suite summary is
unambiguously a regression — no bisection, no snapshot files, no counts.
Julia's `Test` stdlib partitions the summary into `Pass / Fail / Error /
Broken` columns for free.

### Marker format

```julia
# @broken: <one-line reason>[; plan/<slug>.md]
@test_broken <expr>
```

`grep -rn "@broken:" package/*/test/` enumerates every marked test
with its reason. Every `@test_broken` must have a `# @broken:` comment on
the line above — a bare marker with no context is not acceptable.

### Which pattern to use

- **Assertion-level Fail or Error inside `@test`** — convert `@test`
  to `@test_broken`. Julia catches thrown exceptions and reports them as
  `Broken` in the summary, so this handles both `Fail`s and most `Error`s.
- **Testset-setup Error** ("Got exception outside of a @test") — the
  throw happens *before* an `@test` runs. Wrap the testset body in
  `try/catch`, and emit `@test_broken (@warn "..."; false)` on catch:

  ```julia
  @testset "..." begin
      try
      # normal test body with @tests
      catch e
          # @broken: pre-existing drift; testset setup throws
          @test_broken (@warn "setup threw: $e"; false)
      end
  end
  ```

  Only the catch branch fires when the setup actually throws. If someday
  the setup starts working, the catch is skipped and normal assertions
  run — no ceremony to undo.
- **Loop with mixed pass/fail iterations** — check the outcome and
  branch:

  ```julia
  for path in paths
      back = map_reference_backward(p, iomap, forward(path))
      if back == path
          @test back == path
      else
          # @broken: <reason>; some iterations still drift
          @test_broken back == path
      end
  end
  ```

- **Sweep over examples with one broken example** — filter in the
  sweep loop and emit `@test_broken` for the broken example only:

  ```julia
  for ex in domain_examples
      @testset "$(ex.name)" begin
          if ex.name == "json_sorted"
              # @broken: <reason>
              @test_broken (print_document(ex.projection, ex.document); true)
          else
              test_printer(ex)
          end
      end
  end
  ```

- **`@test_skip` — the escape hatch.** Use only when running the code
  would crash the runner (stack overflow, infinite loop, corrupts
  subsequent tests). `@test_broken` catches thrown exceptions, but only
  after they're thrown; if throwing is destructive, `@test_skip` is
  safer. Skipped tests never run and can rot silently, so this is a last
  resort.

### A guard keeps a list of its known violations

A static guard (arguments, exports, style, documentation, the layering and the edges
between the slices) reports a list of violations. Its known violations are a list of
`key => reason` pairs beside the guard (`test/kernel/layering/KnownViolations.jl`): `ARGUMENT_KNOWN`,
`EXPORT_KNOWN`, `STYLE_KNOWN`, `DOCUMENTATION_KNOWN`, and the keyword `known` of
`check_layering` and `check_slice_edges`. The key is the text of the violation
without its line number. A listed violation does not fail the guard, and its test
counts it as broken. A violation that no entry excuses fails, and so does an entry
that excuses none: remove an entry when its violation is fixed.

### A check that fails only at some times

Do not mark such a check with `@test_broken`: when it passes, the marker is an
error. A check of a result that waits a fixed time gets a wait for its condition,
with a bound that holds under the load of a shared machine. A check of a time, or
of a ratio of times, gets `@test_skip` with a `# @broken:` reason.

### A check that depends on its process

A worker of `tool/run-tests.jl` loads every test package of the run, and runs one
part after another. So a check can pass in the environment of its own package and
fail beside the other packages, or after a part that left a global value. If the
test can set what it reads, such as the global logger, set it in the test. Otherwise
skip the check with `@test_skip` where it fails, with a `# @broken:` reason that
names the package or the state that changes its result.

### `@test_broken` semantics you should know

- If the expression evaluates `false` or **throws**, it registers as
  `Broken`.
- If the expression evaluates `true`, it registers as
  `Error: Unexpected Pass` — the automatic signal to promote the
  marker back to `@test`. **Do not ignore this message; it means the
  underlying issue is fixed and the marker should come off.**
- The `Broken` count is shown in a separate column of every summary, so
  the shape "N Pass / M Fail / K Error / L Broken" always has an obvious
  regression signal (`M + K` should be 0).

### Adding a new marker

1. Write a one-line reason. If a plan exists, link it. If the root cause
   is unknown, say so honestly ("pre-existing drift; no investigation
   yet") rather than inventing.
2. Verify locally that the relevant `test_*()` aggregator exits with
   `Fail == 0`, `Error == 0`.
3. If the marker fires unexpectedly on a passing iteration (`Error:
   Unexpected Pass`), narrow the marker's scope — see the loop pattern.

### Removing a marker

When a bug is fixed, `@test_broken` reports `Error: Unexpected Pass`. To
un-mark:

1. Change `@test_broken` back to `@test`.
2. Delete the `# @broken:` comment.
3. Confirm the assertion now passes cleanly.
