# The recorded calls of a data frame fit every frame

Status: in progress, branch `frame-fit`.

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
3. [ ] Measure the session again: the first frame, its compilation, the calls
   compiled again, and the new calls that no list holds. Name each next root,
   but do not fix it.
4. [ ] Run the narrow tests: `test_dataframes()`, `test_sdl()`.

Not in this plan:
- `append_fault!` (122 ms): its call and its only kernel method are in the
  sealed fault layer (`fault/FaultStore.jl`, `fault/FaultDefaults.jl`). A fix
  needs the permission of the owner for each file.
- `get_document_gesture_bindings_own` (10 ms): the kernel has one method, so
  `@max_methods 1` does not close the call, and `Base.invokelatest` changes the
  world in which a binding is read.
