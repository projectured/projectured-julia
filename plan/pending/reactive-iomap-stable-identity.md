# Identity-stable, fully-reactive projections and IoMaps

## Goal — the invariant

Establish and enforce, across every projection in the project:

> **A projection's `print_document` returns an IoMap whose *identity is stable* for
> the life of that projection instance. Every varying output — the output
> document, the output `selection`, and every child IoMap — is wired as a
> *computed cell* deriving from the projection's input/parameter cells, and child
> collections *reconcile by identity* (reuse surviving children, rebuild only the
> ones whose value genuinely changed). A projection never rebuilds or replaces
> the IoMap it returned in response to a change; the reactive graph propagates
> changes through the cells it already wired.**

Corollary: an operation that changes what a projection shows writes a cell the
projection derived from — it does **not** null `editor.iomap`.
`invalidate_projection!` stays reserved for genuine whole-root rebinds.

This is the union + strengthening of four existing rules —
AR-REACTIVE-OUTPUT-SELECTION, AR-SHARED-CHILDREN-IOMAP, AR-NO-WRITE-IN-THUNK,
AR-MUTATE-OR-NULL-IOMAP — promoted from "a compound projection should" to "every
projection must," and given a citable name.

## Why

- **The concrete bug.** `FocusingProjection.print_document`
  ([Focusing.jl:43-45](../../package/base/main/projection/generic/Focusing.jl#L43-L45))
  computes `output = p.part_evaluator(input)` **eagerly** into a plain
  `SimpleIoMap`, and `part` is a plain field
  ([Focusing.jl:80-83](../../package/base/main/projection/generic/Focusing.jl#L80-L83)).
  A focus change (`ReplaceFocusPartOperation`) writes plain fields → no cell
  invalidates → the printed structure has no reactive edge to the change → stale
  output. It already wires `output.selection` correctly with `set_cell_function!`
  — it just never did the same for `output` itself or `part`.
- **The cost elsewhere.** Because projections may *replace* their output identity
  on a change, `ChainingProjection` compensates with bespoke per-stage re-print
  cells (`step_iomaps::Vector{Cell}`) and a synthesized `:output`
  getproperty/propertynames. Under the invariant, each stage's IoMap derivation
  absorbs the re-print and Chaining collapses to wiring stage cells together.

## What already exists (this shrinks the real scope)

- The **template engine** (`ProjectionTemplate` / `RuleIoMap`, used by every
  `XToSyntax`) **already conforms**: `_node_print` builds one `RuleIoMap`, keeps
  its identity, wires `output`/`selection`/`children` as computed cells, and
  reconciles children.
- **Reconciliation helpers already exist** (private in ProjectionTemplate):
  `_reconciling_child_iomaps` (keyed by `(objectid, index)`),
  `_reconciling_child_iomap` (single child by objectid), `_project_output_cell`.
  These are the reusable core — they need a shared home, not reinvention.
- `@projection` / `@iomap` exist (`@cell_struct` + a supertype default).
  `@projection` is used ~25 places; `@iomap` by **zero** IoMaps.

⟹ "throughout the project" = **the hand-written projections that don't go through
the template engine**: the base generic + higher-order projections, and the
visual/domain projections that hand-build IoMaps. The template majority is done.

## The mechanism (and an honest note on the macros)

Three things, in order of importance:

1. **Derivations, not eager values.** Every varying IoMap field is a computed
   cell (`Cell(() -> … input cells …)`) or a `set_cell_function!` field on a
   persistent output object. *This is the load-bearing change.*
2. **Reconciliation.** Child collections use the shared reconciling cell so
   identity survives value changes and only genuinely-moved children rebuild.
3. **Stable IoMap identity.** Build the IoMap once; never replace it on change.

`@projection`/`@iomap` (transparent cell *fields*) are the *vehicle* — but not the
fix by themselves: a cell field holding an eager value still doesn't derive (the
template's `RuleIoMap` is identity-stable and reactive *without* `@iomap`). Per the
locked decisions we adopt `@iomap` on every IoMap and `@projection` on every
projection for uniformity; the derivation + reconciliation wiring remains the
load-bearing work, done per projection.

## Phases

**Phase 0 — Foundations.**
- [x] Write the invariant as a new AR rule in `architecture-requirements.md`;
      cross-link the four rules it subsumes. **Done `cd82b9cd`** (AR-STABLE-IOMAP-IDENTITY).
- [x] **Accessor contract change** (decision 2): `get_iomap_output` / `_input` /
      `_projection` return the value uniformly (property access, off raw `getfield`).
      **Done `5e106fc7`** (no-op on the plain IoMaps; enables the @iomap recipe).
      `SimpleIoMap` was the recipe reference (Phase 1, `1fa78c5a`); ChildrenIoMap/
      ContentIoMap deferred to their batches. iomap-layer seal held.
- [x] Promote the reconciliation helpers to the **iomap layer** (correction: they
      do *not* call `print_child` — the caller's closure does; they need only
      `Cell` + `objectid`, so the iomap layer is their lowest home and reaches every
      projection consumer). New fragment `IoMapReconcile.jl` exporting public
      `reconcile_child_iomaps` / `reconcile_child_iomap`; `ProjectionTemplate` and the
      hand-written projections call them. **Done `f12c5595`.**
- [x] **Reactive test harness** — found to already exist: `printer_locality_report`
      prints once, holds the iomap+output, drives an arbitrary `mutate!`, and diffs
      identity (tests reactive-propagation-vs-reprint). Per-projection reactive tests
      add the content-correctness + iomap-identity assertions directly (done first in
      the Focusing test, `a5f1a1bb`).

**Phase 1 — Exemplar: `FocusingProjection`.** **Done.**
- [x] `@projection FocusingProjection`; `output` a computed cell
      `Cell(() -> evaluate_reference(input, p.part))` on a **stable** `SimpleIoMap`;
      dropped `part_evaluator`; `ReplaceFocusPartOperation` writes the `part` cell.
      Dropped the eager selection mutation entirely (design review: the cursor rides
      the `map_reference_forward` composition). `SimpleIoMap → @iomap` (`1fa78c5a`)
      first; Focusing (`a5f1a1bb`).
- [x] Reactive test: hold the iomap, write `part`, assert `iomap.output` tracks the
      new focus through the same object. gestures 6/6, reactive output 3/3.

**Phase 2 — base generic / degenerate** (Identity, Constant, Reversing, Copying,
Sorting, Filtering, Searching, Dragging): convert struct + wire output/children +
reconcile + reactive tests. One reviewable change.
- **Assessed (impl):** `IdentityProjection` (empty struct, `output === input`) and
  `ConstantProjection` (fixed `output` field) are **already compliant** — no change;
  AR-USE-PROJECTION-MACRO permits their plain structs (no reactive fields). The rest
  use `ChildrenIoMap` (Reversing) or their own IoMap structs, whose **reactive-output**
  compliance depends on those IoMaps being `@iomap`. `reconcile_child_iomaps`
  (child-identity) is independent and applies now; reactive `output` needs `@iomap`.
- **Phase 2a — `ChildrenIoMap → @iomap` sweep. Done `27900e5d`.** The prerequisite
  for reactive-output across every ChildrenIoMap-using projection. `child_iomaps::Cell
  → ::Any`; pure-ChildrenIoMap consumers use `.child_iomaps` (transparent value),
  mixed-dispatch files use `getfield(iomap, :child_iomaps)[]` (uniform-safe: reaches
  the backing cell whether the field is a transparent `@iomap` cell or a plain raw
  `Cell`), and the plain non-converting structs (`SyntaxCompoundToTextIoMap`,
  `GridLayoutIoMap`, `GraphLayout*`, `RuleIoMap`) are left. Verified: kernel guard
  10/10, test_visual 48241, test_domain 106022, 0 Fail/Error.
- **Phase 2b — per-projection reactive-output fixes. Done.** All six base generic
  projections converted, one commit each, every one with a reactive test proving
  the change propagates through the *held* iomap (same `objectid`, output tracks):
  - `Reversing` (`7755778e`) — `ChildrenIoMap`; `reverse(input)` → reactive CellVector
    from reconciled child outputs. New `ReversingTest` (had none).
  - `Filtering` (`741b9937`) — `@iomap`; reactive `kept_indices`+`output` on the
    CellVector path, eager plain-vector paths. New `FilteringTest` (had none).
  - `Searching` (`5392593b`) — `@iomap`; one reactive tree-walk cell feeds both
    `output` and `match_paths`. New `SearchingTest` (had none).
  - `Sorting` (`88b8809c`) — `@iomap`; reconciled children + reactive `index_map`/
    `output`; the two `element_iomaps[][j]` mapper sites drop the inner `[]`
    (@iomap flip). New `SortingTest`. **test_domain green** (production JSON/YAML sort).
  - `Copying` (`800ef2b1`) — `@iomap`; reconciled children + reactive `output` on the
    CellVector path; ListNode/Vector{Cell}/struct/primitive paths unchanged; the
    mappers already read `iomap.children` as a value so **no mapper edits**. Reactive
    +reconciliation testset added. **test_visual + test_domain green** (GraphicsCaching,
    JSON/YAML/Markdown copy paths).
  - `Dragging` (`aa1d360e`) — `@iomap`; transparent printer reconciles the single
    `content` child (`reconcile_child_iomap`) + forwards `output` reactively. `test_dragging`
    + example green.

  **Discovered:** these six have **no mutable config parameters** (unlike Focusing), so
  their reactive-output requirement is about tracking *input* structural/value edits — the
  faithful translation is reactive on the CellVector (reactive-document) path, eager on
  plain-vector/arbitrary inputs (nothing to react to), `@iomap` auto-wrapping the eager
  values. Base generic reactive tests now live in `ProjecturedBaseTest`
  (`test_reversing/_filtering/_searching/_sorting` + Copying's new testset).

**Phase 2c (optional, later):** the base *higher-order* dispatchers are Phase 3 below.
Not-yet-reactive base generics remaining after 2b: none in the generic tier. The
`Recursive` projection and the compound helpers (`GenericCompound`/`HigherOrderCompound`)
are thin wrappers; audit them when convenient.

**Phase 3 — base higher-order. Done `4b2562da`.** The base higher-order tier is
complete (all but Chaining, which is Phase 6). Two kinds turned up:

- **Own wrapper IoMap → converted** (Switching, Nesting, ReferenceDispatching,
  WindowInputUnwrapping): each built its own IoMap with an eager `output =
  inner.output` snapshot. `@iomap` the struct + forward `output` through a cell.
  Only **Switching** has a genuinely runtime-reactive dispatch key (`index::Cell`):
  it reconciles the inner branch by index (`reconcile_child_iomap`) so writing the
  index swaps the branch through the same iomap. The other three dispatch on a
  *fixed/structural* key (nesting position, `ctx.reference`, or none), so the inner
  is fixed per print — pure transparent-output forwarders. None needed mapper edits
  (they already read the iomap fields as values). New `test_switching` (reactive
  branch swap) + `test_window_input_unwrapping` (transparency); Nesting/RDP covered
  by test_visual (CollectionToSyntax) + test_domain (RecursiveProjection).
- **No own IoMap → already compliant, no change** (PredicateDispatching,
  TypeDispatching, Recursive): `print_document` returns the *inner* projection's
  IoMap **directly** (pure delegation, no wrapper struct, no snapshot, no identity
  replacement). Compliant by construction — the invariant is about a projection's
  *own* IoMap, and these have none.

Verified: test_base 158/158; test_visual 48347 / 0 fail; test_domain 106079 /
0 fail; Broken unchanged (1, 5).

**Phase 4 — visual projections** (31 own-IoMap structs). Surveyed and bucketed —
**most hot paths were already reactive.** Classification:

- **A — already reactive, no change (~9+2):** all of text/ (`TextToGraphics`,
  `WordWrapping`, `TextFiltering`, `TextFirstLine`, `TextHighlighting`,
  `SelectionInverting` — the shared `both = Cell(() -> …)` / `CellVector(() -> …)` /
  `set_cell_function!` idiom), `SyntaxCompoundToTextIoMap` (reconciles children via an
  IdDict identity cache — the School-A exemplar), `WidgetTable`/`WidgetTree`
  (reactive `geometry`/`grid_iomap` cells). `ClipboardSlice`/`ClipboardCollection`
  have reactive `output` cells driven by a `display_*::Cell` param (already wired).
  These use explicit `::Cell` fields + `iomap.field[]`; they are compliant *without*
  `@iomap`. **The uniformity-only `@iomap` sweep on these (decision 1) is deferred** —
  it is pure syntactic churn (flip `iomap.field[]`→`iomap.field` at ~30 deref sites)
  with zero behavior change; do it as a separate mechanical pass if wanted, not mixed
  with correctness work.
- **B — transparent forwarders (eager `child.output`). 4a DONE `fed67fc3`:**
  `TooltipDecorator`, `HoverProbe`, `WidgetHoverTracking`, `WidgetPopupResolver` →
  `@iomap` + `Cell(() -> child_iomap.output)`. **`WindowManaging` deferred to Phase 7**
  (its reader imperatively `push!`/`deleteat!`s `output.windows` — a documented
  workaround for Copying's *former* eager children; now that 2b made Copying
  reconcile, remove the workaround holistically in editor tightening).
- **C — eager output/children:**
  - **4b (reconcile fixes). DONE `221bb397`:** `ClipboardCollectionToAnyProjectionIoMap`
    (eager `element_iomaps` comprehension → `reconcile_child_iomaps`, deref at 3 read
    sites; struct stays plain — its output is a deliberately Cell-valued field with
    `.output[]` consumers) and `ScreenToScreenIoMap` (`window_iomaps` Cell-that-rebuilds-all
    → `reconcile_child_iomaps`, no deref change) + `ScreenWindowIoMap` (const
    `Cell(content_iomap.output)` → `Cell(() -> …)`). Output unchanged (pass counts
    identical); identity now stable.
  - **4b-layout (regrouped, intricate):** `GridLayoutIoMap` / Flow / Stack are all eager
    (`CellVector(Cell[Cell(e) for e in wrapped])` + `Cell(entries)`), unlike the reactive
    H/V/Constraint siblings' `build = Cell(() -> _build(…))` + `CellVector(() -> build[].wrapped)`.
    **NOT contained:** Grid's IoMap exposes per-column/row geometry cells (`col_x`, `col_w`,
    `row_h`, `columns`, `row_count`) that `WidgetToGraphics._wt_geometry` reads via
    `iomap.col_x[c][]` — moving `child_iomaps` into a build cell ripples into that external
    geometry contract. Interlocks with 4c; do together. (Layouts are currently "saved" by
    parent-composite reconciliation, so this is a Phase-6 prerequisite, not a live bug yet.)
  - **4c — deferred to its own project (user decision, 2026-07-19).** A per-struct
    analysis showed the eager `_make_canvas` pattern (snapshot `Int32` extent + eager
    `CellVector(Cell[Cell(e) …])` membership, WidgetToGraphics.jl:697-707) spans the
    **whole widget-rendering surface**, not 10 structs: **~27 leaf renderers CONVERT**
    (Label, Text, ContextMenu, Dialog, MenuItem, Select, SpinBox, List — plus the broader
    scan: Button, Checkbox(membership-only), Tooltip, StatusBar, ScrollBar, Badge, Separator,
    Switch, Progress, Slider, RadioGroup, Avatar, Alert, Skeleton, Toggle, ToggleGroup,
    Option, Textarea, Accordion) **+ ~17 container wrappers** (Composite/Shell/SplitPane/
    TabbedPane/Menu/Toolbar/TitlePane snapshot membership). **Already reactive → SKIP:**
    `WidgetScrollPane`/`WidgetTransformPane`/`WidgetScrollPaneToGraphicsViewport` (build cell-backed
    `outer_w/h`), `WidgetCard` (`build = Cell(() -> _card_build(…))`), `WidgetInsertion` (fixed
    placeholder). `ObjectToWidget`/`ProjectionConfiguring` (eager output shell, reactive leaf
    views) also belong here.
    - **Why deferred, not a live bug:** these leaves are masked by the editor re-printing on
      edits (Phase 7's target); staleness only bites once re-printing stops → this is a
      **Phase 6 prerequisite**, not a current defect.
    - **Approach (validated + underway):** `_reactive_canvas(x, y, build_fn)` helper added
      beside `_make_canvas` — `build_fn()` returns `(; width, height, elements)`, run inside a
      cell, so extent+membership re-derive while the canvas keeps identity. Per leaf: wrap the
      print body (after the `w.visible`/`position` prefix) in the thunk, return the named tuple.
    - **4c progress — ALL ~25 widget LEAVES reactive** (`2ead3fa9`, `8ecece19`, `a1f49441`,
      `e9e8d1e6`, `81e0ce46`, `809c0140`). Three conversion patterns, each verified green:
      - **Simple wrap** (18): Badge, Separator, Progress, Slider, StatusBar + a delegated batch
        (Label, Checkbox, Button, Switch, RadioGroup, Avatar, Alert, Skeleton, Toggle,
        ToggleGroup, Option, Textarea). Body → `_reactive_canvas(origin, () -> (; width, height,
        elements))`.
      - **Custom-IoMap / extent-as-shared-cell** (Select, SpinBox, List): one `build` cell feeds
        both the canvas (`_reactive_canvas_cell`) and the IoMap's `Cell(() -> build[].width)` etc.;
        `@iomap` the IoMap struct so the reader reads `iomap.control_width` transparently.
      - **Recursion leaves / single-child-reconcile** (ContextMenu, Text, MenuItem, Tooltip):
        `reconcile_child_iomap` the child (forced only in the recurse branch for the conditional
        ones), build cell reads the child canvas `w/h`; `@iomap` the struct. WidgetText handles both
        editable (grows as typed) + non-editable branches; MenuItem/Tooltip carry a tuple
        `child_iomaps` list read by the `getfield(iomap, :child_iomaps)[]` idiom (compatible).
      Delegating the *simple* batch (Sonnet applies the transform, I verify test_visual + spot-check)
      worked well; the custom/recursion ones were done by hand. All green throughout (0 Fail/Error,
      Broken 1/5; pass counts rose only from added cells).
    - **4c remaining — the container/layout sub-project (distinct, larger):**
      - **~17 container wrappers** (Composite/Shell/SplitPane/TabbedPane/Menu/Toolbar/TitlePane):
        eager `_make_canvas(0,0,elems)` membership → reactive membership + child reconcile.
      - **Geometry-coupled layouts** (Grid/Flow/Stack): their IoMaps expose per-column/row cells
        `WidgetToGraphics._wt_geometry` reads via `iomap.col_x[c][]` — move `child_iomaps` into a
        build cell without breaking that contract.
      - The Workbench domain→widget builders (Phase 5 deferred) fold in here.

Verified after 4a/4b: test_visual 48507 / 0 fail; test_domain 106125 / 0 fail; Broken (1, 5).

## Stopping point (2026-07-19) — merge-ready milestone

**Complete + verified:** the entire **base package** projection tier (Phases 0-3) and the
visual **hot paths** (already reactive: text/, syntax/, TextToGraphics, WidgetTable/Tree,
clipboard outputs) + the visual **decorator forwarders** (4a) + **clipboard/screen reconcile
fixes** (4b). A **text pipeline (json→syntax→text→graphics) is fully reactive end-to-end.**

Phase 5's clean, widget-independent work is now also done (GestureHelp forwarder +
WorkspaceToFileSystem; the domain hot paths were already reactive).

**Remaining — everything now converges on the deferred 4c:**
- **4c (deferred, user decision):** the widget-leaf renderers (~44 `_make_canvas` sites)
  + the geometry-coupled layouts. Also folds in the Workbench domain→widget builders
  (~11 sites in `WorkbenchToWidget.jl`) and `ConversationPartToWidget`, which are the
  same domain→widget build-cell character feeding this layer.
- **Phase 6 (simplify Chaining — the payoff): gated on 4c.** Chaining's `step_iomaps`
  removal is wholesale — it cannot stop re-printing while any pipeline stage (the eager
  widget renderers) is still eager. Text pipelines are ready; widget pipelines are not.
- **Phase 7 (editor tightening): mostly gated on 4c.** One piece may be unblockable now
  (removing WindowManaging's imperative `output.windows` mutation — Copying reconciles
  and ScreenToScreen reconciles windows since 4b), but it is risky/interactive and best
  done with a reactive test after the window path is confirmed reactive end-to-end.
- **Optional, not a gap:** reconcile-by-identity for the ~45 domain `Cell(() -> [rebuild
  all])` sites (a rebuild→reuse optimization; they already satisfy the invariant).

⟹ **Coherent stopping point:** all reactive-identity work that is NOT blocked by the
deferred widget-rendering (4c) is complete. Further substantive progress needs the 4c
project, which then unblocks 6 and 7.

Branch `reactive-iomap`: all commits green (test_visual 48507/0-fail, test_domain
106125/0-fail, Broken 1/5), worktree clean — ready to `add to main`.

**Phase 5 — domain projections.** Surveyed (7 own-IoMap structs + hand-built
shared-IoMap sites). **The domain hot paths are already reactive** — the entire
syntax-node family (yaml/sql/book/markdown/math/formula/filesystem/insertion +
`DbCatalogToSyntax`), `ConversationToSyntax`/`ConversationEditor`, `VersioningToAny`
(the derived-output reference model, `getproperty` over two cells), and both Graph
IoMaps use `CellVector(() -> …)` + `Cell(() -> [print_child …])` + deferred-`iomap_cell`
selection cells. ~48 sites, no change. **Note:** domain uses `reconcile_child_iomaps`
**nowhere** — its reactive baseline is `Cell(() -> [rebuild all])` (recomputes but no
identity reuse); reconcile is a *secondary optimization* across those ~45 sites, not a gap.

- **Done (clean, widget-independent gaps):**
  - `GestureHelpProjectionIoMap` (gesturemap) — transparent forwarder, `@iomap` +
    `Cell(() -> inner_iomap.output)`.
  - `WorkspaceToFileSystem` — `WorkspaceFolderToFileSystemDirectory` eager `dir` →
    `Cell(() -> make_filesystem_pathname(folder.pathname))`; `WorkspaceWorkspaceProjection`
    eager comprehension + `Cell([...])` → `reconcile_child_iomaps` + reactive single-root
    `output` (mappers return `nothing`, so no deref changes).
- **Deferred (with the 4c widget project — same character / interlocked):** the Workbench
  domain→widget builders (`WorkbenchToWidget.jl`: Shell/TabbedPane/Navigator IoMaps + 8
  panel `print_document`s, ~11 sites — build `WidgetShell`/`WidgetTabbedPane`/`WidgetSplitPane`
  trees eagerly, only selection cells reactive) and `ConversationPartToWidget` (eager
  `WidgetCard`). These feed the deferred eager widget→graphics layer, so low marginal value
  until 4c lands.
- **Deferred (low value):** `DbCatalogToSql` (5 sites) — a **read-only** DDL serializer
  (all maps/reader return `nothing`) over a rarely-changing catalog snapshot; reactivity
  would wrap `print_child` subtree calls in thunks (re-projection cost) for little gain.
  `GestureMapToSyntax` — static help-window snapshot input (fixed, snapshot-fine).

**Phase 6 — simplify `ChainingProjection`.**
- [ ] Replace `step_iomaps::Vector{Cell}` + per-stage re-print cells with a plain
      list of stage IoMaps whose input/output cells are shared across the
      boundary; drop the synthesized `:output` getproperty/propertynames.
- [ ] Reactive test: a structural swap mid-chain propagates end-to-end with no
      bespoke chain cell and no iomap drop.

**Phase 7 — editor tightening (conservative, last).**
- [ ] Audit operations that null `editor.iomap`; where the reactive path now
      covers them (proven by a reactive test), stop nulling. Leave genuine
      whole-root rebinds alone. The payoff (fewer full re-prints), done cautiously.

## Implementation notes (discovered during Phase 0-1)

- **The reactive harness already exists.** `printer_locality_report(doc, proj,
  mutate!)` (`package/projectured/test/editor/PrinterLocalityTest.jl`) prints once,
  holds the iomap + output, runs an arbitrary `mutate!`, re-forces the *held*
  output, and diffs object identity — so it already tests "the change propagates
  through the held iomap without a re-print" (the invariant). Dimensions A
  (selection), B (value-edit → `lost==0`), C (structural insert → reconciliation)
  build on it. Phase 1 adds a thin helper for **content-correctness** (the held
  `iomap.output` reflects the driven change) + **iomap-identity**, since the
  locality dimensions measure minimality, not propagation of a *config* change.

- **`SimpleIoMap → @iomap` ripples to the `.output[]` convention.** Some
  projections store a `Cell` in `output` (`TextToString: SimpleIoMap(p, ts, Cell(()
  -> …))`) and ~17 sites deref `iomap.output[]` (TextToString, ObjectToSyntax, sql/
  text pipeline & test sites, ClipboardToAnyTest). Under `@iomap`, `iomap.output`
  auto-unwraps to the *value*, so `.output[]` → `.output` at every site whose
  terminal iomap is converted. Chaining needs no change — its synthesized `.output`
  forwards `step_iomaps[end][].output`, which becomes the value once the last stage
  is `@iomap`. Convert per-iomap and run the full stack to catch the ripple; not the
  clean isolated step first assumed.

- **Focusing conversion specifics.** `@projection` and **drop the redundant
  `part_evaluator::Function`** (a Function field becomes a computed thunk under
  `@cell_struct` — AR-NO-NESTED-CELL); compute `evaluate_reference(input, p.part)`
  directly, and wire `output = Cell(() -> evaluate_reference(input, p.part))` so a
  `part`-cell write re-derives it. Depends on `SimpleIoMap` being `@iomap` first.

## Verification (every phase)
- Targeted printer/reader tests for converted projections stay green.
- The new **reactive test** per converted projection (change → propagation +
  identity).
- Layering guards green; full-stack json/domain sweep after each group;
  `test_all` only at the end.
- **Performance**: spot-check per-frame counters (reads/computes/invalidations/
  writes) on a heavy example (workbench) after Phases 4-6 — the refactor adds
  cells; watch for recompute blow-ups (AR-PROFILE-WITH-COUNTERS). Keep top-level
  derivations reading only *structural* cells (values flow through inner cells),
  as the template does.

## Risks & mitigations
- **Reconciliation correctness** (stale/duplicate/mis-keyed children) → reuse the
  proven `_reconciling_child_iomaps`; the Phase-0 harness is the guard.
- **Test gap** → harness first; no projection converted without a reactive test.
- **Performance** (cells per node) → counters; structural-only top-level reads.
- **AR-NO-NESTED-CELL** (Cell-valued outputs, e.g. Chaining's) → box with
  `Cell(f; as_value=true)`; never `@iomap`-auto-wrap a field whose logical value is
  itself a Cell.
- **`@iomap` access-site audit** (decision 1): converting a reactive IoMap flips
  `iomap.field` from the Cell to its value, so every `iomap.<cell>[]` read must be
  rewritten. Blast radius is the ~19 reactive IoMaps and their reader/mapper call
  sites (`iomap.child_iomaps[]`, `iomap.segs[]`, …). Do it per-IoMap with tests, not
  wholesale; grep each IoMap's `.field[]` uses before converting.
- **Blast radius** (~50 IoMaps, ~40 projections, 4 packages) → land phase-by-phase,
  each green; the template majority already conforms.
- **Editor semantics** → Phase 7 only, never remove a whole-root drop.

## Decisions (locked)

1. **Adopt `@iomap` for every IoMap** (uniformity) — all 52 structs, plus
   `@projection` on every projection (finishing 179 → all). Caveat now *in scope*,
   not a reason to skip: for the 19 reactive IoMaps, `@iomap`'s transparent access
   flips `iomap.field` from *the Cell* to *its value*, so every `iomap.child_iomaps[]`
   / `iomap.<cell>[]` site is audited and rewritten to `iomap.field` (value) or
   `getfield(iomap, :field)` (raw cell, where a consumer genuinely shares/subscribes).
   Done per-IoMap alongside its projection's conversion — never a blanket sweep that
   breaks access sites en masse.
   **Confirmed after impl found the cost:** `ChildrenIoMap` alone is ~150
   `.child_iomaps[]` sites across every package, entangled with `RuleIoMap`; the
   full sweep is still chosen, sequenced *after* the reactive harness exists.
2. **Accessors return the value, uniformly.** `get_iomap_output` / `_input` /
   `_projection` change off raw `getfield` so a consumer never sees a bare `Cell`;
   the deliberately-Cell-valued outputs (Chaining) are handled explicitly.
3. **Convert every hand-written projection** — the full uniform invariant, enforced
   by the new AR rule. (Template-driven domain projections already conform; the real
   surface is the ~82 plain + ~44 widget composites.) Any phase remains a safe
   stopping point.
4. **Hold the iomap-layer seal** until Phases 0-1 settle `IoMapDefaults.jl`
   (`@iomap` adoption + accessor change), then re-audit + seal. (It was audit-clean
   and ready; the seal waits, it is not abandoned.)

Remaining sub-decision (Phase 0): home + names for the promoted reconciliation helpers.

## Scope, sharpened by the survey

The gap is **not** a blanket "eager vs reactive." Most output *containers* are built
once (stable identity already) with reactive innards wired by `set_cell_function!`
(156 uses). The real defects are three narrower kinds:

1. **Config-change edges missing** — a projection parameter has no reactive edge
   to its output (Focusing's `part`; any `mutable struct` projection field mutated
   by an operation). Fix: `@projection` + derive output/children from the param cells.
2. **Write-once children** — child IoMaps boxed in a plain `Cell([...])` that never
   reacts to a structural input change (the widget-graphics composites in
   `WidgetToGraphics.jl`; grid layout). Fix: computed `Cell(() -> …)` + reconcile.
3. **Child-identity loss** — `Cell(() -> [rebuild all children])` reacts, but
   rebuilds every child each recompute (no reconciliation), so child IoMap identity
   is lost. Fix: route through the shared reconciler.

Only the 73 `@projection_template` domain projections and the template's own nodes
avoid all three today (they use `_reconciling_child_iomaps`).

## Inventory (from survey)

**Projections — 261 total** (179 `@projection`, 82 plain `<: Projection`):
- **kernel** 0 (machinery only).
- **base** 17, *all plain* — the hand-written generic + higher-order projections in
  `base/main/projection/`: Identity, Constant, Reversing, **Focusing** (mutable),
  Filtering, Sorting, Searching, Copying, Dragging, Recursive, Nesting, **Chaining**,
  Switching, ReferenceDispatching, PredicateDispatching, TypeDispatching,
  WindowInputUnwrapping. **These are Phases 2-3 + 6.**
- **visual** 95 (60 `@projection`, 35 plain). The 60 macro-form cluster in
  `widget/WidgetToGraphics.jl` (~44 — the write-once-children composites, gap #2).
- **domain** 149 (119 `@projection`, 30 plain). The 119 are almost all `*ToSyntax`
  leaf/node projections driven by `@projection_template` (73 uses) → already conform.
  The 30 plain are the real targets: `workbench/WorkbenchToWidget.jl` (10),
  `conversation/*` (7), `dbcatalog/DbCatalogToSql.jl` (5), `graph/*` (2), + singles.

**IoMaps — 52 total, all plain `struct <: IoMap`, none use `@iomap`.** 19 carry
`::Cell`/`::Vector{Cell}` fields (already partly reactive, via explicit Cell fields —
not `@iomap`); 33 all-plain. Only 2 override `getproperty`: `ChainingProjectionIoMap`
(`base/…/Chaining.jl:35`, synthesized `.output`) and `VersioningToAnyProjectionIoMap`
(`domain/…/VersioningToAny.jl:96`, derived `.output`).

**Reconciliation:**
- Shared-but-private: `_reconciling_child_iomaps` (keyed `(objectid, index)`) and
  `_reconciling_child_iomap` (single child by objectid) in
  `ProjectionTemplate.jl:447/479` → **promote these in Phase 0.**
- Ad-hoc reimplementations to consider unifying: `SyntaxToText.jl:536` (`IdDict`
  child cache), `SyntaxToText.jl` `_DecoCache`, `TextToGraphics.jl:295/534`
  (per-row overlay cache), `HoverProbe.jl` (single-slot reuse).
- **Existing contract test**: `package/projectured/test/editor/PrinterLocalityTest.jl`
  (lines ~405-450) already asserts "keyed reconciliation reuses each prior child" and
  warns on structural loss → **the seed of the Phase-0 reactive harness.**

**Macros:** `@projection` (`Projection.jl:229`), `@iomap` (`IoMapDefaults.jl:72`,
unused), `@projection_template` (`ProjectionTemplate.jl:1435`, 73 domain uses).
