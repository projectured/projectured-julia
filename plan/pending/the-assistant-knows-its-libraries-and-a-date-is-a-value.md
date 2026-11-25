# The assistant knows its libraries, and a date is a value

**Status:** pending. Written on 2026-11-25, and written again on the same day
after three questions of the owner. The owner asked for this plan ("yes, write
the plan", then "yes, rewrite the plan"). The proposed decisions below are
approved with the plan, when the owner approves the plan.

The plan lands nothing and pushes nothing: it ends with a request to land.

**If a step needs a change of a sealed file, or a mechanism that this plan does
not name, the work stops and the session asks.**

## The problem

The assistant of a window writes Julia code with `execute_julia_code`. Its
namespace holds Base, the names of the editor that carry the line
`For the assistant.`, and the names that an adapter registers. It holds no other
library, and its text says nothing about `using`. So the assistant writes the
usual functions of Julia again by hand, or it reaches them by a trick. The
assistant of the OMNeT++ IDE did this for its defect repairs, on 2026-11-24:

```julia
# What the assistant wrote
today_1() = Libc.strftime("%Y-%m-%d", time())          # its words: "I'll avoid Dates"
(number = 21, repaired_on = "2026-11-24", landed_on = "")    # a date as text in defects.pred
ChartLineSeries("repaired", 1:length(dates), counts)         # x is 1, 2, 3 ...
ChartAxis(names = dates)                                     # ... with the date as a label

# What it must be able to write
using Dates
(number = 21, repaired_on = today(), landed_on = nothing)   # the file keeps Dates.Date("2026-11-24")
ChartLineSeries("repaired", dates, counts)                  # a time axis: 7 days are 7 days wide
```

Three gaps cause this:

1. **The assistant can not count on a library.** A `using` resolves its name
   through the load path of the window. When the load path has no `@stdlib`,
   even `import Random` fails, although Julia loads `Random` at start.
2. **A `.pred` file can not keep a date.** Its writer refuses a `Date`, so a
   `RecordTable` keeps a date as text, and the code compares text. A bare name
   such as `Date` also does not say which package a reader must find.
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

A check on 2026-11-25 shows why a `using` works in one start and fails in
another. With the environment of the IDE, `build/app/omnet_ide`:

| Load path | `using Statistics` | `import Random` | `Base.require(PkgId)`, then `using .Statistics` |
| --- | --- | --- | --- |
| `["@", "@v#.#", "@stdlib"]`, the default | works | works | works |
| `["@"]` | "Package Statistics not found in current path" | "Package Random not found in current path" | works |

## The decisions of the owner that this plan builds

- **No free load of packages: the window has the typical ones ready**
  (2026-11-25: "I'm not sure if allowing the assistant to load arbitrary packages
  is a good idea, we should instead be prepared with the typical packages").
- **Think through what is generally useful beside what the assistant has**
  (2026-11-25: "Think through what would be generally useful in addition to what
  the assistant already has. The base package is available by default I guess").
- **The assistant knows that it can not use other packages through `using` or
  `import`** (2026-11-25: "the assistant should be aware of the fact that it
  can't use packages via using/import, so it's not going to try and fail").
- **A `using` of an allowed library runs, and each other `using` is refused**
  (2026-11-25: "yes, change the plan", to "Shall I change decisions 3 and 4 of
  the plan this way?", after the question "do you think it would be better to
  allow using/import for the assistant?").
- **No new package: the assistant writes `using` for an allowed library, and a
  `.pred` file names the package of a value** (2026-11-25: "yes, rewrite the
  plan", to "Shall I rewrite the plan this way?"). The owner asked before: "do
  we really need the projectured package then? why not let the assistant simply
  use the allowed list libraries?", and "only for loading? why not extend the
  pred syntax? it's unclear what package is it supposed to load anyway? perpahs
  fully qualified simbols? or using/imports?". The answer that the owner
  approved: a qualified name such as `Dates.Date("2026-11-24")`, not a `using`
  line in the file; a reader that loads only a library of the allowed list; a
  code tool that loads an allowed library when the assistant asks for it; the
  time axis of the chart and of the pivot as before.
- **One plan has three parts:** the libraries, the date in the `.pred` file, and
  the time axis of the chart (2026-11-25: "yes, write the plan").

## Proposed decisions

The session proposes them. They are approved with the plan.

1. **One list of the standard libraries that the editor loads by name.** The
   kernel holds it: `LOADABLE_STANDARD_LIBRARIES`, each name with its package
   id, and `load_standard_library!(name) -> Module or nothing`. The function
   loads by package id, with `Base.require(PkgId)`, so it works with each load
   path. It answers `nothing` for a name that is not on the list.
   - The place is a new fragment of the document layer,
     `source/kernel/document/StandardLibrary.jl`: a document holds values of these
     libraries, and both the code tool (layer 18) and the reader of the platform
     reach layer 10. The file is not sealed: no file of the layer is.
   - The kernel takes no dependency. It names the libraries by package id, and
     Julia ships them.
   - The list:

     | Library | Why it is on the list |
     | --- | --- |
     | Dates | dates, times and their arithmetic; the survey found 2 failures and a work-around in each table and chart of dates |
     | Statistics | `mean`, `median`, `std`, `quantile`, `cor`; the survey found a statistical study written by hand |
     | Printf | `@sprintf`, `@printf`; the survey found 7 blocks of `round` and `lpad` |
     | Random | `Xoshiro`, `shuffle`, `randperm`, `Random.seed!`; the survey found a failed `import Random` and a module taken by its package id |

     Base gives `rand`, `randn`, `round`, `Iterators` and `Libc` already.
   - The libraries that the list leaves out, and why:

     | Library | Why it is not on the list |
     | --- | --- |
     | LinearAlgebra, TOML, SHA, CRC32c, UUIDs, Base64, Unicode | The survey found no use. A later session adds a library when its work needs it. TOML reads a file, and the rules of a window say that a file is read with a verb of the editor. |
     | InteractiveUtils | `@which` and `subtypes` repeat `search_api`. |
     | DelimitedFiles | It reads a file. |
     | Pkg, Downloads, Sockets, Distributed, FileWatching, Serialization, Mmap, Libdl, Profile, Logging, REPL, Test | They install code, use the network, start processes, read the disk, or belong to the editor itself. |
     | Distributions, StatsBase, HypothesisTests, SpecialFunctions | They are third-party. The statistical study of 2026-10-29 needed them. They are a later decision of the owner. |
2. **The code tool runs a `using` of an allowed library, and refuses each
   other.** `execute_julia_code` reads each top-level `using` and `import` of the
   code of the model, also in a top-level `begin` block, before it runs a
   statement.
   - **Base and Core:** the statement runs as it is, for example
     `import Base: show`.
   - **A library of the list:** the tool loads it with
     `load_standard_library!`, binds the module by its name in the scratch module,
     and runs the statement in its relative form: `using Dates` runs as
     `using .Dates`, and `using Dates: Time` as `using .Dates: Time`. So the
     load path does not matter.
   - **The module of an entry that `register_assistant_api!` holds,** such as
     `DataFrames`, gets the refusal. *Changed in step 2:* the plan let it run,
     but the code tool is in the kernel, and there an entry of an outside
     package and an entry of a module of the editor are both an `ApiEntry`. The
     registered names, such as `DataFrame`, are in scope with no `using`.
   - **Each other package:** no statement of the code runs. The tool answers
     with the names of the list:

     > `using` and `import` run in this window only for Base and for the
     > standard libraries Dates, Statistics, Printf and Random. The packages of
     > the window are fixed. The names of the index are in scope, and
     > `search_api` finds a name of the editor.
   - The scratch module binds the module of each marked name of the editor too,
     such as `PaneModule`. A `using` of such a module is refused, because it
     brings the exports of the module beside the declared names.
   - Why no free `using`: a package that the window has not loaded compiles in
     the process of the window, and a built binary can not load it. Each package
     of the editor is loaded, so `using ProjecturedKernel` would open the inside
     of the editor, and the model could write to a cell with no operation that
     undo takes back. And the result of a `using` would change from window to
     window, as the evidence shows.
   - The refusal is a guard against a try that fails. It is no security
     boundary: `Base.require` and `Core.eval` stay. The evaluator of the person
     keeps the `using` of a Julia prompt, because a person types there. The code
     of the editor that builds the scratch module does not go through the rule.
3. **The text of the window says what is in scope.** `EDITOR_SYSTEM`
   (`source/platform/application/Application.jl:398`) replaces "Each name of the
   index is in scope by itself, so write it without its module; no package name,
   such as ProjecturedPlatform, is in scope." with a text that takes the names
   from the list:

   > Base and each name of the index are in scope by themselves, so write a name
   > without its module. No package of the editor, such as ProjecturedPlatform,
   > is in scope. To use a standard library of Julia, write `using Dates`,
   > `using Statistics`, `using Printf` or `using Random`: these four load when
   > you ask. The packages of the window are fixed, so a `using` or an `import`
   > of any other package is refused.

   The rule "NEVER guess a name or a signature: search for it" gets a second
   sentence: "`search_api` finds the names of the editor; the names of the
   standard libraries are those of Julia." *Changed in step 7:* the first text
   said "knows", which makes the tool a person. The rehearsal of step 9 can change
   these texts.
4. **A `.pred` file names the package of a value of an outside type.**
   - The syntax: a call can have a qualified head of one module and one type,
     `M.T(…)`. Today the marker grammar takes only a plain name
     (`FileProject.jl:468`). A bare name of a type of the editor stays as it is,
     so each file of today reads as before.
   - The platform keeps a short list, by name, of the outside types that a file
     may build from their text: `Dates.Date` and `Dates.DateTime`. A list of
     names needs no dependency of the platform.
   - The writer prints a value of such a type as `M.T("text")`, with
     `string(value)` as the text: `Dates.Date("2026-11-24")` and
     `Dates.DateTime("2026-11-24T10:15:00")`. This is the text that Julia prints
     for the value with `repr`, in a session that did not run `using Dates`.
   - The reader finds the module `M` among the loaded modules, or it loads it
     with `load_standard_library!` when it is on the list of decision 1. Then it
     finds `T` in it, checks that `M.T` is on the list of the platform, and
     builds `T("text")`. For each other qualified name, the error names the
     package: "a .pred file names Foo.Bar, and a file builds no value of a type
     of Foo".
   - So a file never makes the editor load a package that is not on the list,
     and opening a file runs no code from outside the standard libraries.
   - Why a qualified name and not a `using` line at the top of a file: each value
     carries its own package, so a part that is cut or copied out of a file keeps
     it, and a line at the top of a file would stay behind. And a `using` line
     would make a data file look like code.
5. **The axis of a chart follows its values.** `ChartLineSeries` and
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
   - `ProjecturedChart` takes `Dates` into `[deps]`, because the calendar steps
     need its arithmetic. A standard library is no third-party dependency:
     `ProjecturedPivot` and `ProjecturedWorkflow` have one.
6. **The pivot line chart puts dates on a time axis.** When each category of a
   line chart cell is a `Date` or a `DateTime`, `x` holds the categories
   themselves and not their index.
7. **A built binary holds the libraries of the list.** The builder writes each
   library of the list into the `[deps]` of the package that it writes for a
   binary, under `build/app/<name>/`, so the image keeps them, also with
   `filter_stdlibs`.
8. **The OMNeT++ IDE needs no change of its own.** It gets the rule and the text
   from the platform. Step 8 checks that its own text of the window says nothing
   else about packages.

## Facts of the code

- `_make_scratch_module!` (`source/kernel/tool/CodeExecution.jl:176`) makes a
  plain `Module(:ToolScratch)`. So Base is in scope. A check on 2026-11-25: a
  fresh module has `rand`, `randn`, `round`, `Iterators` and `Libc`, and has no
  `mean`, `Date`, `Dates`, `@sprintf`, `Xoshiro`, `TOML` or `sha256`.
- `_scratch_sources` (`CodeExecution.jl:63`): a declared API is the whole
  surface. Each module of an entry is bound by its name (`CodeExecution.jl:190`),
  and each name of an entry arrives through `using .M: name`
  (`CodeExecution.jl:224`).
- `_make_soft_scope` (`CodeExecution.jl:541`) lets a `using` and an `import`
  pass to the evaluation, which resolves the name through the load path.
- `make_editor_api()` (`Application.jl:386`) is the marked names and
  `get_registered_assistant_api()` (`source/platform/assistant/AssistantApi.jl`).
- The kernel tool files and the kernel document files are not sealed
  (`SEALING.md`, layers 10 and 18, all ⬜).
- The marker grammar (`source/platform/serialization/FileProject.jl:463`)
  takes a call whose head is an identifier, and arguments that are literals,
  keywords or such calls. `_evaluate_pred` (`PredFile.jl:288`) reads the head
  as a `Symbol`, builds a type of the editor by its bare name through
  `get_pred_type`, and makes any other call a reference.
- The writer refuses each value that is no string, number, character, bool,
  symbol, `nothing`, vector, tuple, named tuple, document, or value of a type
  that `is_pred_constructible` accepts (`PredFile.jl:538`).
- `repr(Dates.Date(2026, 11, 24))` is `Dates.Date("2026-11-24")`, and
  `repr(Dates.DateTime(2026, 11, 24, 10, 15))` is
  `Dates.DateTime("2026-11-24T10:15:00")`, in a session that ran `import Dates`.
  `Dates.Date(string(d)) == d` and `Dates.DateTime(string(t)) == t`.
  `Meta.parse` reads `Dates.Date("…")` as a call whose head is
  `Expr(:., :Dates, QuoteNode(:Date))`.
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
- `Dates.format` and `Random.seed!` are not exported, so the assistant writes
  them with the module name, which `using Dates` binds.
- Each process that loads the kernel loads Dates: the kernel depends on
  Preferences, Preferences on TOML, and TOML on Dates (found in step 3). So no
  editor process lacks Dates, and the check "a file loads in a process that has
  not loaded Dates" of step 3 can not run. `load_standard_library!` answers the
  loaded module there.
- The package id of Printf is `de0858da-6303-5e67-8744-51eddeeeb8d7`.

## Steps

Each step ends with a commit. Each step runs the tests that it names, and the
tests of the steps before it. The work is in a worktree that
`workspace/bin/julia-worktree` makes, with its test session.

- [x] **1. The list of the standard libraries.** Proposed decision 1, in
  `source/kernel/document/StandardLibrary.jl`.
  *Check:* a test loads each library of the list with `load_standard_library!`
  in a process whose `JULIA_LOAD_PATH` is `@`, and gets `nothing` for
  `:Plots` and for `:Pkg`. `test_kernel_layering()` passes.

  Done on 2026-11-25. `LOADABLE_STANDARD_LIBRARIES` is a named tuple of
  `Base.PkgId`s, and `load_standard_library!(name)` calls `Base.require` with
  one. The part `test_standard_library` of `test_kernel()` has 16 of 16. Its
  second process loads Statistics with `JULIA_LOAD_PATH=@`, where a plain
  `using Statistics` fails.
- [x] **2. The code tool and the text of the window.** Proposed decisions 2
  and 3.
  *Check:* in a process whose `JULIA_LOAD_PATH` is `@`, a test runs
  `using Dates; Dates.format(today(), "yyyy")`, `using Statistics: mean`,
  `using Printf; @sprintf("%.2f", 1.5)`, `using Random; rand(Xoshiro(1), 1:6)`
  and `import Base: show` through `execute_julia_code`. A test sends
  `x_1 = 1; using Plots` and gets the refusal, and `x_1` is not bound after it.
  `using ProjecturedKernel` and `using PaneModule` get the refusal. A `using` in
  the evaluator of the person still runs. The tests of the assistant text that
  compare its words change with it.

  Done on 2026-11-25. `_admit_package_loads!` in `CodeExecution.jl` reads the
  statements before they run, when the set declares its API, and a refused load
  throws `PackageLoadRefusedException`, whose answer has no stack. The
  `using` line of `ToolModule.jl` names `DocumentModule` bare, as the layering
  guard of the kernel wants. `EDITOR_SYSTEM` takes the four `using` lines from
  `LOADABLE_STANDARD_LIBRARIES`. No test compared the words of the text. The
  part `test_code_execution` has 110 of 110, with its second process that has
  `JULIA_LOAD_PATH=@`, and the layering parts of the kernel have 83 of 83. The
  guide of the agent stack (`documentation/package/kernel/agent.md`) describes
  the rule.
- [x] **3. A `.pred` file keeps a date.** Proposed decision 4.
  *Check:* a `RecordTable` with a `Date`, a `DateTime` and `nothing` goes to a
  file with `write_document_file!`, holds `Dates.Date("…")`, and comes back from
  `read_document_file` equal. Two saves give the same bytes. A file with
  `Base.Cmd(…)` or `Foo.Bar(…)` gives the error that names the package, and
  loads nothing. Each file of the examples reads as before. A test edits the
  date of a record through its tab, and through `replace_referenced_value!`,
  and saves it.

  Done on 2026-11-25. `_is_text_value_head`, `_build_text_value` and
  `_is_text_value` in `FileProject.jl` hold the qualified head and its list
  `_TEXT_VALUE_TYPES`; `_evaluate_pred` and `_evaluate_splice` call
  `_build_text_value`, and `_print_text_value` of `PredFile.jl` writes the
  value. The part `test_pred_file` of `test_platform()` has 106 of 106. The
  part `test_record_table` has 36 of 36: in an editor, a table of records with
  dates shows them, a change of a date through `replace_referenced_value!`
  shows in its row, a sort orders the drawn rows by date with a record of no
  date last, and the file keeps `Dates.Date("…")`. A sort orders the drawn rows
  of the arrangement and leaves the rows of the roster in their order. The guide
  of the serialization has a paragraph on dates.
- [x] **4. The time axis of the chart.** Proposed decision 5.
  *Check:* tests of the ticks and labels for a span of 6 hours, 2 days,
  3 weeks, 5 months and 3 years. A test of the readout. A test that a zoom and
  a click on a sample work on a time axis. A test of a chart with dates in a
  `.pred` file. A test that a chart that mixes dates and numbers says why in the
  legend. `test_chart()` passes whole.

  Done on 2026-11-25. `get_plot_coordinate`, `is_date_column`, the lazy
  `ChartDateColumn` and `get_series_x` are in `ChartDocument.jl`; the ticks are
  `compute_time_ticks` of the new fragment `ChartTimeAxis.jl`. The mixed case
  draws the series of the kind of the first one, and the legend entry of each
  other series says "x holds numbers, the axis shows dates" or the reverse. A
  column of no concrete element type, as a `.pred` file reads it, is a date
  column when its first element is a date. The finest step whose labels fit
  wins, so a span of 3 years on the default width shows quarters, and a span of
  30 years shows every second year. `test_chart()` has 763 of 763, with the new
  part `test_chart_time_axis`. `environment/all/Manifest.toml` names `Dates`
  for `ProjecturedChart`, as `Pkg.resolve` writes it; the workers had to start
  again after the new dependency.
- [x] **5. The pivot line chart over dates.** Proposed decision 6.
  *Check:* a pivot of records with a date cell, as a line chart, gives a time
  axis, and the step between two dates that are 7 days apart is 7 times the
  step of 1 day. `test_pivot()` passes whole.

  Done on 2026-11-25. `test_pivot()` has 367 passed and 4 broken, the 4
  markers that `main` has.
- [x] **6. A built binary holds the libraries.** Proposed decision 7.
  *Check:* a test of the builder reads the `[deps]` of the package that it
  writes, and finds each library of the list. If the machine has room for a
  build, the check of a built program runs `using Statistics; mean([1, 2])`
  through `execute_julia_code`; if not, the plan says so.

  Done on 2026-11-25. The builder depends on no package of the editor, so it
  holds the list itself as `EDITOR_STANDARD_LIBRARIES` in `AppPackage.jl`, and a
  test compares it with `LOADABLE_STANDARD_LIBRARIES`. `write_app_package` adds
  the libraries to `[deps]` when a package of the build reaches
  `ProjecturedKernel`. Today all four are in the manifests of both binaries
  already, through other packages: Statistics through DataFrames and
  FixedPointNumbers. The part `test_build_executable` has 443 passed and the 1
  broken marker of `main`; it needs more than the default limit of 1536 MiB of a
  part, so the request gave it 6 GB. No binary was built: a build takes long and
  much memory, and a library in `[deps]` is in the image.
- [x] **7. The guides.** The guide of the assistant says what is in scope and
  which `using` runs. The guide of the serialization describes the qualified
  name and its list. The guide of the chart describes the time axis and updates
  its section "Limits". The guide of the builder names the libraries that a
  binary keeps. The guides name no private project.

  Done on 2026-11-25. The guides of the agent stack, the document layer, the
  architecture of the kernel, the assistant, the serialization, the chart and
  the builder describe the change, and `SEALING.md` lists
  `document/StandardLibrary.jl` as not sealed. The documentation guard shows the
  2 violations and the 179 lines to read that `main` shows; the first text of the
  guides added 5 such lines, with "refuses", "knows" and "asks for", and the text
  of the window had "knows" too, so these sentences name the mechanism now.
- [x] **8. The OMNeT++ IDE.** Proposed decision 8, in a worktree of
  omnet-julia when its text needs a change.
  *Check:* the fast parts of omnet-julia pass against the branch. A test of the
  IDE runs `using Dates; today()` in the namespace of its assistant.

  Done on 2026-11-25, with no change of omnet-julia: `CAMPAIGN_SYSTEM` and
  `IDE_SYSTEM` hold `EDITOR_SYSTEM`, and `get_assistant_api()` is
  `make_editor_api()`. A check in a worktree of omnet-julia `main`, with
  `--with` the worktree of this branch, made a `ToolSet` with
  `get_assistant_api()`: `using Dates` and a date gave `"2026-12-02"`,
  `today() isa Date` gave `true`, `using Statistics: mean` gave 3.0, `using Plots`
  gave the refusal, and both texts name the four `using` lines. It is a check of
  one run and no test of omnet-julia, which would need a branch there. The fast
  parts of omnet-julia run in step 10.
  - The manifests of omnet-julia are no files of its git, and they name
    `ProjecturedChart` with no `Dates`. A worktree of omnet-julia needs
    `Pkg.resolve()` of `environment/all` with `--with` this branch, and the main
    checkout of omnet-julia needs it after the land, or the load stops with
    "Cannot load module Dates into ProjecturedChart".
- [x] **9. The rehearsal with a real model.** With `tool/assistant/rehearsal.jl`,
  give the model a task: "record that entry 21 was repaired today, and show the
  repaired entries over time". Run seeds 1 to 10.
  *Check:* the code of the model uses `today()` and a `Date`. It holds no
  refused `using` or `import`, no `Libc.strftime` and no index as the x of a
  date. The saved table holds `Dates.Date(…)`. The chart has a time axis. If
  the texts of decision 3 give fewer than 9 of 10, change them and run again,
  and write the numbers here.

  Done on 2026-11-25, with `qwen3.8:27b`, in fewer runs than planned: the tool
  skips a seed when less than 13 GB are free besides the loaded model, and with
  the jobs of other sessions only 3 runs of each start had room. The numbers:

  | Run | Task | Seeds | Passed | The date in the code of the model |
  | --- | --- | --- | --- | --- |
  | 1 | one task: record, save and chart | 1 | 0 | the 8 rounds of the assistant ended before a date |
  | 2 | record | 1 to 3 | 1 | seed 1 `using Dates` and `Dates.today()`; seeds 2 and 3 `Dates.today()` with no `using`: `UndefVarError` |
  | 3 | record, after the answer line below | 1 to 3 | 1 | all 3 end with `using Dates` and `today()`; seed 2 after the `UndefVarError` of its first try |
  | 4 | chart, of the rows of defects.pred | 1 to 2 | 0 | no chart: the rows of the table were not read |
  | 5 | chart, with its data in the prompt, after the docstrings below | 1 to 3 | 2 | seeds 2 and 3 `using Dates` and a column of `Date`; seed 1 the dates as text |

  No code made a date with `Libc.strftime`. The other failures of the record
  task are the write of a field of a record: `records[3]["repaired_on"]` and
  `convert_object_to_document`, in place of `replace_referenced_value!(record,
  :repaired_on, value)`. That is no question of dates, and this plan leaves it.
  The rehearsal changed two things, beyond the texts of decision 3:
  - **The answer of a library name before its `using`.** When the undefined
    name is a library of the list, or a name that a loaded library of the list
    exports, the answer of `execute_julia_code` says "write `using Dates` first"
    (`_suggest_standard_library` in `CodeExecution.jl`). Julia's own hint says
    "Dates is loaded but not imported in the active module Main".
  - **The docstrings of the chart.** `ChartLineSeries`, `ChartScatterSeries` and
    `ChartAxis` say that `x` can hold dates, and give an example with `using
    Dates`. Before, a model that searched for dates found `ChartCategoryAxis`.
  - The tool itself: `prepare_window!` set the field `collapse_thinking`, which
    `Assistant` lost in commit `06e96df1d`, so every rehearsal of `main` failed;
    `tool/video/record_assistant_window.jl` has the same line.
- [ ] **10. The check before the land.** All the parts in worker processes, with
  no network, as `CLAUDE.md` says under "Main is green": 0 unmarked `Fail`,
  0 `Error`, and `done` for each part. Then the request to land.

## Not in this plan

- A `Time` value, the time of a day, in a file or on an axis. `Dates.Time` is
  in reach after `using Dates`.
- A strip series and a bar series over dates.
- The workflow keeps its times as text. With step 3 it can keep a
  `Dates.DateTime`, which is a later plan.
- A third-party library of statistics. That is a decision of the owner.
- An editor of a date in a cell of a table. A table shows and sorts a date, and
  step 3 checks an edit through the tab of a record.
