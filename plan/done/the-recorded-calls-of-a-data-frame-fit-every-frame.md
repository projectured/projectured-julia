# The recorded calls of a data frame fit every frame

Status: done, landed on main.

## The issue

After `plan/done/no-later-load-makes-the-first-frame-compile-again.md`, the
first frame of the README session

```julia
using Projectured, SimpleDirectMediaLayer, DataFrames
display_in_editor(df)   # 100 000 rows, two columns of Int64
```

takes 1.08 s and compiles 0.85 s, 0.37 s of it again (main `e52478247`).

The largest new call is `_make_index_node` with the row closure of the data
frame view, 227 ms. The list `ProjecturedDataFrames/precompile/workload.txt`
holds that call, but with another type. `_make_row_list` keeps the element type
of each column in `Dict(name => eltype(frame[!, name]) for name in columns)`,
and Julia chooses the value type of that `Dict` from the frame: `Dict{String,
Type}` for the frame of the workload, which has a column of `Union{Missing,
Int64}`, and `Dict{String, DataType}` for a frame of `Int64` columns only. The
row closure captures the `Dict`, so its type, and each call that it is part of,
differs between the two frames, and the image holds only one of them.

The largest call compiled again comes from `_render_spline!`: it collects the
points of a spline (`points::Any`), so `_stroke_polyline!` gets a vector of no
type, and SentinelArrays `IteratorSize(::BufferedVector)` makes that code
invalid (about 245 ms).

## Steps

1. [x] `_make_row_list` keeps the column types in a `Dict{String,Type}`, so
   the row closure has one type for every frame.
2. [x] `_render_spline!` fills a `Vector{Tuple{Float64,Float64}}`, as
   `_render_polygon!` does.
3. [x] Measure the session again: the first frame, its compilation, the calls
   compiled again, and the new calls that no list holds. Name each next root,
   but do not fix it.

   | | main `e52478247` | this branch |
   |---|---:|---:|
   | the `using` line | 2.2 s | 2.1 s |
   | the first frame | 1.08 s | 0.70 s |
   | compilation in the first frame | 0.85 s | 0.55 s |
   | of it, code compiled again | 0.37 s | 0.27 s |
   | calls compiled again | 10 of 68 | 5 of 59 |

   The new calls that remain take 170 ms together, and the largest takes 26 ms.

   All five calls compiled again have one root: the platform adds
   `get_document_gesture_bindings_own(::Type{WidgetShell})`, and the kernel
   `collect_document_gesture_bindings` calls `get_document_gesture_bindings_own(S)`
   with an abstract `Type`, which inference follows into the one kernel method.
   The earlier rounds measured it at 10 ms only because other roots made its
   callers invalid first. `append_fault!` does not show any more.
4. [x] Run the narrow tests: `test_dataframes()`, `test_sdl()`.
   `test_dataframes()` 628 of 628; `test_sdl()` 1083 passed, 1 failed, 1 error,
   the counts of the known failure of `SdlWorkloadTest` on main.

Not in this plan:
- `append_fault!` (122 ms): its call and its only kernel method are in the
  sealed fault layer (`fault/FaultStore.jl`, `fault/FaultDefaults.jl`). A fix
  needs the permission of the owner for each file.
- `get_document_gesture_bindings_own` (the 0.27 s that the first frame still
  compiles again): the kernel has one method, so `@max_methods 1` does not close
  the call. `Base.invokelatest` closes it, but it changes the world in which a
  binding is read. The owner decided on 2026-10-30: no `invokelatest`.
