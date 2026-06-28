# Atomize the test harness: woven atomic fixtures, not accidental complex examples

## The idea (in one paragraph)

The **example tester functions are good and stay** — `test_printer`,
`test_reader`, `test_repl`, `test_text_navigation`, `test_typein`
([`PrinterTest.jl`](../../package/test/src/editor/PrinterTest.jl),
[`ReaderTest.jl`](../../package/test/src/editor/ReaderTest.jl),
[`ReplTest.jl`](../../package/test/src/editor/ReplTest.jl),
[`TextNavigationTest.jl`](../../package/test/src/editor/TextNavigationTest.jl),
[`TypeinTest.jl`](../../package/test/src/editor/TypeinTest.jl)) already take a
labelled `(document, projection)` pair and need no changes. What's wrong is
**what we run them on**: ~88 large, *accidentally* composed real-world examples
([`Examples.jl`](../../package/example/src/Examples.jl)), each dragging a full
`…ToSyntax → SyntaxToText → TextToGraphics` pipeline through the slow TrueType
layout, so coverage of any one document, stage, or combinator is buried inside a
composition and re-paid dozens of times. Replace that primary fixture set with a
**library of small, hand-woven atomic fixtures** — one minimal document per
domain, one projection *stage* surrounded by *mockup* projections, one
*combinator* woven over a trivial child — run the existing testers over them, and
keep the complex examples as an **opt-in integration tier** for when you want
end-to-end confidence. Because each atomic fixture is a real `(document,
projection)` pair, it is also `run_example`-able: a minimal feature gallery and
manual-debugging aid, useful in its own right.

## Why this beats "pick a representative per pipeline shape" (the earlier draft)

The earlier version of this plan tried to tag the 88-example registry with
`shape`/`coverage` metadata and sweep only representatives. That keeps the
*accidental* fixtures and just runs fewer of them. The better move is to stop
deriving coverage from accidental compositions at all:

- **Direct, not transitive.** A combinator like `SortingProjection` is today only
  exercised because `json_sorted` happens to sort an object's entries. A woven
  fixture (trivial leaf child + a 3-element collection in scrambled order)
  exercises the *sort contract itself* and fails with a name that points at the
  combinator, not at a JSON pipeline.
- **No fragile skip-lists.** The scattered `startswith(name,"widget")` /
  `endswith(name,"_widget")` skip heuristics in
  [`TextNavigationTest.jl:142-168`](../../package/test/src/editor/TextNavigationTest.jl),
  [`MouseClickTest.jl:304`](../../package/test/src/editor/MouseClickTest.jl),
  [`ClickRoundtripTest.jl:194`](../../package/test/src/editor/ClickRoundtripTest.jl)
  exist because the registry mixes navigable and non-navigable examples. An
  atomic fixture is *built* to be editable-or-not, so it simply declares which
  testers apply — the heuristics dissolve.
- **The fixtures pay their way twice.** Each is a runnable editor demo. The big
  composed examples stay for screenshots and integration, but the atomic library
  is what you open when you want to *see one feature working in isolation*.

## The pieces, and what already exists

### 1. Mockup kit (mostly already in the tree)

Small reusable stand-ins that let a single unit be wrapped into a runnable
pipeline without the real stack:

- **Terminal / pass-through projections** — `PreservingProjection`,
  `CopyingProjection` already exist
  ([`HigherOrder.jl`](../../package/domain/src/projection/compound/HigherOrder.jl)).
  Add (if missing) a *minimal leaf-to-text/graphics terminal* so a stage's output
  is observable and the fixture is `run_example`-able, without pulling the full
  `SyntaxToText`/`TextToGraphics` chain when the unit under test sits above them.
- **Spy / observer projections** — model on `_SpyRecursion`
  ([`RecursionContractTest.jl:43`](../../package/test/src/editor/RecursionContractTest.jl)),
  a higher-order projection used as the `recursion` argument that counts
  delegations. The same trick gives combinator fixtures an *observable child*
  (records what input it was handed, in what order) without adding any
  per-projection generic function.
- **Minimal documents per domain** — the bare structs the document tests already
  build (`JsonNull()`, `JsonBool(true)`, a 2-element `JsonArray`, …, cf.
  [`JsonTest.jl`](../../package/test/src/document/JsonTest.jl)). Promote these from
  inline test locals to named fixtures so both the tester and `run_example` share
  them.

### 2. Atomic example registry

A new `atomic_examples::Vector{Example}` in the example package, parallel to
`examples`. Three families:

- **Document fixtures** — `(minimal domain document, minimal mockup terminal)`,
  one per domain. Exercises the document model + its leaf rendering.
- **Stage fixtures** — `(mockup input document, stage-under-test ∘ mockup
  terminal)`, one per projection *stage*. This is exactly the shape
  `test_json_to_syntax()` already uses by hand
  ([`JsonToSyntaxTest.jl:4`](../../package/test/src/projection/JsonToSyntaxTest.jl):
  `RecursiveProjection(JsonToSyntax())` printed on bare `JsonNull()`); the plan
  generalizes it into a runnable, reusable fixture so the *navigation/repl/typein*
  testers — not just `render(...)` assertions — also run against the isolated
  stage.
- **Combinator fixtures** — `(woven document, higher-order projection over a
  trivial/spy child)`, one per combinator, each constructed so the combinator's
  contract is observable (see the table below).

### 3. The testers loop the atomic registry

`test_atomic()` does for `atomic_examples` exactly what `test_printers()` /
`test_readers()` / … do for `examples` today — same functions, new fixture list.
No new tester code.

## Combinators and their woven-fixture contracts

The higher-order projections that must be tested directly (struct defs across
`package/*/src/projection`), each with the minimal weave that makes its contract
fail loudly if broken:

| Combinator | Woven fixture | Observable contract |
|---|---|---|
| `SequentialProjection` | two spy stages over a 1-node doc | stage 2 receives stage 1's output, in order |
| `RecursiveProjection` | container doc + spy child | child invoked once per projectable child node (delegation) |
| `TypeDispatchingProjection` | doc with two node types + two leaf children | each node routed to the child registered for its type |
| `ReferenceDispatchingProjection` | doc with two sibling sub-paths | each sub-path routed by reference, others preserved |
| `PredicateDispatchingProjection` | doc whose nodes split on a predicate | predicate decides the child |
| `NestingProjection` | inner stage + `Preserving` below | recursion handed to inner; nodes below the seam preserved |
| `FocusingProjection` | doc + focus sub-path | output re-rooted at the focus; edits/selection map back under it |
| `FilteringProjection` / `SearchingProjection` | 3-element collection + predicate/query | failing elements hidden; references map past the gaps |
| `SortingProjection` / `SortingAtProjection` | scrambled 3-element collection | output reordered; references map through the permutation |
| `ReversingProjection` | ordered 3-element collection | output reversed; reference inversion round-trips |
| `ProjectionConfiguringProjection` | text doc + control bar | bar stacks above; editing controls re-projects |

`CopyingProjection` / `PreservingProjection` need no fixture of their own — they
*are* the mockups, and the table above exercises them as the trivial children.

## Tiers

- `test_atomic()` — the five testers over `atomic_examples` (documents + stages +
  combinators), plus the existing direct-assertion stage tests. **Primary
  coverage, fast, the dev-loop default.**
- `test_printers()` / `test_readers()` / `test_repls()` / … over the complex
  `examples` registry stay exactly as they are — now an **opt-in integration
  tier** ("if one wants that").
- `test_all()` runs both, for CI.

## Phases (each independently shippable, suite stays green)

- **Phase 0 — mockup kit.** Inventory existing pass-through/spy projections;
  add the minimal leaf terminal and a reusable spy-child if missing; promote the
  per-domain minimal documents to named fixtures. No new coverage yet — just the
  building blocks.
- **Phase 1 — document fixtures + `atomic_examples` + `test_atomic()`.** Wire the
  five testers to loop the new registry; make every fixture `run_example`-able and
  confirm each opens in the editor. This alone moves the *document* axis off the
  complex examples.
- **Phase 2 — stage fixtures.** One mockup-surrounded fixture per projection
  stage; fold the existing hand-written stage tests (JsonToSyntax, SyntaxToText,
  …) onto the shared fixtures so they stop re-building documents inline.
- **Phase 3 — combinator fixtures.** Build the woven fixtures from the table;
  reuse the `_SpyRecursion` pattern for the delegation/order assertions. This is
  the coverage that *did not exist directly* before.
- **Phase 4 — retier & document.** Make `test_atomic()` the documented default in
  [`documentation/testing.md`](../../documentation/testing.md) and CLAUDE.md's
  "Testing a change"; mark the complex-registry sweeps as the integration tier.
  Re-measure dev-loop time vs. the Phase 0 baseline.

## What explicitly does NOT change

- **Complex examples stay fully testable.** `test_printers()` & friends keep
  working over `examples`; the request is to make them *optional*, not gone — "if
  one wants that."
- **The screenshot gallery is untouched** — `generate_example_screenshots`
  ([`ExampleTest.jl:791`](../../package/test/src/editor/ExampleTest.jl)) still runs
  over the full `examples` registry.
- **Lazy/stateful exclusions** (`lazy`, `clipboard`, `versioning`,
  [`Examples.jl:93-142`](../../package/example/src/Examples.jl)) are unaffected;
  atomic fixtures are by construction finite and stateless.

## Risks / open questions

- **Fixture fidelity vs. the real pipeline.** A stage tested only behind a mockup
  terminal could pass while failing in the real composition (e.g. a downstream
  stage relies on output shape the mockup tolerates). Mitigation: the complex-
  example integration sweep stays in CI as the end-to-end gate; the atomic tier is
  the fast dev signal, not the sole one. Model mockup fidelity on the existing
  minimal-document stage tests, which already catch real regressions.
- **The mockup terminal must force the cells that matter.** `_walk!` only finds
  bugs in cells it reaches; a too-trivial terminal may short-circuit the reactive
  graph. Each stage fixture must assert (via the printer walk) that its
  characteristic cells are forced — the "value change propagates" assertions in
  `test_json_to_syntax` are the template.
- **One honest contract per combinator.** The table must describe a contract that
  *actually fails* when the combinator is broken (a spy that's never consulted, a
  permutation that doesn't invert). Where a combinator's contract is subtle
  (focusing/filtering reference mapping), reuse `walk_reference_roundtrip`
  ([`RecursionContractTest.jl`](../../package/test/src/editor/RecursionContractTest.jl))
  rather than inventing a new check.

## Progress

- [ ] Phase 0 — mockup kit (terminal + spy child + named minimal documents)
- [ ] Phase 1 — document fixtures, `atomic_examples`, `test_atomic()`; each fixture verified `run_example`-able
- [ ] Phase 2 — per-stage mockup-surrounded fixtures; existing stage tests folded onto them
- [ ] Phase 3 — per-combinator woven fixtures + direct contract assertions
- [ ] Phase 4 — retier (`test_atomic` default, complex sweep = integration); docs/CLAUDE.md updated; re-measured
