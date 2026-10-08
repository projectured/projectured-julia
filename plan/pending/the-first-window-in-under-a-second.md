# The first window in under a second

Status: pending, 2026-10-08.

## The request

The owner, 2026-10-08: after `using Projectured, DataFrames, SimpleDirectMediaLayer`,
the first `display_in_editor` of a data frame must draw its first frame in under
a second, in the first session after the install, with no other package. Each
package compiles its own code in its own package image. No package extension
holds a workload for a combination of packages ("I hate extensions, and that
just doesn't combine").

## What was measured (2026-10-08)

The session of the README, Julia 1.13.1, one thread, the window offscreen,
interleaved runs, a machine load of 8 to 10.

| Variant | First frame, median of 6 | `using` line | Build of the packages |
| --- | ---: | ---: | ---: |
| no workloads, as released in 0.1.0 | 48.3 s | 1.35 s | 134 s |
| each package replays its own statement files | 19.2 s | 1.87 s | 191 s |

- Of the 2,621 statements that the README session compiled when it was
  recorded, 2,322 name only the kernel, the platform and Base, 154 the SDL side,
  143 the DataFrames side, and 2 both sides. So almost no code needs DataFrames
  and SDL together.
- With the replay, the session still compiles 1,001 statements. 707 of them are
  in no statement file: the file of the README session was recorded on
  2026-10-03 (`78232fc98`), 471 commits and 18,144 inserted lines before the
  measurement. A replayed text file goes out of date; a workload that runs code
  does not.
- The `using` line invalidates 10,424 method instances: 4,582 of
  ProjecturedPlatform, 1,491 of ProjecturedKernel, 303 of ProjecturedSDL. The
  largest causes are methods that later packages add to functions that our code
  calls with an argument of an abstract type:
  `(::Type{T<:Integer})(::SentinelArrays.ChainedVectorIndex)` (3,502),
  our own `get_selection(::DataFrameColumn)` (881),
  `hasproperty(::DataFrames.DataFrameRows, ::Symbol)` (732),
  `&(::Integer, ::CEnum.Cenum)` (694), and methods of PooledArrays and
  InlineStrings.
- The 6,631 invalidated instances of our packages start at 231 methods of ours
  in 80 files. The 12 largest account for about 4,600: `getindex(::CellVector,
  ::Integer)` (888), `get_selection(::Document)` (882), `_sc(px::Integer)` (734),
  `_get_part_color` (478), `with_font_size` (417), `tessellate_spline` (341),
  `_span_len` (203), `_trail_into!` (153), `_render_elem_y` and
  `_render_elem_x` of SDL (292), `UntrackedCell` (105), `_round_pixel` (96).

The scripts are in `/var/tmp/meas`: `first_frame.jl` (the timing),
`roots.jl` (the methods of ours where invalidations start), `invalidations.jl`.

## Decisions

- **D1** (the owner): every package that a session loads compiles its own code
  in its own `@compile_workload`. No extension or extra package exists for a
  combination of packages.
- **D2**: a workload runs code, the path that a user takes, and does not replay
  a statement file.
- **D3**: invalidations are removed where they start, in our code: a value gets
  a concrete type where it is made (`Int`, `Float64`, `String`), and a function
  that other packages extend keeps to its contract (a field, not a method). Then
  a method that a later package adds can not match our compiled calls, and the
  package images stay valid with any set of packages loaded after them.
- **D4**: the rule "a compile workload lives only in a leaf" of
  `package-rules.md` and its test in `PackageGraphTest.jl` change to D1 and D3.
- **D5** (the owner, 2026-10-08): if the first frame is under a second without
  AutoPrecompile, ProjecturEd stops recommending AutoPrecompile.

- **D6** (mine, for the owner to confirm): `DEFAULT_BACKEND`, a `ScopedValue` of
  the kernel, names the backend that a caller who names none gets, for the time
  of a scope. The workload calls `display_in_editor(value)` as a user does, and
  the editor gets `backend = nothing` in both, so the specializations that carry
  the backend in their keywords are the same. A method of `get_backend_output`
  for the workload backend would make it a second backend that draws windows,
  and a session with SDL would then refuse to choose. Outside a scope it holds
  `nothing`, and the choice among the loaded backends is as before.
- **D7**: a call of a protocol that packages loaded later extend goes through
  `invokelatest`, because no argument type can keep it valid: the backend
  protocol of the editor loop (`initialize_backend!`, `configure_devices!`,
  `open_native_windows!`, `wait_for_input`, `take_from_devices!`,
  `write_to_devices!`, `quit_backend!`), `get_backend_output` in the window check
  and the choice of a backend, `apply_settings!` and `find_system_colors` on the
  backend, and the sort of the kept rows, which runs code of DataFrames.
- **D8**: an integration loads the packages below it before the package that it
  joins, as a session of `using Projectured, DataFrames` loads them. Its build
  then meets the platform code that the joined package invalidates, and its
  workload compiles that code into its image.
- **D9**: a value from a cell is `Any`. Where it reaches a function that other
  packages extend, it gets its concrete type first (`::Int`, `::String`,
  `::SpanPath`, `::NamedTuple`), or the helper that takes it has an untyped
  argument: an argument annotation `::Integer` makes Julia infer the body for the
  abstract type, where `Int(x)` meets the constructors that SentinelArrays adds.
  A call that gives up during inference returns `Any`, so its result gets a type
  assertion too.

## Steps

1. [x] `get_selection`. Done: the default of the kernel answers `nothing` for a
   document without a `selection` field, `hasfield(typeof(document), :selection)`,
   and the two methods of ProjecturedDataFrames go. A field that always holds
   `nothing` was tried first and failed: the walk of `set_selection!` treats a
   `selection` field as a cell and writes into it, and it passes over a
   document without the field. So the default now agrees with the walks.
   `hasfield` and not `hasproperty`, because DataFrames adds a method to
   `hasproperty`. The docstring of `get_selection` says the same. Tests:
   `test_selection` 52, and of the data frames the columns 35, the paths 19 and
   the column edits 27.
2. [x] The workloads, with `PrecompileTools`. Done: `DisplayModule` has
   `run_display_workload(value; backend, frames)`, which starts the editor as the
   first `display_in_editor` does, waits for a frame and stops it, and
   `WorkloadBackend`, a backend with no device that reads the whole output so
   that every view prints. The platform shows a `WidgetLabel` with it,
   ProjecturedDataFrames a frame of 20 rows with the columns `Int`, `Float64`,
   `String`, `Bool` and `Union{Missing,Int}`, and ProjecturedSDL a `WidgetLabel`
   with `SdlBackend` under `SDL_VIDEODRIVER=offscreen`. The kernel has no
   workload: the platform reaches its code. PrecompileTools joins the `[deps]`
   of the three packages, and the two manifests that hold them,
   `environment/all` and `environment/readme-data-frame`, are changed by hand,
   because a resolve in a worktree writes wrong paths for the sibling checkout.
   Measured once: the build takes 199 s (134 s with no workload), the `using`
   line 1.79 s, and the first frame 5.2 s (48 s with no workload). The session
   still compiles 271 statements: 140 of the kernel and the platform, 88 of
   Base and others, 30 of SDL, 12 of DataFrames, 1 of both. Among them are
   `SdlBackend()` and `write_to_devices!(::SdlBackend, …)`, which the SDL
   workload runs: when an image loads, Julia drops its code that a method of a
   package loaded before it, absent at its build, can match. So the
   invalidations of step 3 hit each image from both sides.
3. [x] The invalidations, the largest first, by D3, D7, D8 and D9. Done:
   `c1e9427ca`, `79e72c26d`, `e42d82be9`, `0a4a054ff`. Each round ran the root
   report, `precompile_blockers` with the first caller of ours above each
   blocker, and the first frame cold and warm in one process.

   | After | First frame |
   | --- | ---: |
   | the workloads (step 2) | 5.2 s |
   | `hasproperty` → `hasfield` on structs | 4.1 s |
   | the workload calls `display_in_editor`, with events (D6) | 3.2 s |
   | the data frame package loads the platform first (D8) | 2.8 s |
   | the call sites of the blockers (D9), the settings and the sort (D7) | 1.3 s |
   | the backend protocol of the loop and the window check (D7) | 1.06 s |
   | a lazy table in the workloads of the platform and SDL | 0.75 s |

   The `using` line takes 1.68 s, from 1.35 s, because the images are larger.
   A second first frame in the same process takes 0.15 s. Facts found:
   - Without the umbrella, the data frame workload left no recompilation; with
     `using Projectured`, half of its compile time was recompilation, because
     the umbrella loads the platform before DataFrames. D8 fixed it.
   - When an image loads, Julia drops its code that a method of a package loaded
     before it, absent at its build, can match. So the packages of the SDL
     bindings (CEnum, FixedPointNumbers, OrderedCollections, DataStructures)
     invalidated the code of the data frame image, and the packages of
     DataFrames invalidated the code of the SDL image.
   - The workload backend needed the events of a hand and a table whose rows
     come from a lazy list: the first frame of SDL reads window and pointer
     events, and paints list nodes.
   - One blocker is left: `getindex(::CellVector, ::Integer)`, through
     `to_index(::Integer)`, from a caller that this round did not find.
4. [x] A guard. Done (`00489b9ae`): `test_first_window_compiles_little` of the
   integration suite starts the session of the README in a fresh process, with
   `Base.cumulative_compile_time_ns`, and asserts that the first window compiles
   for less than 2 s; it measures 0.65 s. Compile time and not wall time, so a
   slow machine does not fail it. It needs no SnoopCompile: the packages load by
   their ids, so it runs in the test environment of the release too.
5. [x] D4. Done (`00489b9ae`): `package-rules.md` says where a workload lives and
   the three rules that keep its code valid (D9, D7, D8), and the package graph
   test allows the entry files of the three packages. The slice table lets
   `display` use `collection`, `graphics` and `layout` (`0765cb199`), and the
   workload names have their own export statement. Tests: the kernel suite 4,215
   passed; the data frame suite 608; the platform tests that the change broke
   pass again (pane surgery 99, built from empty 50, drag and drop 251, gestures
   73, the window shell 138, the window wrappers 43, the layering guards); the
   package graph 385. Two failures are on `main` as well and not from this
   change: `test_interface_api` counts 32 names where it expects 31, and the SDL
   `TreeRenderTest` sets a field `size` that `WidgetTree` does not have. The
   static guards report what they report on `main`. `ProjecturedTest` does not
   load in a worktree: `environment/all` names `AgentClientProtocol`, which this
   depot lacks, and `ClaudeCodeACP`, a sibling checkout.
6. [x] The measurement, 2026-10-08, interleaved, Julia 1.13.1, one thread, the
   window offscreen, at a load of 48 to 61 from other work:

   | | first frame, median | `using` line | a second first frame |
   | --- | ---: | ---: | ---: |
   | `main` (5 runs) | 53.4 s | 1.46 s | 0.17 s |
   | this branch (6 runs) | **0.86 s** | 1.87 s | 0.12 s |

   At a load of 8 the branch measured 0.75 s. From an empty depot of compiled
   code, the build of the README packages took 199 s with the workloads (the
   first build of step 2) and 134 s with none.
7. [ ] D5: if the target is met, the front page of `Projectured.jl`, the web page
   and the README of AutoPrecompile stop recommending it. The statement files
   in `precompile/` stay while the dev REPL replays them.
8. [ ] Release 0.1.1, by the steps of the release plan for a new version.
