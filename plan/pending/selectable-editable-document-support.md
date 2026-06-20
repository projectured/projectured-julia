# Selectable / editable document support

> **Status: design only.** Captures a general mechanism for gating *selection*
> and *content editing* per node/subtree, independent of any one domain. No code
> yet. Adjacent prior art: [master-detail-editable.md](master-detail-editable.md)
> proposes an `editable` predicate, but scoped only to the master/detail surface;
> this plan generalises the idea into a reusable, two-flag, reader-side gate.

## Motivation

Today selectability and editability are **emergent, not declared**. A node is
selectable iff some projection's reader + `map_reference_forward`/`backward`
accept a selection at it; it is editable iff a reader turns a content gesture
into a mutating operation. There is no stored flag and no way to say "this
subtree is selectable but read-only" without rewriting the producing projection.

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

## Operation taxonomy → flag

The backward path produces a small set of operation classes. They partition
cleanly across the two flags:

| Operation (produced by a reader) | Class | Gated by |
|---|---|---|
| `ReplaceSelectionOperation` | move caret / select range | `selectable` |
| `StringReplaceRangeOperation`, `NumberReplaceRangeOperation` | mutate content (typing, backspace, **paste**) | `editable` |
| clipboard *copy* (reads the current selection, no mutation), `ToggleCollapseOperation`, other view-only ops | read-only / view | neither — always allowed |

Copy/paste asymmetry falls out for free: copy is a clipboard read of the current
selection (no mutating op — see `ClipboardToAnyProjection`, copy reads selection);
paste emits a `StringReplaceRangeOperation`. Under `editable=false`, copy passes
the gate and paste is dropped — no special-casing.

The classifier should be a single predicate over `change.operation` so both
routes below share it:

```julia
is_selection_op(op) = op isa ReplaceSelectionOperation
is_content_op(op)   = op isa StringReplaceRangeOperation || op isa NumberReplaceRangeOperation
# everything else: read-only / view → always allowed
```

(Defaults handled by the generic reader live in
[common/Projection.jl:83-90](../../program/src/common/Projection.jl#L83-L90),
which is the precedent for matching on these exact operation types.)

## Two routes (choose during interview — likely both, layered)

### Route A — node cells, consulted by the producing reader (Model 1)

Give the document/widget node `selectable::Cell{Bool}` and `editable::Cell{Bool}`
(exactly like `visible`). In that domain's `projection_read`, before returning
the op, consume disallowed classes with the existing "no-op" idiom
(`return Change(gesture, nothing)`, as `ProjectionConfiguring` already does):

```julia
is_selection_op(op) && node.selectable[] == false && return Change(g, nothing)
is_content_op(op)   && node.editable[]   == false && return Change(g, nothing)
```

This is the route where **the projection that builds the node declares** its
selectability/editability, and where a later edit can flip the cell **in place**
(it's a real `Cell`, like `visible`). Cost: each domain that wants the flags must
add the cells and the two guard lines.

### Route B — a higher-order `GatingProjection` decorator (Model 2)

A transparent decorator, in the family of `DraggingProjection` /
`TooltipDecoratorProjection` / `ProjectionConfiguringProjection`:

- **printer**: passthrough — returns the inner projection's output unchanged, so
  the projected state (layout, caret, collapse) is fully preserved;
- **reader**: classify `change.operation`; drop the disallowed classes; delegate
  the rest to the inner reader.

```julia
GatingProjection(inner; selectable=true, editable=true)
```

Scope it to a subtree with
`ApplyAtProjection(@reference(...), GatingProjection(inner; editable=false))`
(see [higher-order-projections.md](../../guide/higher-order-projections.md#compound-combinators)).
This is the "another projection flips something later without re-projecting"
model, and it needs **zero changes to the inner domain** — all enforcement is in
the decorator's reader.

**Recommendation:** ship Route B first (domain-agnostic, minimal, and the cleanest
test of the operation-class filter), then add Route A cells to the specific
domains (starting with `TextText`) that want author-declared, in-place-flippable
flags.

## Orthogonality

Keep the two flags independent (the `TextText` case needs `selectable=true,
editable=false`). But note and document the implication: `selectable=false` means
edits have no caret to target, so in practice `!selectable ⇒ effectively
!editable` regardless of the editable flag. `selectable` is the stronger gate.

## Critical files

**New**
- `program/src/projection/higherorder/Gating.jl` — `GatingProjection` +
  `GatingProjectionIoMap`, passthrough printer, classifying reader, passthrough
  reference mapping (mirror `Dragging.jl`'s transparent-decorator shape).

**Edit (Route A, per adopting domain — start with TextText)**
- `program/src/document/Primitive.jl` (or wherever `TextText` lives) — add
  `selectable` / `editable` cells with `=true` defaults.
- that domain's reader — the two guard lines above.

**Reference / reuse**
- [ProjectionConfiguring.jl](../../program/src/projection/higherorder/ProjectionConfiguring.jl)
  — the `return Change(gesture, nothing)` consume idiom and decorator structure.
- [Dragging.jl](../../program/src/projection/higherorder/Dragging.jl) — transparent
  passthrough-printer decorator precedent.
- [common/Projection.jl](../../program/src/common/Projection.jl#L83-L90) — default
  reader matching `ReplaceSelectionOperation` / `*ReplaceRangeOperation`.
- `ApplyAtProjection` (compound/HigherOrder.jl) — scoping a decorator to a subtree.

## Verification (when implemented)

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
4. **Route A in-place flip** — toggle the `editable` cell at runtime and confirm
   editing turns on/off without re-projection (parallel to `visible` flip).
5. **Scoped gating** — `ApplyAtProjection(ref, GatingProjection(...; editable=false))`
   makes exactly the target subtree read-only while siblings stay editable.

## Open decisions (interview before implementing)

1. **Route B only, or A + B?** (Recommendation: both, layered as above.)
2. **Default values** — `selectable`/`editable` default `true` everywhere
   (opt-out), confirmed.
3. **Granularity of `editable`** — does it also gate structural edits
   (insert/delete of children, `MoveRangeOperation`) or only in-node content
   replacement? Decide which operation classes count as "content" beyond the
   `*ReplaceRangeOperation` pair.
4. **Inheritance** — does gating a node implicitly gate its descendants, or is it
   strictly per-node? (Route B + `ApplyAtProjection` gives subtree scoping; Route
   A is per-node unless descendants also carry cells.)
5. **Interaction with master-detail's `editable` predicate** — fold that plan's
   predicate into this mechanism (the predicate selects which detail subtree gets
   wrapped in a `GatingProjection`) rather than implementing it separately.
