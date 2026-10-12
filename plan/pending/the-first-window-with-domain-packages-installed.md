# The first window with domain packages installed

Status: pending, 2026-10-12. The analysis is done; nothing is implemented. The
owner decides the option of §4 before the work starts.

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

**Recommendation (mine, not decided):** options 1 and 3. Option 1 removes the
cause: work that the window does not need. Option 2 only moves the cost into the
images, and every new domain must remember it. Option 2 stays as the fallback if
option 1 can not keep the projection algebra clean.

## 5. Steps for options 1 and 3

- [ ] Read [natural.md](../../documentation/package/platform/natural/natural.md),
      [higher-order-projections.md](../../documentation/package/platform/projection/higher-order-projections.md)
      and the part of package-rules.md that §1 names. Check
      [SEALING.md](../../SEALING.md) for each file before an edit.
- [ ] Design the lazy table: where the maker of a row and the built row live,
      how the table finds the most derived registered type, and what an edit
      of the appearance does to a built row. Write the design here, and ask the
      owner before the code.
- [ ] Implement it, and make `get_natural_entries` and the factories give makers.
- [ ] Give the six roots of §3 concrete types.
- [ ] A test beside `test_first_window_compiles_little`: the first window of a
      data frame in `environment/all`, with every domain installed, compiles
      less than a limit that the measurement after the change sets.
- [ ] Measure again with the method of §6: the table of §2 and the session of
      the README, which must stay at about 0.64 s.
- [ ] The narrow tests: `test_natural_registry()`, `test_natural_notation()`,
      `test_natural_renders_every_atom()` and
      `test_natural_round_trips_every_atom()` of the umbrella, and the suites of
      the domains whose natural rows change.
- [ ] Update natural.md and package-rules.md.

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
