# Drop Tabular → consolidate on base CellTable + WidgetTable

Remove the obsolete `Tabular` document domain (`TabularGrid`/`TabularRow`/
`TabularCell`) and keep the DB-query→table path on the base **`CellTable`**
(`CellVector`-of-`CellVector` rows) rendered to `WidgetTable`.

## Why CellTable, not CellMatrix

The first instinct was `CellMatrix` (dense `Matrix{Cell}`), but on inspection
`CellTable` is the right fit and `CellMatrix` is not:

- **Reference/selection support.** `CellTable` is built on `CellVector`, which
  already has `child_reference_steps`, `ElementReference` indexing, and
  selection descent — cells address as `rows[r][c]`, rows as `rows[r]`, through
  the existing machinery, for free. `CellMatrix` is a bare `Matrix{Cell}` with
  **zero** reference/selection support (it appears only in its own definition);
  adopting it would mean building a new 2D reference step and all its engine
  methods in base/kernel.
- **Shape.** `TabularGrid`'s defining model was "rows own their cells (primary
  axis); column views share cells" — that *is* `CellTable`. `TabularGrid` was a
  domain-level reinvention of base `CellTable`; dropping it and standardizing on
  `CellTable` is the natural consolidation. SQL results are row-shaped too, so
  the row-primary model matches the data; `CellMatrix`'s dense/column-symmetric
  strengths (spreadsheets, math matrices) are irrelevant here.
- **Effort.** `SqlToCellTable` (odbc) and `CellTableToWidgetTable`
  (`tabular/CellTableToTable.jl`) already exist and work. Keeping `CellTable`
  makes this a **deletion + small relocation**, not a migration.

`CellMatrix` stays in base as dormant vocabulary for a genuinely matrix-shaped
future use; it is not adopted here.

## What's obsolete vs. what stays

**Delete (obsolete `Tabular`):**
- `domain/tabular/Tabular.jl` — `TabularModule` (TabularGrid/TabularRow/TabularCell).
- odbc `DatabaseTabularModule` (`db_query(…, ::Type{TabularGrid})`) and
  `DatabaseTableToTabularGridModule` (`DatabaseTableToTabularGrid`, the editable
  ctid-UPDATE direct-table view) — test-only, no example (D2 = drop).

**Keep (the solution — already built):**
- base `CellTable` + `CellVector` (unchanged).
- odbc `SqlToCellTable` (SqlSelectStatement → CellTable), read-only.
- `CellTableToWidgetTable` (CellTable → WidgetTable) — relocated out of the
  deleted `tabular/` slice.
- the `sql_table` example (odbc/example) — **unchanged**, already rides this path.

## Plan

1. **Relocate the renderer.** Move `tabular/CellTableToTable.jl`
   (`CellTableToWidgetTableModule`) to a surviving slice. Since `tabular/` is
   deleted, rename the slice: `domain/tabular/` → `domain/table/`, keeping only
   `CellTableToTable.jl`. Update the include in `domain/ProjecturedDomain.jl`.
2. **Delete `Tabular.jl`** and remove its include + `TabularModule` export from
   `domain/ProjecturedDomain.jl`; drop the `tabular → json` note in the slice
   DAG comment.
3. **Delete the odbc TabularGrid modules** (`DatabaseTabularModule`,
   `DatabaseTableToTabularGridModule`) from `odbc/ProjecturedOdbc.jl` and their
   `using`/`export` lines; drop the `database/{Database,DatabaseAdapters}.jl`
   doc-comment references to `TabularGrid`/`DatabaseTabular`.
4. **Tests.**
   - Delete `domain/test/.../document/TabularTest.jl`; drop `test_tabular` from
     the domain aggregator (`ProjecturedDomainTest`). (Bonus: removes one of the
     pre-existing @document-constructor-drift red failures.)
   - Delete the external live-DB tabular tests `DatabaseTabularTest.jl` /
     `DbCatalogTabularTest.jl` (they drove the deleted editable TabularGrid
     path) and their includes/aggregator calls in `ProjecturedTest`.
   - Keep `DatabaseTest.jl` / the DbCatalog tests that don't use TabularGrid
     (verify each: drop only the TabularGrid-dependent ones).
5. **Sweep** for dangling `Tabular`/`TabularGrid`/`DatabaseTableToTabularGrid`
   refs across code + docs (excl. plan/done history).

## Decisions

- **D1 — slice name for the surviving renderer:** *rename `domain/tabular/` →
  `domain/table/`* (drops the "tabular" name with the obsolete doc). Alt: keep
  `tabular/`. *Proposed: rename to `table/`.*
- **D2 — editable direct-table view (`DatabaseTableToTabularGrid`):** *drop*
  (test-only, no example; read-only browse is just `SELECT * → SqlToCellTable`).
  Reintroduce on `CellTable` later if a live editable browse is wanted.
- **D3 — base `CellTable`:** *keep* (it is the chosen carrier). `CellMatrix`
  also kept as dormant base vocabulary.

## Verification

`test_domain()` offline (its example sweep exercises `CellTableToWidgetTable`
via local fixtures — add one if not already covered); parse-check
`odbc` + `odbc/example` (native ODBC can't load offline — statically verified,
same constraint as the extras split). Confirm no dangling `Tabular` refs remain.

## Out of scope

Reworking `WidgetTable`; the DbCatalog browse path (separate, kept); building
`CellMatrix` reference support (deferred until a matrix-shaped need appears).
