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
3. [ ] The invalidations, the largest first, by D3. After each group, the root
   report again. Each file is checked against `SEALING.md` before the change.
4. [ ] A guard: a test that loads the README packages under
   `@snoop_invalidations` and fails when the invalidated instances of our
   packages pass a ceiling.
5. [ ] D4: the rule and its test.
6. [ ] The measurement: interleaved against `main`, the same script. The target
   is a first frame under one second. The trace of the session tells what is
   still compiled.
7. [ ] D5: if the target is met, the front page of `Projectured.jl`, the web page
   and the README of AutoPrecompile stop recommending it. The statement files
   in `precompile/` stay while the dev REPL replays them.
8. [ ] Release 0.1.1, by the steps of the release plan for a new version.
