# Drop Tabular → CellMatrix + WidgetTable

Remove the obsolete `Tabular` document domain and re-express the "render tabular
data as a table" functionality on the existing base `CellMatrix` (dense
`Matrix{Cell}`) rendered to `WidgetTable`.

## Why

`domain/tabular/` conflates two things:
- **`TabularGrid`/`TabularRow`/`TabularCell`** (`Tabular.jl`) — a bespoke
  row-primary editable-grid document. Obsolete: base already has `CellMatrix`
  (dense) and `CellTable` (ragged) covering 2D reactive data, and no example
  uses `TabularGrid` — only tests do.
- **`CellTableToWidgetTable`** (`CellTableToTable.jl`) — a projection that renders
  base `CellTable` → `WidgetTable`. This is the live-query render path; it does
  **not** use `TabularGrid` at all.

The replacement unifies on `CellMatrix` + `WidgetTable`: one dense reactive
matrix document, one projection to the visual table widget.

## Current consumers (verified)

| thing | uses | consumed by |
| --- | --- | --- |
| `TabularGrid` (Tabular.jl) | — | odbc `db_query(::Type{TabularGrid})`, `DatabaseTableToTabularGrid`; tests only |
| `DatabaseTableToTabularGrid` | `TabularGrid` | `DatabaseTabularTest`, `DbCatalogTabularTest` (external, live-DB) — **no example** |
| `SqlToCellTable` (odbc) | base `CellTable` | `sql_table` example, `CellTableToWidgetTable` |
| `CellTableToWidgetTable` (tabular/CellTableToTable.jl) | base `CellTable` | `sql_table` example |
| `CellMatrix` (base) | — | **nothing yet (greenfield)** |
| `table`/`math_table` examples | `WidgetTable` directly | unaffected |

## Plan

### 1. Add the CellMatrix → WidgetTable projection
New `CellMatrixToWidgetTable` (replaces `CellTableToWidgetTable`), same shape:
row 1 = column headers, rows 2..n = data, each value JSON-wrapped so the table
content recursion (Json→Syntax→Text→Graphics) renders it. Input `CellMatrix`
(base), output `WidgetTable` (visual), JSON-wrap (domain) ⇒ home is **domain**.
Since the `tabular/` slice is being deleted, it lands in a new small slice
`domain/table/` (or folds into `domain/sql/` — see decision D1).

### 2. Migrate the live-query path to CellMatrix
`SqlToCellTable` → **`SqlToCellMatrix`**: produce a `CellMatrix` (row 1 = column
names, rows 2..n = data) instead of base `CellTable`. Read-only, as today.
Update the `sql_table` example (`odbc/example/src/projection/Sql.jl`) to
`SqlToCellMatrix` + `CellMatrixToWidgetTable`.

### 3. Delete the obsolete Tabular domain
- `domain/tabular/Tabular.jl` (TabularModule: TabularGrid/TabularRow/TabularCell)
- `domain/tabular/CellTableToTable.jl` (superseded by #1)
- the whole `domain/tabular/` slice folder
- odbc `DatabaseTabularModule` (`db_query(::Type{TabularGrid})`) and
  `DatabaseTableToTabularGridModule` (`DatabaseTableToTabularGrid`) — see D2.
- Remove the includes/exports from `domain/ProjecturedDomain.jl`,
  `odbc/ProjecturedOdbc.jl`, and the `database/{Database,DatabaseAdapters}.jl`
  doc-comment references.

### 4. Tests
- Delete `domain/test/.../document/TabularTest.jl` (tests `TabularGrid`) — and
  drop `test_tabular` from the domain aggregator. (This is one of the
  pre-existing @document-constructor-drift failures, so this also removes red.)
- `DatabaseTabularTest` / `DbCatalogTabularTest` (umbrella external, live-DB):
  drop if the editable path goes (D2), or rewrite against
  `SqlToCellMatrix` / a CellMatrix table view.
- Add a small `CellMatrixToWidgetTable` render test (local fixture, offline) to
  `domain/test`.

## Decisions to confirm

- **D1 — home of `CellMatrixToWidgetTable`:** new `domain/table/` slice
  (clean, symmetric with other slices) **vs.** fold into `domain/sql/` (fewer
  files, but couples a generic matrix renderer to the sql slice). *Proposed:
  new `domain/table/` slice.*
- **D2 — the editable direct-table view (`DatabaseTableToTabularGrid`):** it is
  the only cell-**editable** table path (ctid-based UPDATE) and is test-only (no
  example). Options: **(a) drop it** with the rest of Tabular (simplest; the
  read-only SQL→table path remains), or **(b) reimplement it** as
  `DatabaseTableToCellMatrix` preserving the cell-edit read_intent. *Proposed:
  (a) drop — it's part of "obsolete tabular"; reintroduce on CellMatrix later
  if a live editable browse is wanted.*
- **D3 — base `CellTable`:** after #2, `CellTable` has no consumers. **(a)
  remove it** from base (`Collection.jl` + the `CollectionDocument` union) to
  fully unify on `CellMatrix`, or **(b) keep** it as unused base vocabulary.
  *Proposed: (a) remove — the point is to standardize on CellMatrix.*

## Verification

`test_domain()` offline (its example sweep covers the render path via local
fixtures); parse-check odbc/example (native ODBC can't load offline — same
constraint as the extras split, so the odbc query path is verified statically +
by the domain-side CellMatrix render test). Confirm no dangling `Tabular` /
`CellTable` refs remain (excl. plan/done history).

## Out of scope

Reworking `WidgetTable` itself; the DbCatalog browse path (separate, kept).
