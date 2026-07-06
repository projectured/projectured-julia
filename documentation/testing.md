# Testing in the REPL

The test suite is a DAG of **test packages** that parallels the runtime
package DAG (see [plan/done/test-package-split.md](../plan/done/test-package-split.md)):

```
runtime:  ProjecturedKernel ← ProjecturedBase ← ProjecturedVisual ← ProjecturedDomain ← Projectured ← {Example, Sdl, …}
tests:    ProjecturedKernelTest ← ProjecturedBaseTest ← ProjecturedVisualTest ← ProjecturedDomainTest ← ProjecturedTest
```

- [package/kernel-test](../package/kernel-test/src/ProjecturedKernelTest.jl) —
  kernel unit tests + the **shared generic drivers** (`test_printer`,
  `test_reader`, `test_repl`, the navigation explorers, `_walk!`) + the shared
  static `check_layering` guard. Aggregator: `test_kernel()`.
- [package/base-test](../package/base-test/src/ProjecturedBaseTest.jl) —
  collection/copying tests + the ground-truth selection enumerators.
  Aggregator: `test_base()`.
- [package/visual-test](../package/visual-test/src/ProjecturedVisualTest.jl) —
  syntax/text/graphics/layout documents, text/graphics/widget projections, the
  type-in and click-roundtrip drivers. Aggregator: `test_visual()`.
- [package/domain-test](../package/domain-test/src/ProjecturedDomainTest.jl) —
  json/xml/sql/tabular documents and parsers, the `*ToSyntax` projections,
  graph, and the domain-fixture-driven Console/Pdf/table/TypeReference suites.
  Aggregator: `test_domain()`.
- [package/test](../package/test/src/ProjecturedTest.jl) — the umbrella:
  the `Example`-typed driver overloads, the all-examples sweeps, and every
  full-stack integration suite that needs the editor loop or an opt-in
  backend (Sdl/Odbc/Tulip/Video). Aggregator: `test_all()`.

Each test package only depends on the runtime package it tests (plus the test
packages below it), so `test_kernel()`…`test_domain()` run without SDL, ODBC,
or any other opt-in dependency installed.

Every top-level function is *callable directly from the REPL*. There is no
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

Runs everything: the four per-layer suites (`test_kernel()`, `test_base()`,
`test_visual()`, `test_domain()` — each includes its package's static
layered-architecture guard) followed by the umbrella integration tests
(printers, readers, selections, REPL-loop tests, the MCP tool tests, and the
mouse-click / click-round-trip sweeps — see
[test/src/ProjecturedTest.jl](../package/test/src/ProjecturedTest.jl)).

`test_all` is just a `@testset` that calls the per-layer functions in
sequence; pick the one you actually need and skip the rest.

## Per-layer tests

| Function | What it covers |
|---|---|
| `test_kernel()` | The whole kernel suite: `test_cell()`, `test_document_contract()`, `test_reference_builder()`, `test_gesture_binding()`, …, plus the kernel layering guard. |
| `test_base()` | `test_collection()`, `test_copying_projection()`, the base layering guard. |
| `test_visual()` | `test_syntax()`, `test_text()`, `test_graphics()`, `test_syntax_to_text()`, `test_text_to_graphics()`, the widget projection suites, the visual layering guard. |
| `test_domain()` | `test_json()`, `test_json_to_syntax()`, the xml/sql/formula/filesystem projections, parsers, graph, Console/Pdf backends, the domain layering guard. |
| `test_cell()` | The reactive cell primitive (in `ProjecturedKernelTest`; run inside `test_kernel()` or standalone). |
| `test_documents()` | The umbrella-only document suites (`test_constraint_solver()` — Tulip, `test_serialization()` — example fixtures). |
| `test_projections()` | The umbrella-only projection suites (example/editor/SDL-coupled: tooltip, hover, dragging, write_image, …). |
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
| `walk_printer_output(doc, proj)` | [kernel-test PrinterTest.jl](../package/kernel-test/src/editor/PrinterTest.jl) | Calls `print_document`, reflexively walks every field of the resulting iomap, and forces every `Cell` via `c[]`. Returns `(errors, status)`. |
| `walk_reader_events(doc, proj)` | [kernel-test ReaderTest.jl](../package/kernel-test/src/editor/ReaderTest.jl) | Prints once, then fires every key / mouse event in `_ALL_READER_EVENTS` through `read_intent`. Returns `errors::Vector{String}`. |
| `walk_repl_loop(doc, proj)` | [kernel-test ReplTest.jl](../package/kernel-test/src/editor/ReplTest.jl) | The complete read → evaluate → reprint → walk cycle, repeated for every event. The closest thing to driving the real editor headlessly. Returns `errors::Vector{String}`. |
| `explore_text_selections(doc, proj[, initial])` | [kernel-test TextNavigationTest.jl](../package/kernel-test/src/editor/TextNavigationTest.jl) | BFS over reachable text-caret selection states using navigation keys. Returns `(state_count, errors, visited)`. |
| `collect_text_selections(doc)` / `collect_tree_selections(doc; is_node)` | [base-test SelectionEnumeration.jl](../package/base-test/src/document/SelectionEnumeration.jl) | Ground-truth selections enumerated directly from the document (all carets / all whole-element nodes), for the completeness suites to check against. |
| `walk_typein(doc, proj)` | [visual-test TypeinTest.jl](../package/visual-test/src/editor/TypeinTest.jl) | Types a character into every reachable string and verifies the cursor renders and the edit lands. Returns one `(ref, ok, message)` result per string. |

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
[kernel-test/src/editor/PrinterTest.jl](../package/kernel-test/src/editor/PrinterTest.jl))
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
julia> Pkg.test("ProjecturedKernelTest")   # or ProjecturedBaseTest / ProjecturedVisualTest / ProjecturedDomainTest
```

Each test package ships a one-line `test/runtests.jl` that calls its
aggregator, so `Pkg.test` and the REPL functions cover the same ground.

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
- **Changed the kernel/base/visual/domain source layering.** The per-package
  layering guards (`test_kernel_layering()`, `test_base_layering()`, …) parse
  the real `import ..XxxModule` headers and re-check the include order in ~1s.
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
