# Layout Extensions

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

## Context

The core layout family — `HorizontalLayout`, `VerticalLayout`, `GridLayout`,
`FlowLayout` — already shipped (see
[../done/layout-documents.md](../done/layout-documents.md)). It is implemented
as a `LayoutDocument` family in `program/src/document/Layout.jl` with the
matching `…LayoutToGraphicsCanvas` projections in
`program/src/projection/primitive/LayoutToGraphics.jl`. Layouts are
content-driven documents whose projections *recurse-then-measure*: project each
child to a `GraphicsCanvas`, read its reactive `w`/`h`, and compute positions
as computed cells.

This plan collects the layout ideas that the shipped plan deliberately did
**not** cover. They are reframed to build on the existing `LayoutDocument`
family rather than the originally proposed (and abandoned) "domain-preserving
`GraphicsCanvas → GraphicsCanvas` projection" approach.

Remaining work:

1. **`StackLayout`** — z-ordered overlays / badges.
2. **`ConstraintLayout`** — constraint-solved free-form arrangement (deferred).
3. **Migrate existing positioners** — fold `TableToGraphics` and the widget
   containers onto the layout family (optional).
4. **Future ideas** — layout debug overlay, `ProjectionContext` integration,
   animation.

---

## 1. StackLayout

A new `LayoutDocument` that lays children on top of each other (z-order =
child order). Used for overlays, badges, and composing
background/foreground (e.g. a cursor rect over text, a count badge over an
icon).

```julia
@document struct StackLayout <: LayoutDocument
    children::CellVector       # element type: Document; first = bottom
    horizontal_align::Symbol   # :left, :center, :right
    vertical_align::Symbol     # :top, :center, :bottom
    selection::Reference
end
```

Projection `StackLayoutToGraphicsCanvas`:

- Recurse into each child to obtain its canvas (same pattern as the other
  layouts).
- All children share the same origin region. Outer `w`/`h` are computed
  cells = max of children's `w`/`h`.
- Per-child `(x, y)` derived from `horizontal_align` / `vertical_align`
  against the outer extent.
- Hit-testing must scan **all** children (they overlap by definition);
  iterate in reverse so the top-most child shadows the ones beneath it.

This is the only proposed layout where the non-overlapping invariant does
not hold, so the output canvas's `overlapping_elements` must be `true` and
no axis early-stop applies.

---

## 2. ConstraintLayout (deferred)

The eventual end-state for arbitrary arrangements (dashboards, free-form
document layout). Each child carries constraints relating its edges to
siblings or to the parent; a solver computes positions satisfying them.

Initial scope, if/when pursued:

- A subset of constraints: per-edge equality/inequality against another
  element's edge, plus min/max sizing.
- A naive relaxation solver (Gauss-Seidel-style, iterate to convergence or
  a max-iteration cap) to validate the design. Cassowary / incremental
  simplex can come later if the naive solver is too slow.

This is **optional and deferred** — pursue only when a concrete use case
(dashboard editor, free-form layout) demands the generality. It does not fit
the recurse-then-measure pattern cleanly: a constraint solver wants a
measure pass and an arrange pass, so it would need either a two-pass
projection or an iterative cell fixpoint. Treat that as part of the design
work, not a given.

---

## 3. Migrate existing positioners (optional)

Several projections still re-implement their own positioning math. They
could become thin compositions over the shipped layout documents:

- `program/src/projection/primitive/TableToGraphics.jl` — the inline grid
  arithmetic overlaps `GridLayout`. Reimplement as: project cells, compose
  with `GridLayout`. The `ChildrenIoMap` shape stays compatible.
- `program/src/projection/primitive/WidgetToGraphics.jl` —
  `WidgetCompositeToGraphicsCanvas`, `WidgetShellToGraphicsCanvas`,
  `WidgetSplitPaneToGraphicsCanvas`, etc. each position children manually.
  The *intrinsic* ones could delegate to `HorizontalLayout` /
  `VerticalLayout` / `StackLayout`; the *parent-bounded split* case belongs
  to the widget-layout plan ([../pending/widget-layout.md](../pending/widget-layout.md))
  instead.

Migration is **incremental and low-priority** — do one positioner at a time
and only if the duplication actually hurts. The existing implementations
work; the win is consolidation, not new capability. Validate
selection / hit-testing / rendering after each migration.

---

## Future ideas / open questions

- **Layout debug overlay.** A debug projection that paints layout cell
  boundaries (grid lines, gutters, padding regions) over the output canvas,
  like a CSS dev-tools "show layout" mode. Cheap, useful for the
  developer-experience track.
- **`ProjectionContext` integration.** *Shipped.* `ProjectionContext` lives
  at `program/src/context/ProjectionContext.jl` and threads
  `available_width` / `available_height` to children via `child_context` /
  `with_available_size`. Already consumed by `WidgetToGraphics` and the
  word-wrapping path. Layout documents themselves do not yet push available
  size to their children — that hookup remains, and would unlock a
  "content-aware" two-pass layout.
- **Animation / transitions.** None of the layouts tween between
  configurations (e.g. an element sliding from one row to another when its
  sort key changes). Would need a separate interpolating layer; out of
  scope.
- **Baseline alignment.** Current cross-axis alignment is by box edges only.
  Text-heavy rows might want baseline alignment; needs font-baseline metadata
  threaded through `GraphicsText`.

---

## Summary

The four core layouts shipped as `LayoutDocument`s. What remains is additive:
a `StackLayout` for overlays, an optional `ConstraintLayout` for free-form
arrangement, optional migration of `TableToGraphics` and widget containers
onto the layout family, and a handful of developer-experience / future
features (debug overlay, `ProjectionContext` integration, animation). None of
these are blocking; `StackLayout` is the only near-term candidate.
