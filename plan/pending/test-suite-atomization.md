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

## The technique, by example

Atomization comes down to one rule: **test a leaf stage bare; test a node stage
with its children mocked as already-projected values passed through
`Preserving` — never recurse the real child pipeline just to test the parent.**

**Leaf stage — no recursion, no combinator.** A leaf projection has no children
to descend into, so it stands completely alone:

```julia
# fixture: minimal leaf document + the leaf stage under test
doc  = JsonString("hi")
proj = JsonStringToSyntaxLeaf()          # no RecursiveProjection wrapper needed
# test_printer("json_string_leaf", doc, proj) — asserts the leaf renders "hi"
```

**Node stage — children mocked, `Preserving` instead of recursion.** A container
projection (`JsonArrayToSyntaxNode`,
[`JsonToSyntax.jl:81`](../../package/domain/src/projection/primitive/JsonToSyntax.jl))
assembles a `SyntaxNode` from its elements — delimiters `[`/`]`, separator `, `,
indentation. To test *that assembly* you do not need the real per-element JSON
projection: populate the document with elements that are **already in the target
syntax domain** (mockups) and pass them through with `Preserving`:

```julia
# fixture: a JsonArray whose elements are already SyntaxLeafs (mocked children)
doc  = JsonArray([SyntaxLeaf(TextString("1")), SyntaxLeaf(TextString("2"))])
proj = RecursiveProjection(TypeDispatchingProjection(
           JsonArray => JsonArrayToSyntaxNode(),   # the node stage under test
           SyntaxLeaf => PreservingProjection(),   # children pre-projected → pass through
       ))
# test_printer("json_array_node", doc, proj) — asserts the node is "[1, 2]"
```

The parent's node-assembly contract is exercised in isolation; the children are
inert mockups, so a failure points squarely at `JsonArrayToSyntaxNode`, not at a
JSON-element regression three levels down. The same shape covers every container
stage (`JsonObjectToSyntaxNode`, the XML/SQL/formula nodes, …): real parent
stage + `Preserving` over mocked, already-projected children.

This relies on a domain document legitimately holding **children from a different
(here, already-projected) domain** — a `JsonArray` whose elements are
`SyntaxLeaf`s. In ProjecturEd-Julia that mixing is supported, not a hack:
documents are not type-closed over their element domain, which is exactly what
makes mockup children possible. So the node-fixture rule applies uniformly to
every container stage; no container needs a real child projection just to satisfy
an element-type constraint.

This is also why the combinator fixtures below use the *same* `Preserving`/spy
children — testing a container stage and testing the `Recursive`/`Type-`/`Reference-`
dispatch that drives it are the same exercise viewed from two ends.

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
- **Stage fixtures** — one per projection *stage*, built by the leaf/node rule in
  "The technique, by example" above: leaf stages bare (`JsonString` +
  `JsonStringToSyntaxLeaf`), node stages with children mocked as already-projected
  values behind `Preserving` (`JsonArray` of `SyntaxLeaf`s +
  `JsonArrayToSyntaxNode`). This is the shape `test_json_to_syntax()` already uses
  by hand for *render assertions*
  ([`JsonToSyntaxTest.jl:4`](../../package/test/src/projection/JsonToSyntaxTest.jl));
  the plan turns each into a runnable, reusable fixture so the
  *navigation/repl/typein* testers run against the isolated stage too — and so the
  fixture opens in the editor.
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

## Generalizing the oracle: goldens as fixture data

The hand-written stage tests (`test_json_to_syntax`
([`JsonToSyntaxTest.jl`](../../package/test/src/projection/JsonToSyntaxTest.jl)),
`test_syntax_to_text`, …) are not logic — they are tables of hardcoded
`(input → expected)` pairs of three kinds: **golden render** (`render(print(j2s,
JsonNull())) == "null"`), **golden reactivity** (mutate a value, assert
`!isuptodate` then the new render), and **golden interaction** (fire an event from
a selection, assert the resulting op/document). The generalization is to move the
oracle **out of the function body and into the fixture as data**, then assert it
generically.

Extend the atomic fixture with optional oracle fields and write each asserter
once:

```julia
struct AtomicFixture
    name; document; projection
    render        # nothing | String | (output -> Bool)   ← golden render
    mutate        # nothing | (document -> ())            ← reactivity probe
    render_after  # nothing | (output -> Bool)
    interaction   # nothing | (selection, event, after::Function)
end

function test_render(fx)
    out = projection_print(fx.projection, fx.document).output
    fx.render === nothing && return walk_printer_output(fx.document, fx.projection) # fallback: no-throw walk
    fx.render isa AbstractString ? (@test render(out) == fx.render) : (@test fx.render(out))
end
```

`test_json_to_syntax`'s assertions become fixture rows:

```julia
AtomicFixture("json_str_leaf",   JsonString("hi"),    JsonStringToSyntaxLeaf(); render="\"hi\"")
AtomicFixture("json_array_node", JsonArray([SyntaxLeaf("1"), SyntaxLeaf("2")]),
              node_with_preserving(JsonArrayToSyntaxNode());                    render="[1, 2]")
AtomicFixture("json_obj_node",   JsonObject("a"=>JsonNumber(1)), j2s;
              render = out -> occursin("\"a\": 1", render(out)))   # predicate ⇒ order-independent
```

Consequences:

- **The per-stage `test_<proj>()` functions are obsoleted as code** — they
  collapse into fixture rows plus three generic asserters (`test_render`,
  `test_reactive`, `test_interaction`). Adding a new stage means adding fixtures,
  not writing a test.
- **No expected value is lost** — the oracle is relocated, not deleted. Because
  the fixture is `run_example`-able, the golden render *is what appears on screen*:
  the oracle is verifiable by eye and doubles as documentation.
- **A small bespoke residue remains** — deep structural contracts (e.g. "a root
  swap nulls `ed.iomap`", "the cursor lands at exactly `value{1}`") that don't
  datafy cleanly stay as hand-written tests. Budget ~10–20% of today's stage
  assertions as residue; the rest become data.
- **A fixture with no oracle still gets coverage** — it falls back to the generic
  no-throw printer walk, so every atomic fixture is at minimum a smoke test even
  before anyone writes its goldens.

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
- **Phase 2 — stage fixtures + oracle datafication.** One mockup-surrounded
  fixture per projection stage; add the `render`/`mutate`/`interaction` oracle
  fields and the three generic asserters; **datafy** the existing hand-written
  stage tests (JsonToSyntax, SyntaxToText, …) into fixture rows, leaving only the
  deep-contract residue as bespoke tests. Net: the per-stage `test_<proj>()`
  functions disappear as code.
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
