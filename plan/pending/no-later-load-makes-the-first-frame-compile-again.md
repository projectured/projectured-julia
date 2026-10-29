# No later load makes the first frame compile again

Status: in progress, branch `invalidation-roots`.

## The issue

The session of the README, with the line

```julia
using Projectured, SimpleDirectMediaLayer, DataFrames
display_in_editor(df)   # 100 000 rows
```

compiles 1.2 s in its first frame, and 0.86 s of it is code that the images
already held. A package that loads after an image adds a method to a function
of Base, and Julia makes invalid each call of that image that it compiled with an
argument of an abstract type, such as `Any`, `Integer` or `AbstractString`.

Measured on main `d338b8d04`, 2026-10-29, `environment/readme-data-frame`:

| | |
|---|---:|
| the `using` line | 2.2 s |
| the first frame | 1.4 s |
| compilation in the first frame | 1.2 s |
| of it, code compiled again | 0.86 s |
| calls compiled again | 23 of 81 |

## The roots

The invalidation log of Julia (`jl_debug_method_invalidation`) names the method
that each later package adds and the call of our code that it makes invalid.
The fix is at the call, so it holds for each load order and each set of
packages: a call with an argument of a concrete type, or a call that inference
does not follow, stays valid when a package adds a method.

| The method that a later package adds | Our call | Time |
|---|---|---:|
| SentinelArrays `eltype(::BufferedVector)` | `_is_hashed_faithfully`: `eltype(value)` of an `AbstractArray` | 244 ms |
| SentinelArrays `Int64(::ChainedVectorIndex)` | `_render_polygon!`: the points of a `GraphicsPolygon` (`points::Any`) collected | about 250 ms, with the next two |
| the same | `_find_cell_slot`: `step.start + 1` of an abstract step, so `get_slot_at(…, ::Integer)` | |
| the same | `drain_system_process_tree!`: `collect(Int, tree.root_process_ids)`, a field read of a document | |
| CEnum `&` on `Cenum` | `_push_icon_mark!`: `string(content)` of an `Integer` | 148 ms |
| CEnum `\|` on `Cenum` | the placeholder of a text widget: `isempty(string(…))` is `Any`, then `\|=` | 37 ms |
| ProjecturedPlatform `operation_reference(::PasteOsClipboardOperation)` | the kernel `read_intent`: `operation_reference(operation)` of `Any`, three kernel methods | 75 ms |
| OrderedCollections `sort!(::LittleDict; by)` | `_write_json`: `sort!` of a comprehension over an `AbstractDict` | with the next two |
| Tables `startswith(::Tables.Col, ::AbstractString)` | `_get_marker_text_tag`: `String(e.args[1])` is `Any` | |
| LaTeXStrings `match(::Regex, ::LaTeXString)` | `_read_command_output` returns `fetch(reader)`, which is `Any` | 22 ms |

The three fault-barrier instances (62 ms) come from `_write_json`,
`_get_marker_text_tag` and `drain_system_process_tree!`.

Most of these values are `Any` because a field read of a `@document` gives no
type, for example `tree.root_process_ids`, declared `Vector{Int}`. The macro is
in the sealed struct layer, so this plan fixes each call and leaves the macro.

## Steps

1. [x] Fix the ten calls of the table: a type assertion with the declared type,
   a vector of a concrete type, or for an open function `@max_methods 1`.
   Done in `6914a01db`. The count of an icon mark uses `Base.inferencebarrier`,
   as `PredFile.jl` does, because a count can be of any integer type.
2. [x] Measure the session again: the first frame, its compilation, the calls
   compiled again, and the invalidation log. Name each next root, but do not fix it.

   | | main `d338b8d04` | this branch |
   |---|---:|---:|
   | the `using` line | 2.2 s | 2.2 s |
   | the first frame | 1.44 s | 1.16 s |
   | compilation in the first frame | 1.2 s | 0.81 s |
   | of it, code compiled again | 0.86 s | 0.48 s |
   | calls compiled again | 23 of 81 | 17 of 75 |

   The next roots, not fixed:

   | The method that a later package adds | Our call | Time |
   |---|---|---:|
   | SentinelArrays `IteratorSize(::BufferedVector)` | `compute_polyline_before_arrowheads(…, ::AbstractVector, …)` | about 215 ms |
   | DataFrames `eltype(::Type{RepeatedVector})` | `_is_hashed_faithfully`: `eltype(typeof(value))` of an abstract array | 213 ms |
   | ProjecturedPlatform `is_collecting_operation(::OpenContextMenuOperation)` | the kernel `_read_outward`, with an operation of type `Any` | 128 ms |
   | SentinelArrays `Int64(::ChainedVectorIndex)` | `_refresh_canvas_bounds!` on a `CellVector{Any}` | 43 ms |

   The fix of step 1 for `_is_hashed_faithfully` moved its root and did not
   remove it: `eltype` of the type is open to a package as `eltype` of the value
   is. A call that inference follows into one method of an argument of an
   abstract type stays open to the next package; only a concrete type, more
   matching methods than `max_methods`, or a call that inference does not follow
   closes it.
3. [x] The owner asked for a second round: fix the four roots of step 2.
   - `_render_polyline!` fills a `Vector{Tuple{Int,Int}}`, as `_render_polygon!` does.
   - `_is_hashed_faithfully` gives a signature only to an `Array`. Another array
     has none, so its leaf is painted whenever it is stale.
   - `is_collecting_operation` has two methods in the kernel, so
     `@max_methods 1` closes it, as it closes `operation_reference`.
   - `_refresh_canvas_bounds!` reads the length of the vector as an `Int`.
   - The `@max_methods` line of `operation_reference` moves from
     `OperationInterface.jl` to `Rerooting.jl`: the kernel guard
     `PAR-INTERFACE-DECLARES-ONLY` allows no macro call in an interface file.
4. [x] Measure the session again, as in step 2. Name each next root, but do not fix it.

   | | main `d338b8d04` | step 1 | step 3 |
   |---|---:|---:|---:|
   | the first frame | 1.44 s | 1.16 s | 1.08 s |
   | compilation in the first frame | 1.2 s | 0.81 s | 0.85 s |
   | of it, code compiled again | 0.86 s | 0.48 s | 0.37 s |
   | calls compiled again | 23 of 81 | 17 of 75 | 10 of 68 |

   The compilation of new calls grows as the recompilation shrinks: a callee
   that a recompile no longer compiles first is compiled with the new call
   that needs it. The largest new call is `_make_index_node` with the types of
   a data frame, 227 ms, which no recorded list holds.

   The next roots, not fixed:

   | The method that a later package adds | Our call | Time |
   |---|---|---:|
   | SentinelArrays `IteratorSize(::BufferedVector)` | `_render_spline!` collects the points of a spline | about 245 ms |
   | ProjecturedPlatform `append_fault!(::FaultSafeModeProjection, …)` | the kernel `_hand_fault_to_targets!`, with a target of type `Any`; the fault layer is sealed | 122 ms |
   | ProjecturedPlatform `get_document_gesture_bindings_own(::Type{SyntaxCompound})` | the kernel `_gesture_bindings`, with an abstract `Type` | 10 ms |

   A root shows only when no root before it made its caller invalid, so each
   round shows the next level.
5. [ ] Run the narrow tests of the changed files: `test_kernel()`, `test_sdl()`,
   `test_dataframes()` and the 229 parts of `test_platform()`. A run on the code
   of step 1 gave: `test_dataframes()` 628 of 628; `test_kernel()` 1 failure, the
   guard above; `test_sdl()` 1 failure and 1 error in `SdlWorkloadTest`, where
   `SDL_PushEvent` says that the event system has been shut down.
