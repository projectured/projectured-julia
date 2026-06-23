# Selectable / editable document support

> **⏳ AUDIT 2026-06-23 — ALL OPEN (verified design-only).** No part of this plan
> is implemented. `GatingProjection`, `ReadOnlyProjection`, `InertProjection`,
> `deny_selection`, `deny_content` appear *only* in this plan file (grep across
> `package/` returns no source hits); no `package/**/Gating.jl` exists. Route A's
> node flags are absent too: `TextText` (`package/domain/src/document/Text.jl:233`)
> has only `elements`/`selection` fields — no `selectable::Cell`/`editable::Cell`.
> The "editable" matches in `package/kernel/src/document/Primitive.jl` are the
> English word in comments, not fields. The plan remains correctly OPEN.
> Path note: old `program/src/...` references map to `package/<subpkg>/src/...`
> (e.g. `program/src/projection/higherorder/` → `package/domain/src/projection/higherorder/`,
> `program/src/document/Widget.jl` → `package/domain/src/document/Widget.jl`).

> **Status: design only.** Captures a general mechanism for gating *selection*
> and *content editing* — and, by the same mechanism, **any future behavioural
> concept** — per node/subtree, independent of any one domain. No code yet.
> Adjacent prior art: [master-detail-editable.md](master-detail-editable.md)
> proposes an `editable` predicate, but scoped only to the master/detail surface;
> this plan generalises the idea into a reusable, reader-side **policy** gate.

## Design constraint: don't re-touch the world per concept

`selectable` and `editable` are only the first two of an open-ended family of
behavioural concepts (`draggable`, `collapsible`, `copyable`, `focusable`,
`deletable`, …). The mechanism **must not require editing every domain — or even
one shared switch statement — each time a new concept arises.** That rules out
"add another boolean field + another guard line everywhere" as the primary
design.

The way out: notice that *every* such concept is the same shape — **a filter on
the backward operation stream, keyed by the class of operation a reader
produces.** So the primitive is not "a `selectable` flag" but **a policy: a
function `operation -> allow?`**. A new concept is then a new policy value, not
new code threaded through the domains. `selectable`/`editable` ship as two
predefined policies; everything else composes from the same primitive. This is
the load-bearing decision of the plan — see *Route B*.

## Motivation

Today selectability and editability are **emergent, not declared**. A node is
selectable exactly when (and only when) some projection's reader +
`map_reference_forward`/`backward` accept a selection at it; it is editable
exactly when a reader turns a content gesture into a mutating operation. There is
no stored flag and no way to say "this subtree is selectable but read-only"
without rewriting the producing projection.

We want a `visible`-shaped capability — a property that can be set by the
projection that builds a node (Model 1) **or** flipped later by another
projection that preserves the projected output and just changes behaviour
(Model 2) — for two independent concerns:

- **selectable** — may a gesture place/move a caret or select a range here?
- **editable** — may a gesture mutate this node's content here?

Worked target (the hard case that proves the design): a `TextText` that is
**selectable but not editable** — put a caret anywhere, select a part / word /
all, **copy**, but **never paste or insert** characters.

## Key insight: this is a *reader-side* gate, not a printer flag

`visible` is **printer-side**: it changes what renders, via a `Cell{Bool}` and
`ShowWidgetOperation`/`HideWidgetOperation`
([Widget.jl:1104-1206](../../program/src/document/Widget.jl#L1104-L1206)).

Selectable/editable are **reader-side**: they gate which gestures get turned into
which operations on the backward path. So although the *flag* can look like
`visible` (a flippable `Cell{Bool}`), the *enforcement* lives in
`projection_read`, by inspecting the operation a reader produces.

Crucially: **gate on the operation a reader produces, not on the raw gesture.**
The same click becomes a `ReplaceSelectionOperation` in a text body but a
`ToggleClipboardSliceDisplayOperation` on a clipboard chip. "Catch mouse clicks"
is the wrong predicate; "this gesture resolved to a selection-change op" is the
right one.

## Operation taxonomy → policy

The backward path produces a small set of operation classes. A **policy** is just
a predicate over the operation a reader produced; `selectable`/`editable` are two
predefined policies, and any future concept is another:

| Operation (produced by a reader) | Class | Denied by policy |
|---|---|---|
| `ReplaceSelectionOperation` | move caret / select range | `deny_selection` (≙ `selectable=false`) |
| `StringReplaceRangeOperation`, `NumberReplaceRangeOperation` | mutate content (typing, backspace, **paste**) | `deny_content` (≙ `editable=false`) |
| clipboard *copy* (reads the current selection, no mutation), `ToggleCollapseOperation`, other view-only ops | read-only / view | — (always allowed) |

Copy/paste asymmetry falls out for free: copy is a clipboard read of the current
selection (no mutating op — see `ClipboardToAnyProjection`, copy reads selection);
paste emits a `StringReplaceRangeOperation`. Under `deny_content`, copy passes the
gate and paste is dropped — no special-casing.

Policies are plain predicates, so the two shipped ones and any later one are
values, not new code paths:

```julia
const allow_all   = op -> true
deny_selection(op) = !(op isa ReplaceSelectionOperation)
deny_content(op)   = !(op isa StringReplaceRangeOperation || op isa NumberReplaceRangeOperation)
# selectable=false → deny_selection;  editable=false → deny_content
# a future concept (e.g. "not deletable") is just another predicate — no domain edits.
# compose: all_of(deny_selection, deny_content), any_of(...), etc.
```

(Defaults handled by the generic reader live in
[common/Projection.jl:83-90](../../program/src/common/Projection.jl#L83-L90),
which is the precedent for matching on these exact operation types.)

## Two routes

### Route A — node cells, consulted by the producing reader (Model 1)

Give the document/widget node `selectable::Cell{Bool}` and `editable::Cell{Bool}`
(exactly like `visible`). In that domain's `projection_read`, before returning
the op, consume disallowed classes with the existing "no-op" idiom
(`return Change(gesture, nothing)`, as `ProjectionConfiguring` already does):

```julia
node.selectable[] == false && op isa ReplaceSelectionOperation && return Change(g, nothing)
node.editable[]   == false && is_content_op(op)                && return Change(g, nothing)
```

The projection that builds the node **declares** its selectability/editability,
and a later edit can flip the cell **in place** (it's a real `Cell`, like
`visible`).

**Pros**
- Author-declared at the source; the flag travels *with* the node.
- In-place runtime flip (toggle the `Cell`, no re-projection), exactly like `visible`.
- No reference-scoping needed — the gate is wherever the node is.

**Cons**
- **Violates the design constraint above:** every new concept = a new field + a
  new guard line **in every domain that wants it**. Selectable/editable alone
  means editing `Primitive.jl`, `Widget.jl`, `Syntax.jl`, … and each future
  concept re-touches them all. This is precisely the "again-and-again" cost.
- Couples domain documents to behavioural policy (a layering smell — the domain
  shouldn't know about caret/edit gating).
- Easy to forget a guard in one reader → silent leak of a denied operation.

### Route B — a policy-driven `GatingProjection` decorator (Model 2) ✅ recommended

A transparent decorator, in the family of `DraggingProjection` /
`TooltipDecoratorProjection` / `ProjectionConfiguringProjection`, parameterised by
a **policy** (not by named booleans):

- **printer**: passthrough — returns the inner projection's output unchanged, so
  the projected state (layout, caret, collapse) is fully preserved;
- **reader**: run `policy(change.operation)`; if denied, consume with
  `Change(gesture, nothing)`; otherwise delegate to the inner reader.

```julia
GatingProjection(inner; policy = allow_all)
# convenience constructors map the two shipped concepts onto policies:
ReadOnlyProjection(inner)   = GatingProjection(inner; policy = deny_content)    # selectable, not editable
InertProjection(inner)      = GatingProjection(inner; policy = all_of(deny_selection, deny_content))
```

Scope it to a subtree with
`ApplyAtProjection(@reference(...), ReadOnlyProjection(inner))`
(see [higher-order-projections.md](../../guide/higher-order-projections.md#compound-combinators)).

**Pros**
- **Satisfies the design constraint:** a new behavioural concept is a new *policy
  value* (one predicate), composed via `all_of`/`any_of` — **zero domain edits,
  no growing switch.** One mechanism covers selectable, editable, and everything
  after them.
- **Zero changes to the inner domain** — all enforcement is in one reader.
- Composable and scopable (`ApplyAtProjection`, `SequentialProjection`); stackable
  policies layer naturally.
- Clean layering — behavioural policy lives in the projection layer where the rest
  of the interaction logic already lives.

**Cons**
- Behaviour lives *outside* the node, so you must place/scope the decorator
  (via reference) rather than reading a flag off the node — slightly more wiring
  at the call site.
- "Flip at runtime" means swapping/retargeting the policy (e.g. via an
  `AlternativeProjection` index or a policy `Cell`), not toggling a bool on the
  node — a little less direct than Route A's in-place cell.
- A purely backward-path gate doesn't change the *rendered* affordance (e.g. greying
  out a read-only field); if visual cues are wanted they need a separate printer
  signal.

**Recommendation:** **Route B is the primary mechanism** — it is the only one that
honours "don't re-touch the world per concept." Ship `GatingProjection` + the
`deny_selection`/`deny_content` policies + the `ReadOnly`/`Inert` conveniences
first. Reserve Route A as an *opt-in escape hatch* for the rare node that genuinely
needs the flag to travel with it and flip in place (and even then, the reader can
delegate to the same shared policy predicates so there is one source of truth).

## Orthogonality

Keep the two flags independent (the `TextText` case needs `selectable=true,
editable=false`). But note and document the implication: `selectable=false` means
edits have no caret to target, so in practice `!selectable ⇒ effectively
!editable` regardless of the editable flag. `selectable` is the stronger gate.

## Critical files

**New (Route B — the primary mechanism)**
- **⏳ OPEN (verified absent):** no `Gating.jl` exists under `package/` and no
  `GatingProjection`/policy symbols are defined anywhere. Target path today would
  be `package/domain/src/projection/higherorder/Gating.jl` (sibling of the existing
  `Dragging.jl`/`ProjectionConfiguring.jl` there).
- `program/src/projection/higherorder/Gating.jl` — `GatingProjection` +
  `GatingProjectionIoMap`, passthrough printer, policy-applying reader, passthrough
  reference mapping (mirror `Dragging.jl`'s transparent-decorator shape); the
  `deny_selection` / `deny_content` / `all_of` / `any_of` policy predicates and the
  `ReadOnlyProjection` / `InertProjection` convenience constructors.

**Edit (Route A — only if/when a node needs an in-place flag; opt-in, start with TextText)**
- **⏳ OPEN (verified absent):** `TextText` lives at
  `package/domain/src/document/Text.jl:233` (not `Primitive.jl`) and currently has
  only `elements::CollectionDocument` and `selection::Reference` — no
  `selectable`/`editable` cells. No reader guard lines exist.
- `program/src/document/Primitive.jl` (or wherever `TextText` lives) — add
  `selectable` / `editable` cells with `=true` defaults.
- that domain's reader — guard lines delegating to the **same** shared policy
  predicates (one source of truth).

**Reference / reuse**
- [ProjectionConfiguring.jl](../../program/src/projection/higherorder/ProjectionConfiguring.jl)
  — the `return Change(gesture, nothing)` consume idiom and decorator structure.
- [Dragging.jl](../../program/src/projection/higherorder/Dragging.jl) — transparent
  passthrough-printer decorator precedent.
- [common/Projection.jl](../../program/src/common/Projection.jl#L83-L90) — default
  reader matching `ReplaceSelectionOperation` / `*ReplaceRangeOperation`.
- `ApplyAtProjection` (compound/HigherOrder.jl) — scoping a decorator to a subtree.

## Verification (when implemented)

> **⏳ OPEN — none of the verification scenarios below are exercisable yet**, since
> the mechanism (Route B `GatingProjection` + policies, optional Route A flags) is
> unimplemented. Listed for when the work lands.

1. **TextText selectable & not editable** (the headline case):
   - click / drag / word-select / select-all → caret and ranges set (selection
     ops pass);
   - `Ctrl+C` → copy works (read-only, passes);
   - typing a char / backspace / `Ctrl+V` → no change (content ops dropped);
   - the text still renders identically and the caret still shows (printer
     untouched).
2. **Not selectable** → a click produces no selection change (selection op
   dropped); confirm no caret appears and content gestures are inert too.
3. **Route B preserves state** — wrapping an already-projected subtree in
   `GatingProjection` changes no output; only the backward flow is filtered.
4. **New concept = no domain edits** — add a third policy (e.g. `deny_delete`) and
   gate a subtree with it **without touching any document/domain file** — proves
   the design constraint is met.
5. **Scoped gating** — `ApplyAtProjection(ref, ReadOnlyProjection(inner))`
   makes exactly the target subtree read-only while siblings stay editable.
6. **(Route A, if built) in-place flip** — toggle the `editable` cell at runtime and
   confirm editing turns on/off without re-projection (parallel to `visible` flip).

## Open decisions (interview before implementing)

1. **Route B alone, or also Route A?** (Recommendation: B is primary; A only as an
   opt-in escape hatch for nodes that need an in-place flag.)
2. **Default policy** — `allow_all` everywhere (opt-out), confirmed.
3. **Granularity of `deny_content`** — does it also gate structural edits
   (insert/delete of children, `MoveRangeOperation`) or only in-node content
   replacement? Decide which operation classes count as "content" beyond the
   `*ReplaceRangeOperation` pair — and whether structural edits deserve their own
   policy (`deny_structure`) so the two stay independently composable.
4. **Inheritance** — does gating a node implicitly gate its descendants, or is it
   strictly per-node? (Route B + `ApplyAtProjection` gives subtree scoping; Route
   A is per-node unless descendants also carry cells.)
5. **Interaction with master-detail's `editable` predicate** — fold that plan's
   predicate into this mechanism (the predicate selects which detail subtree gets
   wrapped in a `GatingProjection`) rather than implementing it separately.
