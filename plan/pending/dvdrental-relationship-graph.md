# dvdrental relationship diagram (Graph domain + Adaptagrams)

Render the **dvdrental** PostgreSQL sample database as an entity-relationship
diagram: one node per catalog table (a card with the table name and a table of
its columns + types), edges drawn from the real foreign-key constraints, laid out
by the native **Adaptagrams** engine.

## Goal / target picture

```
        ┌──────────────────────┐          ┌──────────────────────┐
        │ customer             │          │ address              │
        ├───────────┬──────────┤          ├───────────┬──────────┤
        │ Column    │ Type     │          │ Column    │ Type     │
        │ customer… │ integer  │ ───────▶ │ address_id│ integer  │
        │ store_id  │ smallint │          │ address   │ text     │
        │ address_id│ smallint │          │ …         │ …        │
        └───────────┴──────────┘          └───────────┴──────────┘
```

Each **node** = a `WidgetCard` whose `title` is the table name and whose
`content` is a `WidgetTable` with a `Column | Type` header and one row per column.
Each **edge** = a directed `GraphEdge` from the table holding a foreign key to the
table it references.

## Why this reuses the existing pipeline (low risk)

The graph domain already does almost everything we need; this is mostly an
**example-layer** feature plus one small external-DB query.

- `GraphVertex(content::Document)` holds *any* document, and `GraphEdge` references
  vertices by identity — exactly the model in
  [package/example/src/document/Graph.jl](package/example/src/document/Graph.jl)
  (`make_graph_document_example` builds a `GraphGraph` of mixed-domain vertices by hand).
- The Adaptagrams projection
  (`make_graph_adaptagrams_projection_example`,
  [package/example/src/projection/Graph.jl](package/example/src/projection/Graph.jl))
  is `NestingProjection(SequentialProjection(GraphGraphToGraphLayout(AdaptagramsEngine()), GraphLayoutToGraphicsCanvas()); recursion=content)`.
- `GraphGraphToGraphLayout` already **recurses each vertex's content to a
  `GraphicsCanvas` and reads its `w`/`h`** to feed the engine
  ([GraphToGraphLayout.jl](package/domain/src/projection/primitive/GraphToGraphLayout.jl) lines ~62–98),
  so card-sized nodes flow into Adaptagrams placement automatically.
- `make_table_projection_example`
  ([package/example/src/projection/Table.jl](package/example/src/projection/Table.jl))
  is a `RecursiveProjection(TypeDispatchingProjection(...))` that already dispatches
  `WidgetCard` → `WidgetCardToGraphicsCanvas`, `WidgetTable`, `WidgetLabel`/`WidgetText`,
  and the layout types (via `WidgetToGraphics(...).dispatch` + `LayoutToGraphics().dispatch`).
  `WidgetCardToGraphicsCanvas` renders a **String title directly** and recurses the
  content table ([WidgetToGraphics.jl](package/domain/src/projection/primitive/WidgetToGraphics.jl) lines ~2312–2366).

So the only new render wiring is making the graph projection's **content
dispatcher** route `WidgetCard` through `make_table_projection_example`.

## Decisions

1. **Edges = real foreign-key constraints** (chosen). Add a `db_catalog_foreign_keys`
   query to the external DB layer (information_schema) and build edges from the
   live PostgreSQL FKs. Most faithful ER diagram; the only change outside the
   example layer.
2. **Build the `GraphGraph` as a document** (a document-maker), not a new
   `DbCatalogToGraph` projection. Consistent with `make_graph_document_example`;
   the relationship diagram is a read-mostly *view*, and a bidirectional
   catalog↔graph projection has no meaningful inverse (the graph layout must not
   write back to the DB schema). The projection layer stays the existing
   graph→layout→graphics pipeline.
3. **Node widget = `WidgetCard(title=name, content=WidgetTable(columns))`** —
   directly matches the request ("a widget, table name, table of columns with
   name and types").
4. **Keep out of the auto-test `examples` tuple.** Needs a live DB *and* the
   native Adaptagrams shim, exactly like the existing `dvdrental_*` examples
   (registered as consts, run via `run_example` / `write_example_image`).

## Prerequisites

- The native shim must be built once: `using Pkg; Pkg.build("ProjecturedAdaptagrams")`
  (the projection errors at print time with build guidance otherwise).
- A reachable dvdrental database (same env vars as the other dvdrental examples:
  `PGDATABASE=dvdrental`, `PGUSER`, `PGPASSWORD`, `PGHOST`, `PGPORT`).

## Implementation steps (one commit each)

### Step 1 — Foreign-key query in the external DB layer — **Done**

> Implemented: generic `db_catalog_foreign_keys(adapter, schema)` declared +
> exported in `DatabaseModule`; ODBC method added on `OdbcDatabaseAdapter`. No
> other re-export surface needed editing — the `Projectured` umbrella
> (`package/projectured/src/Projectured.jl`) mechanically re-exports every
> `DatabaseModule` export, so the example layer (`using Projectured`) sees the
> new generic automatically, and dispatch finds the ODBC method.

- **Interface**: add `db_catalog_foreign_keys(adapter, schema)` to
  [package/domain/src/external/Database.jl](package/domain/src/external/Database.jl)
  (declare next to `db_catalog_columns`, export it). Returns a
  `Vector` of named tuples `(from_table, from_column, to_table, to_column)`.
- **ODBC impl**: implement it on `OdbcDatabaseAdapter` in
  [package/odbc/src/ProjecturedOdbc.jl](package/odbc/src/ProjecturedOdbc.jl)
  (mirror `db_catalog_columns`: lazy `db_connect!`, `DBInterface.execute`,
  `_materialize`). SQL:

  ```sql
  SELECT tc.table_name  AS from_table,
         kcu.column_name AS from_column,
         ccu.table_name  AS to_table,
         ccu.column_name AS to_column
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema    = kcu.table_schema
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.table_schema    = tc.table_schema
  WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema    = '<schema>'
  ORDER BY from_table, from_column;
  ```
- Re-export through the package surfaces that re-export the other `db_catalog_*`
  functions (search for `db_catalog_columns` in the `export`/`import` lists).
- **Verify**: in the REPL, `with_connection(pool, inst) do a; db_catalog_foreign_keys(a, "public"); end`
  returns the expected dvdrental FKs (e.g. `rental.customer_id → customer`,
  `payment.rental_id → rental`, `address.city_id → city`, …).

### Step 2 — Document-maker: build the relationship `GraphGraph`

Add to [package/example/src/document/DbCatalog.jl](package/example/src/document/DbCatalog.jl)
(it already hosts the dvdrental catalog makers and imports the DB stack):

- `make_dvdrental_relationship_graph_document_example(; schema="public", <db kwargs>, pool=OdbcConnectionPool())`:
  1. Build the `DatabaseInstance` spec and the **explored** catalog tree
     (reuse `make_dvdrental_dbcatalog_document_example`, which returns a
     `DbCatalogRdbms` with tables+columns materialized). Pass the same `pool`.
  2. Pick the target `DbCatalogSchema` (first database → schema named `schema`).
  3. For each `DbCatalogTable t` build a node via a `_table_card(t)` helper and a
     `GraphVertex`, recording `name → vertex` in a `Dict{String,GraphVertex}`.
  4. Fetch FKs once via `with_connection(pool, inst) do a; db_catalog_foreign_keys(a, schema); end`.
  5. For each FK make `GraphEdge(verts[from_table], verts[to_table]; directed=true)`,
     skipping any whose endpoints aren't both in the node set; de-dup
     `(from_table → to_table)` so multi-column FKs draw one edge.
  6. Return `GraphGraph(collect(values…in table order), edges)`.
- `_table_card(t::DbCatalogTable)` helper:
  ```julia
  rows  = [[c.name, c.data_type] for c in t.columns]      # @document accessors auto-deref
  table = WidgetTable(Point2D(0, 0), ["Column", "Type"], rows; padding=6)
  WidgetCard(Point2D(0, 0); title=t.name, content=table, width=260)
  ```
- **Confirm during impl**: `@document` `getproperty` auto-derefs (`t.name`,
  `t.columns`, `c.name`, `c.data_type` give plain values), and iterating a
  `CellVector` yields the child `DbCatalogColumn` documents. (The `WidgetCard`
  projection reads `w.title`/`w.content` un-`[]`-ed, confirming auto-deref; verify
  the catalog side the same way.)

### Step 3 — Projection-maker: graph → adaptagrams with `WidgetCard` nodes

In [package/example/src/projection/Graph.jl](package/example/src/projection/Graph.jl):

- Add an optional `content` kwarg to `make_graph_projection_example` (default = the
  current `TypeDispatchingProjection`) so callers can supply their own content
  dispatcher without duplicating the graph-stages wiring. Backwards-compatible.
- Add `make_dvdrental_relationship_projection_example(; measure=truetype_measure_text)`:
  ```julia
  content = TypeDispatchingProjection(
      WidgetCard  => make_table_projection_example(measure=measure),
      WidgetTable => make_table_projection_example(measure=measure),
      Any         => make_mixed_projection_example(measure=measure),
  )
  make_graph_projection_example(; measure=measure,
                                  engine=AdaptagramsEngine(), content=content)
  ```
  (`make_table_projection_example` already dispatches `WidgetCard`, `WidgetTable`,
  `WidgetLabel`, and the layout types — no new primitive projection needed.)

### Step 4 — Register the example

- Export the two new makers from
  [package/example/src/ProjecturedExample.jl](package/example/src/ProjecturedExample.jl)
  (next to the existing `make_graph_*` / `make_dvdrental_*` exports).
- Register the const in
  [package/example/src/Examples.jl](package/example/src/Examples.jl)
  beside the other `dvdrental_*` consts:
  ```julia
  const dvdrental_relationship_example = Example("dvdrental_relationship",
      make_dvdrental_relationship_graph_document_example,
      make_dvdrental_relationship_projection_example)
  ```
- **Do not** add it to the `examples` tuple (needs live DB + native shim), and
  add a short comment saying so + how to run it — mirroring the existing
  `dvdrental_object_example` note.

### Step 5 — Verify end to end

- `using Pkg; Pkg.build("ProjecturedAdaptagrams")` once.
- `run_example(dvdrental_relationship_example)` and/or
  `write_example_image(dvdrental_relationship_example, "dvdrental_relationship.png")`
  ([documentation/debugging.md](documentation/debugging.md)). Eyeball: ~15 table
  cards, FK edges with arrowheads, non-overlapping Adaptagrams placement.
- Sanity-check the fallback engine too by temporarily using
  `make_graph_projection_example(engine=FallbackLayoutEngine(), content=…)` —
  isolates "graph/card render" bugs from "native engine" bugs.

## Risks / things to watch

- **Card content width**: `WidgetTable` columns auto-size to content; long
  Postgres type names (`character varying`, `timestamp without time zone`) widen
  cards. Acceptable for v1; could abbreviate types later.
- **Edge endpoints by identity**: edges must reference the *same* `GraphVertex`
  objects stored in `GraphGraph.vertices` (build the dict first, reuse those
  objects) — a fresh `GraphVertex` per edge would not match the layout.
- **Diagram size**: dvdrental is ~15 tables / ~20 FKs — comfortable for Adaptagrams.
- **Read-only view**: no reader/back-mapping is wired for catalog→graph (by
  decision 2). Selection/round-trip through the graph stages still works for the
  *layout*; we are not claiming editability of the schema.

## Out of scope (possible follow-ups)

- A bidirectional `DbCatalogToGraph` projection (live, reactive ER view).
- Drawing FK edges port-anchored to the specific column rows (needs per-row
  anchor hints in `EdgeLayout.source_port`/`target_port`).
- Showing PK / FK badges or column highlighting on the participating columns.
