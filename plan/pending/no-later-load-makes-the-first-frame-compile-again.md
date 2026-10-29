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

1. [ ] Fix the ten calls of the table: a type assertion with the declared type,
   a vector of a concrete type, or for an open function `@max_methods 1`.
2. [ ] Measure the session again: the first frame, its compilation, the calls
   compiled again, and the invalidation log. Name each next root, but do not fix it.
3. [ ] Run the narrow tests of the changed files.
