# MasterDetail: editable detail (edits in the detail flow back into the master)

> **⛔ OBSOLETE (2026-06-23):** This design direction is dead. It is a follow-up
> to `master-detail-document.md` (v1), which was itself ruled obsolete — the
> master/detail feature took the `ComponentMasterDetail` route instead (see
> `package/domain/src/document/Component.jl` and `plan/pending/component-document.md`).
> The `MasterDetail*`-typed architecture this plan extends (the `detail_target`
> resolver, `MasterDetailToWidget` projection, dual-key detail cache) is not being
> pursued, so the editable-detail upgrade described here no longer applies. Moved
> to `plan/obsolete/`.

> **Status: future plan, design only.** Follow-up to
> [master-detail-document.md](master-detail-document.md), which delivers a v1
> **read-only** detail. Do that one first. This plan upgrades the detail from an
> inspection view to an editable one whose edits propagate into the master
> document.
>
> **⏳ AUDIT (verified 2026-06-23): ALL STEPS OPEN.** The v1 prerequisite plan
> `master-detail-document.md` is itself still in `plan/pending/` (not done), and
> no MasterDetail document or projection exists in the codebase: there is no
> `MasterDetail.jl` document, no `MasterDetailToWidget.jl` projection, and no
> `detail_target`/`editable` predicate anywhere under `package/*/src/` (grep for
> `MasterDetail`/`detail_target` finds only these plan files plus the unrelated
> `package/domain/src/document/Component.jl`). The generic infrastructure this
> plan *cites* does exist — `FocusingProjection`, `map_reference_backward`,
> `_concat_path`/`_strip_prefix`, `ReplaceFocusPartOperation` live in
> `package/kernel/src/projection/generic/Focusing.jl` (lines 33-125) — but those
> predate this plan and are reference material, not deliverables. Nothing in this
> plan has been built. Old `program/src/...` paths below map to
> `package/kernel/src/projection/generic/Focusing.jl`.

## Context

In v1 the detail is a *separately-projected, read-only inspection* of the
master's selected item (Resolved decision 2 of the base plan). The detail document
is its own object; edits to it (if any) stay local and are never written back to
the master. That is correct for "inspect the selected item" but limits the
master/detail surface to navigation.

Goal of this plan: make the detail **editable**, so that typing/structural edits
in the right pane mutate the corresponding node in the master document, and the
master pane (left) re-renders to reflect the change — a single source of truth,
two live views.

## The core change: detail = a *view of* the master node, not a *copy*

v1 caches a projected copy. Editable detail instead makes the detail document the
**same node object** the master selection points at (a focus view), so there is
nothing to "write back" — both panes project the same live object and edits land
once.

Two viable mechanisms, to choose between during the interview:

1. **`FocusingProjection` detail.** Render the detail pane as
   `FocusingProjection(part = master_selection_subpath)` over the master, then the
   usual `…→syntax→text→graphics` chain. `FocusingProjection` already provides the
   bidirectional `map_reference_forward`/`map_reference_backward`
   ([Focusing.jl:46-52](../../program/src/projection/generic/Focusing.jl#L46-L52))
   that translate detail-pane edits into paths rooted at the master node, and
   `ReplaceFocusPartOperation` to retarget the focus when the selection moves
   ([Focusing.jl:61-69](../../program/src/projection/generic/Focusing.jl#L61-L69)).
   This is the most idiomatic route — the detail *is* a focus of the master.

2. **Shared-node detail (no copy).** The detail thunk returns the master node
   object itself (not a projected copy); the cache memoises only *projection-side*
   state. Edits mutate the shared node directly. Simpler conceptually but the
   selection re-rooting for the right pane must be written by hand (the base plan's
   `elements[2].child.content.rest…` mapping must continue into the master's own
   reference space rather than a standalone detail space).

Either way the **read path is unchanged** from v1; only the detail document's
identity and the **write/selection re-rooting** change.

## What this plan must add on top of v1

1. **⏳ OPEN.** **Detail-as-focus-of-master.** Replace the v1 read-only projected copy with one
   of the two mechanisms above. The `detail_target` resolver already yields the
   item node and its `ReferencePath`; feed that path into the focus.
   *(Verified OPEN: no MasterDetail projection and no `detail_target` resolver exist; v1 not done.)*

2. **⏳ OPEN.** **Selection/operation re-rooting into the master.** The right pane's
   `map_reference_backward` must produce a path **into the master subtree**
   (`master.<item-path>.<edit-suffix>`), not into a detached detail document, so
   `evaluate_operation` applies edits to the real node. Extend the base plan's
   slot-2 mapping accordingly; reuse `FocusingProjection._concat_path` /
   `_strip_prefix` if going the focus route.

3. **⏳ OPEN.** **Cache semantics under edits.** Edits change the master node, which interacts
   with the dual-key cache (Resolved decision 1 of the base plan):
   - **id-preserving edits** (mutate a field of the existing node) keep the
     `by_id` hit valid — cache entry stays correct.
   - **id-replacing edits** (swap the node for a new object, e.g. a structural
     replace) lose the `by_id` key; the `by_path` fallback must recover the entry
     and re-key it (already specified in the base plan — this plan just exercises
     it under real edits and adds the re-validation guard).

4. **⏳ OPEN.** **Master re-render on detail edit.** Because both panes read the same node
   through reactive cells, a detail edit should invalidate the master pane's cells
   too. Verify the master tree actually re-renders (it should, via the shared
   node's cells) and that the cached detail state (sub-selection, collapse) is not
   clobbered by the re-render.

5. **⏳ OPEN.** **Editability scoping.** Not every detail target is sensibly editable (e.g. a
   read-only DB catalog level vs an editable JSON value). Add an `editable`
   predicate (parallel to `detail_target`) so a master can declare which items get
   an editable detail and which stay inspection-only. DB catalog example: keep
   read-only (the catalog reflects live DB state); JSON/file-content example: make
   editable.

## Critical files (relative to v1)

**Edit**
- `program/src/projection/primitive/MasterDetailToWidget.jl` — detail becomes a
  focus/shared-node view; extend slot-2 backward mapping into the master space;
  add the `editable` predicate.
- `program/src/document/MasterDetail.jl` — if the focus route needs a stored
  `FocusingProjection` or focus path, add it; otherwise unchanged.

**Reference / reuse**
- [Focusing.jl](../../program/src/projection/generic/Focusing.jl) — focus view,
  bidirectional mapping, `ReplaceFocusPartOperation`.
- The base plan's selection-mapping section.

## Verification (when implemented)

1. **Edit propagates** — edit a value in the detail pane; confirm the master pane
   shows the change and `evaluate_reference(master, item_path)` reflects it.
2. **Single source of truth** — confirm no divergence: there is no stale copy; the
   same node backs both panes.
3. **Selection round-trip under edit** — a caret/replace op in the detail re-roots
   to a `master.<…>` path that `evaluate_operation` applies (Descriptor panel
   shows a path into the master).
4. **Cache under id-replacing edit** — perform a structural replace; confirm the
   `by_path` fallback recovers and re-keys the detail entry (no lost state, no
   stale entry surviving).
5. **Editability scoping** — confirm a read-only target (catalog level) rejects
   edits while an editable target (JSON value) accepts them.

## Open decisions (interview before implementing)

1. **Focus route vs shared-node route** (mechanisms 1 vs 2 above).
2. **Undo/transaction granularity** — does a detail edit participate in the same
   operation/undo stream as master edits? (Assume yes — it is an ordinary
   `Operation` on the master — but confirm.)
3. **What "editable" means per domain** — the predicate's default and per-example
   overrides.
