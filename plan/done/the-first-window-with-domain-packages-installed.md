# The first window with domain packages installed

Status: done, 2026-10-12. The owner chose options 2 and 3 of §4; §5 holds
the steps and §5.1 the measurement after them.

## 1. The request

The owner, 2026-10-12, after the CI failed the first-window test: "do A first
then B". A made the test measure the session of the README
(`16ec96743`). B is this plan: the first window of a data frame stays under a
second when domain packages are installed beside the packages of the README.

The rule that this plan keeps is in
[package-rules.md](../../documentation/rule/package-rules.md), under "A package
that a user loads compiles its own first window": no package loaded after the
first window packages makes that code compile again.

## 2. What was measured

All numbers are from 2026-10-12, Julia 1.13.1, on this machine. Each session
is a new process with the same compiled images: a new depot, `Pkg.precompile()`
of `environment/all`, and a project that lists the README packages plus the
domains of the row, with the manifest of `environment/all` and absolute paths.
"Compiles" is `Base.cumulative_compile_time_ns` from the call of
`display_in_editor` until the editor has drawn its first frame, as
`test_first_window_compiles_little` measures it.

| Installed beside the README packages | Load | First window compiles |
| --- | --- | --- |
| none | 1.6 s | 0.64 s |
| one domain (24 rows, one each) | 1.7–2.3 s | 0.58–2.29 s |
| `ProjecturedFormula` | 2.3 s | 2.29 s |
| `ProjecturedRST` | 2.0 s | 2.24 s |
| `ProjecturedFSM`, `ProjecturedProcess`, `ProjecturedJulia`, `ProjecturedPivot` | 1.9–2.3 s | 1.67–1.87 s |
| Console, Database, PDF, SequenceChart | 1.7–1.9 s | 0.58–0.61 s |
| all 24, as `environment/all` | 5.4–5.6 s | 8.3–15 s |

The 24 domains are the packages whose `[auto-integration]` table has the
trigger `Projectured` alone and the default `"auto"`. `using Projectured` loads
each of them that the project lists. The CI failed with 16.3 s in
`environment/all` on a runner with four cores.

## 3. The cause

**The first window builds the row of every registered type.**
`NaturalToGraphics` splices its type table from
`get_natural_graphics_entries` in
[NaturalRegistry.jl](../../source/platform/natural/NaturalRegistry.jl), which
calls each factory of `_GRAPHICS_FACTORIES` and `get_natural_entries(:graphics)`
in [NaturalNotation.jl](../../source/platform/natural/NaturalNotation.jl).
`get_natural_entries` calls `_build` for each row: it makes the projection of
the domain with the appearance of the editor, and that projection makes the
scaled theme of the domain. `make_scaled_theme`, which `@theme` writes in
[Theme.jl](../../source/platform/style/Theme.jl), gives each field of the theme
a `Cell` with its own closure. So a window that shows only a data frame builds
the themes of Math, RST, Markdown and every other installed domain.

That code is specialized on the theme type and the projection type of each
domain. No image holds it: a domain package has no workload, and the workload
of the platform runs with no domain loaded. So it compiles at the first window.

The evidence is a `--trace-compile` of the session, compared with the session
of the README (115 statements):

| Case | Statements | Not in the README session |
| --- | --- | --- |
| `ProjecturedFormula` | 217 | 102: 25 `Core.kwcall` of constructors, the closures of `MathTheme`, `scale_theme_value`, `NaturalModule._build`, `TypeDispatchingProjection` |
| `ProjecturedRST` | 272 | 157: `get`, `setindex!` and `Pair` of the theme, the closures of `RstTheme`, `scale_theme_value` |
| all 24 | 576 | 462: 76 `Core.kwcall`, 17 `scale_theme_value`, 9 `TypeDispatchingProjection`, 8 `_build`, the closures of each theme |

**Invalidations are a small part.** `@snoop_invalidations` of `using
Projectured, DataFrames, ProjecturedSDL` gives 1,669 invalidated instances of
our code under 112 roots with all 24 domains, and 1,555 under 106 roots with
the README packages. The six roots that only the domains add:

| Root | File | Instances |
| --- | --- | --- |
| `NaturalToGraphics` | `source/platform/natural/NaturalProjection.jl:116` | 97 |
| `get_domain_insertion` | `source/platform/domain/Domain.jl:164` | 33 |
| `_read_command_output` | `source/backend/sdl/SystemColorQuery.jl:204` | 18 |
| `wake_editor!` | `source/kernel/editor/Inbox.jl:43` | 16 |
| `_format_layout_note` | `source/platform/pane/PaneProgram.jl:1300` | 16 |
| `build_task_graphics_entry` | `source/platform/task/TaskGroupToWidget.jl:843` | 12 |

The load also rejects more cached code: `ProjecturedPlatform` 87 instances
against 39, `ProjecturedSDL` 56 against 38.

**The load takes longer too:** 5.4 s against 1.6 s, because the session loads 24
more packages. This plan does not change that; a user who installs fewer domains
loads fewer.

## 4. The options

| # | Option | What changes | Effect |
| --- | --- | --- | --- |
| 1 | **The row of a type is built when the table first meets a value of that type.** | The natural table holds a maker for each registered type, and builds and keeps the row at the first dispatch to it. The dispatch belongs to the projection algebra, so the lazy table is a higher-order projection there. | A data frame window builds no other row: its compile and its run time do not grow with the installed domains. The first value of a domain still builds its row, as now. |
| 2 | **Each domain compiles its own rows.** | A `@compile_workload` in the entry file of each domain builds its natural rows and its scaled theme with a default `Appearance`. The rule of package-rules.md allows a workload only in the entry file of a first window package, so the rule grows. | The compile drops. The run time of building every row stays, the images grow, and each new domain must keep its workload. |
| 3 | **The six invalidation roots of §3 get concrete types**, as D9 of [the-first-window-in-under-a-second.md](../done/the-first-window-in-under-a-second.md) did. | Type assertions and untyped helper arguments at the six roots. | A small part of the time. It helps with both options. |

**The decision.** The owner, 2026-10-12: "option 2 and 3". The reason, in the
owner's words: "the domain packages have to have their own compile workloads
anyway, so why not compile natural support? maybe we can do it better but let's
not overcomplicate this". Option 1 stays a possible improvement for later, if
the run time of building every row ever shows in a measurement.

### 4.1 The test of option 2

On 2026-10-12, before the implementation, a `@compile_workload` in the entry
file of a domain built `NaturalToGraphics(; measure = FontFileMeasure(),
appearance = Appearance())`. The measurement is that of §2.

| Case | First window compiles | Statements not in the README session |
| --- | --- | --- |
| README packages only, control | 0.66–0.68 s | – |
| `ProjecturedRST`, before and after | 2.24–2.39 s, 0.65–0.68 s | 157, 1 |
| `ProjecturedFormula`, before and after | 2.29 s, 1.08 s | – |
| all 24 domains, before and after | 8.3–15 s, 1.34–1.58 s | 462, 26 |

Facts that the test found:

- **The workload must run the `__init__` of the domain module first.** A
  domain registers its rows there, and `__init__` runs when the package loads,
  after its workload. Without the call, the workload compiled nothing of the
  domain: RST stayed at 2.35 s.
- **Only a package whose slice registers natural rows needs it.** Thirteen
  domain slices call a `register_natural_…!` function in their `__init__`:
  book, chart, formula, graph, json, julia, markdown, math, rst, sql, workflow,
  xml and yaml. FSM, Process, Pivot and DBCatalog register nothing; their cost
  in §2 came from the rows of Graph, Julia, Chart and SQL below them.
  `ProjecturedDatabase` depends only on the kernel, and the platform names
  that the workload calls are not there.
- **The 26 statements that remain are not rows.** They are code of the kernel
  and the platform that compiles again: the task of the editor loop,
  `initialize_backend!`, `configure_devices!`, `take_from_devices!`,
  `wrap_editor!`, `evaluate_operation`. Option 3 is for them.

## 5. Steps for options 2 and 3

- [x] **The platform function.** `run_natural_rows_workload(domain::Module)`
      beside `run_display_workload` in
      [DisplayWorkload.jl](../../source/platform/display/DisplayWorkload.jl):
      it runs `domain.__init__()`, then builds `NaturalToGraphics` as
      `_start_session` of the display does.
- [x] **The workloads.** The entry file of each of 14 packages ends with
      `@compile_workload run_natural_rows_workload(<Domain>Module)`, and
      `PrecompileTools` joins its `[deps]` and its entry in the manifest of
      `environment/all`: Book, Chart, Formula, Graph, JSON, Julia, Markdown,
      Math, Pivot, RST, SQL, Workflow, XML and YAML.

      **Found during the work: a second channel of rows.** A package that
      defines a method of `make_graphics_projection(::Type{T}; measure,
      appearance)` adds a row too: `collect_graphics_projection_types` reads the
      method table, and `NaturalToGraphics` builds a row for each type. Pivot
      has rows only so, and Julia and DataFrames have them both ways. So Pivot
      got the workload, and the rule names both channels.
- [x] **The rule and its guards.** package-rules.md, under "A package that a
      user loads compiles its own first window", gives the rule for a package
      whose slice has natural rows. In `PackageGraphTest`, `_has_natural_rows`
      finds such a package, the guard of `@compile_workload` allows the
      workload in its entry file, and the new testset "a package with natural
      rows compiles them in its entry file" checks that each one has it. The
      testset fails when a workload is missing (checked by removing the one of
      YAML). The new domain guide says it under "What to add next".
- [x] **Option 3.** `@snoop_invalidations` with all domains, compared with the
      README session, gave the roots that only the domains add, and each got
      its fix by the rules of package-rules.md:
      - `UntrackedCell{T}(value)`: `convert` only when `value` is not a `T`,
        and then through `invokelatest`. `convert(::Type{NamedTuple}, ::GroupKey)`
        of DataFrames invalidated 520 instances, also in the README session.
      - `NaturalToGraphics` and `build_task_graphics_entry` call
        `make_graphics_projection` through `invokelatest`; the domains extend it.
      - `collect_graphics_projection_types` checks each type with `in` before it
        pushes it; `unique!` on a `Vector{Type}` went through a `Set`, whose
        iteration an `iterate` method of DataStructures invalidated.
      - `convert_to_declared_type`, `_is_domain_entry` and
        `get_insertion_candidates` call `get_domain_insertion` through
        `invokelatest`; the domains extend it.
      - `wake_editor!` calls `wake_backend!` through `invokelatest`, as the
        editor loop calls the backend protocol; `ConsoleBackend` extends it.
      - `_format_layout_note` asserts `describe_document(node)::String`, so `*`
        meets no generic path that the `cconvert` of BitFlags invalidates.

      Left as it is: `_read_command_output` of SDL (18 instances). The chain is
      inside Base: `open(::CmdRedirect, ::String)` waits on a condition, and
      the `assert_havelock` method of ConcurrentUtilities invalidates it.
- [x] **A test.** `test_first_window_compiles_little` has a second testset:
      the first window in the active environment, which in the CI is
      `environment/all` with every domain installed, compiles less than 3.0 s.
- [x] **Measure** the table of §2 again (§5.1).
- [x] **The narrow tests:** the guards, `test_package_graph()`, the natural
      tests of the umbrella, the tests of the changed files, and the suites of
      RST and Pivot. All pass: `test_cell` 160 (2 broken, as before),
      `test_editor_wait` 25, `test_editor_feeds` 21, `test_document_composition`
      4, `test_task_views` 36, `test_arrangement_program` 13,
      `test_data_frame_display` 8, `test_document_insertion` 123, the four
      natural tests 2, 3, 1, 2, 4, 1, 4, 2 and 4, `test_package_graph` 398,
      `test_rst` 111, `test_pivot` 299. The style guard fails on
      `source/platform/text/TextDocument.jl:460`, on `main` too, from other
      work.
- [ ] Move this plan to `plan/done/`.

### 5.1 The measurement after the work

2026-10-12, the method of §6, all packages built again. The machine was busy
by other sessions during the first two rows, so each row has its own README
control.

| Stage | README session | All 24 domains | Statements not in the README session |
| --- | --- | --- | --- |
| before | 0.64 s | 8.3–15 s | 462 |
| the workloads (option 2) | 1.00–1.14 s, load 50–65 | 2.27–2.50 s | 27–34 |
| and the invalidation fixes (option 3) | 0.62–0.76 s | 1.08–1.22 s | 9 |

With all domains, our code has 1,472 invalidated instances, and 1,463 in the
README session; before the fixes it was 2,059 against 1,581. Nine statements
remain: three methods of the SDL backend that the load rejects, a Base
function, two theme reads, `get_widget_style`, a `getproperty` of a `Set` and
`compute_code_pieces` for Julia. The load of all 24 domains takes 6.3–6.9 s
against 1.7 s; this plan does not change the load.

## 6. How to measure

1. Make a new depot, and precompile `environment/all` in it:
   `JULIA_DEPOT_PATH=<depot>: julia --project=environment/all -e 'using Pkg;
   Pkg.instantiate(; allow_build = false); Pkg.precompile()'`. The build of
   ODBC fails in a worktree on a Pkg assertion about a source path, so skip the
   builds.
2. For each case, write a project folder: `[deps]` of
   `environment/readme-data-frame/Project.toml` plus the domains of the case,
   and `environment/all/Manifest.toml` with each `path = "…"` made absolute.
   `_make_readme_session_project` in
   [FirstWindowTest.jl](../../test/projectured/FirstWindowTest.jl) does the same
   for the README case.
3. Run `_FIRST_WINDOW_SESSION` of that test in each project with
   `SDL_VIDEODRIVER=offscreen`, and read `FIRST WINDOW COMPILED`.
4. For the cause, add `--trace-compile=<file>` and compare the statements with
   the README case. For the invalidations, stack an environment with
   SnoopCompile on `JULIA_LOAD_PATH`, and run `@snoop_invalidations using
   Projectured, DataFrames, ProjecturedSDL` in each project.
