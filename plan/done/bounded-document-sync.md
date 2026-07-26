# Bounded document sync — drill-down by demand, not by depth

**Status:** complete. Phases 1–6, §4a, and §3's fold into the sealed files.
**Scope:** let `sync_document!` stop at a bound and leave a marker where it
stopped; let a consumer *request* that a marker be filled in on the next sync.
Then a shadow grows only where someone looked.
**Driver:** an inspector for a live `SimulationExecution` and `SimulationInstance`
in omnetpp-julia — see §6.

---

## 1. The idea

The naive way to inspect a running simulation is to shadow it and render the
shadow. That fails on cost: `sync_document!` walks the whole source, and a
sequential engine holds `module_hashes` and `event_counts` at 1345 entries each
for the NTT backbone, `module_event_logs`, and an FES heap of thousands of
events whose actions are closures over the model. Syncing that every ~100 ms to
display a handful of numbers is absurd, which is why omnetpp's workbench
currently dodges the problem with a hand-written four-field view
(`SimulationExecutionView`) instead of shadowing the execution at all.

The obvious fix is to make the *projection* lazy — render only what is expanded.
That is the wrong layer. It leaves the sync cost untouched: you would still walk
1345 elements per slice and then throw them away.

**Put the laziness in the sync instead.** Sync to a bound; where it stops, write
a marker document. A marker renders as an unexpanded node. When the user expands
it, the marker is *flagged*; the next sync sees the flag and fills that node in
one level deeper, writing fresh markers below. Widgets need no laziness at all —
they render whatever the shadow holds, and the shadow is small because the sync
was bounded.

Three consequences fall out, and they are the reason to prefer this shape:

- **Cost is proportional to what is being looked at**, not to the model. An
  unexpanded engine costs a handful of field writes per slice.
- **Expansion state needs no side table.** It lives in the shadow, as the
  presence-or-absence of markers. `sync_document!` preserves identity for
  same-type children (`_sync_fields!` syncs in place, replacing only on a type
  change), so the shadow a widget holds stays the shadow it holds.
- **It is reusable.** Any consumer shadowing anything large gets it: a debugger
  over a deep AST, a file-tree view, a live object inspector.

---

## 2. Mechanism

### 2.1 The marker

```julia
@document struct UnsyncedDocument
    kind::Any        # what stands here (a type name, for the label)
    size::Int        # how many children it would have, if cheaply known; -1 unknown
    requested::Bool  # set by the UI; the next sync fills this node in
end
```

A marker is a real `Document`, so it flows through printers and references like
anything else. A projection shows it as a collapsed node labelled from `kind`
(and `size`, when known), with a chevron.

### 2.2 The bounded sync

```julia
sync_document!(shadow, source, policy::SyncPolicy)
```

`SyncPolicy` decides, per node, whether to descend, stop with a marker, or
descend because a marker there was `requested`. The default policy is a depth
bound plus "always follow requests":

```julia
struct DepthPolicy <: SyncPolicy
    depth::Int          # how deep to sync without being asked
    collection_cap::Int # elements per collection before a marker stands in
end
```

`collection_cap` matters as much as depth: an engine's 1345-element
`module_hashes` is one level down but must not be walked. A capped collection
syncs its first `n` and leaves a marker for the rest.

### 2.3 The request round trip

Expanding a node writes `requested = true` on its marker — an ordinary
`ReplaceReferencedValueOperation`, so it is just an edit to the shadow. The next
`sync_document!` sees it and syncs that subtree one level, replacing the marker
with the real child (identity changes *there*, which is exactly the
materialisation; ancestors keep theirs).

Collapsing writes a marker back — which is also how the shadow *shrinks* again,
so a long inspection session does not accumulate the whole model.

---

## 3. The sealed-file question

`package/kernel/main/document/DocumentSync.jl` is **🔒 sealed**.

**Phase 1–5 do not touch it.** `sync_document!` is a generic function, so the
policy-taking methods can live in a new, unsealed file — most naturally
`package/base/main/document/BoundedSync.jl`, beside the existing unsealed
document code. The sealed 2-argument `sync_document!(shadow, source)` keeps its
exact current behaviour and is what the 3-argument version calls once it decides
to descend fully.

**The user is open to unsealing it if the feature proves out** — bounded sync is
something they have wanted, with no occasion for it until now. That is
*conditional*, and the condition is the point: build it beside the sealed file
first, demonstrate the value with §6's acceptance test, and only then come back
with evidence and ask.

So the sequencing is deliberate, not timid:

- **If the out-of-file version is clean**, leave it there. A generic function
  extended from an unsealed file is not a workaround; it is how Julia is meant
  to work, and it keeps the audited file audited.
- **If it turns out to duplicate the sealed recursion** — i.e. the bounded walk
  has to re-implement `_sync_fields!` / `_sync_elements!` rather than delegate to
  them — then the honest implementation lives *inside* `DocumentSync.jl`, and
  that is when to ask. Duplicated traversal logic that must stay in step with a
  sealed file is worse than editing the sealed file with permission.

Either way the ask happens **with a working feature and a measurement in hand**,
never speculatively, and per the standing rule it is a per-change review of a
specific diff — not a blanket grant.

### 3.1 What Phase 1 found: the duplication signal fired

The out-of-file version works, but it is the *second* case above, not the first.

The sealed walk recurses through the **two-argument** `sync_document!`, so there
is no seam to thread a policy through: `_sync_fields!` calls `sync_document!(cur,
sv)` and that method knows nothing of a bound. A three-argument method defined
elsewhere cannot re-enter that recursion carrying state. So `_bounded_fields!`
and `_bounded_elements!` **mirror** `_sync_fields!` (18 lines) and
`_sync_elements!` (16 lines) rather than delegating — two traversals, identical
in every decision except the policy check, that must now be kept in step by hand.

Phase 2 then added a third mirror, `_bounded_copy`, against
`copy_document(K, doc)` in the equally sealed `DocumentCopy.jl` — same shape,
same reason. (It replaced a worse `_prune!` that copied the whole subtree and
walked back over it; the mirror is the honest version.)

Inside the sealed files none of this is needed: a `policy`/`depth` pair defaulted
to unbounded on the existing functions makes the bound one branch in the walks
that are already there. Roughly **-70 lines of mirrored logic, +15 in the sealed
files**, and one traversal of each kind instead of two.

Holding to the sequencing anyway: build Phases 2–3 on the out-of-file version,
get §6's measurement, then ask with the diff. If the measurement shows `_prune!`'s
eager copy is not actually a problem in practice, the ask gets weaker and the
duplication may simply not be worth an unseal.

### 3.2 What the fold actually cost — asked, approved, applied

The estimate above was **wrong**, and knowing why is the useful part.

It assumed the bound could be added to two sealed files. It could not: the policy
hooks live in `base`, *above* the kernel, so for the sealed walk to carry a bound
the **protocol** has to sink to the kernel (AR-PACKAGE-CHAIN). Five sealed files,
not two:

| | |
|---|---|
| `DocumentInterface.jl` | declares the three hooks + `HiddenElements` |
| `DocumentDefaults.jl` | their unbounded defaults |
| `DocumentModule.jl` | exports them |
| `DocumentSync.jl` | threads `policy`/`depth`; one shared `_synced_child` |
| `DocumentCopy.jl` | the same, plus the capped element copy |

The marker type does **not** sink. The kernel knows only that *something* goes in
a stopped slot and asks the policy for it, so `UnsyncedDocument` and `DepthPolicy`
stay in base. `HiddenElements` is the one piece of vocabulary the contract needed
— the elements a capped walk is not keeping, handed over without copying them,
since a positional collection document is not `view`-able.

`BoundedSync.jl` lost ~150 lines and now answers three questions instead of
walking anything.

**A stronger reason than duplication surfaced while drafting.** The out-of-file
mirror could only reach the kinded-copy machinery by importing
`_declared_value_types` / `_kinded_value_type` — *non-exported* kernel internals,
from a higher layer. AR-MODULE-BOUNDARY-IS-API forbids exactly that ("reaching
into an internal is the smell, never the fix"). The mirror was not merely
duplicative; it was a layering violation. Folding in removed it.

**Three things the apply caught that the draft did not:**

- **`AR-INTERFACE-DECLARES-ONLY` fired.** Putting the defaults and a concrete
  struct in `DocumentInterface.jl` is exactly what that guard exists to stop;
  they belong in `DocumentDefaults.jl`. The layering test caught it, which is the
  audit working as designed.
- **A capped copy must wrap its placeholder in a cell** like the elements beside
  it — a `Vector{Cell}` cannot hold a bare document.
- **The element walk nearly lost an `isequal` short-circuit.** Routing every
  document-valued slot through the shared `_synced_child` would have rebuilt a
  slot already holding the very same object. Caught by reading, not by a test.

**Verified:** kernel 455/3/2 — *identical to the pre-change baseline*, whose 3
failures and 2 errors are pre-existing `DmSoleVector` macro tests; base 269/269;
visual 49 228/49 229; omnetpp suites and all watch self-tests green. The
measurements are unchanged: 1 536 B per slice for a 334-module engine, the same
for a 7-module one.

**Re-audit of the five sealed files** against `architecture-requirements.md`,
done rather than deferred. The layering guard covers AR-INTERFACE-DECLARES-ONLY,
AR-MODULE-BOUNDARY-IS-API and the layer heights, and passes. By hand:

- **AR-NO-CONSUMER-DOCS — violated, fixed.** `DocumentInterface.jl` pointed at
  `base`'s guide "for the policy `base` supplies", and the kernel's document
  guide said the same. A lower layer naming its consumer inverts the dependency
  in prose exactly as an import would. Both now describe the contract offered to
  *any* caller. Same fix in `BoundedSync.jl`, which named OMNeT++ in its
  motivation.
- **AR-QUALIFIED-EXTENSION — not applied, deliberately.** The rule wants
  `using ..XxxModule` plus `XxxModule.f(…) = …`; `BoundedSync.jl` uses
  `import ..DocumentModule: …` and extends by bare definition. That matches every
  sibling in `base` — `Collection.jl` extends `copy_document` the very same way —
  and the rule's own text describes a staged rollout. Converting one file would
  leave it inconsistent with its layer for no gain (AR-FOCUSED-DIFFS). Worth
  doing as its own sweep of `base`.
- **AR-DOCUMENT-IDENTITY** — the element walk's `isequal` short-circuit is
  preserved, so a slot holding the very same object is still not rebuilt.
- **AR-FIELDS-ARE-CELLS / AR-EVERY-DOCUMENT-HAS-SELECTION** — `HiddenElements` is
  a plain value type, not a `Document`; `UnsyncedDocument` is a `@document` and
  gets both by construction.
- **AR-NO-PROJECTION-GLOBALS / AR-PER-EDITOR-STATE** — no state added; the policy
  is a parameter the caller holds.
- **AR-NEW-CODE-SHIPS-TESTS** — `test_bounded_sync` / `test_document_reflection`
  in `test_base`, `test_reflection_to_widget` in `test_visual`.

The five files are unchanged in behaviour for every existing caller (kernel tests
match the pre-change baseline exactly) and are ready to be considered sealed
again.

---

## 4. Tree vs ObjectToWidget — which renders it

Once sync is bounded, *both* candidates become viable, because both would be
rendering a small shadow. The choice is about shape, not cost. Recorded here
because the question came up and the answer is not obvious.

| | `WidgetTree` | `ObjectToWidget` |
|---|---|---|
| **Built for** | hierarchical drill-down | reflecting one object as a form/card |
| **Expansion UI** | already has chevrons + `collapsed::Set{Vector{Int}}`, and the flattening walk skips collapsed subtrees | none today — recurses on print, bounded by `_MAX_DEPTH = 16` |
| **Density** | one compact row per node; deep structures stay readable | cards and forms; bulky per node, so depth costs a lot of space |
| **Values** | label text only — everything is stringified | value-appropriate widgets, and **editable** where a field is cell-backed |
| **Reflection** | you write the object → node mapping | already solved: field selection, classification, opaque-value handling |
| **Fit for a live engine** | good: read-only inspection is what you want | editing a running engine's internals is not obviously desirable |

**Leaning:** `ObjectToWidget` for the *content*, because it already answers "what
fields does this object have and how should each value be shown", which is the
bulk of the work and is exactly what we do not want to hand-write for
`SequentialSimulator`, `RoutingModel`, `Recorder`, … With bounded sync its
depth-recursion stops being a liability, because there is little to recurse
*into*.

**✅ Decided — `WidgetTree`.** §4a inverted the argument. The leaning above rested
entirely on `ObjectToWidget` already doing the reflection; now
`DocumentReflection` does it, ahead of any widget, and both candidates render the
same `ReflectedNode` tree. What is left of the table is density — one compact row
per node versus a card per node — and for an inspector meant to be drilled into,
that is not close. `ObjectToWidget` also brings editability, which is the wrong
affordance for a running engine's internals.

The wiring, from reading `WidgetToGraphics`:

- A tree chevron already emits `ReplaceReferencedValueOperation(tree, "collapsed",
  next_set)`. The reader diffs old against new to find the one toggled path, maps
  it to a `ReflectedNode`, and either `request_sync!`s that node's marker or
  writes a marker back — then swallows the operation. The printer derives
  `collapsed` from the domain (a node whose `children` is a marker is collapsed),
  which is the same round-trip discipline the workbench's selection uses.
- A collapsed node has no materialised children, but the flattener draws a
  chevron only when `!isempty(children)`. So a marker node emits **one placeholder
  child** carrying the marker's summary ("1000 items"). It is never rendered — the
  path is in `collapsed` — it exists so the chevron is there to click.

**But** it needs an expansion affordance it does not have today. Two ways:

- **(a)** Give `ObjectToWidget` a chevron per composite value that toggles the
  marker's `requested` — small, and the marker is already in the shadow.
- **(b)** Use `WidgetTree` for the skeleton and `ObjectToWidget` for a selected
  node's detail — a two-pane inspector. More UI, but each widget does what it is
  good at.

Decide after §7 Phase 3, when there is something to look at. `WidgetTree` alone
remains the fallback if `ObjectToWidget`'s density turns out to be unworkable.

---

## 4a. The gap Phase 3 exposed: the engine is not a document

`sync_document!` — bounded or not — requires **both sides to be `Document`s**, and
plenty of what one wants to inspect is not one.

*(Corrected during Phase 5: the omnetpp engine and execution actually **are**
`@document`s — the engine was made one for the dashboard's sake — so bounded
`sync_document!` would have applied to them directly. The gap is real but
narrower than stated: it is the model, the recorder and everything reached
through them. Reflection is still the right answer, because it gives **one**
uniform tree over documents and plain structs alike, and the inspector should not
have to care which it is standing on.)*

So §6 needs one more piece: a **reflective bounded shadow** — walk an arbitrary
Julia object and produce a generic document tree (a node with a label, a value
and a child collection), bounded by the same policy and marked by the same
`UnsyncedDocument`. That is the reflection `ObjectToWidget` already performs,
emitting documents instead of widgets.

This does not change Phases 1–3, and the element cap becomes *more* load-bearing
under it: in a reflected tree an engine's 1345-entry array is a child collection,
which is exactly what Phase 3 caps. It does reshape Phase 5, which is now two
steps (reflect, then render) rather than one, and it moves §4's Tree-vs-
ObjectToWidget question — the reflection is shared either way, so the choice is
purely about presentation.

**✅ Built** as `package/base/main/document/DocumentReflection.jl` +
`DocumentReflectionTest.jl` (`test_document_reflection`, in `test_base`).
`ReflectedNode(label, kind, value, children)`, where `children` is a `CellVector`
when expanded, an `UnsyncedDocument` when collapsed and `nothing` for a leaf —
the same three states `should_descend_sync` already distinguishes, so collapsing
is just writing a marker there and no new policy concept was needed.

What the build settled:

- **The child interface is an iterator plus a count**, `reflect_child_pairs` /
  `reflect_child_count`, not a vector. The first version returned a vector and
  cost **162 KB per sync** on a 1000-element field showing four of them — the
  bound was defeated by the act of enumerating what it was withholding. This is
  the sharpest lesson of the phase: a cap only saves you if the code above it
  never materialises what is capped.
- **Measured**: a collapsed 1 000 000-element field costs the same per sync as a
  1 000-element one (~74 KB, and the test asserts within 2×), and a small object
  costs ~650 B per *shown* node. That is §6's "does not grow with model size"
  criterion, met at the sync layer before any UI exists.
- Type labels keep their parameters (`Vector{Int64}`, not `Array`) and drop
  module qualifiers.

## 5. Open questions

- **Does a marker need to remember its source?** Filling it in requires the
  *source* subtree, which sync has in hand at that moment — so probably not. But
  a marker whose parent got replaced wholesale must not resurrect a stale
  request; worth a test.
- **Cycles.** Bounded sync makes cycles survivable (you stop), but a user could
  expand around a loop forever. A visited-set per sync pass, or a hard depth
  ceiling on requests?
- **Cost of the check.** The policy is consulted per node; it must not make an
  unbounded sync measurably slower than today's. Benchmark before/after.
- **Who owns `default_depth`?** Proposed as a field on the projection, per the
  original suggestion — but it is really a property of the *sync*, so it may
  belong on the policy the consumer holds. The projection then reads the shadow
  and nothing else.

---

## 6. Consumer: the omnetpp inspector

The driver, and the acceptance test. In `omnetpp-julia`'s workbench, two cards
each holding a scroll pane:

- **Instance** — the built object graph: model, topology, resolved parameters.
- **Execution** — the live engine: FES, clock, counters, recorder.

Both must open cheaply on a 57-node routing network and let the user drill to any
depth on demand. Success is: opening the cards costs a bounded sync; expanding
one node costs one more level; and the per-slice sync while a run is in flight
stays flat as the model grows.

This is also the honest test of whether the mechanism is worth it — if the
inspector still needs a hand-written view to be usable, the answer is no.

---

## 7. Staged build

**Invariants:** the sealed `DocumentSync.jl` is untouched (§3); existing
`sync_document!` callers keep byte-identical behaviour; `test_visual` and
`test_kernel` stay green.

### Phase 1 — the marker + bounded sync ✅ done
`UnsyncedDocument`, `SyncPolicy`, `DepthPolicy`, and
`sync_document!(shadow, source, policy)` in a new unsealed file. No consumer yet.
*Verify: a depth-bounded sync of a deep nested document produces markers at the
bound and leaves ancestors identical to an unbounded sync; an unbounded policy
reproduces today's result exactly.*

Built as `package/base/main/document/BoundedSync.jl` +
`package/base/test/document/BoundedSyncTest.jl` (`test_bounded_sync`, wired into
`test_base`). 39 assertions green; `test_base` 197/197. What the build settled:

- **The unbounded policy delegates**, so "reproduces today's result exactly" is
  true by construction rather than by test — and §5's worry about the per-node
  policy check slowing an unbounded sync is answered: there is no check on that
  path. The test still compares both walks, because the guarantee is only as good
  as the delegation, and a later "optimisation" could quietly remove it.
- **Identity holds across a bounded sync** (asserted directly): a same-type child
  is synced in place, so a widget holding a node still holds it afterwards. This
  is the premise §1 rests on for keeping expansion state in the shadow.
- **`@document` appends a `selection` field to every document**, so a marker's
  `size` for a record is `fieldcount - 1`. Counting raw fields misreports every
  label by one — caught by the test, not by inspection.
- **The bounded walk mirrors rather than delegates per level**, see §3 below.

### Phase 2 — requests ✅ done
`requested` honoured: flagging a marker fills that node one level on the next
sync, writing fresh markers below. Collapsing restores a marker.
*Verify: expand/collapse cycles converge — the shadow after expand-then-collapse
equals the shadow before; repeated expansion walks down a chain one level per
sync.*

Verified, and it forced two design changes that §2.3 had not anticipated.

- **The shadow decides, not the depth.** The first attempt consulted the depth
  for every slot and honoured `requested` as an override. It *oscillated*: a
  request materialises a node past the bound, and the next sync sees a real node
  past the bound and collapses it again — expand, collapse, expand, forever. The
  rule is now three cases, and only the third is the bound: a marker descends iff
  `requested`; a slot already holding a document is kept whatever its depth; an
  **empty** slot faces the depth. So `depth` means "where growth starts", not
  "the deepest anyone may see" — and collapse becomes symmetric at every level,
  including inside the bound, which the depth-first rule got wrong too.
- **A shadow must be born bounded**, hence `copy_document(kind, doc, policy)`.
  Once the shadow is authoritative, a shadow made by the ordinary full copy has
  already grown everything and the bound has nothing left to withhold. This also
  **deletes `_prune!`**: materialising a request builds only to the bound instead
  of copying the whole subtree and walking back over it, so §3.1's complaint
  about the eager copy is answered without touching `DocumentCopy.jl` — the same
  unsealed-extension trick as the sync. The mirrored-traversal complaint stands.

### Phase 3 — collection cap ✅ done
Large collections sync a prefix and mark the tail. This is what makes a 1345-
element engine array survivable.
*Verify: a 10 000-element vector syncs in bounded time; the marker reports the
remaining count.*

`DepthPolicy` gained `elements` (default 32) and a second hook,
`sync_element_limit(policy, total, shown, requested)`, deliberately *not* folded
into `should_descend_sync` — "how many siblings" and "descend into this one" are
different questions and a policy may well answer them independently.

The hook's shape repeats Phase 2's rule one dimension over: what is already shown
stays shown, and a request buys **one more page** rather than the whole tail.
Verified on a 10 000-element vector — 8 shown, tail marker reporting 9 992, and
re-syncing allocates under 100 KB, so the cost tracks what is displayed rather
than what exists.

One implementation note worth keeping: the capped copy builds with
`similar(v, 0)`, not a comprehension. A collection document declares its backing
vector's element type (`Vector{Cell}`), and an `Any[]` fails the type assert on
first index — which is how it was found.

### Phase 4 — rendering ✅ done
Whichever of §4 wins. A marker renders as a collapsed node with a chevron whose
toggle writes `requested`.
*Verify: a headless test drives expand → sync → deeper node appears.*

`package/visual/main/widget/ReflectionToWidget.jl` + `ReflectionToWidgetTest.jl`
(`test_reflection_to_widget`, in `test_visual`). 19 assertions; `test_visual`
49 228/49 229 with the one pre-existing `@test_broken`.

The round trip came out as §4 predicted, with one wrinkle worth keeping: the
printer *derives* `collapsed` from the shadow and the reader swallows the
chevron's write, so the widget never holds a second copy of the expansion state.
The wrinkle is that `WidgetTree` draws a chevron only for a node with children,
and a collapsed node has none — so a marker node emits one placeholder child
carrying the marker's summary ("100 items not loaded"). It is never rendered,
since its parent's path is in `collapsed`; it exists so there is a chevron to
click. That also gives the collapsed row somewhere to state what it is hiding,
which turned out to read better than a bare chevron.

### Phase 5 — the omnetpp inspector ✅ done
The two cards of §6, in the workbench, scroll-paned like Topology — preceded by
the reflective bounded shadow of §4a, without which there is nothing to render.
*Verify: opening on a 57-node routing instance is bounded; drilling to a
per-node queue works; the per-slice sync cost does not grow with model size —
measured, not assumed.*

In omnetpp-julia: `watch/SimulationInspectorToWidget.jl`, the standalone
`watch/inspector.jl` / `inspector_sdl.jl`, and two cards spliced into the
workbench — **Instance details** beside Topology (an instance-stage view: no
engine, nothing run) and **Execution details** after Control. `SimulationWorkbench`
grew `instance_shadow` / `execution_shadow`, refreshed in `workbench_refresh!`.

**The measurements, which are the actual result:**

| | |
|---|---|
| per-slice sync, 334-module RoutingModel engine, one level open | **1 536 B** |
| per-slice sync, 7-module ChainModel, same | **1 536 B** — identical |
| refreshing both workbench cards on a finished run | **2.7 KB** |
| collapsed 1 000 000-element field vs 1 000-element | same (~74 KB) |

So the criterion is met literally: cost is flat in model size and tracks the rows
on screen. The honest test §6 set — "if the inspector still needs a hand-written
view to be usable, the answer is no" — passes: the Execution details card shows
the engine itself, and `SimulationExecutionView` survives only because the
Control card wants four specific scalars in a status line, not because the engine
is unaffordable to show.

Two things worth keeping:

- **Rendering caught what assertions could not**, again. A `+`/`-` icon column
  beside the chevron read as noise; document labels printed their cell-kind type
  parameters (`SimulationRun{Cell, Cell, Cell, Cell, Cell}`); and both cards
  reserved ~70 px of dead space. None of these is a test failure.
- The scroll pane's recursion had to become a **dispatch**, since a pane in the
  workbench can now hold either a topology graph or a reflected shadow.

### Phase 6 — docs + close-out ✅ done
`package/base/doc/bounded-sync.md` (the guide), a pointer from
`package/kernel/doc/document.md`'s sync section, and index entries in
`documentation/README.md` and `CLAUDE.md`.

### Phase 6 — docs + close-out
Document bounded sync in `package/base/doc/`, note it in the sync guide, and
record what the build changed about this design.
