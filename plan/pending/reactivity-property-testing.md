# Reactivity property testing — touch an input, watch the output move

> **Status (2026-08-14): PHASES 1 TO 4 DONE.** The walk, the
> observation
> primitives live in
> `package/projectured/test/editor/ReactivityTest.jl`. Phases 5 and 6 remain.
>
> The 2026-08-12 note said NOT STARTED because it searched for the names this
> plan invented — `test_reactivity`, `iomap_nodes`, `reactive_surface`,
> `check_reactivity`. Much of §2.2 already existed under other names in
> `PrinterLocalityTest.jl`. See §8.

**Status:** staged build (§7), phases 1 to 4 done. Phase 5 (structural edits) and phase 6 (docs) remain.
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
for a child-list change) and is now forbidden by PAR-REACTIVE-OUTPUT-STRUCTURE.
PAR-FINEST-GRANULARITY says the same thing positively. So the harness measures the
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

PAR-STABLE-IOMAP-IDENTITY still holds and is still asserted: the IoMap **object**
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
  `test_kernel()` / `test_base()`. `PAR-SMALLEST-TEST` still applies: nobody should
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

### Phase 1 — walk the IoMap tree — **DONE 2026-08-14**
`iomap_nodes(iomap)` yielding every node, each with its projection, input and
output. Nothing is asserted yet. `test_iomap_walk(label, document, projection)`
checks the walk itself.

*Verified:* the node count is stable across two walks of one printed tree, and
the walk descends. json 61 nodes / depth 5 / 6 projection types, xml 141 / 7 / 5,
graph 38 / 9 / 12, math 26 / 6 / 9, object_to_widget 3 / 1 / 3.

**Design decision — find a child by field inspection, never by a name list.**
The plan said "via `child_iomaps` / `inner_iomap`". That is wrong. The loaded set
holds more than forty IoMap types using at least twelve names for the relation:
`child_iomaps`, `inner_iomap`, `step_iomaps`, `content_iomap`, `content_iomaps`,
`element_iomaps`, `child_iomap`, `root_iomap`, `window_iomaps`, `palette_iomap`,
`log_iomap`, `slice_iomap`. So `_iomap_children` scans every field except
`projection`, `input` and `output`, one level into a vector, and unwraps a `Cell`
at each step — `ChainingProjectionIoMap.step_iomaps` is a `Vector{Cell}`.

The first version tested `element isa IoMap` without unwrapping the cell, and
every example reported a one-node tree. That is the dangerous failure: the walk
reports success and the property then passes everywhere by measuring nothing.
`test_iomap_walk` exists to catch it.

### Phase 2 — the observation primitives — **DONE 2026-08-14**
`reactive_surface(node)` returns the node's own field cells PLUS the cells
reachable from its output, forcing both so that validity means something.
`invalidated(surface)` and `followed(surface)` read validity only. The
output-reachable half reuses `_collect_locality!` from `PrinterLocalityTest.jl`
rather than a second collector. `test_reactive_surface()` is the acceptance test
and it passes on all four checks.

**Design decision — a nested surface is DISJOINT from the root's, not inside
it.** The verification below asked for a strict subset. Measurement says
otherwise: on `json_example` every one of the 60 nested nodes shares **zero**
cells with the root's 1022. The root of an example is a chaining projection, its
steps are siblings in different domains — Json, Syntax, Text, Graphics — and step
k's output is step k+1's input, never a part of the chaining IoMap's output.

This matters beyond the test. **Phase 3 must compare a node against its own
output and never against the root's**, and a "fraction of the output invalidated"
bound in §6 Q2 has to be per node for the same reason.

**Design decision — the write goes to the input, not the output.** An early draft
of check 2 wrote to a cell of the output and saw nothing move. Writing a cell
makes that cell valid again and invalidates only its dependents, and a terminal
output cell has none.
*Verify: forcing then snapshotting twice with no edit reports zero invalidations;
writing one leaf by hand reports at least one. A nested node's surface is a strict
SUBSET of the root's — if they are equal, the walk is not descending. And
critically: construct a projection whose `output` is a computed cell, and assert
the surface catches its invalidation even though every cell of the OLD output
tree is untouched — that is the orphaning case of §2.1, and a harness that misses
it reports false failures forever.*

### Phase 3 — the property, one example — **PARTLY DONE 2026-08-14**
`check_reactivity(node)` and `check_reactivity(example)` return per-node
verdicts. `_next_value` is the type-directed mutator of §2.4. `input_leaves(node)`
collects the writable leaves of a node's input, `MutableCell` included on
purpose — that cell always answers "up to date", which is the third bug of §1.1.
Every write is undone in a `finally`, because the examples are shared objects
inside one process.

**The acceptance test passes.** `test_reactivity_property()` builds two fixtures:
one that captures its input value into a constant cell, the way
`WidgetScrollPane(content)` did, and one that re-derives. The harness calls the
first frozen and the second reactive. That separation is what the whole plan
depends on.

**The oracle IS wired now, and it changed everything.** `input_leaf_targets`
pairs each writable leaf with a `Reference` from `search_references(...;
raw=true)` — those carry the right type checkpoints, which a hand-built path
would not. `is_obliged` then asks `map_reference_forward` and keeps three
outcomes apart: shown and owed, deliberately dropped, and unanswerable. Only the
first can produce a frozen verdict.

Before the oracle, `json_example` reported 51 frozen of 75 writes. After it,
**zero** — every leaf the projection says it shows did follow. The 51 were all
false positives, exactly as §3 predicted.

**The oracle must be asked with the DOCUMENT-SCOPED path.** The first wiring
asked with the leaf path, which ends at the scalar (`…JsonString.value`). A
projection maps document-scoped locations — a selection lands on a `JsonString`,
never on its `value` field — so `map_reference_forward` answered `nothing` for
almost everything and the harness read that as "this projection shows nothing".
It shows all of it. The question is now the parent path, re-annotated with type
checkpoints, while the leaf path still names the field for the message.

That is a large correction. json went from 11 leaves measured to 31, and math
from none to 20.

### 8.6 Oracle rule 2: obligation has two tiers

Two questions are asked of `map_reference_forward`, because neither alone can
express "this field is shown", and each failed in an opposite direction.

- Ask with the **leaf** path only and it declines 64 of 75 locations on json: a
  projection maps document-scoped locations, not scalar fields.
- Ask with the **document** path only and it approves every field of every shown
  document. That is how `:indentation` became a false finding. A `SyntaxLeaf`
  carries an `indentation` field, and `syntax_indentation` has **no method for a
  leaf** — nothing consults it, so writing it correctly moves nothing.

So: `:strong` when the leaf path maps, `:weak` when only the document path maps,
`:none` when neither, `:unknown` when the question cannot be asked. A frozen
verdict under a strong obligation is a finding. Under a weak one it is
`unproven` and never becomes a marker.

### 8.7 The result, all 103 examples

At 12 nodes and 2 leaves per example:

| outcome | count |
|---|---|
| followed | 193 |
| **frozen, strongly obliged** | **1** |
| unproven, weakly obliged | 42 |
| carried by reference | 58 |
| not shown | 796 |
| unanswerable | 5 |

**The one finding is real, and it is confirmed.** At
`root.child_iomap.step_iomaps[1].editing_page_iomap` — the
`WorkbenchPageToWidgetTabbedPane` node — obligation is **strong** and writing
`WorkbenchEditor.filename` invalidates **0 of 964** cells. The tab title of the
editing page does not follow the filename of the editor it names.

A first probe appeared to refute it, reporting `obligation === :none`. That probe
was wrong: it evaluated the obligation *after* writing the cell, so it asked the
mapper about a mutated document. Measured before the write, the obligation is
strong at that node and `:none` at the element nodes below it, which is
consistent and reproducible.

`test_verdict_stability` settles the doubt properly. The same leaves measured
forward and backward, and one run repeated, give identical counts on json, xml,
workbench, book and syntax. The sweep does not depend on the order of its own
measurements.

The 42 unproven are `:indentation` in 14 examples, plus `:level` and
`:alignment` once each. `:indentation` is understood — a field with no reader.
The other two are not yet examined.

Over-invalidation remains a non-issue: median 0% of a surface per write, worst
35%, and no write anywhere moves a whole surface.

### 8.5 Oracle rule 1: a value carried by reference is owed nothing

The chart examples reported `:title` and `:label` frozen on all eight. The chart
printer is not at fault: `ChartPlotToGraphicsCanvas` builds its geometry in a
`ComputedCell` that reads `chart.title` inside the thunk.

The node reporting frozen was `ChartToChartPlot`, whose output is a `ChartPlot` —
a wrapper holding the live `Chart`. The written cell **is itself part of that
node's output**. Writing it cannot invalidate anything there, and nothing is
stale: the renderer one stage on reads the same cell. Charging that node is
charging it for not copying.

So the property gains a rule, checked before any write is judged: **if the
written cell is reachable from the node's own output, the node passes the value
through and owes nothing.** The obligation belongs to whichever node re-derives
from the value, and that node is measured on its own.

The effect, at 12 nodes and 2 leaves per example:

| example | frozen before | frozen after | carried |
|---|---|---|---|
| chart_line, sequencechart (8 charts) | 2 | 0 | 2 |
| json_sorted | 8 | 0 | 8 |
| sorting, reversing | 7 | 0 | 7 |
| json | 0 | 0 | 0 |

`json` now measures 18 leaves and all 18 follow.

### 8.4 The first real finding: syntax chrome does not propagate

With 25 nodes and 3 leaves each:

| example | tested | followed | frozen | not shown |
|---|---|---|---|---|
| json | 31 | 22 | 9 | 44 |
| xml | 12 | 4 | 8 | 63 |
| math | 20 | 0 | 20 | 45 |

**Every frozen verdict, in all three, is `:collapsed` or `:indentation`.** Not a
scattered set — one signature, on `SyntaxLeafToText`, `SyntaxCompoundToText`,
`JsonObjectToSyntaxNode` and `JsonObjectEntryToSyntaxNode`. Content fields follow;
these two do not. On math every measured leaf is one of them, which is why it
reports nothing followed.

Both are chrome fields of a syntax node, and collapse is implemented at
`SyntaxToText`. So either a write to `collapsed` genuinely fails to re-render —
which would mean a collapse toggle shows stale text — or the projection reads
these through a cell other than the one addressed by
`node.collapsed` / `node.indentation`.

**This is one finding to verify, not thirty-seven.** Verify it the direct way:
toggle collapse on a syntax node in the live editor and see whether the text
re-lays out. The harness has done its job by narrowing weeks of possible
staleness to two field names.

**The fixtures bypass the oracle**, with `check_reactivity(node; oracle=false)`.
They are the ground truth: the location is shown by construction, and neither
fixture carries a projection to ask a mapper about. The oracle filters for real
projections; the fixtures test the mechanism it filters for.

The original text of this phase follows.
*Verify: `json_example` passes with no allowlist. Then INJECT each of the three
§1.1 bugs in turn and assert the harness FAILS — that is the real acceptance
test, and it is worth writing the injections as a fixture rather than by hand.*

### Phase 4 — all examples, and the granularity bound — **DONE 2026-08-14**
`test_reactivity()` sweeps every registered example. It runs green at **103 pass,
1 broken, 0 fail, 0 error in 7 minutes**. The one broken marker is the workbench
tab title, keyed on the FIELD `:filename` rather than on the example, so a
different frozen field there stays an unmarked failure. When the bug is fixed the
marker turns into an unexpected pass and has to be removed.

An unproven verdict is reported but never asserted on: only the document path
mapped, so the field may have no reader, which is true of `SyntaxLeaf.indentation`.

**§6 Q2 is answered: no bound is needed.** Over-invalidation was measured across
all 103 examples and there is nothing to bound — median 0% of a surface moved per
write, worst 35%, and no write anywhere moves a whole surface. Pinning a fraction
would add a number with no violation behind it.

`test_verdict_stability` guards the sweep itself: the same leaves measured
forward, forward again and backward must give identical counts.
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

---

## 8. What the build found

### 8.1 Half of §2.2 already existed, under other names

`package/projectured/test/editor/PrinterLocalityTest.jl` already holds:

| this plan calls it | it is called there |
|---|---|
| the cells reachable from an output | `_collect_locality!` / `LocalityCell` |
| the §2.2 procedure | `printer_locality_report(document, projection, mutate!)` |
| §1.2, the over-invalidation bound | `test_selection_locality`, `explore_selection_locality` |
| §7 phase 5, structural edits | `explore_structural_locality` |
| the orphaning problem of §2.1 | the object-identity diff, `lost_objects` / `preserved_objects` |

So this harness is **the other half**, not a new one. What is genuinely missing:

1. The IoMap **tree** walk. `printer_locality_report` snapshots from the root
   output only, so a failure can not name the projection that froze. Phase 1.
2. The **under**-invalidation assertion. That file asserts a minimal set changed;
   it never asserts that anything changed. That is the half that catches the
   three §1.1 bugs.
3. A node's **own field cells** in the surface (§2.1).
4. The generic type-directed **leaf mutator** (§2.4). That file takes a
   caller-supplied `mutate!`.
5. The `map_reference_forward` **oracle** (§3).

Phases 2 to 5 reuse `_collect_locality!` rather than write a second collector.

### 8.2 A finding: the workbench IoMaps carry no projection

26 of the 29 nodes of `workbench_example` answer `nothing` to
`get_iomap_projection`. `package/workbench/main/WorkbenchToWidget.jl:267`
constructs `WorkbenchWorkbenchToWidgetShellIoMap(nothing, w, shell, …)` with a
literal `nothing`, and the whole subtree under it inherits the habit.

Two consequences. A failure in that subtree can not name the projection that
caused it. Worse, the §3 oracle is `map_reference_forward(projection, iomap,
reference)`, so a node with no projection **can not be measured at all** — the
workbench, the one example whose bugs drove this plan, is the least reachable.

This is a defect in the workbench projection, not in the harness. It is recorded
here and left alone: fixing it is its own task and needs its own test.

### 8.3 §6 Q1 is settled: validity, not values

§2.3 argues for validity with values as diagnostic, and §6 Q1 proposed the
reverse. §2.3 wins; §6 Q1 was the older text. The argument stands: a re-derived
output orphans the old tree's cells, so a value diff reports a correct
projection as frozen. §6 Q2, Q3 and Q4 stay open and are answered by
measurement in phase 4.
