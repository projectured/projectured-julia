# Rect borders, filled polygons, and point selection

Three follow-ups to the chart domain, two of which were deferred there.

## 1. A bordered rect must not tint its own interior

Both the SDL and PDF backends draw a bordered `GraphicsRect` as *a fill in the
border colour with the fill inset on top*. That is only correct when the fill is
opaque: a translucent fill composites against the border colour instead of
against whatever is behind the rect, so the whole shape takes the border's hue.
Reproduced on clean `main`, so it predates the chart work; the chart currently
works around it by never asking for the combination.

The fix is to paint the border as a **ring** — the outer shape minus the inset
one — rather than as a full fill under the interior:

- The straight (all radii zero) case is four edge rectangles.
- The rounded case needs the ring's scanline spans, which `_fill_corner_band!`
  already has the geometry for: for each device row, fill from the outer left
  edge to the inner left edge and from the inner right edge to the outer right.
- PDF can stroke `_rrect_path!` instead, inset by half the border width.
- The web canvas can `stroke()` the same rounded path it already builds.

An opaque fill must come out pixel-identical to today, since that is what every
existing widget uses.

- [ ] SDL, PDF and web draw the border as a ring
- [ ] A translucent fill shows the background, not the border colour
- [ ] `test_visual()` has no new failures

## 2. `GraphicsPolygon`

There is no filled-polygon primitive, which is why the chart's marker set stops
at the seven shapes the existing primitives draw exactly. Adding one unlocks the
diamond, triangle, pentagon and star markers OMNeT++ offers, and area fills
later.

`GraphicsPolygon(points, color; border_width, border_color)` — a closed filled
shape, the polygon counterpart of `GraphicsPolyline`.

- SDL fills via `SDL_RenderGeometry`. A triangle fan only covers convex shapes
  and a star is not convex, so the triangulation must be ear clipping over a
  simple polygon.
- PDF fills the path (`m`/`l`/`h`/`f`), and strokes it when a border is asked
  for.
- The web canvas fills and strokes the same path.
- `hit_element_at` needs a point-in-polygon branch, or the primitive is
  invisible to clicks; `graphics_size` needs its bounds.

- [ ] The primitive, its constructor and its documentation
- [ ] All three backends, plus hit-testing and bounds
- [ ] Chart markers: diamond, triangle up/down/left/right, pentagon, star

## 3. Point selection

A chart can select its title, either axis, its legend and any series, but not an
individual sample — the plan that built it deferred this because a data column
is a bare vector, and `AR-EVERY-DOCUMENT-HAS-SELECTION` says a selection-reachable
child should be a `Document`.

Wrapping every sample in a document is what the chart's data model exists to
avoid: a cell per sample costs about 88 bytes and buys nothing for the millions
of samples the domain is built to hold. So a sample is addressed the way a pixel
offset inside a rendered element already is — with a **reference step**, not a
child document. `PointReferenceStep` is the precedent: a `:structural` step that
names a position inside an otherwise opaque leaf and evaluates to the value at
that position.

`ChartSampleReferenceStep(index)` names sample *i* of a series and evaluates to
its `(x, y)` pair.

**Reachable by pointing, not by walking.** Clicking a data point selects it, and
the crosshair already snaps to the nearest sample. Arrow-key navigation
deliberately stays at part granularity: the navigation sweeps enumerate every
reachable selection state by BFS, so letting the keyboard walk into samples
would make a chart's state space its sample count — hundreds of reprints for the
registered examples, and unbounded in principle.

- [x] `ChartSampleReferenceStep`, registered with the reference DSL
- [x] Click on a data point selects that sample; the printer draws it
- [x] Navigation stays at part granularity, with the reason recorded
- [x] `chart.md` documents the step and why samples are not walked

Notes from implementing:
- The `@reference` DSL cannot parse a runtime type (`::t`) followed by an
  extension step, so a sample path is built structurally and typed by
  `annotate_reference_types`, which fills the sample node's own type from what
  `chart_sample` returns.
- The reader must emit **plot-rooted** paths — stage 1 peels its `chart` step
  off on the way back — so the chart-rooted sample path is prefixed rather than
  rebuilt.
- Snapping the crosshair used to scan every scatter point on each pointer move;
  it now declines a folded cloud, which also removes an O(n)-per-mouse-move
  cost that was already there.
