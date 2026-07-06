# Drop Tabular; consolidate on base CellTable; renderer → visual; split Collection.jl

Four coupled changes:
1. Delete the obsolete `Tabular` document domain (`TabularGrid`/`TabularRow`/
   `TabularCell`) and its ODBC TabularGrid projections.
2. Keep the DB-query→table path on base **`CellTable`** (the right fit — see
   below), unchanged apart from #3.
3. Move the `CellTable → WidgetTable` renderer **down into `visual`** and make
   it **domain-free** (wrap cells in base `Primitive*`, not domain `Json*`).
4. Split base `Collection.jl` into **per-type fragment files**.

## Why CellTable (not CellMatrix)

`CellTable` is a `CellVector`-of-`CellVector`s, so cells inherit
reference/selection support from `CellVector` (`child_reference_steps`,
`ElementReference`, selection descent) for free — `rows[r][c]`. `CellMatrix` is
a bare `Matrix{Cell}` with **zero** reference support; adopting it would mean
building a new 2D reference step in the engine. `TabularGrid`'s model ("rows own
their cells; column views share cells") *is* `CellTable`, and SQL results are
row-shaped — so `CellTable` is both the natural fit and already wired end-to-end
(`SqlToCellTable` + the renderer both exist). `CellMatrix` stays in base as
dormant vocabulary for a future matrix-shaped need.

## Why the renderer goes to visual (not base, not domain)

`CellTableToWidgetTable` emits a `WidgetTable`, which lives in **visual**; base
cannot depend upward on visual, so **base is impossible**. Its only *domain*
dependency is the `Json*` value-wrapping — replace that with base `Primitive*`
(rendered by the existing visual `Primitive*ToSyntaxLeaf` path) and its deps
become `CellTable`/`Primitive*` (base) + `WidgetTable` (visual) ⇒ **lowest legal
home = visual, no domain dependency.** The domain then has no table slice at all.

---

## A. Remove obsolete Tabular

- Delete `package/domain/src/tabular/Tabular.jl` (`TabularModule`).
- Delete the ODBC TabularGrid modules from `package/odbc/src/ProjecturedOdbc.jl`:
  `DatabaseTabularModule` (`db_query(…, ::Type{TabularGrid})`) and
  `DatabaseTableToTabularGridModule` (`DatabaseTableToTabularGrid` — the editable
  ctid-UPDATE direct-table view; test-only, no example → **drop**, D2). Remove
  their `using .…`/`export` lines (~lines 376–648, 812–817).
- `package/domain/src/ProjecturedDomain.jl`: drop `include("tabular/Tabular.jl")`,
  the `TabularModule` from the re-export, and the `tabular → json` slice-DAG note.
- `package/domain/src/database/{Database,DatabaseAdapters}.jl`: drop the
  `TabularGrid`/`DatabaseTabular` doc-comment references.
- After moving the renderer (B), the `domain/src/tabular/` folder is empty →
  delete it.

## B. Move the renderer to visual, Primitive-wrapped

- New `package/visual/src/widget/CellTableToWidgetTable.jl`, module
  `CellTableToWidgetTableModule`, from the current
  `domain/tabular/CellTableToTable.jl` body, with:
  - imports rebased to visual: `..CellModule`, `..CollectionModule`
    (CellVector, CellTable), `..WidgetModule` (WidgetTable, Point2D),
    **`..PrimitiveModule`** (PrimitiveBool, PrimitiveNumber, PrimitiveString) in
    place of `..JsonModule`, `..ProjectionApiModule`, `..IoMapModule`.
  - `_to_doc`: `AbstractString → PrimitiveString`, `Bool → PrimitiveBool`,
    `Real → PrimitiveNumber`, `Nothing/Missing → PrimitiveString("")` (no
    `PrimitiveNull` exists), fallback `→ PrimitiveString(string(v))`.
  - drop the deprecated `const CellTableToTable = …` alias.
- Register in `package/visual/src/ProjecturedVisual.jl`: add the include in the
  `widget/` slice section (after `Widget.jl`, before `WidgetToGraphics.jl`). The
  umbrella re-export loop picks the module up automatically.
- Update the `sql_table` example
  (`package/odbc/example/src/projection/Sql.jl`): the `table_renderer`
  dispatches the three concrete `Primitive*` types through a primitive pipeline
  (`PrimitiveStringToSyntaxLeaf`/`…Number…`/`…Bool…` → `SyntaxToText` →
  `TextToGraphics`) instead of `JsonDocument → JsonToSyntax`. `SqlToCellTable`
  and `CellTableToWidgetTable` calls stay.

## C. Split base Collection.jl into per-type fragments

`package/base/src/document/Collection.jl` (597 lines, one `CollectionModule`)
→ aggregator + fragment files (0-module files sharing the module namespace, the
established fragment pattern the layering guard supports):

- new `package/base/src/document/collection/CellVector.jl` (§ CellVector, ~32–216)
- new `…/collection/CellMatrix.jl` (§ CellMatrix, ~217–318)
- new `…/collection/CellTable.jl` (§ CellTable, ~319–374)
- new `…/collection/ListNode.jl` (§ ListNode, ~375–516)
- `Collection.jl` keeps: the `module CollectionModule` header, all imports +
  the `export`, the `include("collection/…")` lines, the
  `const CollectionDocument = Union{CellVector, CellMatrix, CellTable, ListNode}`,
  and the **cross-cutting** deep-copy + `child_reference_steps` +
  children-container sections (§ ~519–596; they dispatch across all four types).
- Hoist the mid-file `import`s (OperationModule, ReferenceModule.RangeReference,
  ChildrenContainerModule) to the aggregator header so the fragments and shared
  sections resolve.
- Update `package/base/doc/{architecture,document}.md` if they cite
  `Collection.jl` line ranges.

## D. Tests

- Delete `package/domain/test/src/document/TabularTest.jl`; drop `test_tabular`
  from `ProjecturedDomainTest` (its aggregator + export). (Bonus: removes one of
  the pre-existing `@document`-constructor-drift red failures.)
- Delete the external live-DB tabular tests
  `package/projectured/test/src/external/{DatabaseTabularTest,DbCatalogTabularTest}.jl`
  (they drove the deleted editable TabularGrid path); drop their includes +
  aggregator calls in `ProjecturedTest`. Keep `DatabaseTest.jl` and the
  non-TabularGrid DbCatalog tests (verify each).
- Add a small offline `CellTableToWidgetTable` render test to
  `package/visual/test` (local `CellTable` fixture → assert a `WidgetTable`
  with the expected header row + Primitive-wrapped cells) and wire it into
  `test_visual()`.
- `base/test` `CollectionTest`: unaffected by the fragment split (same module),
  but re-run to confirm.

## E. Verification (offline)

- `test_base()` (Collection split — same module, all tests pass) + its layering
  guard (fragment include-tree still valid).
- `test_visual()` (new renderer test + example sweep) + visual layering guard.
- `test_domain()` (no more `test_tabular`; layering guard confirms
  `tabular/` gone and no dangling include).
- Parse-check `odbc` + `odbc/example` (native ODBC can't load offline — the SQL
  query half is verified statically, same constraint as the extras split; the
  render half is covered by the visual render test).
- Sweep: no dangling `Tabular`/`TabularGrid`/`DatabaseTableToTabularGrid`/
  `CellTableToTable` refs remain (excl. plan/done history).

## Decisions (settled)

- D1 renderer home: **visual** (`widget/` slice), Primitive-wrapped, domain-free.
- D2 editable direct-table view: **dropped**.
- D3 base `CellTable`: **kept** (the carrier); `CellMatrix` kept as dormant base
  vocabulary.

## Out of scope

Reworking `WidgetTable`; the DbCatalog browse path (kept); `CellMatrix`
reference support (deferred until a matrix-shaped need appears).
