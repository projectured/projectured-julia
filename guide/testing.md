# Testing in the REPL

The test suite is structured as a regular Julia package
([test/src/ProjecturedTest.jl](../test/src/ProjecturedTest.jl)) whose
top-level functions are *all callable directly from the REPL*. There is no
hidden runner: anything `test_all` does is something you can do one piece
at a time.

```sh
cd predj
julia --project=.
```

```julia
julia> using Projectured, ProjecturedExample, ProjecturedTest
```

## The top-level entry point

```julia
julia> test_all()
```

Runs everything: cells, per-domain document tests, projection tests,
printers, readers, selections, REPL-loop tests, and the MCP tool tests.
Mouse-click tests are currently disabled — see
[test/src/ProjecturedTest.jl:63](../test/src/ProjecturedTest.jl#L63).

`test_all` is just a `@testset` that calls the per-layer functions in
sequence; pick the one you actually need and skip the rest.

## Per-layer tests

| Function | What it covers |
|---|---|
| `test_cell()` | The reactive cell primitive. |
| `test_documents()` | Aggregates the per-domain document tests below. |
| `test_json()`, `test_syntax()`, `test_text()`, `test_graphics()`, `test_graphics_layout()`, `test_collection()` | Domain-specific document tests in [test/src/document/](../test/src/document/). |
| `test_projections()` | Aggregates the projection-to-projection tests. |
| `test_json_to_syntax()`, `test_syntax_to_text()`, `test_text_to_graphics()`, `test_copying_projection()` | Pipeline-stage tests in [test/src/projection/](../test/src/projection/). |
| `test_printers()` | Runs `test_printer` over every entry in `examples`. |
| `test_readers()` | Runs `test_reader` over every example. |
| `test_selections()` | Runs `test_selection` over every example. |
| `test_repls()` | Runs `test_repl` (full read-eval-print loop) over every example. |
| `test_mcp_tools()`, `test_mcp_resources()` | MCP server tools and resources. |
| `test_mouse_clicks()` | Mouse-click round-tripping. Disabled in `test_all` until fixed. |

## Testing a single example

Each example-level test is also defined for a single `Example` or a labelled
`(document, projection)` pair:

```julia
julia> test_printer(json_example)
julia> test_reader(json_example)
julia> test_selection(json_example)
julia> test_repl(json_example)

julia> ex = widget_example;
julia> test_printer("widget", ex.document, ex.projection)
```

`test_example(ex)` bundles printer + reader + selection for one example —
useful when you have just added a new domain and want a single command to
exercise it.

## The walker helpers (non-`@testset` variants)

When you want errors back as a `Vector{String}` instead of `@test` output —
e.g. you are iterating in the REPL and want to keep going on failure —
every test has a sibling that does the same work without wrapping it in
`@testset`:

| Helper | Location | What it does |
|---|---|---|
| `walk_printer_output(doc, proj)` | [PrinterTest.jl:75](../test/src/editor/PrinterTest.jl#L75) | Calls `projection_print`, reflexively walks every field of the resulting iomap, and forces every `Cell` via `c[]`. Catches errors per object. |
| `walk_reader_events(doc, proj)` | [ReaderTest.jl:32](../test/src/editor/ReaderTest.jl#L32) | Prints once, then fires every key / mouse event in `_ALL_READER_EVENTS` through `projection_read`. |
| `walk_repl_loop(doc, proj)` | [ReplTest.jl:14](../test/src/editor/ReplTest.jl#L14) | The complete read → evaluate → reprint → walk cycle, repeated for every event. The closest thing to driving the real editor headlessly. |
| `explore_selections(doc, proj[, initial])` | [SelectionTest.jl:19](../test/src/editor/SelectionTest.jl#L19) | BFS over reachable selection states using navigation keys. Returns `(state_count, errors)`. |

```julia
julia> errors = walk_printer_output(json_example.document, json_example.projection);
julia> isempty(errors)
true

julia> result = explore_selections(syntax_example.document, syntax_example.projection);
julia> result.state_count, length(result.errors)
```

## The shared reflexive walker

`_walk!` (in
[test/src/editor/PrinterTest.jl:25](../test/src/editor/PrinterTest.jl#L25))
is the workhorse behind every printer-based test. It descends every field
via `fieldnames` / `getfield`, follows every `Vector`, forces every `Cell`,
and uses an `objectid` `Set` to break cycles. New document types are
covered automatically as long as their fields are reachable through the
struct.

If you write a domain that stores state outside of struct fields (e.g. in a
side table), `_walk!` will not see it; either expose it as a field or add a
dedicated test under [test/src/document/](../test/src/document/).

## Running tests via Pkg

The standard `Pkg` workflow also works and is what CI uses:

```julia
julia> using Pkg
julia> Pkg.test("ProjecturedTest")
```

…but for iterative work the REPL functions are much faster because they
keep the SDL backend initialised between runs (`__init__` in
[test/src/ProjecturedTest.jl:10](../test/src/ProjecturedTest.jl#L10)).

## Typical workflows

- **Added a new example.** `test_printer(my_example)`, then
  `test_reader(my_example)`, then `test_selection(my_example)`, then
  `test_repl(my_example)`. Once those pass, the example is automatically
  picked up by `test_printers` / `test_readers` / etc. because they loop
  over the `examples` vector.
- **Changed a projection.** `walk_printer_output` and `walk_repl_loop`
  against the affected example give you a fast failure surface; the latter
  also catches reader/operation mismatches.
- **Suspected reactive bug.** `test_cell()` first, then
  `walk_printer_output` (which forces every reachable cell) on the
  affected example.
- **Selection navigation bug.** `explore_selections(doc, proj)` returns
  every reachable state; small `state_count` numbers are often the symptom
  of a stuck navigator.

See [the debugging guide](debugging.md) for the matching REPL helpers
(`run_example`, `print_example`) that let you reproduce a failure
interactively before reaching for the test functions.
