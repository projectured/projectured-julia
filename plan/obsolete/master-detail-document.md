# MasterDetail: a generic master/detail document with a selection-driven, lazily-populated detail pane

> **Status: design only. No implementation in this plan.** This is a blueprint to
> review and refine before any code is written. The "Open decisions" section at the
> end lists the choices that should be settled first.

> **⛔ OBSOLETE (verified 2026-06-23): this specific design was NOT taken; the
> master/detail feature was instead realized via the Component layer.** None of
> this plan's named artifacts exist anywhere under `package/` — grep for
> `MasterDetailMasterDetail`, `MasterDetailToWidget`, `MasterDetailModule`,
> `MasterDetailDocument`, `DetailCache`, `DetailEntry`, `master_detail_example`,
> `master_projection`, `detail_projection`, `detail_target` returns matches only in
> this file and the follow-up `master-detail-editable.md`. Instead, a different
> master/detail design was implemented: `ComponentMasterDetail`
> (`package/domain/src/document/Component.jl:62`, in `ComponentModule`), a simpler
> document with fields `master` / `detail` / `selected_item` / `master_title` /
> `detail_title` / `split_ratio` / `selection` — it has **no** `DetailCache`
> (dual `by_id`/`by_path` memo), **no** `orientation` field, **no** `detail_target`
> resolver, and **no** split into separate `master_projection`/`detail_projection`
> configs. The ongoing master/detail work is tracked under
> [component-document.md](component-document.md) (document DONE; `ComponentToWidget`
> projection and examples still OPEN there). This plan's standalone
> `MasterDetail*`-typed architecture and its four NEW files are therefore
> superseded and will not be built as written.

## Goal

A generic, reusable UI behaviour with **two coupled presentations**:

- a **master** on the left — a navigable document (e.g. a `DbCatalogRdbms`
  database catalog, or a `Workspace`/file-system tree), and
- a **detail** on the right — whatever the master's *current selection* points
  at, rendered through a **generic default projection** (typically
  `something → syntax → text → graphics`).

When the master selection changes, the detail **follows** it. The detail is
populated **lazily** (nothing is built for an item until it is first selected),
and once an item has been visited its detail **state is memorised** so that
re-selecting it later restores what the user had (sub-selection, collapse/expand,
scroll), rather than rebuilding from scratch.

v1 layout: a simple horizontal split — master left, detail right.

## Precedents this builds on (read these first)

| Mechanism | Where it already exists | What we reuse |
|---|---|---|
| Two-pane split with weighted layout | `WorkbenchAssistantToWidgetSplitPane` — `WidgetSplitPane(:vertical, [conv, input])` with `LayoutConstraint`s ([WorkbenchToWidget.jl:312-338](../../program/src/projection/primitive/WorkbenchToWidget.jl#L312-L338)) | The split-pane build + min/weight tokens; ours is `:horizontal` |
| Selection routing through a split pane | `map_reference_forward`/`map_reference_backward` for the assistant (`elements[i].child.content.rest…`) ([WorkbenchToWidget.jl:449-454](../../program/src/projection/primitive/WorkbenchToWidget.jl#L449-L454), [:525-544](../../program/src/projection/primitive/WorkbenchToWidget.jl#L525-L544)) | The exact forward/backward shape for the two slots |
| "Follow a selection / focus a sub-document" | `FocusingProjection` — navigates into a document along a `ReferencePath`, and recomputes the longest selection-prefix of a given type ([Focusing.jl](../../program/src/projection/generic/Focusing.jl), esp. `_longest_prefix_of_type` :120) | The detail-target resolution logic |
| A "generic default projection" (`X → syntax → text → graphics`) | `combined_w2g` in the workbench example — a `TypeDispatchingProjection` mapping each domain to its `…ToSyntax → SyntaxToText → TextToGraphics` chain ([example/src/projection/Workbench.jl:19-46](../../example/src/projection/Workbench.jl#L19-L46)) | The detail projection is exactly this kind of per-domain dispatch |
| Recursing a child document through the surrounding widget chain | `_recurse` + `WidgetScrollPane(content)` letting the outer `TypeDispatchingProjection` route by type ([WorkbenchToWidget.jl:137-138](../../program/src/projection/primitive/WorkbenchToWidget.jl#L137-L138), [:321-328](../../program/src/projection/primitive/WorkbenchToWidget.jl#L321-L328)) | How both panes get projected without MasterDetail knowing the domain |
| Reader routing / re-rooting per slot | `projection_read` + `_retarget_panel_op`/`map_reference_backward` ([WorkbenchToWidget.jl:747-783](../../program/src/projection/primitive/WorkbenchToWidget.jl#L747-L783)) | Translating widget-domain ops back into master/detail domain |

The whole `WorkbenchAssistant` work ([plan/done/workbench-assistant.md](../done/workbench-assistant.md))
is the closest structural analogue: a workbench panel that is itself a split of
two independently-projected sub-documents with full bidirectional selection.

## Architecture

```
┌── MasterDetailMasterDetail ────────────────────────────────────────────┐
│  master      : Document        (e.g. DbCatalogRdbms, Workspace)        │
│  details     : DetailCache      memo: {by_id, by_path} → DetailEntry    │
│  orientation : Symbol          (:horizontal for v1)                     │
│  selection   : Reference                                                │
└───────────────┬────────────────────────────────────────────────────────┘
                │ MasterDetailToWidget(master_projection, detail_projection, detail_target)
                ▼
        WidgetSplitPane(:horizontal,
          [ LayoutConstraint(master_pane, min_width=…, weight=…),
            LayoutConstraint(detail_pane, weight=main) ])

   master_pane = master  ─[ master_projection ]─►   ONE fixed pipeline
   detail_pane = detail_doc ─[ detail_projection ]─► MANY pipelines,
                                  type-dispatched on the content document type
                              ▲
                              │  detail_doc is resolved reactively:
                              │   1. read master selection (the subpath inside master)
                              │   2. detail_target(master, sel) → the "selected item" node
                              │      (longest selection-prefix that is a selectable item)
                              │   3. memo lookup details[key(item)]; if absent, build the
                              │      detail document for `item` and store it (lazy + memo)
                              └────────────────────────────────────────────────────────
```

### How the detail "follows" the master selection (reactive, not stored)

The detail content is **derived**, never a fixed field. The `detail_pane`'s
content is a `Cell` thunk that:

1. reads the master's current selection (the portion of `MasterDetail.selection`
   that descends into `master`);
2. resolves the **selected item** — the longest prefix of that selection whose
   target node is a "selectable item" for this master (a catalog level, a file
   entry, …). This is the same idea as `FocusingProjection._longest_prefix_of_type`
   ([Focusing.jl:120](../../program/src/projection/generic/Focusing.jl#L120)); the
   item-type predicate is a parameter of the projection so the same MasterDetail
   works for any master domain;
3. returns the **memoised detail document** for that item (see next section).

Because step 1 reads a `Cell`, the detail pane re-renders automatically when the
master selection changes — the standard pull-based reactive behaviour
([guide/reactive-cells.md](../../guide/reactive-cells.md)). No imperative "on
selection changed" callback is needed.

### Lazy population + memoised detail state

`details` is a per-item cache living **on the document** (not on the projection),
so it survives projection rebuilds. It is a small struct holding **two indices
into the same `DetailEntry`** — an identity map and a path map (see Resolved
decision 1):

- **Dual key** — `by_id::IdDict{Any,DetailEntry}` keyed on the item node's object
  identity (authoritative, fast), and `by_path::Dict{ReferencePath,DetailEntry}`
  keyed on the item's `ReferencePath` (recovery index). Lookup tries id first;
  on a miss falls back to path (re-validating the node still satisfies
  `detail_target`), then re-keys the entry under the new identity so identity
  heals forward.
- **Value (`DetailEntry`)** = the **detail document** the generic projection
  consumes — a separately-projected, read-only inspection of the item (v1).
  It carries the detail's own mutable state (its `selection`, syntax collapse
  flags, …) so reselecting restores it.
- **Lazy**: both maps start empty. The detail thunk does the dual-key lookup and,
  on a full miss, builds the detail document and inserts it under both keys.
  Nothing is constructed for an item until it is first selected.
- **Memo**: revisiting an item returns the same cached `DetailEntry`, with its
  accumulated state intact.

This mirrors how the workbench keeps per-panel documents alive; the cache is the
only genuinely new piece relative to the assistant precedent.

### Why a document *and* a projection

- **Document** `MasterDetailMasterDetail` — owns the `master`, the memo `details`
  cache, the `orientation`, and the unified `selection`. Following the `@document`
  idiom in [Workbench.jl](../../program/src/document/Workbench.jl) and
  [Workspace.jl](../../program/src/document/Workspace.jl).
- **Projection** `MasterDetailToWidget(master_projection, detail_projection,
  detail_target)` — builds the horizontal split, runs the master through its one
  fixed pipeline and the resolved detail through its type-dispatched family, and
  owns the forward/backward selection mapping and reader routing for the two slots.

Both `master_projection` (one pipeline) and `detail_projection` (a
`TypeDispatchingProjection` over content type) are supplied by the caller — the
detail's table mirrors the `combined_w2g` shape from
[example/src/projection/Workbench.jl:19](../../example/src/projection/Workbench.jl#L19).
MasterDetail stays domain-agnostic: it never names `DbCatalog` or `FileSystem`.

## Document types — NEW `program/src/document/MasterDetail.jl`

**⛔ OBSOLETE:** No `MasterDetail.jl` document file exists under `package/*/src/`
(glob `**/MasterDetail*.jl` → none) and there is no `MasterDetailModule` /
`MasterDetailMasterDetail` / `DetailCache` / `DetailEntry` anywhere. The
master/detail document that *was* built is `ComponentMasterDetail` in
`package/domain/src/document/Component.jl:62` (a different, cache-less design).

`module MasterDetailModule`, included in `program/src/Projectured.jl` near the
other high-level domains (Workbench/Workspace).

```julia
abstract type MasterDetailDocument <: Document end

@document struct MasterDetailMasterDetail <: MasterDetailDocument
    master::Document
    details::Any            # DetailCache: {by_id::IdDict, by_path::Dict{ReferencePath}}
    orientation::Symbol     # :horizontal (v1)
    selection::Reference
end
```

where `DetailCache` is the dual-index struct of Resolved decision 1 — `by_id` and
`by_path` both pointing at the same `DetailEntry`, with helpers `cache_lookup`
(id-first, path-fallback, re-key-on-heal) and `cache_insert!` (store under both
keys).

Keyword constructor defaulting `details` to an empty `DetailCache`, `orientation`
to `:horizontal`. No operations are strictly required for v1 (the detail is
derived, not edited as a list); selection moves come through the existing
`ReplaceSelectionOperation` machinery.

## Projection — NEW `program/src/projection/primitive/MasterDetailToWidget.jl`

**⛔ OBSOLETE:** No `MasterDetailToWidget` projection exists (grep → only this file
and `master-detail-editable.md`). The analogous projection for the chosen design
(`ComponentToWidget`) is itself still unimplemented — see `component-document.md`,
where it is tracked as OPEN.

A `Projection` struct `MasterDetailToWidget` carrying **two independent
projections** (Resolved decision 4) plus the target resolver:

- `master_projection` — the **one** fixed pipeline the master is rendered with
  (e.g. `catalog → syntax → text → widget`). A single `SequentialProjection`,
  chosen per MasterDetail instance, tuned for a compact navigable tree.
- `detail_projection` — a **`TypeDispatchingProjection` keyed on the content
  document type**: many pipelines, one per inspectable domain (JSON, file/text,
  table, syntax, …), each free to be richer than the master's (expanded,
  word-wrapped, `SyntaxToWidget` cards). The detail node is routed by its own type
  to the matching entry.
- `detail_target::Function` — `(master_doc, master_selection) -> item_node_or_nothing`,
  defaulting to the `FocusingProjection`-style longest-*content*-prefix resolver
  that skips technical/layout nodes (Resolved decision 3). Parameterising it keeps
  MasterDetail domain-agnostic.

Both panes are recursed through their **explicitly supplied** projection — not the
ambient outer dispatch — which is exactly what lets the same content type render
*differently* in the master vs the detail (mechanical note in Resolved decision 4).

`projection_print`:
- recurse `master` via `_recurse(recursion, master, child_context(...))` (left);
- resolve the detail document through the memo (right), wrapped so its content is
  a reactive thunk of the master selection;
- wrap each in a `WidgetScrollPane` and assemble a horizontal `WidgetSplitPane`
  with `LayoutConstraint`s — master at a small `min_width` + side weight, detail
  at the main weight (mirror the tokens in
  [WorkbenchToWidget.jl:128-135](../../program/src/projection/primitive/WorkbenchToWidget.jl#L128-L135)).

`map_reference_forward` / `map_reference_backward`: two slots, identical in shape
to the assistant's split mapping —
```
master.rest…  ↔  elements[1].child.content.rest…
detail.rest…  ↔  elements[2].child.content.rest…
```
(cf. [WorkbenchToWidget.jl:449-454](../../program/src/projection/primitive/WorkbenchToWidget.jl#L449-L454)
and [:525-544](../../program/src/projection/primitive/WorkbenchToWidget.jl#L525-L544)).

`projection_read`: translate path-bearing ops via `map_reference_backward`, pass
widget-target ops (scroll) through — same pattern as `_retarget_panel_op`
([WorkbenchToWidget.jl:769-783](../../program/src/projection/primitive/WorkbenchToWidget.jl#L769-L783)).

Export a `MasterDetailToWidget` factory and register the type in the outer
`TypeDispatchingProjection` so both panes recurse correctly.

### Selection semantics to settle in the printer

- The unified `MasterDetail.selection` may point into the **master** (drives the
  detail) or into the **detail** (editing the inspected node). Both must route.
- A subtle question: editing in the detail edits *the cached detail document*. If
  the detail is a *focus view* of the master node, edits flow back into the master
  (shared object). If the detail is a *separate projected copy* (e.g. the
  `…ToSyntax` stage), edits live only in the detail and are not written back. v1
  should pick one — see Open decisions — and the forward/backward mapping is the
  same either way; only the identity of `detail_doc` differs.

## Examples — NEW `example/src/document/MasterDetail.jl` + `example/src/projection/MasterDetail.jl`

**⛔ OBSOLETE:** No master/detail example files exist (no `MasterDetail.jl` under
`package/example/src/`, no `master_detail_example`). The DB-catalog master/detail
example is instead tracked (still OPEN) under `component-document.md`.

Two concrete masters demonstrate genericity:

1. **DB catalog master/detail** — master = a `DbCatalogRdbms` (built lazily via
   `DatabaseInstanceToDbCatalog(pool)`, [example/src/projection/DbCatalog.jl:3](../../example/src/projection/DbCatalog.jl#L3));
   selecting a table/column shows it inspected on the right through the
   `DbCatalog → syntax → text → graphics` chain.
2. **File-system master/detail** — master = a `Workspace`
   (`WorkspaceToFileSystem` → `FileSystemToSyntax` → …,
   [example/src/projection/Workbench.jl:41](../../example/src/projection/Workbench.jl#L41));
   selecting a file shows its inspected content on the right.

Each example supplies **two** projections (Resolved decision 4):

- `master_projection` — the master's one navigable-tree pipeline (catalog tree /
  file-system tree).
- `detail_projection` — a `TypeDispatchingProjection` of inspector
  `…→syntax→text/widget→graphics` chains keyed on content type. Seed its entry
  list from the workbench example's `combined_w2g`
  ([example/src/projection/Workbench.jl:19-46](../../example/src/projection/Workbench.jl#L19-L46))
  and override the entries that should be richer in inspection (e.g. word-wrapped
  JSON, `SyntaxToWidget` cards).

Register `master_detail_example` in `example/src/ProjecturedExample.jl` and
`example/src/Examples.jl`.

## Critical files

**⛔ OBSOLETE:** None of the four "Create" files were created and the listed
"Edit" registrations were never made for these types (no `MasterDetailModule`
include/export in any `Projectured*.jl`; no `master_detail_example` in
`example/src/Examples.jl`). The "Reference / reuse" files do still exist, just at
remapped paths under `package/` (e.g.
`package/domain/src/projection/primitive/WorkbenchToWidget.jl`,
`package/kernel/src/projection/generic/Focusing.jl`).

**Create**
- `program/src/document/MasterDetail.jl`
- `program/src/projection/primitive/MasterDetailToWidget.jl`
- `example/src/document/MasterDetail.jl`, `example/src/projection/MasterDetail.jl`

**Edit**
- `program/src/Projectured.jl` — include + export the new module/projection
- `example/src/ProjecturedExample.jl`, `example/src/Examples.jl` — register example
- (optional) extract the `combined_w2g` type-dispatch entry list from
  [example/src/projection/Workbench.jl:19-46](../../example/src/projection/Workbench.jl#L19-L46)
  into a shared helper, so the example's **detail** `TypeDispatchingProjection` can
  seed from it and override the inspector entries (the master pipeline is separate)

**Reference / reuse (unchanged)**
- [WorkbenchToWidget.jl](../../program/src/projection/primitive/WorkbenchToWidget.jl) — split-pane + selection-mapping template
- [Focusing.jl](../../program/src/projection/generic/Focusing.jl) — detail-target resolution
- [guide/reactive-cells.md](../../guide/reactive-cells.md) — the derived-detail thunk
- [guide/editor/selection.md](../../guide/editor/selection.md) — forward-projecting selection

## Verification (when implemented)

1. **Smoke** — `MasterDetailMasterDetail(master)` builds; `details[]` is empty.
2. **Follow** — select a master item, confirm the detail pane renders that item
   through the default chain; select a different item, confirm the detail switches.
3. **Lazy** — confirm `details[]` gains an entry only on first visit of an item.
4. **Memo** — give the detail some state (move its sub-selection / collapse a
   syntax node), select another item, reselect the first, confirm state restored.
5. **Selection round-trip** — a click/caret in the detail produces a
   `ReplaceSelectionOperation` whose re-rooted path resolves under
   `MasterDetail.selection` (inspect via the Descriptor panel).
6. **Genericity** — the same `MasterDetailToWidget` drives both the DB-catalog and
   file-system examples, differing only in the supplied master document,
   `master_projection`, `detail_projection`, and `detail_target`.
7. **Master/detail differentiation** — confirm a content type that appears in both
   panes renders compactly in the master and richly (e.g. word-wrapped / cards) in
   the detail, proving the two pipelines are independent.

## Resolved decisions

1. **Memo key — dual key, id-first with reference fallback.** Each cache entry is
   stored under **both** the item's object identity (`objectid`, via an `IdDict`)
   **and** its `ReferencePath`. Lookup order on (re)selection:
   1. try the `IdDict` by the item node's identity — the fast, exact hit;
   2. if that misses (the node object was replaced by an edit, so identity was
      "lost"), fall back to the `ReferencePath` index;
   3. on a path hit, **re-key** the entry under the new node's identity so the
      next lookup is an id hit again (identity heals forward).

   So `details` is a small struct holding two maps that stay in sync:
   `by_id::IdDict{Any,DetailEntry}` and `by_path::Dict{ReferencePath,DetailEntry}`,
   both pointing at the same `DetailEntry`. Identity is authoritative when present;
   the path is the recovery index when an edit swaps the node out underneath us.
   (Caveat to handle in implementation: a *structural* master edit can leave a
   stale path mapping to a different node — guard the path fallback by
   re-validating that `evaluate_reference(master, path)` still yields a node the
   `detail_target` predicate accepts before reusing the entry.)

2. **Detail is read-only inspection for v1.** The detail is a separately-projected
   inspection of the selected item; edits in the detail are not written back to the
   master. Editable detail (edits flowing back into the master node) is deferred to
   a follow-up — see [master-detail-editable.md](master-detail-editable.md).

3. **Technical layout nodes are not selectable as detail targets.** The
   `detail_target` predicate accepts only *content* items (catalog levels, file
   entries, JSON values, …) and rejects structural/layout wrappers (split panes,
   scroll panes, tabbed panes, `LayoutConstraint`s, page/composite containers).
   Concretely it walks the master selection prefix and returns the longest prefix
   whose node is a content item, skipping any node whose type is a known
   layout/structural type. Per-example the predicate is narrowed further (e.g. only
   `DbCatalog*` levels for the catalog, only `FileSystemFile`/`Directory` for the
   tree).

4. **Two independent projection configs: one master pipeline + many detail
   pipelines (type-dispatched).** The master is rendered by a **single fixed
   pipeline** (`master_projection`); the detail is rendered by a
   **`TypeDispatchingProjection` over the content document type**
   (`detail_projection`) — many pipelines, one per inspectable domain. They are
   *not* the same table, so the same content type can render compactly in the
   master and richly in the detail. See the detailed rationale below.

5. **Orientation kept as a field, fixed `:horizontal` for v1.** Lets a later
   iteration flip to `:vertical` or a tabbed detail without a schema change.

6. **Empty selection → blank detail.** When nothing selectable is selected, the
   detail pane is a blank `WidgetScrollPane(nothing)` (no hint text).

### Decision 4 in detail — one master pipeline, many detail pipelines

The master and the detail want **fundamentally different presentations of the same
data**, so they get **two separate projection configs**, both supplied to
`MasterDetailToWidget`:

- **Master → one fixed pipeline (`master_projection`).** The master is a single
  document domain rendered one way: a compact, collapsed, no-wrap *navigable tree*
  (e.g. `DbCatalog → syntax → text → widget`, or `Workspace → file-system → syntax
  → text`). One `SequentialProjection`, chosen when the MasterDetail is built.

- **Detail → many pipelines, type-dispatched (`detail_projection`).** The detail
  can be *any* content type (the selected item could be a catalog column, a JSON
  value, a file's text, a table, …), so it is a `TypeDispatchingProjection` keyed
  on the **content document type** — one entry per inspectable domain, exactly the
  shape of the workbench example's `combined_w2g`
  ([example/src/projection/Workbench.jl:19-46](../../example/src/projection/Workbench.jl#L19-L46)),
  but tuned for *inspection* rather than a side tree: expanded, word-wrapped,
  `SyntaxToWidget` cards where useful.

**Why two configs rather than one shared table:**

- **Master/detail differentiation** — a given content type renders *compactly* in
  the master and *richly* in the detail. The workbench's single table can't do
  this: it deliberately renders JSON/XML **no-wrap**
  ([Workbench.jl:26-27](../../example/src/projection/Workbench.jl#L26-L27)), right
  for a tree but cramped for an inspector that wants wrapping
  ([WordWrapping](../../example/src/projection/Workbench.jl#L12)) and cards.
- **Per-pane configuration** — collapse markers, wrap policy, and syntax→widget vs
  syntax→text are chosen independently for each pane.
- **Detail still gets automatic domain coverage** — because the detail config is
  itself a type-dispatch table, every inspectable domain is covered, and adding a
  new one is a single entry in that table.

**Cost accepted:** two tables/pipelines to maintain instead of one, and the detail
table must enumerate the content domains it inspects (it can be seeded by reusing
the `combined_w2g` entry list and then overriding the entries that should differ —
so the maintenance overlap is small).

#### Mechanical note (resolve in implementation)

In the workbench, panes are `WidgetScrollPane(content)` and the **ambient outer**
`TypeDispatchingProjection` recurses into them by type. Here we instead want each
pane recursed by its **own** projection. So `MasterDetailToWidget` must drive the
two sub-projections explicitly rather than relying on the ambient recursion:

- run `master`   through `master_projection`,
- run `detail_doc` through `detail_projection` (which type-dispatches internally),
- embed each resulting widget tree as a split-pane child.

The base mechanism exists — `projection_print(proj, proj, doc, child_context(…))`
runs a *specific* projection on a child (cf. how `RecursiveProjection` and the
generic `Copying`/`Focusing` projections invoke a chosen recursion). The
implementation detail to settle is **where the pipelines stop**: if
`master_projection`/`detail_projection` run all the way to a `WidgetDocument`,
`MasterDetailToWidget` embeds those widgets directly and the *outer* chain only
needs to widget→graphics the surrounding split (not re-recurse the pane contents).
The two pane projections, the split widget, and the outer widget→graphics step
must compose to exactly one graphics pass over the pane contents — verify no
double-projection.
