# Reactivity property testing — touch an input, watch the output move

**Status:** design proposal, staged build (§7). Not started.
**Scope:** a property-based harness over the 88 registered examples that writes to
one input field at a time and asserts the output followed.
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

## 2. Mechanism

For one example and one input leaf:

```
1. print_document(projection, document)      -> iomap
2. force every Cell reachable from iomap.output   (walk_printer_output already does this)
3. snapshot: which output cells are valid, and their values
4. write ONE input leaf with a different value
5. re-read the snapshot set
6. assert: >= 1 cell changed   AND   fraction changed <= bound
```

Step 2 matters: an unforced cell is already invalid, so without it every test
passes vacuously. `walk_printer_output` (kernel/test) already forces every
reachable cell and is the right starting point.

### 2.1 Detecting the change

Two candidate observations, and the choice is not obvious:

- **Validity flags.** `ReactiveCell` carries `valid::Bool`. Reading it directly
  measures invalidation exactly, which is what the property says.
- **Values.** Force again and diff. Coarser — an invalidation that recomputes to
  the same value is invisible — but it measures what a user would see, and it
  does not depend on cell internals.

**Proposal: values, with validity as the diagnostic.** A projection that
invalidates and recomputes an identical value has not misbehaved; a projection
whose visible output is unchanged after an input edit has, whatever its flags
say. Validity flags then explain a failure ("nothing was even invalidated" vs
"invalidated but recomputed the same").

### 2.2 Mutating a leaf, generically

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

Documents are not mutated wholesale — the walk recurses into them, so their own
leaves get their turn. The skip count is reported, because a harness that
silently skips most of the tree looks green while testing nothing.

---

## 3. The hard part: not every input field owes the output anything

`FilteringProjection`, `SearchingProjection` and focusing all **deliberately**
drop parts of their input. Touching a filtered-out element legitimately changes
nothing, and a naive harness would report a false failure on every one of them.

So the property needs a reachability oracle, and there is already exactly one:

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

### Phase 1 — the observation primitives
`force_output!(iomap)` (reuse `walk_printer_output`), `snapshot_output(iomap)`
returning a `Vector{Pair{Cell,Any}}`, and `changed(snapshot)` re-reading it.
*Verify: on `json_example`, forcing then snapshotting twice with no edit reports
zero changes; writing one leaf by hand reports at least one.*

### Phase 2 — the leaf walk and the mutator
`input_leaves(document)` (reuse `walk_document`) and `mutate_leaf!` per §2.2,
with restore.
*Verify: on `json_example`, the leaf count is stable and every mutation is
reversible — the document compares equal to a pre-walk copy afterwards. The skip
count is reported, and it is small.*

### Phase 3 — the property, one example
`check_reactivity(example)` returning per-leaf verdicts, with the
`map_reference_forward` oracle deciding obligation.
*Verify: `json_example` passes with no allowlist. Then INJECT each of the three
§1.1 bugs in turn and assert the harness FAILS — that is the real acceptance
test, and it is worth writing the injections as a fixture rather than by hand.*

### Phase 4 — all 88, and the granularity bound
`test_reactivity()` over the registry, with the over-invalidation bound from §6
Q2 measured first and pinned second.
*Verify: report per example — leaves tested, skipped, obliged, failed, and the
worst invalidation fraction. Whatever fails on the first full run is a FINDING,
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
