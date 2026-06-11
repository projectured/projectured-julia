# Table Cell / Row / Column Selection

**Status: phases 1–3 done; phase 4 deferred.** Whole cell / row / column / table
selection, the highlight layer, and the mouse + keyboard gestures all shipped in
`program/src/projection/primitive/TableToGraphics.jl`. Range and rectangular-block
selection (§6) remain the deferred slice. See **What shipped** below.

Plan for selecting a **whole cell**, a **whole row**, a **whole column**, or the
**whole table** in `TableTable` (and the `TableRow` / `TableColumn` / `TableCell`
friends), plus the gestures to create and navigate those selections. This is the
table-domain analog of [`syntax-tree-selection.md`](syntax-tree-selection.md) /
[`finish-syntax-tree-navigation.md`](../done/finish-syntax-tree-navigation.md),
and it deliberately reuses the conventions those settled: whole-element selection
is the **empty path `∅`**, drawn as a translucent highlight, with the gesture-aware
reader resolving pointer/keyboard intent against the live document.

## What shipped

All in `TableTableToGraphicsCanvas` (`program/src/projection/primitive/TableToGraphics.jl`):

- **Reference (phase 1).** Whole-element selection rides the generic `∅`
  machinery, exactly as §1 specifies: `∅` (table), `.rows[r]∅`, `.columns[c]∅`,
  `.cells[idx]∅`. No new `ReferenceStep`. `_selection_shape` / `_field_element_terminal`
  decode a path into its shape; the flat-index ↔ (r,c) conversion is isolated in
  one place for a future `TabularGrid` migration.
- **Geometry + highlight (phase 1).** The grid layout is lifted into a persisted
  reactive `TableGeometry` on a new `TableTableToGraphicsCanvasIoMap` (the table
  analog of `TextToGraphics`'s `char_to_coord`). A highlight layer prepends one
  translucent `GraphicsRect(…, 0x88,0xbb,0xee,0x40, 4)` band per shape, *behind*
  the grid lines and content. `map_reference_forward` stays `nothing`.
- **Mouse gestures (phase 2).** A gesture-aware 4-arg `Change` reader hit-tests
  the click against the geometry: header strip → row/column, corner → table,
  `Alt`+click on a data cell → whole cell, plain click → routed into that cell's
  content with translated coordinates (replacing the old dispatch-to-every-cell
  routing). Left clicks resolve entirely here.
- **Keyboard navigation (phase 3).** Resolved against the live table in the same
  reader, no courier operation: `Ctrl+Alt+Home` → table; `Alt`+arrows → grid move
  with promotion + edge clamping (and row/column axis stepping / narrowing);
  `Shift+Space` / `Ctrl+Space` → widen the active cell to its row / column;
  `Enter` → narrow a row/column to its first cell, or drop a whole cell into a
  real content character cursor (obtained from the content pipeline's `Ctrl+Home`).
  Plain unmodified arrows are *not* consumed, so they keep editing cell text.
- **Tests.** `test/src/projection/TableSelectionTest.jl` (`test_table_selection`)
  and `test/src/projection/TableNavigationTest.jl` (`test_table_navigation`,
  `explore_table_selections`), registered in `ProjecturedTest` and runnable via
  `test_table()`.

## Motivation

Today a table selection can only land **inside** a cell's content — a path of the
form `.cells[idx].content.<inner>` produced by a plain click that the table reader
routes into the cell's own sub-pipeline (`TableToGraphics.jl:52-63`). There is no
way to say "this whole cell", "this entire row", "this column", or "the whole
table" as one atom, and nothing draws a selection band. Whole cell/row/column
selection is needed for:

- structural navigation (move the active cell, widen to its row/column/table);
- range edits later (cut/copy/paste/clear a row, a column, a block);
- visual feedback (a highlighted active cell / row / column);
- a coherent click + keyboard story that matches the rest of the editor.

## Current data model (recap)

`program/src/document/Table.jl`:

| Type | Fields | Role |
|---|---|---|
| `TableTable` | `rows::CellVector`, `columns::CellVector`, `cells::CellVector`, `padding::Int`, `selection` | the grid |
| `TableRow` | `content::Document`, `selection` | one row's **axis handle** (+ optional header content) |
| `TableColumn` | `content::Document`, `selection` | one column's axis handle (+ optional header content) |
| `TableCell` | `content::Document`, `selection` | one data cell |

`rows` and `columns` define the grid **dimensions**; `cells` is a **flat
row-major** vector with `idx = (r-1)*ncols + c` (1-based `r`, `c`). The current
projection (`TableTableToGraphicsCanvas`) derives `nrows = length(rows)`,
`ncols = length(columns)`, lays out header bands when a row/column has header
content, and computes cumulative `col_x` / `row_y` pixel positions — but discards
that geometry after building the canvas.

> The future row-primary `TabularGrid` foundation (see
> [`../done/tabular.md`](../done/tabular.md)) is orthogonal to this plan. We design
> against `TableTable` as it exists; if `TableTable` later stores its cells in a
> `TabularGrid`, only the *flat-index ↔ (r,c)* helper changes, not the selection
> grammar or the gestures.

## 1. Reference representation (ride `∅`, no new step)

Follow the resolved syntax-tree decision: **whole-element selection is just a path
that terminates at the element** (`EmptyReferencePath`, printed `∅`). No new
`ReferenceStep` is introduced for the single cell/row/column/table cases — the one
node whose `selection` cell holds `∅` is the wholly-selected one; ancestors hold
the routing path; descendants hold `nothing`. `set_selection!` /
`clear_selection!` / `evaluate_reference` / the `@reference_case ∅` pattern already
handle `∅`-terminated paths with zero changes.

Selection shapes on a `TableTable`:

| Selection | Path | Notes |
|---|---|---|
| Whole table | `∅` | the table node itself |
| Whole row `r` | `.rows[r]∅` | terminates at the `TableRow` axis handle |
| Whole column `c` | `.columns[c]∅` | terminates at the `TableColumn` axis handle |
| Whole cell (r,c) | `.cells[idx]∅` | `idx = (r-1)*ncols + c` |
| Cursor in cell content | `.cells[idx].content.<inner>` | **existing** behavior, unchanged |
| Row range `r1..r2` | `.rows{r1:r2}` | `RangeReference` over `rows` — Phase 4 |
| Column range `c1..c2` | `.columns{c1:c2}` | `RangeReference` over `columns` — Phase 4 |
| Rectangular block | — | needs a dedicated step — Phase 4, see §6 |

**The crucial idea: the selection path names an *axis handle*, the projection
turns it into a 2-D band.** A row selection stores `∅` on the `TableRow`, which
visually is just the header object — but the *table projection* reads
`table.selection[]`, recognizes the `.rows[r]∅` shape, and paints a highlight band
spanning that row's full pixel extent (header column + every data cell in the
row). Likewise `.columns[c]∅` paints a column band. The 1-D reference grammar
never has to express a 2-D region for these cases because the projection — which
already owns the grid geometry — does the 1-D-handle → 2-D-band expansion. This is
exactly how `SyntaxNodeToText` turns a `∅` child selection into a
`TextRectangularReference` box: the layer that has the pixels supplies the extent.

This keeps cell / row / column / table whole-selection on the generic `∅`
machinery (free for every consumer of `set_selection!`), and confines all 2-D
knowledge to the one projection that has the geometry.

## 2. Rendering — geometry in the iomap + a highlight layer

Two changes to `TableTableToGraphicsCanvas.projection_print`
(`program/src/projection/primitive/TableToGraphics.jl`):

**(a) Persist the grid geometry in the iomap.** Today `col_x`, `row_y`,
`row_offset`, `col_offset`, `col_widths`, `row_heights`, `total_w/h` are local to
the `elements` closure. Lift them into a shared reactive `Cell` stored on the
iomap (the table analog of `TextToGraphics`'s `char_to_coord`). The reader needs
it for hit-testing; the highlight needs it for extents. Add a small helper:

```julia
# (r,c) 1-based ↔ flat idx, and pixel rect of a cell / row band / column band,
# accounting for header offsets. Built from the persisted geometry cell.
cell_rect(geom, r, c) -> (x, y, w, h)
row_band_rect(geom, r) -> (x, y, w, h)     # full width, row r's height
col_band_rect(geom, c) -> (x, y, w, h)     # full height, column c's width
table_rect(geom)       -> (x, y, w, h)
```

**(b) Paint a highlight in its own layer, behind the grid.** Read
`table.selection[]` in a reactive cell and, for a whole-selection shape, prepend
one (or more) translucent `GraphicsRect`s to the canvas element list — *before*
the grid lines and content, so glyphs stay on top (same layering rationale as the
syntax-text highlight layer). Reuse the established accent:
`GraphicsRect(x, y, w, h, 0x88, 0xbb, 0xee, 0x40, 4)`.

| `table.selection[]` | Highlight |
|---|---|
| `∅` | `table_rect` |
| `.rows[r]∅` | `row_band_rect(r)` |
| `.columns[c]∅` | `col_band_rect(c)` |
| `.cells[idx]∅` | `cell_rect(r, c)` |
| `.cells[idx].content.…` | none here — the cursor is drawn by the cell's own sub-pipeline (unchanged) |
| `.rows{r1:r2}` / `.columns{c1:c2}` | union of bands (Phase 4) |

`map_reference_forward` stays returning `nothing`: a `GraphicsCanvas` is not a
selectable container, so we do **not** forward-project a selection onto it — the
table draws the band in place during print (just as `SyntaxNodeToText` computes
its box in place). The in-cell cursor continues to be forward-projected by the
cell's own pipeline and is untouched.

## 3. Gestures — creating selections (mouse)

Mirror the syntax surface: a plain click is a plain cursor; **Alt promotes to a
structural pick**; header strips select their axis. All resolved in the table's
gesture-aware reader (§5), which has the geometry to hit-test.

| Gesture | Result | Path |
|---|---|---|
| **Left-click** on a data cell | cursor in that cell's content (**existing**) | `.cells[idx].content.<inner>` |
| **Alt + left-click** on a data cell | select the whole cell | `.cells[idx]∅` |
| **Left-click** on a row header (left band) | select the whole row | `.rows[r]∅` |
| **Left-click** on a column header (top band) | select the whole column | `.columns[c]∅` |
| **Left-click** on the top-left corner (header intersection) | select the whole table | `∅` |
| **Shift + click** | extend current selection to a range / block | Phase 4 |

Header / corner hit-testing only applies when the table actually renders those
bands (`has_row_headers` / `has_col_headers`); when a header strip is absent, that
pixel region doesn't exist and those gestures are simply unavailable (a click
there lands on the nearest data cell as today).

## 4. Gestures — navigating selections (keyboard)

Mirror `SyntaxNodeToText`'s navigation idiom (**Alt+arrows** structural, plain
arrows stay character-level inside the cell text) and add the two universal
spreadsheet chords for the row/column axes (because a cell belongs to *both* a row
and a column, an unmodified "widen" key would be ambiguous — make the axis
explicit):

| Gesture | Precondition | Result |
|---|---|---|
| **Alt + ↑ / ↓ / ← / →** | cell-content cursor **or** whole cell | promote to whole cell (if a cursor) and move the active cell one step; clamp at edges, no wrap |
| **Shift + Space** | any cell selection | select the whole **row** of the active cell → `.rows[r]∅` |
| **Ctrl + Space** | any cell selection | select the whole **column** of the active cell → `.columns[c]∅` |
| **Ctrl + Alt + Home** | anywhere | select the whole **table** → `∅` |
| **Alt + ↑ / ↓** | whole row selected | move to the adjacent row (`.rows[r±1]∅`) |
| **Alt + → / Enter** | whole row selected | narrow to the first cell of the row |
| **Alt + ← / →** | whole column selected | move to the adjacent column (`.columns[c±1]∅`) |
| **Alt + ↓ / Enter** | whole column selected | narrow to the first cell of the column |
| **Enter** | whole cell selected | drop into the cell content (place a cursor) |
| **Plain arrow / plain click** | any | exit structural mode → ordinary character cursor in the active cell |

The promotion rule matches syntax: pressing **Alt+arrow** from a character cursor
inside a cell first promotes to the enclosing whole cell, then moves — so the user
enters "grid navigation mode" the moment they hold Alt, and leaves it on the next
unmodified arrow/click. `Shift+Space` / `Ctrl+Space` / `Ctrl+Alt+Home` are the
explicit widen-to-row / widen-to-column / widen-to-table chords.

> **Binding philosophy is an open question** (see §7): the table above follows the
> editor's existing *Alt = structural* idiom so plain arrows keep editing cell
> text. A spreadsheet-native alternative (plain arrows move cells, `F2`/`Enter`
> enters edit mode, `Tab`/`Shift+Tab` advance) is also viable but diverges from
> the syntax navigation already shipped. Recommendation: stay consistent with
> syntax (Alt-based) for now; revisit if table editing becomes the primary use.

## 5. Reader architecture (where the logic lives)

All of §3 and §4 live in a gesture-aware **4-arg `Change` reader** on
`TableTableToGraphicsCanvas`, exactly parallel to `SyntaxNodeToText`'s
(`SyntaxToText.jl:222`). The `Change` carries the originating `gesture`
(`MousePress` / `KeyDown`) plus the backward-mapped `operation`; the table layer
is the one place with both the grid geometry (from the iomap, §2a) and the live
`TableTable` (`iomap.input`, for its selection and dimensions).

```julia
function projection_read(p::TableTableToGraphicsCanvas, recursion,
                         change::Change, iomap)
    g = change.gesture
    # Mouse: hit-test header / corner / data cell; Alt promotes a data-cell
    # click to a whole-cell pick; header/corner clicks pick row/column/table.
    if g isa MousePress && g.button === :left
        hit = hit_test(geometry(iomap), g.x, g.y)   # :corner | :row(r) | :col(c) | :cell(r,c) | :outside
        op  = mouse_select(hit, g.modifiers.alt)     # ReplaceSelectionOperation or nothing
        op === nothing || return Change(g, op)
    end
    # Keyboard: Alt-arrows / Ctrl+Alt+Home / Shift+Space / Ctrl+Space, resolved
    # against iomap.input.selection and (nrows, ncols).
    if g isa KeyDown
        op = key_navigate(iomap.input, g)            # ReplaceSelectionOperation or nothing
        op === nothing || return Change(g, op)
    end
    # Fall through: plain clicks route into the cell content as today.
    payload = change.operation === nothing ? g : change.operation
    return Change(g, projection_read(p, iomap, payload))   # existing cells[idx].content routing
end
```

Two supporting facts make the keyboard half work without a courier operation, just
like syntax:

- `TextToGraphics` already **declines Alt-modified navigation keys**
  (`TextToGraphics.jl:213`), so an `Alt+arrow` raw `KeyDown` falls through the
  cell's text pipeline up to the table reader.
- The table reader recognizes **and** resolves the chord in one place against the
  live table — no `TableNavigateOperation` type is needed (the syntax plan
  deleted its `TreeNavigateOperation` courier for the same reason).

The existing 3-arg `projection_read(p, iomap, event)` (the `cells[idx].content`
routing) stays as the fall-through for plain clicks.

## 6. Deferred — range & rectangular block selection (Phase 4)

- **Row/column ranges** are cheap and need no new type: `.rows{r1:r2}` and
  `.columns{c1:c2}` are ordinary `RangeReference`s over the `rows` / `columns`
  CellVectors. `Shift+Alt+↑/↓` extends a row selection into a row range;
  `Shift+Alt+←/→` extends a column selection into a column range. The highlight
  cell unions the per-row / per-column bands.

- **A rectangular block** (`r1..r2 × c1..c2`) is the one case the `∅`/`RangeReference`
  grammar cannot name, because `cells` is a *flat* vector — a block is contiguous
  by row but strided by column, so no single `RangeReference` over `cells`
  describes it. This needs a dedicated step, analogous to `TextRectangularReference`:

  ```julia
  struct TableRegionReference <: ReferenceStep
      row_start::Int; row_stop::Int   # 0-based half-open boundaries
      col_start::Int; col_stop::Int
  end
  ```

  A whole cell is `(r-1, r, c-1, c)`, a row is `(r-1, r, 0, ncols)`, a column is
  `(0, nrows, c-1, c)`, the table is `(0, nrows, 0, ncols)` — i.e. the §1 cases are
  all degenerate regions, so a later refactor *could* unify everything onto
  `TableRegionReference`. We deliberately **don't** lead with it: the `∅` form
  keeps cell/row/column/table selection on the generic machinery (every domain
  inherits it for free), and the region step is added only when true block
  selection (drag-select, `Shift+click`, block cut/paste) is actually built.
  `set_selection!` must then treat `TableRegionReference` as terminal (no child to
  descend into), and `@reference` / `@reference_case` need surface syntax for it.

## 7. Open questions

- **Gesture binding philosophy (§4)** — Alt-based structural navigation
  (consistent with shipped syntax navigation; plain arrows keep editing cell text)
  vs. spreadsheet-native (plain arrows move cells, `F2`/`Enter` to edit,
  `Tab`/`Shift+Tab`). Recommendation: Alt-based, for editor consistency.
- **Widen ambiguity** — a cell is in both a row and a column, so "select parent"
  has no single answer. Resolved here by explicit `Shift+Space` (row) /
  `Ctrl+Space` (column) chords rather than overloading `Alt+↑`. Confirm this reads
  naturally before committing.
- **Header-less tables** — when a row/column has no header content the projection
  draws no header strip, so the header-click and corner-click gestures have no
  target. Row/column selection is then only reachable via the keyboard chords.
  Acceptable, or should the projection always reserve a thin selectable gutter?
- **`TabularGrid` migration** — if `TableTable` moves to row-primary storage, only
  the flat-index ↔ (r,c) helper changes; the grammar and gestures are unaffected.
  Worth keeping the (r,c) ↔ idx conversion isolated in one helper from the start.

## 8. Phasing

1. **Reference + rendering.** ✅ Done. Grid geometry persisted in the iomap;
   highlight layer for `∅` / `.rows[r]∅` / `.columns[c]∅` / `.cells[idx]∅`.
2. **Mouse gestures.** ✅ Done. Gesture-aware `Change` reader: header / column /
   corner clicks; `Alt+click` whole-cell promotion; plain click routes into the
   clicked cell's content with translated coordinates.
3. **Keyboard navigation.** ✅ Done. `Alt+arrows` grid move with promotion;
   `Ctrl+Alt+Home` table; `Shift+Space` row; `Ctrl+Space` column; `Enter` to
   narrow / enter cell editing. Plain arrows still edit cell text.
4. **Deferred.** Row/column ranges (`RangeReference`), then rectangular block via
   `TableRegionReference` with `Shift+click` / `Shift+Alt+arrows`. Not started.

## 9. Tests

Mirror the syntax suites:

- `test/src/projection/TableSelectionTest.jl` (`test_table_selection`) — forward/
  storage: `set_selection!` placing `∅` at table / row / column / cell nodes;
  `clear_selection!` round-trip; the highlight cell emitting the right rect for
  each shape; existing `.cells[idx].content` cursor still works.
- `test/src/projection/TableNavigationTest.jl` (`test_table_navigation`) — the
  `Alt+arrow` grid moves (with edge clamping), `Shift/Ctrl+Space` widen,
  `Ctrl+Alt+Home`, `Alt+click` promotion; `explore_table_selections` walker.
- Extend `test_selection(table_example)` / `test_selection(math_table_example)`
  coverage and the click round-trip lists (`MouseClickTest.jl`,
  `ClickRoundtripTest.jl`) once the table answers pointer gestures.

Use the narrow runners per [CLAUDE.md](../../CLAUDE.md): `test_table()`,
`test_selection(table_example)`, `explore_selections(doc, proj)` — not `test_all`.
</content>
</invoke>
