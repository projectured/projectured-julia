# Converge Tables on WidgetTable (one table, GridLayout does the layout)

Make **`WidgetTable` the single table abstraction**. Delete the `Table` domain
(`TableTable`/`TableRow`/`TableColumn`/`TableCell`) and its bespoke renderer
`TableToGraphics` — they duplicate grid math and carry no value once `WidgetTable`
absorbs their capabilities. `WidgetTable`'s renderer delegates **all positioning to
`GridLayout`** ("layout is just layout") and draws table decorations
(borders, rules, headers, selection bands) as an **overlay computed from grid
geometry read out of the GridLayout iomap**.

## Why

Three renderers re-derive the same grid arithmetic today
(`GridLayoutToGraphicsCanvas`, `TableTableToGraphicsCanvas`,
`WidgetTableToGraphicsCanvas`), even though `allocate_axis` is already a shared
allocator. The duplicated piece is the 2-D "max-width-per-column /
max-height-per-row + cumulative offsets" step plus the decoration drawing. This
plan removes the duplication by:

1. having exactly **one** grid layout engine (`GridLayout`), and
2. having exactly **one** table document (`WidgetTable`) whose renderer is a thin
   decoration overlay on top of that engine.

## Principles (from the decision)

- **Converge *into* `WidgetTable`.** It is the survivor; the `Table` domain is
  obsolete and removed (not the reverse).
- **Layout is just layout.** `GridLayout` only positions children — it draws no
  borders, rules, or headers. Decorations are the table renderer's job.
- **Read geometry from the iomap.** The renderer obtains `col_x` / `row_y` /
  `col_w` / `row_h` from the GridLayout iomap to place borders/rules and to turn a
  1-D axis selection handle (`rows[r]∅` / `columns[c]∅`) into a 2-D highlight band.

---

## Phase 1 — Expose grid geometry on the GridLayout iomap

### File: `program/src/projection/primitive/LayoutToGraphics.jl`

`GridLayoutToGraphicsCanvas` already computes `col_w`, `row_h`, `col_x`, `row_y`
cells internally (see `_gl_col_w_cell` / `_gl_col_x_cell` / …) but its
`ChildrenIoMap` only carries `(x_cell, y_cell, cim)` per child. Extend the iomap
so the geometry is readable by a parent renderer:

- Either add a `GridLayoutIoMap <: IoMap` (subtype/extension of `ChildrenIoMap`)
  carrying `col_x::Vector{Cell}`, `row_y::Vector{Cell}`, `col_w`, `row_h`,
  `columns::Cell`, `gaps`, and the outer `w/h` cells; or attach a
  `grid_geometry` field to the existing iomap.
- No behavioural change to GridLayout's own output — purely additive. "Layout is
  just layout" stays true: GridLayout still emits only positioned child canvases.

This is the seam that lets the table renderer draw decorations without GridLayout
knowing about tables.

---

## Phase 2 — Upgrade `WidgetTable` to the canonical table

### File: `program/src/document/Widget.jl`

Today `WidgetTable` holds **string** headers/rows and is printer-only. To replace
`TableTable` it must host **document cells**, optional headers, and selection:

```julia
@document struct WidgetTable <: WidgetDocument
    position::Point2D
    column_headers::CellVector   # of Document (or nothing) — optional top strip
    row_headers::CellVector      # of Document (or nothing) — optional left strip
    rows::CellVector             # of rows; each row is a CellVector of Document cells
    column_count::Int
    padding::Int
    border_width::Int
    visible::Bool
    selection::Reference
end
```

- **Cells are `Document`s**, recursed via the shared recursion (so a cell can be a
  `JsonString`, an `XmlElement`, text, even a nested `WidgetTable`) — matching what
  `TableCell.content::Document` allowed.
- **Keep the string convenience constructor** (`WidgetTable(pos, headers::Vector,
  rows::Vector)`) by wrapping strings in a small text/label document, so existing
  call sites keep working with a one-line shim.
- Field names (`rows`, `column_headers`, `row_headers`) become the public reference
  vocabulary for selection — mirror the names `TableToGraphics` selection used
  (`rows[r]`, `columns[c]`) so the band logic ports cleanly.

---

## Phase 3 — Rewrite `WidgetTableToGraphicsCanvas` on top of GridLayout

### File: `program/src/projection/primitive/WidgetToGraphics.jl`

`projection_print`:
1. Build a `GridLayout` whose `children` are the recursed cell documents (headers
   first when present), `columns = column_count (+1 for a row-header strip)`,
   `horizontal_gap/vertical_gap = 0`, and per-cell padding applied via
   `LayoutConstraint` or the table's `padding`.
2. Project that `GridLayout` through the recursion → its `GraphicsCanvas` + the
   Phase-1 grid-geometry iomap.
3. **Overlay decorations** using geometry read from that iomap:
   - outer + inner borders / hairline rules at `col_x` / `row_y` edges,
   - header strip styling (distinct text style / background for header rows/cols),
   - the table's `border_width` and `padding`.
4. **Selection bands:** port the `TableToGraphics` logic that turns
   `rows[r]∅` / `columns[c]∅` / whole-table `∅` into a 2-D highlight rect, now
   computed from `col_x`/`row_y` in the iomap (this is exactly the
   "1-D handle → 2-D band" mapping the old renderer did, just sourced from
   GridLayout geometry).
5. Composite: GridLayout child canvas + decoration overlay → outer canvas.
6. Return a `ChildrenIoMap` delegating cell references to the GridLayout child
   iomaps (drop `@_printer_only` — cells become selectable, which `TableTable`
   supported and the string `WidgetTable` did not).

Mappers/reader: `rows[r].cells[c]` ↔ the corresponding GridLayout child;
peel-and-delegate per the tutorial School-A pattern. The GridLayout reader already
routes clicks/scroll to children — reuse it for cell hit-testing.

---

## Phase 4 — Migrate consumers off the `Table` domain

Retarget everything that produced/rendered `TableTable` to `WidgetTable`:

- `program/src/projection/primitive/CellTableToTable.jl` → produce a `WidgetTable`
  (rename to `CellTableToWidgetTable`, or retarget output). Update `Projectured.jl`
  include/using/export.
- SQL / database paths that render via `Table` (`example/src/projection/Sql.jl`,
  the `CellTable → Table → Graphics` chain) → point at `WidgetTable`.
- Examples: `example/src/document/Table.jl`, `example/src/projection/Table.jl`,
  `Examples.jl`, `ProjecturedExample.jl` — keep a `table_example`, but built on
  `WidgetTable` and projected through `WidgetToGraphics`.
- Tests: `test/src/external/DbCatalogTabularTest.jl` and any table tests →
  assert against `WidgetTable` output.

Confirm there are no remaining references to the removed types before deletion
(grep `TableTable|TableRow|TableColumn|TableCell|TableToGraphics`).

---

## Phase 5 — Delete the `Table` domain and its renderer

- Remove `program/src/document/Table.jl` and
  `program/src/projection/primitive/TableToGraphics.jl`.
- Remove their `include` / `using` / `export` lines from `Projectured.jl` and the
  `TypeDispatchingProjection` entry (`TableTable => TableTableToGraphicsCanvas`).
- Move the `tabular.md`-style notes if any reference these types.

(If a clean removal is risky mid-migration, do Phase 4 first, leave Phase 5 as the
final commit once the grep is clean.)

---

## Phase 6 — Tests

Per [testing.md](../testing.md) / CLAUDE.md, targeted helpers:

- GridLayout iomap geometry — `col_x`/`row_y`/`col_w`/`row_h` are exposed and
  correct for a known grid (pure, no rendering).
- `WidgetTable` renderer — column widths = max over header+body per column; rules
  land on the geometry edges; document cells (a `JsonString` cell) recurse and
  render; the string convenience constructor still works.
- Selection bands — `rows[r]∅` highlights the right row rect; `columns[c]∅` the
  column; whole-table `∅` the whole rect (ported assertions from the old
  `TableToGraphics` tests).
- `test_printer` / `test_text_navigation` on the migrated `table_example` —
  selection descends into a cell's own domain.
- DB/SQL table tests pass against `WidgetTable` output.

---

## Implementation order

1. Phase 1 — expose grid geometry on the GridLayout iomap (additive, safe).
2. Phase 2 — upgrade `WidgetTable` document (+ string shim constructor).
3. Phase 3 — rewrite the renderer on GridLayout + decoration overlay + selection
   bands.
4. Phase 4 — migrate consumers (CellTable, SQL/DB, examples, tests).
5. Phase 5 — delete `Table.jl` + `TableToGraphics.jl` once grep is clean.
6. Phase 6 — tests throughout (geometry first, then renderer, then migration).

## Risks / honest caveats

- **The real work is the `WidgetTable` upgrade** (string cells → document cells +
  selection), not the GridLayout wiring. This is the Option-B-sized change.
- **Selection bands must be preserved** — the old `TableToGraphics` "1-D axis
  handle → 2-D band" behaviour is the trickiest bit to port; it now sources its
  geometry from the iomap, which is cleaner but must be re-verified.
- **Consumer churn** — CellTable, SQL/DB, examples, and tests all move; do Phase 4
  before the Phase 5 deletion so nothing breaks mid-flight.
- Per-cell padding via `LayoutConstraint` vs a table-level `padding` field — pick
  one; the plan assumes a table-level `padding` plus uniform per-cell insets for
  simplicity.

## Outcome

One grid layout engine (`GridLayout`), one table document (`WidgetTable`), and a
table renderer that is a thin decoration overlay reading geometry from the layout
iomap. The duplicated grid math and the redundant `Table` domain are gone.
</content>
