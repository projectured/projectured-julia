# Reactivity property testing — touch an input, watch the output move

> **Status (2026-08-12): NOT STARTED.** No part of the harness exists — a search
> for `test_reactivity`, `iomap_nodes`, `reactive_surface`, and `check_reactivity`
> across `package/` finds nothing. §7's phases 1 through 6 are all still to do.

**Status:** design proposal, staged build (§7). Not started.
**Scope:** a property-based harness over the 88 registered examples that walks the
**IoMap tree**, writes to each node's input, and asserts that node's output
followed.
**Driver:** three bugs in one work stream, all the same shape, none caught by any
test — because every test re-printed, and a re-print always looks correct.

---

## 1. The property

> **Touch any field of the input, and at least one field of the output must be
> invalidated.**

That is the whole idea and it is worth stating plainly, because the bugs it
catches are exactly the ones nothing else catches: the output does not go *wrong*,
it goes **stale**. Nothing errors, no assertion trips, the pixels are merely from
a document that no longer exists.

### 1.1 What it would have caught

Three instances in one work stream, at three different layers:

| bug | shape |
|---|---|
| Staged disclosure never fired in the live workbench | a `Vector` handed to a layout is frozen into constant `Cell`s, so the card set was correct on frame one and never changed |
| `WorkbenchEditor.content` could not be replaced | `WidgetScrollPane`'s constructor wraps its argument in `Cell(content)`, a constant, so a panel kept rendering the document it was born with |
| Stages built with `...Mut` constructors | `MutableCell`s sit outside the reactive graph, so a button label would not flip |

Every one survived a full green suite for weeks or months. Every one is a
one-line consequence of "a value was captured where a thunk was needed".

### 1.2 The dual property, which is worth as much

> **Touching one input field must NOT invalidate the whole output.**

The cheap way to pass the first property is to rebuild everything — which is
precisely the fix this codebase already rejected once (`invalidate_projection!`
for a child-list change) and is now forbidden by AR-REACTIVE-OUTPUT-STRUCTURE.
AR-FINEST-GRANULARITY says the same thing positively. So the harness measures the
**fraction** of output cells invalidated, and a projection that invalidates
everything for a leaf edit fails just as loudly as one that invalidates nothing.

Under-invalidation is staleness. Over-invalidation is churn. One harness, two
bounds.

---

## 2. The unit is an IoMap node, not a document leaf

The property is stated per **IoMap**, because that is the thing that pairs an
input with an output:

> For every node of the IoMap tree: touch that node's `input`, and something
> under that node's `output` must be invalidated.

An IoMap is exactly `(projection, input, output)` plus its children —
`ChildrenIoMap.child_iomaps`, `ContentIoMap.inner_iomap` — so the tree is
walkable and every node carries the projection responsible for it. Three things
follow, and they are why this framing beats walking the input document's leaves:

- **Failures localise.** "This `ContentIoMap` for `WorkbenchEditorToWidgetScrollPane`
  did not follow its input" names the projection and the file. A leaf walk says
  only "something in this 88-example tree went stale".
- **Sub-projections are covered by construction.** The bugs were in *nested*
  projections, and a nested projection is exactly a child IoMap.
- **Most of the reachability problem disappears.** A projection that drops part of
  its input produces no IoMap for the dropped part, so the IoMap tree is
  self-selecting at node granularity. §3's oracle is then only needed *within* a
  node.

This is also what the codebase already says it intends. `ContentIoMap`'s own
docstring: *"its `output` / `inner_iomap` may be computed cells that re-derive
reactively while the IoMap keeps its identity"*. The WorkbenchEditor bug was that
one of them was a constant.

### 2.1 The observable is the node's whole reactive surface

Not "the output document", and not "the `output` cell" — **both, plus the IoMap's
other cells**. An `@iomap` struct stores every field as a Cell, so a node's
reactive surface is:

```
{ getfield(iomap, :output), getfield(iomap, :inner_iomap | :child_iomaps), ... }
  union  { cells reachable from iomap.output }
```

**Watching only the output tree is not merely incomplete, it produces FALSE
FAILURES.** If a projection re-derives its output wholesale, the `output` cell
invalidates and yields a *new* tree — and the cells snapshotted from the *old*
tree are now orphaned. Re-reading them shows no change, so a correctly reactive
projection is reported as frozen. The invalidation happened one level up, on the
IoMap's own cell, which is exactly where a test that never looked would miss it.

Both shapes are legitimate and both must pass:

| shape | where the invalidation shows |
|---|---|
| stable output, reactive interior (the workbench's root layout, whose `children.elements` is a thunk) | a cell inside the output tree |
| re-derived output (an `@iomap` whose `output` is a computed cell) | `getfield(iomap, :output)` |
| reconciled children (`ContentIoMap.inner_iomap`) | the child-IoMap cell |

AR-STABLE-IOMAP-IDENTITY still holds and is still asserted: the IoMap **object**
keeps its identity. Its **field cells** are exactly what may re-derive — that is
what the `@iomap` macro exists for.

### 2.2 The procedure, per node

```
1. print once; force every Cell reachable from the ROOT output
2. for each IoMap node, in tree order:
     a. snapshot the node's reactive surface — its own field cells AND the cells
        currently reachable from its output — recording which are VALID
     b. mutate one leaf of THIS node's input
     c. assert: >= 1 snapshotted cell became invalid
                and the IoMap object itself is the same object
     d. restore the leaf, and re-force
```

Printing once and restoring after each write keeps one tree alive for a whole
example, which is what makes 88 examples affordable at all.

### 2.3 Validity, not values

An earlier draft proposed diffing *values* on the grounds that it measures what a
user would see. That is wrong here, for two independent reasons:

- **It cannot see a re-derived output.** Per §2.1, the old tree's cells are
  orphaned and their values never move, so the correct projection fails.
- **This test is about reactivity.** The question is whether the graph propagated,
  not whether the pixels happen to differ. A cell that invalidates and recomputes
  an identical value has behaved correctly; a cell that never invalidates has not,
  even if some coincidence makes the render look right.

So the primary observation is `valid`, and values are kept only as a **diagnostic**
on failure — "nothing invalidated" (a frozen cell) reads very differently from
"invalidated everywhere" (§1.2's churn).

### 2.4 Mutating a leaf, generically

The awkward part. A type-directed mutator over leaf values:

| type | new value |
|---|---|
| `Int` / `Float64` | `x + 1` |
| `String` | `x * "'"` |
| `Bool` | `!x` |
| `Symbol` | a fresh gensym |
| `Char` | `x + 1` |
| enum | the next member, wrapping |
| anything else | **skip, and count it** |

Documents are not mutated wholesale — the walk recurses, so their own leaves get
their turn. The skip count is reported, because a harness that silently skips most
of a tree looks green while testing nothing.

## 3. The hard part: not every input field owes the output anything

`FilteringProjection`, `SearchingProjection` and focusing all **deliberately**
drop parts of their input. Touching a filtered-out element legitimately changes
nothing, and a naive harness would report a false failure on every one of them.

At node granularity the IoMap tree already handles this — a dropped child has no
IoMap. But *within* a node, an input document may still carry fields the
projection does not show, so the oracle is still needed there, and there is
already exactly one:

```julia
map_reference_forward(projection, iomap, input_reference)
```

If it returns a reference, that input location is *shown* and the output must
follow. If it returns `nothing`, the location is not shown and there is no
obligation.

That is the principled formulation, and it has a pleasant side effect: it tests
the **mappers** too. A mapper that wrongly claims a location is visible turns
into a reactivity failure; one that wrongly claims it is hidden turns into a
skipped field that the skip count surfaces.

**Escape hatch:** a per-example allowlist of `(reference, reason)` pairs for
genuine exceptions, starting empty. Every entry must carry a written reason, the
way `# @broken:` does. An allowlist that grows without reasons is how this kind of
harness dies.

---

## 4. Cost, and how to keep it bearable

88 examples x every leaf x (print + force twice) is not a per-commit test.

- The **walk is per-leaf, but the print is not**: print once, force once, then for
  each leaf write / re-force / restore. Restoring the old value keeps one printed
  tree for the whole example.
- Bound the leaves per example (say 200, sampled deterministically) and **report
  what was skipped** — silent truncation reads as coverage.
- Ship it as `test_reactivity()`, run in the broad sweep rather than in
  `test_kernel()` / `test_base()`. `AR-SMALLEST-TEST` still applies: nobody should
  run this to check a one-line change.

---

## 5. What this does not test

Worth stating so nobody assumes otherwise:

- **Reader-side reactivity.** This is printer-only. The dual property for readers
  — an output edit produces an operation that changes the input — is
  `test_readers`' territory.
- **Ordering and timing.** It asserts *that* the output follows, never *when*.
- **Correctness of the new value.** Only that something moved. A projection that
  invalidates and computes nonsense passes.
- **Structure changes.** Adding an element to a collection is not a leaf write;
  §7's phase 5 covers it separately, and it is where the disclosure bug actually
  lived.

---

## 6. Open questions

1. **Validity or values (§2.1)?** Proposed: values, with validity as diagnostic.
   The alternative reads the property more literally at the cost of coupling the
   harness to cell internals.
2. **What is the over-invalidation bound?** A fraction is crude — a small output
   legitimately changes proportionally more. Perhaps "not 100% unless the input
   leaf is the root's own field", or a per-example recorded baseline that may only
   improve. Needs measuring before it is pinned.
3. **Do transient widget fields count as output?** `hovered`, `pressed`,
   `scroll_position` and `collapsed` are view state, not projections of the input.
   They are in the output tree, so they inflate the denominator. Exclude them?
4. **How do the 88 examples divide?** Some are `:abstract`, some terminal in
   `:graphics`. Forcing a graphics tree is much more expensive. Run the property
   at the widget level where an example has one?

---

## 7. Staged build

**Invariants:** existing suites stay green; the harness adds no dependency; it is
opt-in, not part of `test_kernel` / `test_base` / `test_visual`.

### Phase 1 — walk the IoMap tree
`iomap_nodes(iomap)` yielding every node via `child_iomaps` / `inner_iomap`, each
with its projection, input and output. Nothing is asserted yet.
*Verify: on `json_example` the node count is stable and every node's projection is
non-nothing; on `object_to_widget_example` the tree is deeper than one node, so
the walk genuinely descends into sub-projections.*

### Phase 2 — the observation primitives
`force_output!`, `reactive_surface(node)` returning the node's own field cells
PLUS the cells reachable from its output, and `invalidated(snapshot)`.
*Verify: forcing then snapshotting twice with no edit reports zero invalidations;
writing one leaf by hand reports at least one. A nested node's surface is a strict
SUBSET of the root's — if they are equal, the walk is not descending. And
critically: construct a projection whose `output` is a computed cell, and assert
the surface catches its invalidation even though every cell of the OLD output
tree is untouched — that is the orphaning case of §2.1, and a harness that misses
it reports false failures forever.*

### Phase 3 — the property, one example
`check_reactivity(example)` returning per-node verdicts, with the
`map_reference_forward` oracle deciding obligation within a node.
*Verify: `json_example` passes with no allowlist. Then INJECT each of the three
§1.1 bugs in turn and assert the harness FAILS — that is the real acceptance
test, and it is worth writing the injections as a fixture rather than by hand.*

### Phase 4 — all 88, and the granularity bound
`test_reactivity()` over the registry, with the over-invalidation bound from §6
Q2 measured first and pinned second.
*Verify: report per example — nodes walked, leaves tested, skipped, obliged,
failed, and the worst invalidation fraction. Whatever fails on the first full run is a FINDING,
not a bug in the harness — record each one before fixing it.*

### Phase 5 — structural edits
Beyond leaf writes: push/pop an element, replace a child document, swap a
`nothing` for a value. This is where the disclosure bug lived, and a leaf-only
harness would not have caught it.
*Verify: an example whose projection builds children from a plain `Vector` fails;
the same one passes once its container is a thunk.*

### Phase 6 — docs + close-out
Document the property and its exemptions in `documentation/testing.md`, and
record what the build changed about this design.
