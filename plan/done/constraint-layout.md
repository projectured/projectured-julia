# Constraint Layout

> **Status: ✅ DONE — verified green 2026-06-28.** All seven implementation steps
> are written, with the solver dependency **extracted into a separate opt-in
> package** (see "Packaging" below) so core `ProjecturedDomain` stays
> dependency-free. The pending verification has now run clean (see "Verification
> result" below).
>
> - `ConstraintLayout`, `LayoutRelation`, `LayoutAnchor` + the `anchor`/`constrain`
>   DSL — `package/domain/src/document/Layout.jl`.
> - The solver **seam** (`SolverAnchor`/`SolverRelation`, abstract
>   `ConstraintSolver`, `solve_constraint_layout` generic, dependency-free
>   `FallbackConstraintSolver`) — `package/domain/src/document/ConstraintSolver.jl`.
>   **No `Tulip`/`MOI` in core.**
> - `ConstraintLayoutToGraphicsCanvas` (with a `solver::ConstraintSolver` field,
>   default `FallbackConstraintSolver`) —
>   `package/domain/src/projection/primitive/LayoutToGraphics.jl`.
> - The **LP solver** `TulipConstraintSolver` (goal-programming over
>   `MathOptInterface` + `Tulip`) — new package `package/tulip/`
>   (`ProjecturedTulip`), which adds a `solve_constraint_layout` method to the
>   core seam. Mirrors `ProjecturedAdaptagrams`/`AdaptagramsEngine`.
> - Examples: core `constraint_layout` (fallback solver, in the core sweep) +
>   `constraint_layout_tulip` (real solver) in `ProjecturedExtrasExample`.
> - Tests: `test_constraint_solver` (in `ProjecturedTest`, which now depends on
>   `ProjecturedTulip`) covers both the fallback and the Tulip solver.
>
> **Packaging.** Core domain has zero heavy deps; the constraint layout works
> out of the box (degraded: children stack at the origin) and upgrades to real
> solving by loading `ProjecturedTulip` and passing
> `ConstraintLayoutToGraphicsCanvas(solver = TulipConstraintSolver())` — the same
> dependency-injection pattern as `GraphGraphToGraphLayout(engine = AdaptagramsEngine())`.
>
> **Verification result (2026-06-28).** Tulip/MOI resolve and precompile cleanly;
> `test_constraint_solver()` (fallback + Tulip: equality pinning, inequality
> min-size, fill, soft centering, infeasible-falls-back-no-throw, empty) and
> `test_layout_constraint_helpers()` are all green; `constraint_layout` printer
> 872 / reader 225 green; and `constraint_layout_tulip` printer 872 green — the
> real Tulip LP solver prints end-to-end. (`test_example` was not used for the
> examples because `constraint_layout` is on the text-navigation exclusion list;
> printer + reader were run instead.)

Add a `ConstraintLayout` document type whose children are positioned by solving
a system of **linear equality/inequality constraints** over their edges, using
an existing constraint/LP solver rather than a hand-rolled positioner. This is
the free-form / dashboard layout end-state deferred from the shipped layout
family ([layout-extensions.md §2](../tentative/layout-extensions.md#2-constraintlayout-deferred)).

## Context

The shipped layouts — `HorizontalLayout`, `VerticalLayout`, `GridLayout`,
`FlowLayout`, `StackLayout` (`package/domain/src/document/Layout.jl`) — each
encode **one fixed positioning policy**. Their projections in
`package/domain/src/projection/primitive/LayoutToGraphics.jl` all follow the
same *recurse-then-measure* shape: project each child to a `GraphicsCanvas`,
read its reactive `w`/`h`, then compute each child's `(x, y)` and the outer
`w`/`h` as computed `Cell`s (see `_hl_build` at `LayoutToGraphics.jl:400` for
the canonical example). No solver is involved; positions are closed-form
arithmetic.

`ConstraintLayout` generalizes this to *arbitrary* arrangements: each child
declares **relations between its edges** and sibling/parent edges (e.g. "my
left = panel A's right + 8", "my width ≥ 120", "center me in the parent"). A
solver finds positions satisfying the hard constraints while minimizing
violation of the soft ones. This is what Apple Auto Layout, Qt's
`QGraphicsAnchorLayout`, and CSS-grid-with-constraints all do underneath, and
it is the natural fit for dashboards, free-form document canvases, and diagram
node placement.

The key architectural tension (already flagged in the deferred note): the
shipped layouts are *single-pass* (measure → arrange in one closed-form sweep),
but a constraint solver wants a **measure pass and a separate arrange pass** —
measure children to learn their intrinsic `w`/`h`, feed those as constants into
the constraint system, solve, then place. This plan resolves that by keeping
the recurse-to-measure phase identical to the other layouts and inserting a
single `solve` step between measure and arrange, wrapped in one reactive `build`
cell so the whole solve re-runs lazily when any child's extent or any constraint
changes.

### Naming

`LayoutConstraint` is **already taken** (`Layout.jl:207`) — it is the per-child
*sizing-policy* wrapper (`min/preferred/max/weight` per axis) consumed by the
existing flex layouts via `allocate_axis`. To avoid collision, this plan uses:

- `ConstraintLayout` — the new layout container document.
- `LayoutRelation` — one linear edge-to-edge constraint.
- `LayoutAnchor` — a `(child, edge)` handle naming a solver variable.

## Library decision (use an existing solver)

**Landscape (verified 2026-06-24):** There is **no maintained Julia port of
Cassowary/Kiwi** in the General registry. Cassowary itself (Badros/Borning) is
the canonical *algorithm* for UI layout — incremental simplex over linear
equalities/inequalities with a **strength hierarchy** (`required` ≫ `strong` ≫
`medium` ≫ `weak`) and *edit variables* for cheap re-solve on drag. The widely
used implementation is the C++ **kiwi** (`nucleic/kiwi`), with no Julia
binding.

What *is* available off-the-shelf in Julia is general **linear-programming**
solvers reachable through `MathOptInterface` (MOI):

- **Tulip.jl** — pure-Julia interior-point LP solver, MOI-compatible. No native
  binary, fits this repo's lean-dependency posture (only SDL/ODBC are native
  today).
- **HiGHS.jl** — best-in-class open-source LP/MIP (C, precompiled via
  `HiGHS_jll`); fastest, drop-in via the same MOI interface.
- `Clp.jl`, `GLPK.jl` — older C alternatives.

A UI layout problem maps cleanly onto an LP via **goal programming**:

- **Hard constraints** (`required`) → LP equality/inequality rows.
- **Soft constraints** (strong/medium/weak) → introduce non-negative slack
  variables `s⁺, s⁻` per soft relation, add `lhs − rhs = s⁺ − s⁻`, and
  **minimize a weighted sum** `Σ wₖ (s⁺ₖ + s⁻ₖ)` where `wₖ` encodes strength
  (e.g. weak=1, medium=1e3, strong=1e6). This reproduces Cassowary's
  prioritized least-violation behaviour with a single LP solve. (Exact
  lexicographic priority would need staged solves; the weighted approximation
  is standard and sufficient for v1.)

**Recommendation:**

- **Primary: `Tulip.jl` accessed through `MathOptInterface`** (not full JuMP —
  MOI directly keeps per-solve overhead low for the tiny, frequently-re-solved
  systems layout produces, typically 4·n + parent variables for n children).
  Pure Julia, no new native dependency.
- **Performance fallback: `HiGHS.jl`** — identical MOI calling code, swap the
  optimizer factory if Tulip's interior-point latency is too high on large
  dashboards. Make the optimizer pluggable (a field/const) so this is a
  one-line change.
- **Long-term, if incremental re-solve latency matters** (live dragging of
  constrained elements): vendor a minimal **Cassowary/kiwi** implementation to
  get O(Δ) edit-variable re-solves instead of O(full LP) per frame. Recorded as
  a Future Extension, **not** v1 scope.

> **Decision point for the maintainer:** confirm Tulip-via-MOI as the primary
> dependency before Phase 2. The alternative — HiGHS for raw speed at the cost
> of a native `_jll` — is a one-field swap and does not change the rest of this
> plan. Everything below is written against the MOI abstraction so it is
> solver-agnostic.

## Phase 1: Document types

### File: `package/domain/src/document/Layout.jl`

Add to `LayoutModule`, mirroring the conventions of the existing layout structs
(`@document struct`, `CellVector` children, `selection::Reference`, positional
constructor + keyword convenience constructor).

```julia
# An edge of a child (or of the parent container).
# child::Int is the 1-based index into ConstraintLayout.children,
# or 0 to denote the parent container itself.
@document struct LayoutAnchor <: Document
    child::Int                  # 0 = parent container
    edge::Symbol                # :left, :right, :top, :bottom, :width, :height,
                                #  :centerx, :centery
    selection::Reference
end

# One linear relation:  scale * anchor + constant  (op)  rhs_expr
# Represented in the normalized form the solver consumes:
#   Σ coeff_i * var_i  (op)  constant
@document struct LayoutRelation <: Document
    terms::CellVector           # of (LayoutAnchor, coefficient::Float64)
    op::Symbol                  # :(==), :(<=), :(>=)
    constant::Float64
    strength::Symbol            # :required, :strong, :medium, :weak
    selection::Reference
end

@document struct ConstraintLayout <: LayoutDocument
    children::CellVector        # of arbitrary Document (the positioned content)
    relations::CellVector       # of LayoutRelation
    bounding_width::Int         # parent container width  (parent :width)
    bounding_height::Int        # parent container height (parent :height)
    selection::Reference
end
```

**Design notes**

- `LayoutAnchor`/`LayoutRelation` are *documents* (not plain structs) so the
  constraint system itself is editable/selectable/projectable like everything
  else in ProjecturEd — you can later build a visual constraint editor for free.
- `terms` is a list so a relation can reference several anchors
  (`a.left == b.right` is `1·a.left + (−1)·b.right == 0`); `:centerx` etc. are
  *derived* anchors expanded during assembly (`centerx = left + width/2`), they
  are not independent variables.
- Per-child intrinsic size enters as **constants** (from the measure pass), not
  variables — unless a relation constrains `:width`/`:height`, in which case
  those become free variables seeded by a `weak` stay-constraint at the
  intrinsic value (Cassowary's "stay" idea, expressed as a weak soft equality).
- `bounding_width`/`bounding_height` fix the parent's `:right`/`:bottom`
  (parent `:left`/`:top` pinned to 0) so constraints can reference the
  container.

Provide a small **DSL** for authoring relations ergonomically, so examples and
tests read well — e.g. `anchor(2, :left) == anchor(1, :right) + 8` building a
`LayoutRelation`. Implemented as helper functions/operators in the module
(kept out of the struct definitions).

Export: `ConstraintLayout`, `LayoutRelation`, `LayoutAnchor`,
`IConstraintLayout`, `ILayoutRelation`, `ILayoutAnchor`, plus the DSL helpers.

## Phase 2: The solver bridge (pure, no reactive cells)

### File: `package/domain/src/document/ConstraintSolver.jl` (new)

A pure module that knows nothing about cells, projections, or graphics — it
takes plain numbers and returns plain numbers, exactly like `allocate_axis` is
pure today. This keeps the solver dependency isolated and unit-testable in
`LayoutAllocatorTest`-style tests.

```julia
"""
    solve_constraint_layout(n, intrinsic_w, intrinsic_h, relations,
                            bounding_w, bounding_h; optimizer) -> Vector{NTuple{4,Int}}

Pure solve. Builds one MOI model:
  variables: per child i → left_i, top_i, width_i, height_i  (+ parent fixed)
  for each relation → an LP row; soft relations add slack vars + objective terms.
Returns one (x, y, w, h) Int rect per child (rounded). Returns the intrinsic
fallback layout if the system is infeasible (logged), so the editor never
crashes on a bad constraint set.
"""
```

Steps inside:

1. Allocate variables: `4·n` child edge variables + parent edges as fixed
   constants (`0, 0, bounding_w, bounding_h`).
2. **Stay constraints** (weak): `width_i == intrinsic_w[i]`,
   `height_i == intrinsic_h[i]`, and a weak anchor on `left_i`/`top_i` toward 0
   so the system is fully determined even when relations under-constrain a
   child.
3. Expand derived edges: `right_i = left_i + width_i`, `bottom_i = top_i +
   height_i`, `centerx_i = left_i + 0.5·width_i`, etc. (substitution, not new
   variables).
4. Translate each `LayoutRelation` into an MOI `ScalarAffineFunction` row with
   the appropriate `EqualTo`/`LessThan`/`GreaterThan` set; soft ones get slack
   variables and weighted objective contributions per the goal-programming
   scheme above.
5. Optionally add implicit **non-negativity / containment** bounds
   (`left_i ≥ 0`, `right_i ≤ bounding_w`) as `required` — make this a flag so
   off-canvas placement is possible when desired.
6. `optimize!`, read the solution, round to `Int`.

`optimizer` defaults to a module-level `const DEFAULT_OPTIMIZER = Tulip.Optimizer`
(swap to `HiGHS.Optimizer` to benchmark) — passed in so tests can inject a
deterministic optimizer.

### Dependency wiring

- Add `Tulip` (and `MathOptInterface`) to the `[deps]` of the package that owns
  `domain` (`package/projectured/Project.toml` — confirm which `Project.toml`
  compiles `package/domain/src`) and `[compat]` bounds.
- `import` MOI inside `ConstraintSolver.jl`; `include` the new file from the
  domain package's top-level module next to the other `document/*.jl` includes.

## Phase 3: ConstraintLayout → GraphicsCanvas projection

### File: `package/domain/src/projection/primitive/LayoutToGraphics.jl`

Add `struct ConstraintLayoutToGraphicsCanvas <: Projection end` and follow the
`_hl_build` / `projection_print` template exactly (`LayoutToGraphics.jl:400`,
`:461`):

`_cl_build(recursion, doc, ctx)`:

1. **Measure (recurse).** For each child, `child_context` + `_recurse_child`
   (strip `available_width`/`available_height` to avoid the feedback loop the
   other layouts guard against — see the comment at `LayoutToGraphics.jl:405`),
   collecting `child_iomaps`.
2. Build a single `solve` `Cell` that:
   - reads each child's intrinsic `w`/`h` via `_child_w`/`_child_h`
     (`:226`/`:232`),
   - reads `doc.relations` (so structural constraint edits re-run the solve),
   - reads `doc.bounding_width`/`bounding_height`,
   - calls `solve_constraint_layout(...)` and returns the `Vector` of rects.
3. Per-child `child_x[i]`/`child_y[i]` become computed `Cell`s reading
   `solve[][i]`. Where a relation drove `:width`/`:height`, the solver's size
   is applied by wrapping with size-override (the canvas `w`/`h` cells stay the
   child's own unless the layout owns sizing — v1: position-only override, sizes
   from the solve are advisory; **decide in Phase 3** whether to also override
   child canvas extent, which the existing layouts do *not* do).
4. `_wrap_child` each child canvas at its solved `(x, y)` (`:108`).
5. Outer `w`/`h` = `bounding_width`/`bounding_height` (the container is
   extrinsically sized, unlike the intrinsic layouts) — or max child extent if
   bounding dims are 0.
6. Return `(wrapped, w, h, entries)`, and build the outer `GraphicsCanvas` +
   `ChildrenIoMap` exactly like `projection_print(::HorizontalLayoutToGraphicsCanvas, …)`.

**`overlapping_elements`:** constraints can place children anywhere, including
overlapping, so the outer canvas must set `overlapping_elements = true` (like
`StackLayout`) — hit-testing scans all children, no axis early-stop.

**`projection_read`:** reuse `_route_layout_event(iomap, evt)` (`:197`) — the
shared edit-transparent router already handles `ChildrenIoMap`. Because children
overlap, ensure the router scans all entries (mirror `StackLayout`'s reverse
scan at `:1012` if topmost-wins is desired).

**`map_reference_forward`/`backward`:** delegate to `_children_forward`
(`:311`) / `nothing`, identical to `HorizontalLayout` (`:472`).

## Phase 4: Factory + exports

### File: `package/domain/src/projection/primitive/LayoutToGraphics.jl`

- Add to the `export` list and to the `LayoutToGraphics()` `TypeDispatchingProjection`
  table (`:1110`): `ConstraintLayout => ConstraintLayoutToGraphicsCanvas()`.

### File: domain package top-level module (where `Layout.jl` is `include`d)

- `include("document/ConstraintSolver.jl")` before `document/Layout.jl` (Layout
  uses the solver) and re-export the new symbols.

### File: `package/projectured/src/Projectured.jl` (or the umbrella that re-exports)

- Re-export `ConstraintLayout`, `LayoutRelation`, `LayoutAnchor`, the DSL
  helpers, and `ConstraintLayoutToGraphicsCanvas`, following the existing
  layout re-exports.

## Phase 5: Example

### Files: `package/example/src/document/Layout.jl`, `package/example/src/projection/Layout.jl`, `package/example/src/Examples.jl`

- `make_constraint_layout_document_example` — a small dashboard: a header
  pinned to the top spanning full width, a sidebar pinned left at fixed width,
  a main panel filling the remainder (`main.left == sidebar.right + 8`,
  `main.right == parent.right`, `main.top == header.bottom + 8`), and a footer
  centered horizontally. This shows equality (pinning), inequality (min sizes),
  and soft centering in one figure.
- `make_constraint_layout_projection_example` — same dispatcher shape as
  `make_layout_projection_example` (`projection/Layout.jl:9`), adding
  `ConstraintLayout => ConstraintLayoutToGraphicsCanvas()` to the
  `RecursiveProjection(TypeDispatchingProjection(...))`.
- Register `const constraint_layout_example = Example("constraint_layout",
  make_constraint_layout_document_example, make_constraint_layout_projection_example)`
  in `Examples.jl` (next to `layout_example` at `:70`) and add it to the
  `export`/example lists so `run_example("constraint_layout")`,
  `print_example`, and the test sweeps pick it up.

## Phase 6: Tests

### File: `package/test/src/document/ConstraintSolverTest.jl` (new, mirrors `LayoutAllocatorTest.jl`)

Pure-solver unit tests — no cells, no projection, fast and deterministic
(inject the optimizer):

- equality pinning: `b.left == a.right + 8` ⇒ exact offset.
- inequality min-size: `width ≥ 120` honoured; with a competing soft pull, the
  hard min wins.
- fill-remaining: sidebar fixed + main `right == parent.right` ⇒ main width =
  bounding_w − sidebar − gap.
- soft centering: weak `centerx == parent.centerx` satisfied when unconstrained,
  yields to a hard constraint when they conflict.
- infeasible system ⇒ falls back to intrinsic layout, no throw.

### Standard example coverage

- `test_printer(constraint_layout_example)` — projection produces a canvas with
  correctly positioned child rects.
- `test_reader(constraint_layout_example)` and
  `test_text_navigation(constraint_layout_example)` — selection/navigation
  round-trips through the new `ChildrenIoMap` (reuses the shared layout router,
  so this is mostly a smoke test that wiring is correct).
- `test_example(constraint_layout_example)` for all three at once.

Per `CLAUDE.md`, run the narrow `test_*` for the new example plus
`test_layout_allocator`-adjacent `ConstraintSolverTest`; only sweep
`test_printers()`/`test_readers()` after the targeted tests pass.

## Implementation Steps

1. ✅ DONE — Solver dependency confirmed by the maintainer: **Tulip-via-MOI**
   (the plan's primary pick), but **isolated in a separate opt-in package**
   `ProjecturedTulip` (`package/tulip/`) rather than added to core — core
   `ProjecturedDomain` keeps zero heavy deps. `Tulip = "0.9"` /
   `MathOptInterface = "1"` live in `package/tulip/Project.toml`.
2. ✅ DONE — `LayoutAnchor`, `LayoutRelation`, `ConstraintLayout` document types
   + the `anchor`/`constrain` DSL (with a plain `LayoutExpr` affine layer; `==`
   / `<=` / `>=` intentionally *not* overloaded to preserve `@document`
   identity equality) in `package/domain/src/document/Layout.jl`.
3. ✅ DONE — Solver **seam** in core
   `package/domain/src/document/ConstraintSolver.jl` (plain `SolverAnchor`/
   `SolverRelation`, abstract `ConstraintSolver`, `solve_constraint_layout`
   generic, dependency-free `FallbackConstraintSolver`). The goal-programming LP
   (`TulipConstraintSolver`: hard rows + slack-penalized soft rows, weak
   intrinsic/origin stays, intrinsic fallback on infeasible/throw) lives in
   `package/tulip/src/ProjecturedTulip.jl` and adds a `solve_constraint_layout`
   method to the seam.
4. ✅ DONE — `ConstraintLayoutToGraphicsCanvas` (`_cl_build` + single `solve`
   cell + `projection_print` + stack-style read + `_children_forward`) in
   `LayoutToGraphics.jl`. **Two-pass size override** implemented (open question
   below): solved sizes are applied via re-projection with available size, not
   just advisory.
5. ✅ DONE — Factory entry (`ConstraintLayout => ConstraintLayoutToGraphicsCanvas()`),
   `include("document/ConstraintSolver.jl")` before `Layout.jl`; umbrella
   re-exports are mechanical (driven by the module `export` lists). New package
   `ProjecturedTulip` wired into the root `Project.toml` `[deps]` + `[sources]`.
6. ✅ DONE — `constraint_layout` example (dashboard: header / sidebar / main /
   footer) document in `package/example/src/document/Layout.jl`; the core
   projection (`make_constraint_layout_projection_example`) takes a `solver`
   kwarg defaulting to `FallbackConstraintSolver`, so `constraint_layout_example`
   stays in the core sweep. The real-solver `constraint_layout_tulip` example
   (`solver = TulipConstraintSolver()`) lives in `ProjecturedExtrasExample`,
   alongside `graph_adaptagrams`.
7. ✅ DONE — `package/test/src/document/ConstraintSolverTest.jl`
   (`test_constraint_solver`: pinning, min-size, fill-remaining, soft centering,
   infeasible fallback, empty) registered in `ProjecturedTest.jl`; the example
   is in the `examples` list so the printer/reader/navigation sweeps pick it up.

> **⚠ All of the above is written but UNVERIFIED** — see the audit-status note
> at the top. Run `Pkg.resolve()` then the targeted tests before marking this
> plan done and moving it to `plan/done/`.

## Open questions / risks

- **Does the layout own child sizing?** *Implemented — the recommended
  end-state.* `ConstraintLayoutToGraphicsCanvas` is now **two-pass**: pass 1
  measures every child with available size stripped (cycle-free intrinsics that
  feed the solve); pass 2 re-projects each child whose size axis a relation
  *explicitly* constrains (references its `:width`/`:right`/`:centerx` for x, or
  `:height`/`:bottom`/`:centery` for y — see `_cl_size_constrained`), handing it
  the solved extent as its available size so content that honors available size
  reflows to fill. The available cells read `solve`, which depends only on the
  measure pass, so it is cycle-free and a resize propagates without
  re-projection. Children with no size axis constrained reuse the measure pass
  unchanged. Children whose projection ignores available size simply keep their
  intrinsic draw extent inside the solved box (no reflow, no error).
- **Reactive granularity.** v1 re-solves the *entire* LP whenever any child
  extent or any relation changes (one `solve` cell). Fine for tens of children;
  for large dashboards or live dragging this is the latency bottleneck — see
  the incremental Future Extension.
- **Cycle/feedback safety.** Constraints can reference any edge; the solver
  itself handles cyclic *constraints* (that's its job), but the *reactive*
  graph must not loop: keep children measured with `available_*` stripped (as
  the existing layouts do) so child extents never read the layout's solved
  output.
- **Determinism.** Interior-point solvers can return slightly different optima
  for degenerate (under-constrained) systems; the weak stay-constraints make
  the solution unique enough for stable rendering, but pin tests to tolerances,
  not exact pixels.
- **Strength model.** The weighted-objective approximation of Cassowary's
  lexicographic strengths can let many weak constraints outvote one medium if
  weights are mis-scaled. Use well-separated magnitudes (weak=1, medium=1e3,
  strong=1e6) and document the limitation.

## Future extensions

- **Incremental re-solve (Cassowary edit variables).** Vendor a minimal kiwi
  port for O(Δ) re-solve on drag, replacing the batch LP `solve` cell. Biggest
  win for interactivity; largest effort.
- **Visual constraint editor.** Because relations are documents, project the
  constraint set itself (handles, arrows between anchored edges) so users edit
  layout constraints graphically — a natural ProjecturEd showcase.
- **Migrate positioners.** Once proven, `GridLayout`/widget split panes could be
  expressed as constraint sets, unifying the layout family (tracked separately
  in [layout-extensions.md §3](../tentative/layout-extensions.md#3-migrate-existing-positioners-optional)).
- **AnchoredLayout overlap.** The relative-positioning use cases in
  [anchored-layout.md](anchored-layout.md) are a constrained special case;
  evaluate whether `ConstraintLayout` subsumes it or stays complementary.
