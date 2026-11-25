# The assistant knows its libraries, and a date is a value

**Status:** pending. Written on 2026-11-25. The owner asked for this plan
("yes, write the plan"). The proposed decisions below are approved with the plan,
when the owner approves the plan.

The plan lands nothing and pushes nothing: it ends with a request to land.

**If a step needs a change of a sealed file, or a mechanism that this plan does
not name, the work stops and the session asks.**

## The problem

The assistant of a window writes Julia code with `execute_julia_code`. Its
namespace holds Base, the names of the editor that carry the line
`For the assistant.`, and the names that an adapter registers. It holds no other
package, and its text says nothing about `using`. So the assistant writes the
usual functions of Julia again by hand, or it reaches them by a trick. The
assistant of the OMNeT++ IDE did this for its defect repairs, on 2026-11-24:

```julia
# What the assistant wrote
today_1() = Libc.strftime("%Y-%m-%d", time())          # its words: "I'll avoid Dates"
(number = 21, repaired_on = "2026-11-24", landed_on = "")    # a date as text in defects.pred
ChartLineSeries("repaired", 1:length(dates), counts)         # x is 1, 2, 3 ...
ChartAxis(names = dates)                                     # ... with the date as a label

# What it must be able to write
(number = 21, repaired_on = today(), landed_on = nothing)   # the file keeps Date("2026-11-24")
ChartLineSeries("repaired", dates, counts)                  # a time axis: 7 days are 7 days wide
```

Three gaps cause this:

1. **No usual library is in scope.** `Dates`, `Statistics`, `Printf` and the
   names of `Random` beyond `rand` are not in the namespace.
2. **A `.pred` file can not keep a date.** Its writer refuses a `Date`, so a
   `RecordTable` keeps a date as text, and the code compares text.
3. **A chart has no time axis.** The x values must be numbers. A date goes at its
   index, with the date as a label, so the steps between the points are wrong.
   The pivot line chart does the same for a cell of dates.

## The evidence

A survey of the 23 sessions of the assistant of the OMNeT++ IDE, 2026-10-29 to
2026-11-25, with 862 calls of `execute_julia_code`:

| Library | What failed | What the assistant wrote in its place |
| --- | --- | --- |
| Dates | 2 times `UndefVarError: Dates not defined in Main.ToolScratch`, with the hint "Dates is loaded but not imported" | `Libc.strftime("%Y-%m-%d", time())`, and dates as text in a table |
| Random | `import Random`: "Package Random not found in current path" | the module from `Base.root_module(Base.PkgId(…))`; the thinking first chose "my own small deterministic RNG" |
| Statistics | `isdefined(@__MODULE__, :Statistics)` was false | a mean, a correlation, a Wilson interval, a z-test and log-factorials by hand |
| Printf | — | `lpad(round(x; digits = 1), 8)` in 7 blocks |

The survey found no use of `CSV`, `readdlm`, `sha256`, `TOML`, `norm`,
`@which` or `subtypes`. Only 3 calls held a `using` or an `import`.

The result of a `using` depends on how the window starts. The `import Random`
of 2026-10-29 failed in the IDE. On 2026-11-25, a plain Julia process with the
environment of the IDE, `build/app/omnet_ide`, and the default load path
`["@", "@v#.#", "@stdlib"]` loads `Dates`, `Random` and `Statistics` in a module
such as `ToolScratch`. So the assistant can not know whether a `using` works.

## The decisions of the owner that this plan builds

- **No free load of packages: the window has the typical ones ready**
  (2026-11-25: "I'm not sure if allowing the assistant to load arbitrary packages
  is a good idea, we should instead be prepared with the typical packages").
- **A small package puts useful Julia names into the vocabulary of the
  assistant** (2026-11-25: "a small package for putting various helpful Julia
  stuff into the assistant's vocabulary is fine. Think through what would be
  generally useful in addition to what the assistant already has").
- **The assistant knows that it can not use `using` or `import`** (2026-11-25:
  "the assistant should be aware of the fact that it can't use packages via
  using/import, so it's not going to try and fail").
- **A `using` of a library that is in scope runs, and each other `using` is
  refused** (2026-11-25: "yes, change the plan", to "Shall I change decisions 3
  and 4 of the plan this way?", after the question "do you think it would be
  better to allow using/import for the assistant?").
- **One plan has three parts:** the names, the date in the `.pred` file, and
  the time axis of the chart (2026-11-25: "yes, write the plan", to "Shall I
  write one plan in `plan/pending/` with these three parts").

## Proposed decisions

The session proposes them. They are approved with the plan.

1. **One package, `ProjecturedStandardLibraries`.** Its code is in
   `source/adapter/standardlibraries/`, and its module is
   `StandardLibrariesModule`. It makes the usual values and functions of the
   standard libraries of Julia work in the editor. It gives two things: the
   names for the assistant (decision 2), and the `.pred` notation of a date
   (decision 5). Both need `Dates`, so one package holds both.
   - It is an adapter, because the rule of 2026-10-08 says that the platform
     takes no dependency that a new Julia process does not load. A new process
     does not load `Dates`, `Statistics` or `Printf`.
   - It has no third-party dependency, so it is a sub-stem, and `ProjecturedAll`
     aggregates it. So each application that loads `ProjecturedAll` has it.
   - The methods of decision 5 are methods of a function of the platform for a
     type of `Dates`. The package rules give an adapter that job, as
     `ProjecturedDataFrames` does for `DataFrame`.
2. **The vocabulary.** The package registers these names with
   `register_assistant_api!` in its `__init__`, as the DataFrames adapter does.
   The scratch module binds each module of an entry by its own name too, so
   `Dates.format` and `Random.seed!` work, although Julia does not export them.

   | Module | The names in scope |
   | --- | --- |
   | `Dates` | `Date`, `DateTime`, `today`, `now`, `UTC`, `Year`, `Month`, `Week`, `Day`, `Hour`, `Minute`, `Second`, `Millisecond`, `year`, `month`, `day`, `hour`, `minute`, `second`, `dayofweek`, `dayname`, `monthname`, `firstdayofmonth`, `lastdayofmonth`, `DateFormat`, `unix2datetime`, `datetime2unix`, `canonicalize` |
   | `Statistics` | `mean`, `median`, `std`, `var`, `quantile`, `cor`, `cov`, `middle` |
   | `Printf` | `@sprintf`, `@printf` |
   | `Random` | `Xoshiro`, `shuffle`, `shuffle!`, `randperm`, `randstring` |

   No name of the list is a name that projectured-julia or omnet-julia exports.
   The list leaves out `MersenneTwister`, because the simulator of omnet-julia
   exports a `MersenneTwister` of its own (`source/simulator/random/RandomModule.jl:26`).
   Base gives `rand`, `randn`, `round`, `Iterators` and `Libc` already.

   The libraries that the set leaves out, and why:

   | Library | Why it is not in the set |
   | --- | --- |
   | LinearAlgebra, TOML, SHA, CRC32c, UUIDs, Base64, Unicode | The survey found no use. A later session adds a library when its work needs it. TOML reads a file, and the rules of a window say that a file is read with a verb of the editor. |
   | InteractiveUtils | `@which` and `subtypes` repeat `search_api`. |
   | DelimitedFiles | It reads a file. |
   | Pkg, Downloads, Sockets, Distributed, FileWatching, Serialization, Mmap, Libdl, Profile, Logging, REPL, Test | They install code, use the network, start processes, read the disk, or belong to the editor itself. |
   | Distributions, StatsBase, HypothesisTests, SpecialFunctions | They are third-party, and a sub-stem has no third-party dependency. The statistical study of 2026-10-29 needed them. They are a later decision of the owner. |
3. **The text of the window says what is in scope.** `EDITOR_SYSTEM`
   (`source/platform/application/Application.jl:398`) replaces "Each name of the
   index is in scope by itself, so write it without its module; no package name,
   such as ProjecturedPlatform, is in scope." with:

   > Base and each name of the index are in scope by themselves, so write a name
   > without its module. The packages of the window are fixed: a `using` or an
   > `import` of a package that is not in scope is refused. No package of the
   > editor, such as ProjecturedPlatform, is in scope.

   The platform text names no library of the adapter, because the adapter can be
   absent. The description of the package names them. The text of the window
   shows it with the domains, only while the package is loaded:

   > Dates, Statistics, Printf and Random are in scope: write `today()`,
   > `Date(2026, 11, 24)`, `mean(values)`, `@sprintf("%.2f", x)` or
   > `rand(Xoshiro(1), 3)` with no `using`. The names `Dates`, `Statistics`,
   > `Printf` and `Random` reach the other names of each, such as `Dates.format`.

   The rehearsal of step 8 can change these two texts.
4. **The code tool refuses a `using` and an `import` of a package that is not
   in scope.** In scope are Base, Core and the module of each entry that
   `register_assistant_api!` holds. With decision 2 these are `Dates`,
   `Statistics`, `Printf` and `Random`, and `DataFrames` when its adapter is
   loaded.
   - A `using` or an `import` of such a module, or of names of it, runs:
     `using Dates`, `using Dates: Time`, `import Base: show`. It loads nothing
     and opens nothing. A model writes `using Dates` from habit, and a refusal
     would cost it a round for nothing.
   - For each other top-level `using` or `import`, `execute_julia_code` runs no
     statement of the code. It answers with the modules of the registry, so the
     answer says what the window holds:

     > `using` and `import` run in this window only for a package that is in
     > scope: Base, Dates, Statistics, Printf and Random. The packages of the
     > window are fixed. The names of the index are in scope too, and
     > `search_api` finds a name.
   - The scratch module binds the module of each marked name of the editor too,
     such as `PaneModule`. A `using` of such a module is refused, because it
     brings the exports of the module beside the declared names.
   - Why no free `using`: a package that the window has not loaded compiles in
     the process of the window, and a built binary can not load it. Each package
     of the editor is loaded, so `using ProjecturedKernel` would open the inside
     of the editor, and the model could write to a cell with no operation that
     undo takes back. And the result would change from window to window: today
     it depends on how the window started.

   The refusal is a guard against a try that fails. It is no security boundary:
   `Base.require` and `Core.eval` stay. The evaluator of the person keeps
   `using`, because a person types there, and the code of the editor that builds
   the scratch module does not go through the refusal.
5. **A `.pred` file keeps a `Date` and a `DateTime`.** A `Date` prints as
   `Date("2026-11-24")`, and a `DateTime` as `DateTime("2026-11-24T10:15:00")`,
   the text of `string(value)`. The reader builds each one again from that text.
   With no date, a record keeps `nothing`, as before. A file that names
   `Date(…)` loads only when the package is loaded. The error of today says so:
   "a .pred file names Date, and no loaded type that a file may build has that
   name".
6. **The axis of a chart follows its values.** `ChartLineSeries` and
   `ChartScatterSeries` take an `x` of `Date` or `DateTime` values, and
   `ChartAxis` takes a `min` and a `max` of them. No new axis type is made.
   - One function gives the plot coordinate of an x value. It gives a number
     as itself, and a date as the milliseconds of `DateTime(value)`, which are
     exact in a `Float64`. Each read of x in the chart goes through it: the
     bounds, the search of a sorted column, the lines, the symbols, the
     intervals, the hit test and the readout.
   - An axis is a time axis when the x columns of its line and scatter series
     hold dates. The element type of a column says it, so the test costs no
     walk. When the series mix dates and numbers, the chart draws the series of
     the first kind. The legend entry of each other series says why, as the
     entry of a function series does.
   - The ticks fall on whole calendar units. The step is the smallest of 1, 2,
     5, 10, 15 or 30 seconds or minutes, 1, 3, 6 or 12 hours, 1 or 2 days,
     1 week, 1, 3 or 6 months, or 1, 2, 5 or 10 years, whose labels fit. A label
     is `yyyy` for years, `yyyy-mm` for months, `yyyy-mm-dd` for days and weeks,
     and `HH:MM` or `HH:MM:SS` below a day, with the date at the first tick of
     each day.
   - The readout gives the time in the form of the labels. A time axis draws
     linear, and the guide says that it ignores `log`.
   - `ProjecturedChart` takes `Dates` into `[deps]`. A standard library is no
     third-party dependency: `ProjecturedPivot` and `ProjecturedWorkflow` have
     one.
7. **The pivot line chart puts dates on a time axis.** When each category of a
   line chart cell is a `Date` or a `DateTime`, `x` holds the categories
   themselves and not their index.
8. **The OMNeT++ IDE loads the package.** `OmnetIde` names
   `ProjecturedStandardLibraries` in its `Project.toml` and imports it, as it
   imports `ProjecturedPivot`.

## Facts of the code

- `_make_scratch_module!` (`source/kernel/tool/CodeExecution.jl:176`) makes a
  plain `Module(:ToolScratch)`. So Base is in scope. A check on 2026-11-25: a
  fresh module has `rand`, `randn`, `round`, `Iterators` and `Libc`, and has no
  `mean`, `Date`, `Dates`, `@sprintf`, `Xoshiro`, `TOML` or `sha256`.
- `_scratch_sources` (`CodeExecution.jl:63`): a declared API is the whole
  surface. Each module of an entry is bound by its name (`CodeExecution.jl:190`),
  and each name of an entry arrives through `using .M: name`
  (`CodeExecution.jl:224`).
- `make_editor_api()` (`Application.jl:386`) is the marked names and
  `get_registered_assistant_api()`. `register_assistant_api!`
  (`source/platform/assistant/AssistantApi.jl:32`) takes a module, or
  `module => (names...)`, and a description.
- `_make_soft_scope` (`CodeExecution.jl:541`) lets a `using` and an `import`
  pass to the evaluation.
- `describe_api` (`source/kernel/tool/Documentation.jl:883`) makes the index. A
  `Type` goes under `types:`, and each other name goes in the list of
  functions. A macro such as `@sprintf` is a new kind of name there, and step 1
  checks how the index and `search_api` show it.
- The kernel tool files are not sealed (`SEALING.md`, layer 18, all ⬜).
- The `.pred` writer refuses each value that is no string, number, character,
  bool, symbol, `nothing`, vector, tuple, named tuple, document, or value of a
  type that `is_pred_constructible` accepts
  (`source/platform/serialization/PredFile.jl:538`). `is_pred_constructible`
  accepts a `Document` by default (`FileProject.jl:358`). `get_pred_type`
  (`FileProject.jl:375`) finds a name in each loaded module, and
  `get_document_schema_name(Date)` is `:Date`. So a type of `Dates` needs
  three methods: `is_pred_constructible`, `pred_arguments` and
  `make_pred_document`.
- A roster shows a value through `format_roster_value`, which gives
  `string(value)` (`source/platform/roster/RosterDocument.jl:213`). So a table
  shows a `Date` as `2026-11-24`, and a sort orders dates.
- `ChartAxis` has `min`, `max` and `names` (`source/domain/chart/ChartDocument.jl:88`).
  `_x_ticks_labels` (`ChartPlotToGraphics.jl:500`) makes the ticks of a numeric
  axis with `compute_nice_ticks` and `format_tick` of the plot slice
  (`source/platform/plot/PlotGeometry.jl:312`, `:361`), and `_format_axis_value`
  (`ChartPlotToGraphics.jl:492`) makes the readout. The guide of the chart says
  "Any `AbstractVector{<:Real}` works".
- The pivot line chart (`source/domain/pivot/PivotChartView.jl:133`) uses the
  index of each category that is not a number. The pivot bins a date by year,
  month or day already (`PivotCrossTable.jl:83`).
- The workflow keeps a time as text in the form `yyyy-mm-ddTHH:MM:SS`
  (`source/domain/workflow/WorkflowDocument.jl:226`).
- A new process of `julia-merged-next` loads `Random`, `LinearAlgebra`, `SHA`,
  `FileWatching` and `Sockets` at start. It does not load `Dates`,
  `Statistics`, `Printf`, `Unicode`, `UUIDs`, `Base64` or `Serialization`.
- `Dates` exports 115 names, `Statistics` 13, `Printf` 4 and `Random` 25.
  `Dates.format` and `Random.seed!` are not exported.

## Steps

Each step ends with a commit. Each step runs the tests that it names, and the
tests of the steps before it. The work is in a worktree that
`workspace/bin/julia-worktree` makes, with its test session.

- [ ] **1. The package and its names.** Proposed decisions 1 and 2. Make
  `ProjecturedStandardLibraries` with the kinds that it needs, by
  `documentation/rule/package-rules.md`. Its entry file ends with one
  `@compile_ahead`; read `documentation/design/compile-ahead.md` first.
  `ProjecturedAll` aggregates it. Make `ProjecturedStandardLibrariesTest` with
  `test_standardlibraries()` and its layering guard.
  *Check:* a test builds the namespace of a `ToolSet` with `make_editor_api()`
  and runs `today()`, `Dates.format(Date(2026, 11, 24), "yyyy-mm-dd")`,
  `@sprintf("%.2f", mean([1, 2, 4]))` and `rand(Xoshiro(1), 1:6)` in it, with
  no `using`. A test shows that the index lists the names of decision 2, the
  macros among them, and that `search_api("today")` finds `today`.
  `test_package_graph()` passes.
- [ ] **2. The text of the window, and the refusal.** Proposed decisions 3 and
  4. Change `EDITOR_SYSTEM` and give the package its description.
  `execute_julia_code` refuses a top-level `using` and `import` of a package
  that is not in scope.
  *Check:* a test sends `x_1 = 1; using Plots` and gets the refusal, and `x_1`
  is not bound after it. `using ProjecturedKernel` and `using PaneModule` get
  the refusal. `using Dates`, `using Dates: Time` and `import Base: show` run.
  A `using` in the evaluator of the person still runs. The tests of the
  assistant text that compare its words change with it.
- [ ] **3. A `.pred` file keeps a date.** Proposed decision 5, in the package
  of step 1.
  *Check:* a `RecordTable` with a `Date`, a `DateTime` and `nothing` goes to a
  file with `write_document_file!` and comes back from `read_document_file`
  equal. Two saves give the same bytes. A test also edits the date of a record
  through its tab, and through `replace_referenced_value!`, and saves it.
- [ ] **4. The time axis of the chart.** Proposed decision 6.
  *Check:* tests of the ticks and labels for a span of 6 hours, 2 days,
  3 weeks, 5 months and 3 years. A test of the readout. A test that a zoom and
  a click on a sample work on a time axis. A test of a chart with dates in a
  `.pred` file, with the package of step 1. A test that a chart that mixes dates
  and numbers says why in the legend. `test_chart()` passes whole.
- [ ] **5. The pivot line chart over dates.** Proposed decision 7.
  *Check:* a pivot of records with a date cell, as a line chart, gives a time
  axis, and the step between two dates that are 7 days apart is 7 times the
  step of 1 day. `test_pivot()` passes whole.
- [ ] **6. The guides.** The guide of the new package in
  `documentation/package/adapter/standardlibraries/`. The guide of the
  assistant says what is in scope and why `using` is refused. The guide of the
  serialization lists the date values. The guide of the chart describes the
  time axis and updates its section "Limits". `package-rules.md` gets the new
  package, and the summary table of `source/tool/builder/ProjecturedProgram.jl`
  gets a row. The guides name no private project.
- [ ] **7. The OMNeT++ IDE loads the package.** Proposed decision 8, in a
  worktree of omnet-julia. Its text of the window has no sentence of its own
  about packages. If it has one, it says the same as decision 3.
  *Check:* the fast parts of omnet-julia pass against the branch. A test of
  the IDE runs `today()` in the namespace of its assistant.
- [ ] **8. The rehearsal with a real model.** With `tool/assistant/rehearsal.jl`,
  give the model a task: "record that entry 21 was repaired today, and show the
  repaired entries over time". Run seeds 1 to 10.
  *Check:* the code of the model uses `today()` and a `Date`. It holds no
  refused `using` or `import`, no `Libc.strftime` and no index as the x of a
  date. The saved
  table holds `Date(…)`. The chart has a time axis. If the texts of decision 3
  give fewer than 9 of 10, change them and run again, and write the numbers here.
- [ ] **9. The check before the land.** All the parts in worker processes, with
  no network, as `CLAUDE.md` says under "Main is green": 0 unmarked `Fail`,
  0 `Error`, and `done` for each part. Then the request to land.

## Not in this plan

- A `Time` value, the time of a day, in a file or on an axis. The module name
  `Dates` reaches `Dates.Time`.
- A strip series and a bar series over dates.
- The workflow keeps its times as text. With step 3 it can keep a `DateTime`,
  which is a later plan.
- A third-party library of statistics. That is a decision of the owner.
- An editor of a date in a cell of a table. A table shows and sorts a date, and
  step 3 checks an edit through the tab of a record.
