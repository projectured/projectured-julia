# Bounded document sync — drill-down by demand, not by depth

**Status:** design proposal, staged build (§7). Not started.
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

**But** it needs an expansion affordance it does not have today. Two ways:

- **(a)** Give `ObjectToWidget` a chevron per composite value that toggles the
  marker's `requested` — small, and the marker is already in the shadow.
- **(b)** Use `WidgetTree` for the skeleton and `ObjectToWidget` for a selected
  node's detail — a two-pane inspector. More UI, but each widget does what it is
  good at.

Decide after §7 Phase 3, when there is something to look at. `WidgetTree` alone
remains the fallback if `ObjectToWidget`'s density turns out to be unworkable.

---

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

### Phase 1 — the marker + bounded sync
`UnsyncedDocument`, `SyncPolicy`, `DepthPolicy`, and
`sync_document!(shadow, source, policy)` in a new unsealed file. No consumer yet.
*Verify: a depth-bounded sync of a deep nested document produces markers at the
bound and leaves ancestors identical to an unbounded sync; an unbounded policy
reproduces today's result exactly.*

### Phase 2 — requests
`requested` honoured: flagging a marker fills that node one level on the next
sync, writing fresh markers below. Collapsing restores a marker.
*Verify: expand/collapse cycles converge — the shadow after expand-then-collapse
equals the shadow before; repeated expansion walks down a chain one level per
sync.*

### Phase 3 — collection cap
Large collections sync a prefix and mark the tail. This is what makes a 1345-
element engine array survivable.
*Verify: a 10 000-element vector syncs in bounded time; the marker reports the
remaining count.*

### Phase 4 — rendering
Whichever of §4 wins. A marker renders as a collapsed node with a chevron whose
toggle writes `requested`.
*Verify: a headless test drives expand → sync → deeper node appears.*

### Phase 5 — the omnetpp inspector
The two cards of §6, in the workbench, scroll-paned like Topology.
*Verify: opening on a 57-node routing instance is bounded; drilling to a
per-node queue works; the per-slice sync cost does not grow with model size —
measured, not assumed.*

### Phase 6 — docs + close-out
Document bounded sync in `package/base/doc/`, note it in the sync guide, and
record what the build changed about this design.
