# Testing in the REPL

The test suite is a DAG of **test packages** that parallels the main
package DAG (see [plan/done/test-package-split.md](../plan/done/test-package-split.md)):

```
main:     ProjecturedKernel ← ProjecturedBase ← ProjecturedVisual ← ProjecturedDomain ← Projectured ← {Example, Sdl, …}
tests:    ProjecturedKernelTest ← ProjecturedBaseTest ← ProjecturedVisualTest ← ProjecturedDomainTest ← ProjecturedTest
```

- [package/kernel/test](../package/kernel/test/ProjecturedKernelTest.jl) —
  kernel unit tests + the **shared generic drivers** (`test_printer`,
  `test_reader`, `test_repl`, the navigation explorers, `_walk!`) + the shared
  static `check_layering` guard. Aggregator: `test_kernel()`.
- [package/base/test](../package/base/test/ProjecturedBaseTest.jl) —
  collection/copying tests + the ground-truth selection enumerators.
  Aggregator: `test_base()`.
- [package/visual/test](../package/visual/test/ProjecturedVisualTest.jl) —
  syntax/text/graphics/layout documents, text/graphics/widget projections, the
  type-in and click-roundtrip drivers. Aggregator: `test_visual()`.
- [package/domain/test](../package/domain/test/ProjecturedDomainTest.jl) —
  json/xml/sql documents and parsers, the `*ToSyntax` projections, graph, the
  domain-fixture-driven Console/Pdf/table/TypeReference suites, and the
  domain-coupled projection/editor tests (GestureMap/GestureHelp, DbCatalog→Sql,
  HoverProbe/ReferenceInspector, Dragging, Serialization, Mcp, Conversation,
  JuliaTypein, Workbench, …). Aggregator: `test_domain()`.
- The **opt-in** main packages each have their own test package, so a suite
  that needs a native backend lives with the backend it exercises (not in the
  umbrella): [package/sdl/test](../package/sdl/test) (`test_sdl()` — DirtyRect,
  write_image), [package/tulip/test](../package/tulip/test) (`test_tulip()` —
  the LP constraint solver), [package/video/test](../package/video/test)
  (`test_video()` — record_video), and [package/odbc/test](../package/odbc/test)
  (`test_odbc()` — the live-DB adapter + DbCatalog suites). Like the opt-in
  example packages they resolve through the root env and precompile only where
  the native dependency (SDL2 / Adaptagrams / FFMPEG / ODBC) is installed.
- [package/projectured/test](../package/projectured/test/ProjecturedTest.jl) — the umbrella:
  only the genuinely **cross-package** suites that sweep the interleaved `examples`
  / `catalog` aggregate (`ExampleSweeps`, `ExampleTest`, `CatalogTest`,
  `RecursionContract`, `MouseClick`, `PrinterLocality`). It `using`s every
  main-package test package and opt-in test package so `test_all()` still
  orchestrates the whole suite.

The examples follow the same split (`package/kernel/example` — the `Example`
harness core; `package/visual/example` / `package/domain/example` — the
per-package example sets with `visual_examples` / `domain_examples` registry
subsets; the
opt-in example packages — `package/odbc/example`, `package/tulip/example`,
`package/adaptagrams/example`, and `package/sdl/example` (the `LiveExample`
window/record timelines) — hold the examples that need a native dependency; the
`ProjecturedExample` umbrella keeps the interleaved `examples` registry and
Catalog discovery). Each test package depends on its example package: the
`Example`-typed driver overloads live beside the drivers, and `test_visual()` /
`test_domain()` run a printer sweep over their own package's examples
(`test_visual_examples()` / `test_domain_examples()`).

Each test package only depends on the main package it tests (plus the test
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

Runs everything: the four per-package suites (`test_kernel()`, `test_base()`,
`test_visual()`, `test_domain()` — each includes its package's static
layered-architecture guard) followed by the umbrella integration tests
(printers, readers, selections, REPL-loop tests, the MCP tool tests, and the
mouse-click / click-round-trip sweeps — see
[test/ProjecturedTest.jl](../package/projectured/test/ProjecturedTest.jl)).

`test_all` is just a `@testset` that calls the per-package functions in
sequence; pick the one you actually need and skip the rest.

## Per-package tests

| Function | What it covers |
|---|---|
| `test_kernel()` | The whole kernel suite: `test_cell()`, `test_document_contract()`, `test_reference_builder()`, `test_gesture_binding()`, …, plus the kernel layering guard. |
| `test_base()` | `test_collection()`, `test_copying_projection()`, the base layering guard. |
| `test_visual()` | `test_syntax()`, `test_text()`, `test_graphics()`, `test_syntax_to_text()`, `test_text_to_graphics()`, the widget projection suites, the visual layering guard, and the package's example printer sweep (`test_visual_examples()`). |
| `test_domain()` | `test_json()`, `test_json_to_syntax()`, the xml/sql/formula/filesystem projections, parsers, graph, Console/Pdf backends, the domain layering guard, and the package's example printer sweep (`test_domain_examples()`). |
| `test_cell()` | The reactive cell primitive (in `ProjecturedKernelTest`; run inside `test_kernel()` or standalone). |
| `test_cell_struct()` | The `@cell_struct` transparent-Cell struct codegen that `@document`/`@iomap`/`@projection` build on (in `ProjecturedKernelTest`; run inside `test_kernel()` or standalone). |
| `test_documents()` | The umbrella-only document suites (`test_constraint_solver()` — Tulip, `test_serialization()` — example fixtures). |
| `test_projections()` | The umbrella-only projection suites (example/editor/SDL-coupled: tooltip, hover, dragging, write_image, …). |
| `test_printers()` | Runs `test_printer` over every entry in `examples`. |
| `test_readers()` | Runs `test_reader` over every example. |
| `test_position_navigations()` | Runs `test_position_navigation` (position/caret BFS, no-error sweep) over every example. |
| `test_position_navigations_complete()` | Over a curated subset, additionally asserts navigation reaches every position enumerated from the document (`collect_position_selections`). |
| `test_tree_navigations_complete()` | Same idea for whole-element/structural selections (`collect_tree_selections`); curated to the native syntax tree. |
| `test_repls()` | Runs `test_repl` (full read-eval-print loop) over every example. |
| `test_text_nav_invariants_all()` | Runs `test_text_nav_invariants` (walk the cursor end to end, rightwards from Ctrl+Home and leftwards from Ctrl+End, and cross-check the two walks) over every example with a text pipeline. |
| `test_typeins()` | Runs `test_typein` (type a character at every cursor position of every string and check the edit) over the supported field-addressed examples. ~1200 positions, ~30s. |
| `test_mcp_tools()`, `test_mcp_resources()` | MCP server tools and resources. |
| `test_mouse_clicks()` | Mouse-click round-tripping. Run by `test_all`. |
| `test_catalog()` | Runs printer/reader/repl (+ position-navigation on `:graphics`) over the **generated** atomic-example catalog — see below. Run by `test_all`. |

## The generated example catalog

Alongside the hand-authored `examples` registry there is a **generated catalog** of
atomic examples (`ProjecturedExample.catalog()`), built to give broad, cheap coverage of
every domain's leaf projections. Its *documents* are hand-authored — one meaningful
instance per atomic (leaf) document type, in each domain's `example/document/*.jl` file,
registered as an `AtomicDocument(:domain, "name", make_document)`. Its *projections* are
**discovered**: for each atomic document the catalog finds the trivial single-step
projection, then a projection to `:text`, then one to `:graphics` (via a small set of
whole-tree bridges), and emits one `Example` per reachable variant.

Each entry is a plain `Example` whose `name` is a hierarchical **`domain/name/variant`**
path — the name doubles as the filter:

```julia
julia> catalog()                                  # every generated Example (~90)
julia> catalog(; domain = :json)                  # one domain
julia> catalog(; document = "string")             # one document across domains
julia> catalog(; terminal = :graphics)            # everything runnable on screen
julia> catalog(; only_runnable = true)            # :text (console) + :graphics (screen)
julia> run_example(only(catalog(; domain=:json, document="null", terminal=:graphics)))
```

The `variant` is the projection's terminal domain, which decides *which tests apply*:
`:syntax` runs printer/reader/repl; `:text` / `:graphics` also add position-navigation
(caret geometry needs the graphics layer, so navigation routes to `:graphics`). Run the
whole thing, or any slice, with `test_catalog`:

```julia
julia> test_catalog()                             # all applicable testers over the catalog
julia> test_catalog(; domain = :julia)            # just one domain
julia> test_catalog(; testers = (test_printer,))  # just one tester
```

A domain is included once its leaf projections are **bidirectional and navigable**.
Deliberately *not* in the catalog yet (each would need real domain work, not a catalog
change): SQL (read-only v1 — no readers), `filesystem/file` (introduced-token caret not
wired for graphics navigation), and the type-swap-on-commit leaves (`julia/nothing`,
`julia/insertion`). See `plan/done/atomic-example-catalog.md` for the full list.

## Testing a single example

Each example-level test is also defined for a single `Example` or a labelled
`(document, projection)` pair:

```julia
julia> test_printer(json_example)
julia> test_reader(json_example)
julia> test_position_navigation(json_example)                 # no-error position BFS
julia> test_position_navigation(json_example; check_reaches_all=true)  # + reaches every enumerated position
julia> test_repl(json_example)
julia> test_typein(json_example)                               # every caret of every string
julia> test_typein(json_example; positions=:ends)              # just the boundary carets + one interior
julia> test_text_nav_invariants(json_example)                  # end-to-end cursor walk, both directions

julia> ex = widget_example;
julia> test_printer("widget", ex.document, ex.projection)
```

`test_text_nav_invariants` is the linear counterpart to `test_position_navigation`'s
BFS: it walks a single cursor from one end of the text to the other and back, so a
direction that skips a caret or stalls partway is caught. Several examples are known
to fail the leftward walk; the sweep marks those `@test_broken`, but a bare
single-example call does not. Pass `broken=nav_broken(example.name)` to see one
example exactly as the sweep does:

```julia
julia> test_text_nav_invariants(json_example; broken=nav_broken("json"))
julia> test_text_nav_invariants(json_example; directions=(:left,))   # one walk, while debugging
```

`test_example(ex)` bundles printer + reader + repl + text-navigation + typein
for one example — useful when you have just added a new domain and want a single
command to exercise it.

Each example-level test emits **one `@test` per unit verified** rather than a
single `isempty(errors)` assertion, so the pass count reflects the work done:
`test_printer` asserts once per forced reactive cell, `test_reader`/`test_repl`
once per event, `test_position_navigation` once per reachable selection state, and
`test_typein` once per cursor position of every string. A failing unit names the
offending cell/event/state/reference in a `@warn`.

## The walker helpers (non-`@testset` variants)

When you want errors back as a `Vector{String}` instead of `@test` output —
e.g. you are iterating in the REPL and want to keep going on failure —
every test has a sibling that does the same work without wrapping it in
`@testset`:

| Helper | Location | What it does |
|---|---|---|
| `walk_printer_output(doc, proj)` | [kernel/test PrinterTest.jl](../package/kernel/test/editor/PrinterTest.jl) | Calls `print_document`, reflexively walks every field of the resulting iomap, and forces every `Cell` via `c[]`. Returns `(errors, status)`. |
| `walk_reader_events(doc, proj)` | [kernel/test ReaderTest.jl](../package/kernel/test/editor/ReaderTest.jl) | Prints once, then fires every key / mouse event in `_ALL_READER_EVENTS` through `read_intent`. Returns `errors::Vector{String}`. |
| `walk_repl_loop(doc, proj)` | [kernel/test ReplTest.jl](../package/kernel/test/editor/ReplTest.jl) | The complete read → evaluate → reprint → walk cycle, repeated for every event. The closest thing to driving the real editor headlessly. Returns `errors::Vector{String}`. |
| `explore_selections(doc, proj; nav_keys, seed_gesture)` | [kernel/test NavigationTest.jl](../package/kernel/test/editor/NavigationTest.jl) | The generic navigation BFS over reachable selection states, parameterized by gesture set and seed. Returns `(state_count, errors, visited)`. |
| `explore_position_selections(doc, proj[, initial])` / `explore_tree_selections(doc, proj)` | [visual/test NavigationPresets.jl](../package/visual/test/editor/NavigationPresets.jl) | The two presets over `explore_selections`: position (caret) navigation keys and Alt+arrow structural navigation. |
| `collect_position_selections(doc)` / `collect_tree_selections(doc; is_node)` | [base/test SelectionEnumeration.jl](../package/base/test/document/SelectionEnumeration.jl) | Ground-truth selections enumerated directly from the document (all positions/carets / all whole-element nodes), for the completeness suites to check against. |
| `walk_typein(doc, proj; positions=:all)` | [visual/test TypeinTest.jl](../package/visual/test/editor/TypeinTest.jl) | Types a character at every character boundary of every reachable string — undoing each edit so the next boundary starts from the same string — and verifies the cursor renders and the edit lands. The boundary carets (`0` and `n`) are the ones that catch a character landing in the neighbouring chrome. Returns one `(ref, position, length, ok, message)` result per (string, position); `positions=:ends` / `:first` trade coverage for time. |

`walk_printer_output`, `walk_reader_events`, `walk_repl_loop`, and
`explore_position_selections` keep their plain return values for REPL use; each also
takes an optional callback (`oncell` / `onevent` / `onstate`) that the
`test_*` wrappers use to emit one `@test` per unit.

```julia
julia> errors, status = walk_printer_output(json_example.document, json_example.projection);
julia> isempty(errors)
true

julia> result = explore_position_selections(syntax_example.document, syntax_example.projection);
julia> result.state_count, length(result.errors)
```

## The shared reflexive walker

`_walk!` (in
[kernel-test/editor/PrinterTest.jl](../package/kernel/test/editor/PrinterTest.jl))
is the workhorse behind every printer-based test. It descends every field
via `fieldnames` / `getfield`, follows every `Vector`, forces every `Cell`,
and uses an `objectid` `Set` to break cycles. New document types are
covered automatically as long as their fields are reachable through the
struct.

If you write a domain that stores state outside of struct fields (e.g. in a
side table), `_walk!` will not see it; either expose it as a field or add a
dedicated test under [domain/test/document/](../package/domain/test/document/).

## Validating the recursion contract

The four core projection functions (`print_document`, `read_intent`,
`map_reference_forward`, `map_reference_backward`) must each be **recursive** —
descending into children only by delegating to the child projection's own version
of the same function. That is [the recursion contract](../package/kernel/doc/projection-system.md#the-recursion-contract),
and a load-bearing half of it is that **no fifth recursive function may be
introduced** to do the descent: the four functions are the only interface every
projection implements, so any extra recursive function would break the moment a
pipeline composed a projection that lacks it.

The same constraint binds the *validation*: it is done **externally**, by a harness
that drives the four functions over composed examples, and it must add **no new
per-projection generic function** of its own. The harness reuses the existing
walkers rather than introducing an interface method:

- **Reachability** — enumerate every reference with `collect_position_selections` /
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
[package/projectured/test/editor/RecursionContractTest.jl](../package/projectured/test/editor/RecursionContractTest.jl):

| Function | What it does |
|---|---|
| `test_recursion_contract(example)` / `test_recursion_contracts()` | `@testset` running the delegation probe over the curated structural pipelines (`json`, `xml`, `syntax`, `math`). |
| `probe_delegation(doc, proj)` | Re-invokes each node projection with a spy `recursion` and reports `(projection_name, count, delegated, broken)` per node. |
| `walk_reference_roundtrip(doc, proj)` | The reachability + round-trip check, returning findings as a `Vector{String}` for REPL use. |
| `walk_recursion_contract(doc, proj)` | Both checks combined, findings as a `Vector{String}`. |

The asserted check is the **delegation probe** — the discriminating test, which adds
no per-projection generic function (the spy is an ordinary higher-order projection).
Every probed node now delegates: `SyntaxCompoundToText` was the last flattener (reached
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
[projectured/test/ProjecturedTest.jl:13](../package/projectured/test/ProjecturedTest.jl#L13)).

## Typical workflows

- **Added a new example.** `test_printer(my_example)`, then
  `test_reader(my_example)`, then `test_position_navigation(my_example)`, then
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
- **Selection navigation bug.** `explore_position_selections(doc, proj)` returns
  every reachable state; small `state_count` numbers are often the symptom
  of a stuck navigator. To check *coverage*, compare against
  `collect_position_selections(doc)` (or use `test_position_navigation(ex; check_reaches_all=true)`).

See [the debugging guide](debugging.md) for the matching REPL helpers
(`run_example`, `print_example`) that let you reproduce a failure
interactively before reaching for the test functions.

## Marking known-failing tests

**Invariant:** every currently-failing assertion is marked with
`@test_broken`. An unmarked `Fail` or `Error` in a suite summary is
unambiguously a regression — no bisection, no snapshot files, no counts.
Julia's `Test` stdlib partitions the summary into `Pass / Fail / Error /
Broken` columns for free.

### Marker format

```julia
# @broken: <one-line reason>[; plan/<slug>.md]
@test_broken <expr>
```

`grep -rn "@broken:" package/*/test/` enumerates every marked test
with its reason. Every `@test_broken` must have a `# @broken:` comment on
the line above — a bare marker with no context is not acceptable.

### Which pattern to use

- **Assertion-level Fail or Error inside `@test`** — convert `@test`
  to `@test_broken`. Julia catches thrown exceptions and reports them as
  `Broken` in the summary, so this handles both `Fail`s and most `Error`s.
- **Testset-setup Error** ("Got exception outside of a @test") — the
  throw happens *before* an `@test` runs. Wrap the testset body in
  `try/catch`, and emit `@test_broken (@warn "..."; false)` on catch:

  ```julia
  @testset "..." begin
      try
      # normal test body with @tests
      catch e
          # @broken: pre-existing drift; testset setup throws
          @test_broken (@warn "setup threw: $e"; false)
      end
  end
  ```

  Only the catch branch fires when the setup actually throws. If someday
  the setup starts working, the catch is skipped and normal assertions
  run — no ceremony to undo.
- **Loop with mixed pass/fail iterations** — check the outcome and
  branch:

  ```julia
  for path in paths
      back = map_reference_backward(p, iomap, forward(path))
      if back == path
          @test back == path
      else
          # @broken: <reason>; some iterations still drift
          @test_broken back == path
      end
  end
  ```

- **Sweep over examples with one broken example** — filter in the
  sweep loop and emit `@test_broken` for the broken example only:

  ```julia
  for ex in domain_examples
      @testset "$(ex.name)" begin
          if ex.name == "json_sorted"
              # @broken: <reason>
              @test_broken (print_document(ex.projection, ex.document); true)
          else
              test_printer(ex)
          end
      end
  end
  ```

- **`@test_skip` — the escape hatch.** Use only when running the code
  would crash the runner (stack overflow, infinite loop, corrupts
  subsequent tests). `@test_broken` catches thrown exceptions, but only
  after they're thrown; if throwing is destructive, `@test_skip` is
  safer. Skipped tests never run and can rot silently, so this is a last
  resort.

### `@test_broken` semantics you should know

- If the expression evaluates `false` or **throws**, it registers as
  `Broken`.
- If the expression evaluates `true`, it registers as
  `Error: Unexpected Pass` — the automatic signal to promote the
  marker back to `@test`. **Do not ignore this message; it means the
  underlying issue is fixed and the marker should come off.**
- The `Broken` count is shown in a separate column of every summary, so
  the shape "N Pass / M Fail / K Error / L Broken" always has an obvious
  regression signal (`M + K` should be 0).

### Adding a new marker

1. Write a one-line reason. If a plan exists, link it. If the root cause
   is unknown, say so honestly ("pre-existing drift; no investigation
   yet") rather than inventing.
2. Verify locally that the relevant `test_*()` aggregator exits with
   `Fail == 0`, `Error == 0`.
3. If the marker fires unexpectedly on a passing iteration (`Error:
   Unexpected Pass`), narrow the marker's scope — see the loop pattern.

### Removing a marker

When a bug is fixed, `@test_broken` reports `Error: Unexpected Pass`. To
un-mark:

1. Change `@test_broken` back to `@test`.
2. Delete the `# @broken:` comment.
3. Confirm the assertion now passes cleanly.
