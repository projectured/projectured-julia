# Testing in the REPL

The test suite is structured as a regular Julia package
([test/src/ProjecturedTest.jl](../package/test/src/ProjecturedTest.jl)) whose
top-level functions are *all callable directly from the REPL*. There is no
hidden runner: anything `test_all` does is something you can do one piece
at a time.

```sh
cd projectured
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
printers, readers, selections, REPL-loop tests, the MCP tool tests, and the
mouse-click / click-round-trip tests (`test_mouse_clicks()` /
`test_click_roundtrips()` are called by `test_all` — see
[test/src/ProjecturedTest.jl](../package/test/src/ProjecturedTest.jl)).

`test_all` is just a `@testset` that calls the per-layer functions in
sequence; pick the one you actually need and skip the rest.

## Per-layer tests

| Function | What it covers |
|---|---|
| `test_cell()` | The reactive cell primitive. |
| `test_documents()` | Aggregates the per-domain document tests below. |
| `test_json()`, `test_syntax()`, `test_text()`, `test_graphics()`, `test_graphics_layout()`, `test_collection()` | Domain-specific document tests in [test/src/document/](../package/test/src/document/). |
| `test_projections()` | Aggregates the projection-to-projection tests. |
| `test_json_to_syntax()`, `test_syntax_to_text()`, `test_text_to_graphics()`, `test_copying_projection()` | Pipeline-stage tests in [test/src/projection/](../package/test/src/projection/). |
| `test_printers()` | Runs `test_printer` over every entry in `examples`. |
| `test_readers()` | Runs `test_reader` over every example. |
| `test_text_navigations()` | Runs `test_text_navigation` (text-caret BFS, no-error sweep) over every example. |
| `test_text_navigations_complete()` | Over a curated subset, additionally asserts navigation reaches every caret enumerated from the document (`collect_text_selections`). |
| `test_tree_navigations_complete()` | Same idea for whole-element/structural selections (`collect_tree_selections`); curated to the native syntax tree. |
| `test_repls()` | Runs `test_repl` (full read-eval-print loop) over every example. |
| `test_typeins()` | Runs `test_typein` (type a character into every string and check the edit) over the supported field-addressed examples. |
| `test_mcp_tools()`, `test_mcp_resources()` | MCP server tools and resources. |
| `test_mouse_clicks()` | Mouse-click round-tripping. Run by `test_all`. |

## Testing a single example

Each example-level test is also defined for a single `Example` or a labelled
`(document, projection)` pair:

```julia
julia> test_printer(json_example)
julia> test_reader(json_example)
julia> test_text_navigation(json_example)                 # no-error caret BFS
julia> test_text_navigation(json_example; check_reaches_all=true)  # + reaches every enumerated caret
julia> test_repl(json_example)
julia> test_typein(json_example)

julia> ex = widget_example;
julia> test_printer("widget", ex.document, ex.projection)
```

`test_example(ex)` bundles printer + reader + repl + text-navigation + typein
for one example — useful when you have just added a new domain and want a single
command to exercise it.

Each example-level test emits **one `@test` per unit verified** rather than a
single `isempty(errors)` assertion, so the pass count reflects the work done:
`test_printer` asserts once per forced reactive cell, `test_reader`/`test_repl`
once per event, `test_text_navigation` once per reachable selection state, and
`test_typein` once per string. A failing unit names the offending
cell/event/state/reference in a `@warn`.

## The walker helpers (non-`@testset` variants)

When you want errors back as a `Vector{String}` instead of `@test` output —
e.g. you are iterating in the REPL and want to keep going on failure —
every test has a sibling that does the same work without wrapping it in
`@testset`:

| Helper | Location | What it does |
|---|---|---|
| `walk_printer_output(doc, proj)` | [PrinterTest.jl:115](../package/test/src/editor/PrinterTest.jl#L115) | Calls `print_document`, reflexively walks every field of the resulting iomap, and forces every `Cell` via `c[]`. Returns `(errors, status)`. |
| `walk_reader_events(doc, proj)` | [ReaderTest.jl:51](../package/test/src/editor/ReaderTest.jl#L51) | Prints once, then fires every key / mouse event in `_ALL_READER_EVENTS` through `read_intent`. Returns `errors::Vector{String}`. |
| `walk_repl_loop(doc, proj)` | [ReplTest.jl:27](../package/test/src/editor/ReplTest.jl#L27) | The complete read → evaluate → reprint → walk cycle, repeated for every event. The closest thing to driving the real editor headlessly. Returns `errors::Vector{String}`. |
| `explore_text_selections(doc, proj[, initial])` | [TextNavigationTest.jl:24](../package/test/src/editor/TextNavigationTest.jl#L24) | BFS over reachable text-caret selection states using navigation keys. Returns `(state_count, errors, visited)`. |
| `collect_text_selections(doc)` / `collect_tree_selections(doc; is_node)` | [SelectionEnumeration.jl](../package/test/src/editor/SelectionEnumeration.jl) | Ground-truth selections enumerated directly from the document (all carets / all whole-element nodes), for the completeness suites to check against. |
| `walk_typein(doc, proj)` | [TypeinTest.jl](../package/test/src/editor/TypeinTest.jl) | Types a character into every reachable string and verifies the cursor renders and the edit lands. Returns one `(ref, ok, message)` result per string. |

`walk_printer_output`, `walk_reader_events`, `walk_repl_loop`, and
`explore_text_selections` keep their plain return values for REPL use; each also
takes an optional callback (`oncell` / `onevent` / `onstate`) that the
`test_*` wrappers use to emit one `@test` per unit.

```julia
julia> errors, status = walk_printer_output(json_example.document, json_example.projection);
julia> isempty(errors)
true

julia> result = explore_text_selections(syntax_example.document, syntax_example.projection);
julia> result.state_count, length(result.errors)
```

## The shared reflexive walker

`_walk!` (in
[test/src/editor/PrinterTest.jl:45](../package/test/src/editor/PrinterTest.jl#L45))
is the workhorse behind every printer-based test. It descends every field
via `fieldnames` / `getfield`, follows every `Vector`, forces every `Cell`,
and uses an `objectid` `Set` to break cycles. New document types are
covered automatically as long as their fields are reachable through the
struct.

If you write a domain that stores state outside of struct fields (e.g. in a
side table), `_walk!` will not see it; either expose it as a field or add a
dedicated test under [test/src/document/](../package/test/src/document/).

## Validating the recursion contract

The four core projection functions (`print_document`, `read_intent`,
`map_reference_forward`, `map_reference_backward`) must each be **recursive** —
descending into children only by delegating to the child projection's own version
of the same function. That is [the recursion contract](projection-system.md#the-recursion-contract),
and a load-bearing half of it is that **no fifth recursive function may be
introduced** to do the descent: the four functions are the only interface every
projection implements, so any extra recursive function would break the moment a
pipeline composed a projection that lacks it.

The same constraint binds the *validation*: it is done **externally**, by a harness
that drives the four functions over composed examples, and it must add **no new
per-projection generic function** of its own. The harness reuses the existing
walkers rather than introducing an interface method:

- **Reachability** — enumerate every reference with `collect_text_selections` /
  `collect_tree_selections` and assert `map_reference_forward` returns a non-`nothing`
  image for each. A deeply nested reference can only have an image if the mapper
  delegated all the way down; a flattening mapper drops what it never recursed into.
- **Round-trip** — `map_reference_backward(map_reference_forward(ref))` returns the
  original (modulo the documented `ProjectionReference`/flat-offset collapse for
  projection-introduced positions). Round-tripping at every level is the signature
  of lockstep recursion.
- **Printer lockstep** — reuse `_walk!` to reach every iomap; for any iomap carrying
  `child_iomaps`, assert each `child_iomap.output` is object-identical to the
  corresponding child of the parent output (the printer spliced delegated children,
  it did not rebuild the subtree).
- **Composition substitution** — the discriminating check: substitute the projection
  used for one child subtree (via an existing higher-order projection), and assert
  the parent output reflects it. A compliant projection delegates, so the swap takes
  effect; a flattening one ignores `recursion` and the swap is a no-op — the test
  fails. This is what flags `SyntaxToText`.

The harness lives in
[package/test/src/editor/RecursionContractTest.jl](../package/test/src/editor/RecursionContractTest.jl):

| Function | What it does |
|---|---|
| `test_recursion_contract(example)` / `test_recursion_contracts()` | `@testset` running the delegation probe over the curated structural pipelines (`json`, `xml`, `syntax`, `math`). |
| `probe_delegation(doc, proj)` | Re-invokes each node projection with a spy `recursion` and reports `(projection_name, count, delegated, broken)` per node. |
| `walk_reference_roundtrip(doc, proj)` | The reachability + round-trip check, returning findings as a `Vector{String}` for REPL use. |
| `walk_recursion_contract(doc, proj)` | Both checks combined, findings as a `Vector{String}`. |

The asserted check is the **delegation probe** — the discriminating test, which adds
no per-projection generic function (the spy is an ordinary higher-order projection).
Every probed node now delegates: `SyntaxNodeToText` was the last flattener (reached
transitively by all four examples) and the refactor in
`plan/done/syntaxtotext-delegation.md` converted it to School A, so it is now a plain
`@test`. `test_recursion_contracts()` is opt-in (not yet wired into `test_all`); the
reference round-trip is exposed as the REPL walkers above rather than asserted,
pending calibration on a running editor.

## Running tests via Pkg

The standard `Pkg` workflow also works and is what CI uses:

```julia
julia> using Pkg
julia> Pkg.test("ProjecturedTest")
```

…but for iterative work the REPL functions are much faster because they
keep the SDL backend initialised between runs (`__init__` in
[test/src/ProjecturedTest.jl:13](../package/test/src/ProjecturedTest.jl#L13)).

## Typical workflows

- **Added a new example.** `test_printer(my_example)`, then
  `test_reader(my_example)`, then `test_text_navigation(my_example)`, then
  `test_repl(my_example)`. Once those pass, the example is automatically
  picked up by `test_printers` / `test_readers` / etc. because they loop
  over the `examples` vector.
- **Changed a projection.** `walk_printer_output` and `walk_repl_loop`
  against the affected example give you a fast failure surface; the latter
  also catches reader/operation mismatches.
- **Suspected reactive bug.** `test_cell()` first, then
  `walk_printer_output` (which forces every reachable cell) on the
  affected example.
- **Selection navigation bug.** `explore_text_selections(doc, proj)` returns
  every reachable state; small `state_count` numbers are often the symptom
  of a stuck navigator. To check *coverage*, compare against
  `collect_text_selections(doc)` (or use `test_text_navigation(ex; check_reaches_all=true)`).

See [the debugging guide](debugging.md) for the matching REPL helpers
(`run_example`, `print_example`) that let you reproduce a failure
interactively before reaching for the test functions.
