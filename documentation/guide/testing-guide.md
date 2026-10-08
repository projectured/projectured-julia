# Testing in the REPL

> **Kind:** procedure · **Status:** current · **Stands on:** [package-rules.md](../rule/package-rules.md)

The test suite is a DAG of **test packages** that parallels the main
package DAG (see [plan/done/test-package-split.md](../../plan/done/test-package-split.md)):

```
main:     ProjecturedKernel ← ProjecturedPlatform ← the 18 domains ← Projectured ← {Example, Sdl, …}
tests:    ProjecturedKernelTest ← ProjecturedPlatformTest ← the 18 domain test packages ← ProjecturedTest
```

- [package/kernel/test](../../package/ProjecturedKernelTest/src/ProjecturedKernelTest.jl) —
  kernel unit tests + the **shared generic drivers** (`test_printer`,
  `test_reader`, `test_repl`, the navigation explorers, `_walk!`) + the shared
  static `check_layering` guard. Aggregator: `test_kernel()`.
- [package/platform/test](../../package/ProjecturedPlatformTest/src/ProjecturedPlatformTest.jl) —
  the unit tests of every one of the thirty-eight slices of the platform: the
  collection and copying tests, the ground-truth selection enumerators, the
  syntax, text, graphics and layout documents, the text, graphics and widget
  projections, and the type-in and click-roundtrip drivers. Aggregator:
  `test_platform()`.
- `package/<domain>/test` — one test package per domain, holding the suites
  whose fixtures are that domain's documents: its parser, its `*ToSyntax`
  projections, its editor tests. Aggregator: `test_json()`, `test_sql()`,
  `test_xml()`, … Each also runs its package's layering guard
  (`test_json_layering()`, …).
- The console, PDF and web backends and the MCP adapter each have their own
  test package: [ProjecturedConsoleTest](../../package/ProjecturedConsoleTest)
  (`test_console()`), [ProjecturedPDFTest](../../package/ProjecturedPDFTest)
  (`test_pdf()`), [ProjecturedWebTest](../../package/ProjecturedWebTest)
  (`test_web()`) and [ProjecturedMCPTest](../../package/ProjecturedMCPTest)
  (`test_mcp()`). Each runs its package's layering guard, and its fixture is a
  JSON document where it needs one. A test that reads the whole surface of the
  application stays in the umbrella.
- The **opt-in** main packages each have their own test package, so a suite
  that needs a native backend lives with the backend it exercises (not in the
  umbrella): [package/sdl/test](../../package/ProjecturedSDLTest) (`test_sdl()` — DirtyRect,
  write_image), [package/tulip/test](../../package/ProjecturedTulipTest) (`test_tulip()` —
  the LP constraint solver), [package/video/test](../../package/ProjecturedVideoTest)
  (`test_video()` — record_video), and [package/odbc/test](../../package/ProjecturedODBCTest)
  (`test_odbc()` — the live-DB adapter + DbCatalog suites). Each one names the
  packages it uses, so it runs in its own environment, and it precompiles only
  where the native dependency (SDL2 / Adaptagrams / FFMPEG / ODBC) is installed.
  [package/ollama/test](../../package/ProjecturedOllamaTest) follows the same
  shape (`test_ollama()` — request/stream translation, a meaning-vector suite
  against a stand-in server, and two live-server tests that skip themselves
  when no Ollama server answers), but gates on a reachable server rather than
  a native library.
  [package/acp/test](../../package/ProjecturedACPTest) (`test_acp()` — the
  translation of the updates of an agent, the connection against a fake agent
  in the test process, the transport with a small child agent, and the start of
  the built-in agent) needs no network, no Node.js, no `claude` and no sign-in.
- [package/projectured/test](../../package/ProjecturedTest/src/ProjecturedTest.jl) — the umbrella:
  the genuinely **cross-package** suites. Two kinds live here: the sweeps over
  the interleaved `examples` / `catalog` aggregate (`ExampleSweeps`,
  `ExampleTest`, `CatalogTest`, `RecursionContract`, `MouseClick`,
  `PrinterLocality`, `test_domain_examples()`), and every suite whose **fixture
  names several domains** — `ConstructTest` (JSON, YAML and XML), the table,
  dragging, insertion, gesture, serializer and MCP suites, and the Console and
  Pdf backend tests. It `using`s every test package so `test_all()` still
  orchestrates the whole suite, and re-exports their entry points so
  `using ProjecturedTest` alone gives you `test_json()` as well as `test_all()`.

The examples follow the same split (`package/kernel/example` — the `Example`
harness core; `package/platform/example` / `package/domain/example` — the
per-package example sets with `platform_examples` / `domain_examples` registry
subsets; the
opt-in example packages — `package/odbc/example`, `package/tulip/example`,
`package/adaptagrams/example`, and `package/sdl/example` (the `LiveExample`
window/record timelines) — hold the examples that need a native dependency; the
`ProjecturedExample` umbrella keeps the `Example` registry, the gallery, the
file editor and the cross-domain compositions — a registry that names every
domain belongs to none of them). Each test package depends on its example
package: the `Example`-typed driver overloads live beside the drivers.
`test_platform()` sweeps its own package's examples; the concrete-domain sweep is
`test_domain_examples()` at the umbrella.

Each test package only depends on the main package it tests (plus the packages
below it), so every per-package suite runs without SDL, ODBC, or any other
opt-in dependency installed.

Every top-level function is *callable directly from the REPL*. There is no
hidden runner: anything `test_all` does is something you can do one piece
at a time.

```sh
cd projectured
julia --project=environment/all
```

```julia
julia> using ProjecturedAll, ProjecturedExample, ProjecturedTest
```

`ProjecturedAll` gives the names of every package in one namespace, as the
test packages and the example packages use them.

## The top-level entry point

```julia
julia> test_all()
```

Runs everything: the per-package suites (`test_kernel()`, `test_platform()`,
and one `test_<domain>()` per domain — each includes its package's static
layered-architecture guard) followed by the umbrella integration tests
(printers, readers, selections, REPL-loop tests, the MCP tool tests, and the
mouse-click / click-round-trip sweeps — see
[test/ProjecturedTest.jl](../../package/ProjecturedTest/src/ProjecturedTest.jl)).

`test_all` is just a `@testset` that calls the per-package functions in
sequence; pick the one you actually need and skip the rest. `test_integration()`
runs the umbrella integration tests alone, and `test_repository()` the tests of
the umbrella that read this repository (the package graph). The builder has its
own test package, `ProjecturedBuilderTest` (`test_builder()`).
[The time and the memory of each part](#the-time-and-the-memory-of-each-part)
gives what each of them costs.

## Per-package tests

| Function | What it covers |
|---|---|
| `test_kernel()` | The whole kernel suite: `test_cell()`, `test_document_contract()`, `test_reference_builder()`, `test_gesture_binding()`, …, plus the kernel layering guard. |
| `test_platform()` | `test_collection()`, `test_syntax()`, `test_text()`, `test_graphics()`, `test_syntax_to_text()`, `test_text_to_graphics()`, the widget projection suites, the layering guard of every slice of the platform, and the package's example printer sweep (`test_platform_examples()`). |
| `test_json()` … `test_yaml()` | One per domain package: that domain's documents, parser and projections, plus its layering guard. The bare name is the package aggregator; a single file's suite carries a more specific name (`test_json_document()`, `test_graph_projection()`). `test_database()` is the domain aggregator like the rest; the ODBC live-connection suite is the separate `test_odbc_database*` family (`test_odbc_database()`, `test_odbc_database_connection()`, `test_odbc_database_no_db()`). |
| `test_domain_examples()` | A printer sweep over every concrete-domain example. Umbrella, because the registry it walks names all eighteen. |
| `test_text_gutter()`, `test_text_folding()` | The gutter of a block of lines and its alignment, and the text folds: a closed fold hides its lines after its first, the numbers count the hidden lines because `TextLineNumbering` stands before `TextFolding` in the chain, and a click on a triangle of a syntax node toggles the node (in `ProjecturedPlatformTest`). The example `syntax_folding` is that chain on syntax with `text_folds`, so the example sweeps walk it. |
| `test_help()` | the help slice's suite: the layering guard, the docstring description, and the two lists and the page that the Help menu opens. |
| `test_cell()` | The reactive cell primitive (in `ProjecturedKernelTest`; run inside `test_kernel()` or standalone). |
| `test_cell_struct()` | The `@cell_struct` transparent-Cell struct codegen that `@document`/`@iomap`/`@projection` build on (in `ProjecturedKernelTest`; run inside `test_kernel()` or standalone). |
| `test_cell_struct_plan()` | The `CellStructPlan` parse and the positional constructors, called on expressions (in `ProjecturedKernelTest`; run inside `test_kernel()` or standalone). |
| `test_documents()` | The umbrella-only document suites (`test_constraint_solver()` — Tulip, `test_serialization()` — example fixtures). |
| `test_projections()` | The umbrella-only projection suites (example/editor/SDL-coupled: tooltip, hover, dragging, write_image, …). |
| `test_printers()` | Runs `test_printer` over every entry in `examples`. |
| `test_readers()` | Runs `test_reader` over every example. |
| `test_position_navigations()` | Runs `test_position_navigation` (position/caret BFS, no-error sweep) over every example. |
| `test_position_navigations_complete()` | Over a curated subset, additionally asserts navigation reaches every position enumerated from the document (`collect_position_selections`). |
| `test_tree_navigations_complete()` | Same idea for whole-element/structural selections (`collect_tree_selections`); curated to the native syntax tree. |
| `test_repls()` | Runs `test_repl` (full read-eval-print loop) over every example. |
| `test_text_navigation_invariants_all()` | Runs `test_text_navigation_invariants` (walk the cursor end to end, rightwards from Ctrl+Home and leftwards from Ctrl+End, and cross-check the two walks) over every example with a text pipeline. |
| `test_typeins()` | Runs `test_typein` (type a character at every cursor position of every string and check the edit) over the supported field-addressed examples. About three minutes. |
| `test_mcp_tools()`, `test_mcp_resources()` | MCP server tools and resources. |
| `test_mouse_clicks()` | Mouse-click round-tripping. Run by `test_all`. |
| `test_catalog()` | Runs printer/reader/repl (+ position-navigation on `:graphics`) over the **generated** atomic-example catalog — see below. Run by `test_all`. |

`test_kernel()` also runs the tool, llm and agent suites under
[test/kernel/tool/](../../test/kernel/tool/DeclaredApiTest.jl) (the declared API a model
may call, search by name/pattern/description, and `execute_julia_code!`),
[test/kernel/llm/LlmDefaultsTest.jl](../../test/kernel/llm/LlmDefaultsTest.jl) (the
fallbacks of the provider contract) and
[test/kernel/agent/AgentDefaultsTest.jl](../../test/kernel/agent/AgentDefaultsTest.jl) (the
inbound agent-server seam) with
[AgentLoopTest.jl](../../test/kernel/agent/AgentLoopTest.jl) (the agent loop) — this
table does not name them individually.

## The time and the memory of each part

`test_all()` calls 82 parts. Two runs on 2026-09-25 measured each part alone, in
a process of its own, so the peak memory of a process is the peak of one part.
The table gives each part that took more than 60 s or more than 1.5 GB in one of
the two runs. Each other part took less than 60 s and less than 1.5 GB.

| Part | Time | Peak memory | Allocated |
|---|---|---|---|
| `test_catalog()` | 556–666 s | 1.6 GB | 46 GB |
| `test_position_navigations()` | 379–392 s | 1.4 GB | 368 GB |
| `test_platform()` | 250–365 s | 4.3 GB | 20 GB |
| `test_typeins()` | 175–212 s | 1.0 GB | 231 GB |
| `test_application()` | 158–174 s | 2.2 GB | 18 GB |
| `test_text_navigation_invariants_all()` | 128–150 s | 1.1 GB | 72 GB |
| `test_repls()` | 129–149 s | 1.2 GB | 20 GB |
| `test_natural_renders_every_atom()` | 110–146 s | 1.2 GB | 14 GB |
| `test_natural_round_trips_every_atom()` | 80–117 s | 1.1 GB | 9 GB |
| `test_evaluator_toplevel()` | 58–101 s | 1.8 GB | 6 GB |
| `test_kernel()` | 91–99 s | 2.5 GB | 8 GB |
| `test_click_roundtrips()` | 90–99 s | 1.1 GB | 45 GB |
| `test_readers()` | 88–95 s | 1.1 GB | 9 GB |
| `test_tree_navigations()` | 90–93 s | 1.2 GB | 12 GB |
| `test_domain_examples()` | 83–93 s | 1.2 GB | 10 GB |
| `test_printers()` | 83–86 s | 1.2 GB | 9 GB |
| `test_sql()` | 74–82 s | 1.7 GB | 7 GB |
| `test_mouse_clicks()` | 71–72 s | 1.1 GB | 7 GB |
| `test_projections()` | 59–63 s | 1.5 GB | 6 GB |
| `test_chart()` | 40–45 s | 1.9 GB | 4 GB |
| `test_graph()` | 34–38 s | 1.7 GB | 3 GB |

- **Time.** The sum over the 82 parts was 72 and 70 minutes. The load of
  `ProjecturedTest` takes about 8 s in each process, so about 11 minutes of the
  sum is load. The first process after a change of the source also precompiles
  the changed packages, which adds up to two minutes.
- **Memory.** Each peak includes about 0.75 GB for the loaded packages. No part
  needed more than 4.5 GB, so a cap of 8 GB on each process is enough.
- **Allocation.** `test_position_navigations()` and `test_typeins()` allocate the
  most, and spend 43 s and 28 s in garbage collection. Their objects are short
  lived, so their peak stays under 1.5 GB.
- **Noise.** Other work ran on the machine, with a load average from 2 to 24 on
  32 CPUs. The time of a part changed by up to 43 % between the two runs. The
  peak memory changed by at most 220 MB.

To measure a part again:

1. Find the name of the part in the body of `test_all()` in
   [ProjecturedSuite.jl](../../test/projectured/ProjecturedSuite.jl).
2. Run the part in a process of its own under `/usr/bin/time`. `%e` is the
   time in seconds, and `%M` is the peak resident memory in KB.

   ```bash
   /usr/bin/time -f "%e s, %M KB" julia -t 2 --project=environment/all \
       -e 'using ProjecturedTest, Test; @testset "part" begin test_catalog() end'
   ```

3. To get the allocation, read `Base.gc_num()` before and after the call, and
   subtract the two with `Base.GC_Diff`.

## The generated example catalog

Alongside the hand-authored `examples` registry there is a **generated catalog** of
atomic examples (`ProjecturedExample.catalog()`), built to give broad, cheap coverage of
every domain's projections. Its *documents* are hand-authored — one meaningful instance
per document type: the atomic **leaves** (a JSON scalar, a primitive, …) and a minimal
non-empty **compound** for each node type (`JsonArray(JsonNumber(1))`,
`JsonObject("a" => JsonString("x"))`), in each domain's `example/document/*.jl` file,
registered as an `AtomicDocument(:domain, "name", make_document)`. Its *projections* are
**discovered**: for each atomic document the catalog finds the trivial single-step
projection, then a projection to `:text`, then one to `:graphics` (via a small set of
whole-tree bridges), and emits one `Example` per reachable variant. A compound's syntax
variant uses the domain's whole-tree **dispatching** projection (a bare node projection
has no recursion to project its children), not the trivial single-step leaf.

Each entry is a plain `Example` whose `name` is a hierarchical **`domain/name/variant`**
path — the name doubles as the filter:

```julia
julia> catalog()                                  # every generated Example (~315)
julia> catalog(; domain = :json)                  # one domain
julia> catalog(; document = "string")             # one document across domains
julia> catalog(; terminal = :graphics)            # everything runnable on screen
julia> catalog(; only_runnable = true)            # :text (console) + :graphics (screen)
julia> run_example(only(catalog(; domain=:json, document="null", terminal=:graphics)))
```

The `variant` is the projection's terminal domain, and it sets *which tests apply*:
`:syntax` runs printer/reader/repl; `:text` / `:graphics` also add position-navigation
(caret geometry needs the graphics layer, so navigation routes to `:graphics`). Run the
whole thing, or any slice, with `test_catalog`:

```julia
julia> test_catalog()                             # all applicable testers over the catalog
julia> test_catalog(; domain = :julia)            # just one domain
julia> test_catalog(; testers = (test_printer,))  # just one tester
```

A domain is included once its leaf projections are **bidirectional and navigable**. The
catalog covers every domain that has a registered `AtomicDocument` — run
`catalog(; domain = :formula)`, or any domain symbol, to see one — plus the platform's
atoms (primitive, collection, graphics, layout, syntax, text, widget), including the
opaque display leaves (their introduced-text carets collapse to a
bounded `proj(p, …)` position, navigable but non-editable) and the self-modifying
`*Nothing` / `*Insertion` documents (whose syntax variant uses the domain's dispatching
projection, since a bare leaf can't reproject a type swap). It covers a minimal non-empty
**compound** for *every* node type too — the whole document grammar of each domain (json
array/object/object_entry, all the julia AST nodes, all the sql clause/statement nodes, the
markdown blocks/inlines, …) — so every projection is exercised, not just the leaves.
`process` is the one domain with no generated atoms; its examples are hand-authored instead.

**No document type is skipped.** A node whose projection still has a bug stays in the catalog
with its failure recorded `@test_broken` — the failure is *information* (a real bug to fix),
keyed on its signature so a *different* failure still surfaces as an unmarked `Fail` (a
regression). The open bugs are `grep "@catalog-broken"` in
[CatalogTest.jl](../../test/projectured/projection/CatalogTest.jl). See
`plan/**/catalog-{deferred,compound,all}-*.md` for how the atoms were added.

## A test that checks the root of a built editor

`build_editor` applies the wrappers that are on by default, and the platform has
three: `tabs`, `appearance` and `settings`. Each puts a document around the root.
A test that checks the root document after `build_editor`, or the depth of a
selection path, turns them off: `tabs = false, appearance = false,
settings = false`. A keyword that is off and that no loaded package declares is
ignored, so a test of the kernel alone can pass them too.

With the `settings` wrapper on and no `Settings` given, the settings read the
values of the editor and of its backend when the editor starts, so a test that
gives `build_editor` a `fault_policy`, or a backend its keywords, keeps them.

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
julia> test_text_navigation_invariants(json_example)                  # end-to-end cursor walk, both directions

julia> ex = widget_example;
julia> test_printer("widget", ex.document, ex.projection)
```

`test_text_navigation_invariants` is the linear counterpart to `test_position_navigation`'s
BFS: it walks a single cursor from one end of the text to the other and back, so a
direction that skips a caret or stalls partway is caught. Several examples are known
to fail the leftward walk; the sweep marks those `@test_broken`, but a bare
single-example call does not. Pass `broken=get_navigation_broken(example.name)` to see one
example exactly as the sweep does:

```julia
julia> test_text_navigation_invariants(json_example; broken=get_navigation_broken("json"))
julia> test_text_navigation_invariants(json_example; directions=(:left,))   # one walk, while debugging
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

## What each generic driver checks

The tables above say *what each driver runs on*; this section says *what it
actually asserts*. Every entry is the same four fields — **Seed** (the starting
state and what, if anything, it enumerates), **Drive** (how it exercises the
editor), **Asserts** (the invariant, at the `@test`-per-unit granularity from the
section above), and **A failure means** (how to read a red result). All of these
are example-driven: the single-example call and the `examples`/`catalog` sweep run
the identical algorithm.

### Print-based drivers

**`test_printer`** — the projected output evaluates without error.
- **Seed:** `print_document(projection, document)` once → an iomap.
- **Drive:** `_walk!` reflexively descends every field of the iomap (`fieldnames`/`getfield`), follows every `Vector`, and forces every reactive `Cell` with `c[]`; cycles are broken by `objectid`, and the walk is capped at depth 100 / 500 000 nodes.
- **Asserts:** one `@test` per forced `Cell` (and per `getfield`) — that forcing it does not throw. Hitting the depth/node cap is reported as `@info`, not a failure (lazy/large documents don't fail the test).
- **A failure means:** a cell in the projected output errors when evaluated, or a field is unreadable — a broken printer or iomap.

**`test_reader`** — every gesture is handled without crashing.
- **Seed:** clear the selection, print once → iomap.
- **Drive:** fire every event in `_ALL_READER_EVENTS` (every key symbol × {ctrl on/off}, key repeats, `KeyUp`, printable `KeyPress`; mouse down/up/press/move/scroll at sample coordinates) through `read_intent(projection, iomap, event)`.
- **Asserts:** one `@test` per event — that `read_intent` *returns* (any value, `nothing` included) rather than throwing. It does **not** inspect the intent's content — only that no event makes the reader blow up. A `broken` predicate can mark known-failing events `@test_broken`.
- **A failure means:** some gesture throws inside the reader.

**`test_repl`** — the full read→eval→reprint loop is stable under every gesture.
- **Seed:** clear the selection, print once → iomap.
- **Drive:** for each event, run the whole cycle: `read_intent` → if the op is non-`nothing`, `evaluate_operation` on a stand-in `_ReplEditor` (which picks up whole-document swaps) → re-`print_document` → `_walk!` the new output. The iomap threads forward into the next event exactly as the real editor loop does.
- **Asserts:** one `@test` per event — the entire read→evaluate→reprint→walk cycle completes without throwing and every cell in the reprinted output forces cleanly.
- **A failure means:** an operation fails to apply, or leaves the document in a state that can't be re-projected or forced: a reader, operation or printer mismatch. This check is strictly stronger than `test_reader`.

### Navigation drivers

The two BFS drivers share one engine (`explore_selections` / `test_navigation`); they differ only in the **seed gesture** and **nav-key set** they're preset with, and in the ground-truth enumerator used for the coverage check.

**`test_position_navigation`** — caret navigation is closed and (optionally) complete.
- **Seed:** fire `Ctrl+Home`; the first selection is the resulting `ReplaceSelectionOperation.path`.
- **Drive:** BFS over selection states. At each state: set the selection, reprint, `_walk!`; then try each `POSITION_NAVIGATION_KEYS` gesture (arrows, Home/End, Ctrl+arrows, Ctrl+Home/End) via `read_intent`, enqueuing every new target path (deduped modulo type checkpoints via `strip_reference_types`) not yet visited.
- **Asserts:** one `@test` per reachable state (its reprint + walk don't throw), plus `@test state_count > 0`. With `check_reaches_all=true`: additionally one `@test` per selection enumerated by `collect_position_selections(document)` asserting it was reached (subset check: *enumerated ⊆ reachable*), plus `@test !isempty(enumerated)`.
- **A failure means:** a navigation gesture throws, a reached state can't be reprinted, or, in completeness mode, navigation can't reach a caret the document actually has. The last case is the caret motion stuck or leaking.

**`test_tree_navigation`** — the same, for whole-element (∅) structural selections.
- **Seed:** `Ctrl+Alt+Home`, which selects the root ∅.
- **Drive:** identical BFS, but with the `TREE_NAVIGATION_KEYS` (Alt+arrow) structural moves.
- **Asserts:** same shape (one `@test` per reachable whole-element state; `state_count > 0`; optional *enumerated ⊆ reachable*), against `collect_tree_selections` — or a projection-aware enumerator for domains whose document is not a native syntax tree (e.g. JSON passes `collect_json_tree_selections`, mirroring `JsonToSyntax`'s decomposition).
- **A failure means:** structural navigation throws or can't reach an enumerated node.

**`test_text_navigation_invariants`** — linear cursor walks are chains and agree both ways. This is the *linear* counterpart to the position-navigation BFS: a BFS proves reachability but hides a direction that skips or stalls; this catches it.
- **Seed / Drive:** two walks. **Right:** seed `Ctrl+Home`, step `:right`. **Left:** seed `Ctrl+End`, step `:left`. Each fires its seed, then repeats its step — reprinting between moves — until the reader declines the step (edge of text), the step is a fixed point (edge), or it lands on an already-visited state (cycle).
- **Asserts:** *per direction* — the walk ran without error, `terminated` on its own (not by exhausting `max_steps`), never revisited a state (`cycle === nothing`, i.e. it is a chain), and moved at least once (`length(paths) > 1`). *Cross-direction* — both walks visit the same caret count (`:same_length`), the right walk ends where `Ctrl+End` lands, and the left walk ends where `Ctrl+Home` lands. Exact caret-*sequence* equality is deliberately **not** asserted: at a line boundary the same logical caret renders in two places and the two directions canonicalize to different ones.
- **A failure means:** a direction skips a caret, stalls partway, loops, or the two directions disagree on caret count / endpoints — a directional asymmetry invisible to the BFS.

### Editing drivers

**`test_typein`** — typing and deleting at every caret lands the right string and caret.
- **Seed:** collect every string reference reachable in the document.
- **Drive:** for each string, at each character boundary `0…n` (policy `:all` / `:ends` / `:first`), run three edits in order — **insert** (`KeyPress`), **backspace** (`KeyDown(:backspace)`), **delete** (`KeyDown(:delete)`). Each edit sets the cursor at the boundary, drives the event through the reader, evaluates it, then restores the string to pristine before the next edit (so each edit starts from the same string).
- **Asserts:** per `(string, position, edit)` — the caret **renders** in the Graphics image; the resulting string equals the expected edited string; and the post-edit caret is where it belongs (insert → `k+1`, backspace → `k−1`, delete → `k`). At a declined boundary (backspace at `0`, delete at `n`) the reader must produce **no** edit, and the walk asserts that decline without evaluating anything. A string that can't be restored ends that target (the rest of the document walk continues).
- **A failure means:** an edit at some caret produces the wrong string or wrong caret, a character lands in neighbouring chrome (the boundary carets `0`/`n` are what catch this), or the caret fails to render.

**Structural insert-by-typing** — turning a *nothing* placeholder into a real document.
- **Today:** `test_document_insertion()` is a *domain-specific* suite (in [DocumentInsertionTest.jl](../../test/projectured/projection/DocumentInsertionTest.jl)), **not** example-driven. It asserts the insert-by-typing machinery directly: the factory/completion functions (`default_factory`, `default_completion`), the reflection-derived insertion names and resolution (`DomainModule.get_insertion_names` / `resolve_insertion`), the completion states (`:empty` / `:invalid` / `:unambiguous` / `:ambiguous`), and that typing a domain name into a `DocumentInsertion` commits the corresponding `document/insertion`.
**Live example construction** — rebuilding a whole document from nothing by typing.
- **`test_construct` / `test_json_construct`** (engine in [ConstructTest.jl](../../test/projectured/editor/ConstructTest.jl); the oracle `compare_content` lives in the kernel test) are the *reachability* counterpart to `test_typein`: seed the domain's empty `*Nothing` placeholder, drive the editor's own gestures to rebuild a target document from scratch, then assert the result equals the target **by content**.
- **Drive:** recurse over the *target's* structure — a leaf is authored by typing its surface (opening delimiter + value; the closing delimiter is projection chrome, so it is not typed), a container by its kind-selecting keystroke (`[`/`{`/digit/`"`/…) followed by navigating to each child slot (programmatic ∅ selection) and recursing. Every keystroke goes through the real `read_intent → evaluate_operation` loop.
- **Asserts:** `compare_content(reached, target)` — a strict recursive content-equality (types compared by name, cells unwrapped, `:selection`/`:ref` skipped) that returns the **first mismatch path** (`.field` / `[i]`), or empty when equal. Strict on scalar type, so `42 ≠ 42.0`.
- **A failure means:** an editor authoring gap (a kind with no gesture recipe), a reader/operation bug (wrong shape or non-inverting leaf), or a located content regression. Covers JSON scalars and arrays today; the cross-domain `test_construct(example::Example)` sweep is still pending (see [plan/pending/live-example-construction.md](../../plan/pending/live-example-construction.md)).

> Two more generic example drivers, out of scope for the list above but built the same way, are documented in [ClickRoundtripTest.jl](../../test/platform/editor/ClickRoundtripTest.jl) and [MouseClickTest.jl](../../test/projectured/editor/MouseClickTest.jl): `test_click_roundtrip` / `test_mouse_click_roundtrip` fire a click at each rendered character cell and assert the resulting selection lands in, or immediately beside, the clicked cell. This is the pointer-side inverse of the caret-rendering that `test_typein` checks.

## The walker helpers (non-`@testset` variants)

When you want errors back as a `Vector{String}` instead of `@test` output —
e.g. you are iterating in the REPL and want to keep going on failure —
every test has a sibling that does the same work without wrapping it in
`@testset`:

| Helper | Location | What it does |
|---|---|---|
| `walk_printer_output(doc, proj)` | [kernel/test PrinterTest.jl](../../test/kernel/editor/PrinterTest.jl) | Calls `print_document`, reflexively walks every field of the resulting iomap, and forces every `Cell` via `c[]`. Returns `(errors, status)`. |
| `walk_reader_events(doc, proj)` | [kernel/test ReaderTest.jl](../../test/kernel/editor/ReaderTest.jl) | Prints once, then fires every key / mouse event in `_ALL_READER_EVENTS` through `read_intent`. Returns `errors::Vector{String}`. |
| `walk_repl_loop(doc, proj)` | [kernel/test ReplTest.jl](../../test/kernel/editor/ReplTest.jl) | The complete read → evaluate → reprint → walk cycle, repeated for every event. The closest thing to driving the real editor headlessly. Returns `errors::Vector{String}`. |
| `explore_selections(doc, proj; nav_keys, seed_gesture)` | [kernel/test NavigationTest.jl](../../test/kernel/editor/NavigationTest.jl) | The generic navigation BFS over reachable selection states, parameterized by gesture set and seed. Returns `(state_count, errors, visited)`. |
| `explore_position_selections(doc, proj[, initial])` / `explore_tree_selections(doc, proj)` | [test/platform/editor/NavigationPresets.jl](../../test/platform/editor/NavigationPresets.jl) | The two presets over `explore_selections`: position (caret) navigation keys and Alt+arrow structural navigation. |
| `collect_position_selections(doc)` / `collect_tree_selections(doc; is_node)` | [base/test SelectionEnumeration.jl](../../test/platform/document/SelectionEnumeration.jl) | Ground-truth selections enumerated directly from the document (all positions/carets / all whole-element nodes), for the completeness suites to check against. |
| `walk_typein(doc, proj; positions=:all)` | [test/platform/editor/TypeinTest.jl](../../test/platform/editor/TypeinTest.jl) | Types a character at every character boundary of every reachable string — undoing each edit so the next boundary starts from the same string — and verifies the cursor renders and the edit lands. The boundary carets (`0` and `n`) are the ones that catch a character landing in the neighbouring chrome. Returns one `(ref, position, length, ok, message)` result per (string, position); `positions=:ends` / `:first` trade coverage for time. |

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
[kernel-test/editor/PrinterTest.jl](../../test/kernel/editor/PrinterTest.jl))
is the workhorse behind every printer-based test. It descends every field
via `fieldnames` / `getfield`, follows every `Vector`, forces every `Cell`,
and uses an `objectid` `Set` to break cycles. New document types are
covered automatically as long as their fields are reachable through the
struct.

If you write a domain that stores state outside of struct fields (e.g. in a
side table), `_walk!` will not see it; either expose it as a field or add a
dedicated test under [domain/test/document/](../../test/projectured/document).

## Validating the recursion contract

The four core projection functions (`print_document`, `read_intent`,
`map_reference_forward`, `map_reference_backward`) must each be **recursive** —
descending into children only by delegating to the child projection's own version
of the same function. That is [the recursion contract](../package/kernel/projection-system.md#the-recursion-contract),
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
  original, a reference to a projection-introduced position included. Round-tripping
  at every level is the signature of lockstep recursion.
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
[package/projectured/test/editor/RecursionContractTest.jl](../../test/projectured/editor/RecursionContractTest.jl):

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
[plan/done/syntaxtotext-delegation.md](../../plan/done/syntaxtotext-delegation.md) converted it to School A, so it is now a plain
`@test`. `test_recursion_contracts()` is opt-in (not yet wired into `test_all`); the
reference round-trip is exposed as the REPL walkers above rather than asserted,
pending calibration on a running editor.

## Scale: does a pane of 20,000 tasks stay a window?

`test_task_group_scale(; task_count = 20_000, jobs = 16)` (`ProjecturedPlatformTest`)
starts a group of `task_count` process tasks and checks P7 of the catalog of
legacy documents: a print of the pane of the group builds only the rows of a
window of 900 pixels, before and after the run, and the drains while the group
runs cost no walk of every task. It starts 20,000 processes in about 25 s, so
`test_platform` does not call it. Run it after a change of the task slice, of
the walk of the part under the pointer, or of a lazy table.

## Reactivity: does the output follow the input?

`test_reactivity()` sweeps every registered example and asserts the property no
other suite can see:

> Touch a leaf of a projection's input, and something in that projection's own
> output must go invalid.

The bug it catches does not make the output **wrong**, it makes it **stale**.
Nothing errors and no assertion trips; the pixels are simply from a document that
no longer exists. Every other printer test re-prints from scratch, and a re-print
always looks correct, so this shape survives a green suite indefinitely.

It is opt-in and slow — about seven minutes over 103 examples. Do not run it to
check a one-line change; run the narrowest test as usual and leave this to a
broad sweep.

```julia
test_reactivity()                      # the whole sweep
check_reactivity(json_example)         # one example, per-node verdicts
check_structural_reactivity(json_example)   # append an element instead of writing a leaf
```

The unit is an **IoMap node**, not a document leaf, because an IoMap pairs one
projection's input with its output. A failure then names the projection that
froze rather than saying "something in this example went stale".

### The four outcomes

A node is not charged for every write. `map_reference_forward` is asked first,
and the answer determines what a non-reacting write means.

| outcome | meaning |
|---|---|
| **followed** | the surface moved; the node did its job |
| **frozen** | the leaf path maps, so the field is rendered, and nothing moved — a finding |
| **unproven** | only the document path maps; the field may have no reader, so nothing is proven |
| **carried** | the output holds the written cell itself, so the value passes through by reference and the node owes nothing |
| **not shown** | neither path maps; a filtering, searching or focusing projection drops it deliberately |

`SyntaxLeaf.indentation` is the reason `unproven` exists: the field is there, and
`get_indentation` has no method for a leaf, so nothing consults it.
`ChartToChartPlot` is the reason `carried` exists: its output wraps the live
`Chart`, so writing `chart.title` moves nothing there and nothing is stale — the
renderer one stage on reads the same cell.

### What it does not test

- **Reader-side reactivity.** This is printer-only; `test_readers` owns the
  other direction.
- **Correctness of the new value.** Only that something moved.
- **Over-invalidation.** `PrinterLocalityTest.jl` owns that bound, and shares its
  cell collector with this file. Measured across all examples, over-invalidation
  is not a problem: the median write moves 0% of a surface and the worst moves
  35%.

### Trusting the sweep

Three acceptance tests guard the harness itself, because a harness that cannot
fail reports zero whether or not anything is wrong:

- `test_reactivity_property()` — a captured value must be called frozen and a
  re-deriving output must not.
- `test_reactive_surface()` — includes the orphaning case, where a projection
  re-derives its whole output and every cell of the old tree is untouched.
- `test_structural_property()` — children built once into constant cells must be
  called frozen; the same shape as a computation must pass.

`test_verdict_stability(names)` additionally requires that the same leaves
measured forward, forward again and backward give identical counts.

## The static guards

`test/suite/*.jl` holds the guards of the rules that a program can check. Each
reads the repository as text, loads no package, and runs in about a second:

| Function | What it guards |
|---|---|
| `test_tree()` | every top-level folder holds one kind of thing, the rule of [repository-tree.md](../../plan/done/repository-tree.md) §3. |
| `test_naming()` | the mechanical rules of [naming-rules.md](../rule/naming-rules.md): a module name against its file and its slice, an alias no file declares, a banned abbreviation, a test package's entry point, and a definition two files of one module state twice. |
| `test_arguments()` | the rule of three positional arguments of [code-quality-rules.md](../rule/code-quality-rules.md) §4, unless a `# @positional:` marker says why a definition stands over the line. |
| `test_exports()` | the rule of the export block of [code-quality-rules.md](../rule/code-quality-rules.md) §1: one `export` statement per fragment, in the order of the includes. |
| `test_documentation()` | the part of [writing-rules.md](../rule/writing-rules.md) that a program can check: a dead link, an unknown `resource://guide/…`, a document with no header or no summary, and a forbidden phrase. |
| `test_style()` | every font, color and length comes from a theme; see below. |
| `test_kernel_layering()`, `test_platform_layering()`, … | the layering guard of each package; see [Per-package tests](#per-package-tests) below. |

Each is callable alone from the REPL, and `test_all()` runs them first, before
any per-package suite.

### The style guard

`test_style()` is the style guard: a font, a color or a size that a line of
`source/` writes as a literal value, outside a theme, fails. It reads the code
as text and loads nothing, so it also runs standalone, with no environment:

```bash
julia test/suite/style.jl
```

It fails on a line of `source/` that holds:

- a font description, `StyleFont("…`;
- a color of numbers, `StyleColor(0.…`, or a color of the palette by its name
  (a constant that [Color.jl](../../source/platform/style/Color.jl) declares,
  other than `color_transparent` and `color_default`);
- a length with a number other than 0: `Inset(`, `Spacing(`, `Radius(`,
  `LineWidth(`, `ControlSize(` or `IconSize(`.

It skips a `@theme` declaration, a preset of a theme (a function whose name
ends in `_theme`), the palette and the registry of font faces
(`source/platform/style/FontFace.jl`), a docstring, a comment, and an `export`,
`import` or `using` statement.

A line that holds such a value on purpose carries the marker
`# @style: <reason>`, on that line or on the line above it: the content of a document
that its author set, a mark that is not the look of the editor, or a value
that waits for a decision of the owner. A marker on a line of its own covers
every line below it, up to the next blank line, so a table of several values
needs one marker and not one for each line. `STYLE_EXEMPT_FILES` in
`test/suite/style.jl` lists a whole file that is exempt by name, with its
reason — for example, a file whose colors wait on an open question.

## CI

[CI.yml](../../.github/workflows/CI.yml) runs on each push to `main` and on each
pull request, except a push that changes only `plan/`:

- One job runs each static guard, `test/suite/*.jl`, alone. The guards read the
  source as text and load no package, so the job takes seconds.
- One job runs the suite of each test package in its own environment, for
  example `test_json()` in `package/ProjecturedJSONTest`. A suite that uses a
  package that its `Project.toml` does not name fails there, and passes in
  `environment/all`, where AutoIntegration finds every trigger as a direct
  dependency. Two jobs run the umbrella's suite: `test_integration()` and
  `test_repository()`.
- Each job collects the coverage of the files of this repository and sends it
  to Codecov. SDL draws with `SDL_VIDEODRIVER=offscreen`, because the runner
  has no display.

To run one suite as CI runs it:

```bash
julia --project=package/ProjecturedJSONTest \
      -e 'using Pkg; Pkg.instantiate(); using ProjecturedJSONTest; test_json()'
```

## Typical workflows

- **Added a new example.** `test_printer(my_example)`, then
  `test_reader(my_example)`, then `test_position_navigation(my_example)`, then
  `test_repl(my_example)`. Once those pass, the example is automatically
  picked up by `test_printers` / `test_readers` / etc. because they loop
  over the `examples` vector.
- **Changed a projection.** `walk_printer_output` and `walk_repl_loop`
  against the affected example give you a fast failure surface; the latter
  also catches reader/operation mismatches.
- **Changed the kernel/platform/domain source layering.** The per-package
  layering guards (`test_kernel_layering()`, `test_platform_layering()`) parse
  the real `import ..XxxModule` headers and re-check the include order in ~1s.
- **Suspected reactive bug.** `test_cell()` first, then
  `walk_printer_output` (which forces every reachable cell) on the
  affected example.
- **Selection navigation bug.** `explore_position_selections(doc, proj)` returns
  every reachable state; small `state_count` numbers are often the symptom
  of caret motion stuck in place. To check *coverage*, compare against
  `collect_position_selections(doc)` (or use `test_position_navigation(ex; check_reaches_all=true)`).

See [the debugging guide](debugging-guide.md) for the matching REPL helpers
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
