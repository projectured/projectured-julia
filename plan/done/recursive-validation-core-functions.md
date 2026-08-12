# Validate the four core functions are recursive — without a fifth recursive function

> **Status (2026-08-12): DONE.** Part A (audit), Part B (harness), and Part C
> (docs) all landed. The harness lives at
> [package/projectured/test/editor/RecursionContractTest.jl](../../package/projectured/test/editor/RecursionContractTest.jl)
> (moved from `package/test/src/editor/` in the later package split). The one
> confirmed violation, `SyntaxNodeToText`/`SyntaxListToText` (now
> `SyntaxCompoundToText`/`SyntaxListToText`), was fixed by
> [syntaxtotext-delegation.md](../done/syntaxtotext-delegation.md), which is now
> in `plan/done/`. The harness's known-flattener list,
> `_is_known_flattener(p) = nameof(typeof(p)) in ()`, is empty — no `@test_broken`
> marker is active any more; every probed node is asserted with a plain `@test`.
> `test_recursion_contracts()` is still opt-in (not called from `test_all()`).

## Context

A projection exposes exactly **four** generic functions — the "great four":

| Function | Direction | Role |
|---|---|---|
| `projection_print`        | forward  | printer |
| `projection_read`         | backward | reader |
| `map_reference_forward`   | forward  | mapper (input ref → output ref) |
| `map_reference_backward`  | backward | mapper (output ref → input ref) |

Every screen the user sees and every gesture they make flows through one or more
projections via these four functions and nothing else. They are declared in
[package/kernel/main/projection/ProjectionApi.jl](../../package/kernel/main/projection/ProjectionApi.jl)
and dispatched on the concrete projection struct.

Each of the four is **recursive**: when a projection descends into child
documents, the function must hand each child to the **child projection's own**
version of *the same* function. The vehicles for that delegation already exist:

- the **`recursion`** parameter, invoked through
  `projection_printer_recurse(recursion, child, ctx)` (printer side); and
- the **stored child IO maps** (`ChildrenIoMap.child_iomaps`) that the reader and
  both mappers walk to reach the child projection (reader / mapper side).

**The contract this plan validates and documents:**

> Recursion across projections flows **only** through the four functions, by each
> function delegating a child to the child projection's own version of *that same
> function*. A projection may **not** introduce a *new* recursive generic
> function (a fifth interface method) to perform descent, and may **not** walk /
> flatten a child subtree itself by dispatching on the child's concrete type.

**Why the "no fifth function" rule is the whole point.** The four functions are
the *universal* interface — every projection, primitive or higher-order,
implements them. A fifth recursive function would **not** be implemented by every
projection. The moment a pipeline composes a projection that needs the fifth
function with one that does not, recursion breaks at the boundary. So the only
way to keep arbitrary projections composable is to express *all* descent through
the four functions that everyone already implements. This is also why the
validation below must be **external** (a test harness that drives the four
functions) and must itself add **no** new per-projection generic function.

This is the same rule the guides already call "School A" (delegate one level via
the child IO map) versus the "School B" anti-pattern (re-walk the input by child
type). This plan names it, states the negative constraint explicitly, audits the
codebase against it, and designs a validation that uses only the four functions.

---

## Part A — Audit: who breaks the contract

A full sweep of every projection implementation under (old, pre-restructure
paths — the twenty domains are each their own package now, see
[documentation/domains.md](../../documentation/domains.md), each with a
`main/`/`example/`/`test/` split) `package/kernel/src/projection/`,
`package/domain/src/projection/`, `package/projectured/example/src/projection/`,
and the opt-in example packages' `package/{odbc,adaptagrams,tulip}/example/src/projection/`
was performed (the four functions plus every private helper they call).

### Confirmed violation (exactly one)

**`SyntaxNodeToText` / `SyntaxListToText`** (now `SyntaxCompoundToText` /
`SyntaxListToText`, and the violation described here is fixed — see the status
banner) —
[package/syntax/main/SyntaxToText.jl](../../package/syntax/main/SyntaxToText.jl)

- `projection_print(::SyntaxNodeToText, recursion, node, ctx)` (≈ L194) threads
  `recursion` but **never invokes it**. It calls `_collect_spans` (≈ L778) →
  `_collect_child_spans` (≈ L765) which **dispatches on the child's concrete type**
  (`SyntaxNode` vs `SyntaxLeaf`) and recurses over the whole subtree, flattening it
  into one flat `TextBlock` span array. This is printer-side "School B".
- `SyntaxListToText` does the same via `_syntax_list_to_text_node` (≈ L422) →
  `_render_syntax_to_spans` (≈ L472).
- The mapper / reader flat-character walkers (`_syntax_to_flat`, `_subtree_len`,
  `_pos_to_selection`, `_pos_to_tree_selection`, `_node_at_collapse_glyph`) re-walk
  the same subtree in flat-character space — the backward-side twin of the same
  violation. (These exist *only* to invert the flattening; they disappear once the
  printer delegates.)

This was scoped for repair in
[syntaxtotext-delegation.md](../done/syntaxtotext-delegation.md) (Part A), which
has since landed and is now in `plan/done/`. **This plan did not perform that
refactor** — it documented the violation and deferred the fix, which is done.

### Allowed patterns that look similar but are NOT violations

Distinguish "walks **its own** input domain" (allowed) from "walks / flattens
**children** that should be delegated" (violation):

- `*ToSyntax` node projections (`JsonArrayToSyntaxNode`, `JsonObjectToSyntaxNode`,
  `XmlElementToSyntaxNode`, `MathBinaryOperationToSyntaxNode`, `SyntaxToWidget`,
  `BookBookToSyntaxNode`, …): iterate children but delegate each via
  `projection_printer_recurse` and store `child_iomaps`. ✅ compliant.
- `CollectionToSyntax` (`_map_listnode`, `CollectionCellVectorToSyntax`): delegates
  each element via `projection_printer_recurse`; `_translate_collection_path` peels
  **one** level (`children[i] ↔ element[i]`) and the mapper delegates the tail —
  not a subtree walk. ✅ compliant.
- `TextToGraphics` (`_build_paragraph_node`): walks a `ListNode` of
  `TextString`/`TextNewline` — those are its **own** text-domain input elements,
  not projected children. ✅ compliant.
- `LayoutToGraphics`, `DbCatalog*`, all kernel generic/higher-order projections:
  delegate via `projection_printer_recurse` or wrap an inner projection. ✅.
- `SyntaxToText`'s keyboard tree navigation (`_tree_navigate`, `_is_tree_selection`,
  `_promote_to_structural`, …): walk the **input** SyntaxNode tree and its selection
  *paths* — the projection's own domain, reached only at the root node. ✅ allowed
  (these stay even after the printer is fixed).

**Result: 1 confirmed violation, 0 other suspects, ~150 compliant files.**

---

## Part B — Validation strategy (no fifth recursive function)

> **Implemented** in
> [package/projectured/test/editor/RecursionContractTest.jl](../../package/projectured/test/editor/RecursionContractTest.jl)
> (this file moved from `package/test/src/editor/` in the later package split).
> The realized harness keeps the two highest-value, lowest-false-positive checks:
> the **delegation probe** (the composition-substitution idea below, realized with a
> spy `recursion`) is the asserted test, and the **reference reachability + round-trip**
> is shipped as REPL walkers (`walk_reference_roundtrip` / `walk_recursion_contract`)
> pending calibration on a running editor before promotion to a hard assertion. The
> printer-lockstep splice-identity check was dropped as largely redundant with the
> existing `test_printer` walk and prone to false positives on legitimately
> copy-then-splice projections (e.g. `CopyingProjection`). The spy is an ordinary
> higher-order projection, so **no new per-projection generic function is added** —
> the core requirement. Entry points: `test_recursion_contract(example)`,
> `test_recursion_contracts()`, `probe_delegation`, `walk_reference_roundtrip`,
> `walk_recursion_contract`.

Validate the contract **externally**: a test harness that drives the existing four
functions over **composed / nested** examples and asserts observable recursion
properties. It lives only in the test package and dispatches on examples, **not**
on projections — so it introduces no new per-projection generic function.

All building blocks already exist (paths as of 2026-08-12; the test package split
moved them out of a shared `package/test/src/editor/`):

- `_walk!` ([PrinterTest.jl:45](../../package/kernel/test/editor/PrinterTest.jl)) —
  reflexive walk of an iomap, forcing every `Cell`.
- `collect_text_selections` / `collect_tree_selections` — renamed
  `collect_position_selections`
  ([SelectionEnumeration.jl](../../package/substrate/test/document/SelectionEnumeration.jl)) —
  ground-truth references enumerated directly from a document. This is the name
  the shipped harness actually uses.
- `_assert_reaches_all`
  ([NavigationTest.jl](../../package/kernel/test/editor/NavigationTest.jl), renamed
  from `TextNavigationTest.jl`) — subset assertion.
- `explore_text_selections` / `explore_tree_selections` — renamed
  `explore_position_selections` — navigation BFS.

### New harness: `package/projectured/test/editor/RecursionContractTest.jl`

Expose `test_recursion_contract(example)` / `test_recursion_contracts()` and the
non-`@testset` walker `walk_recursion_contract(doc, proj) -> errors::Vector{String}`,
matching the existing test conventions. Each checks three properties, all using
only the four functions of the **top-level** projection (which recurse internally):

1. **Reference reachability (mappers descended into every node).** Enumerate every
   reference with `collect_text_selections` / `collect_tree_selections`; for each,
   assert `map_reference_forward(proj, iomap, ref) !== nothing`. A non-nothing image
   for a deeply nested reference is only possible if the mapper delegated all the way
   down — a flattening mapper drops references it never recursed into.

2. **Reference round-trip (forward/backward agree through delegation).** For each
   forward image `out = map_reference_forward(...)`, assert
   `map_reference_backward(proj, iomap, out)` returns the original reference (modulo
   the documented `ProjectionReference`/flat-offset collapse for
   projection-introduced positions). Round-tripping through every level is the
   signature of lockstep recursion.

3. **Printer structural lockstep (printer spliced delegated children).** Reuse
   `_walk!` to reach every iomap; for any iomap exposing a `child_iomaps` field,
   assert each `child_iomap.output` is **object-identical** to the corresponding
   child in the parent output (the printer composed delegated outputs rather than
   rebuilding the subtree). Reflection-based, generic over iomaps — no per-projection
   method.

### The discriminating test: composition substitution

The above catch *missing* recursion. To catch a printer that **flattens** while
still appearing to work, add a composition test that is the operational meaning of
"recursive = composable":

- Take a node example, and via an existing higher-order projection
  (`AlternativeProjection` / `ReferenceDispatchingProjection`, or a tiny test-only
  tagging projection composed under the same `RecursiveProjection`) **substitute the
  projection used for one child subtree**.
- Assert the parent's **output changes** to reflect the substituted child, and that
  references into that child still map through.
- A compliant projection delegates, so the substitution takes effect; a flattening
  projection (School B) ignores `recursion` and the substitution has **no effect** —
  the test fails. This is exactly what would flag `SyntaxToText`.

This needs no new interface method — it is built from existing higher-order
projections, satisfying the "no new recursive function" constraint.

### Handling the known violator — ✅ resolved, no longer applies

`test_recursion_contract` would fail on the `SyntaxToText` pipeline (json/xml/math/
syntax examples that route through it). The plan called for recording it as a
**known/expected** failure (an `xfail`-style skip pointing to
[syntaxtotext-delegation.md](../done/syntaxtotext-delegation.md)) so the suite
stayed green with the exception visible. That refactor landed instead, so the
skip was never needed as a permanent fixture: the shipped harness's
`_is_known_flattener` list is empty, and every probed node is a plain `@test`.

### Wiring

`test_recursion_contracts()` is exported from
[package/projectured/test/ProjecturedTest.jl](../../package/projectured/test/ProjecturedTest.jl)
and is documented in
[documentation/testing.md](../../documentation/testing.md) (line 364 onward), but
is **still opt-in** — `test_all()` does not call it, even though the violator
that motivated keeping it out is now fixed. Adding it to `test_all()` is the one
small remaining follow-up.

---

## Part C — Documentation (landed in this change)

State the contract — including the "no fifth recursive function" rule — as a
first-class, named concept, cross-linked across the API and guides.

- **API** —
  [package/kernel/main/projection/ProjectionApi.jl](../../package/kernel/main/projection/ProjectionApi.jl):
  add a **"The recursion contract"** section to the module docstring naming the four
  functions, the delegation vehicles (`recursion` / `child_iomaps`), and the negative
  constraint (no fifth recursive generic function; it breaks composition because not
  all projections implement it).
- **Guide** —
  [package/kernel/doc/projection-system.md](../../package/kernel/doc/projection-system.md):
  add a dedicated **"The recursion contract"** section consolidating the rule, the
  "no fifth function" constraint, and a pointer to how it is validated; reinforce the
  existing "Recursion across projections" and "School B" anti-pattern callouts to
  reference the named contract.
- **Guide** —
  [package/kernel/doc/higher-order-projections.md](../../package/kernel/doc/higher-order-projections.md):
  cross-link the `RecursiveProjection` section to the named contract (it already
  explains `recursion` keeps projections single-level/composable).
- **Concepts / architecture** (the deferred "B4" from the syntaxtotext plan):
  one-line mention in
  [documentation/concepts.md](../../documentation/concepts.md) (projections combine
  by single-level delegation through `recursion`) and a note in
  [documentation/architecture.md](../../documentation/architecture.md).
- **Testing** —
  [documentation/testing.md](../../documentation/testing.md): a
  **"Validating the recursion contract"** subsection describing the Part B harness
  and that it adds no per-projection function.

---

## Verification

- Documentation: prose only; no test impact. Confirm cross-links resolve.
- When Part B lands: `test_recursion_contract(json_example)` and `…(xml_example)`
  exercise the harness; `walk_recursion_contract(doc, proj)` returns errors as a
  `Vector{String}` for REPL iteration. Confirm the `SyntaxToText` pipelines surface
  as the only (expected) failures, and that every other example passes all three
  properties plus the substitution test.
- Regression guard: a future projection that flattens a subtree (School B) is caught
  by reachability + the substitution test without any change to the projection API.
