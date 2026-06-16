# DatabaseInstance → catalog/SQL projections (staged)

## Context

A refactor of the DbCatalog domain in `program/src/document/DbCatalog.jl` was
started: the catalog types were renamed `DbCatalogConnection → DbCatalogRdbms`
and changed from *parent-pointer + embedded adapter* to a *pure nested tree*
(each level holds a child `CellVector`: `databases / schemas / tables / columns`).
That refactor is **half-applied** — the struct fields changed, but the
constructors, `show` methods, every consumer projection, and the whole
`test/src/external/DbCatalog*` suite still use the old `DbCatalogConnection` +
parent-chain-adapter API, so the tree currently does not even build consistently.

`example/src/document/DatabaseInstance.jl` was also added, referencing
`DatabaseInstance` / `DatabaseCredentials` document types that **do not exist
yet** in `program/src`.

Goal: separate the connection spec (`DatabaseInstance`) from the catalog *data*
tree, drive everything through an ODBC **connection pool passed as a projection
parameter**, and add a small SQL-statement document with three new projections
(SQL→syntax, SQL→CellTable results, CellTable→TableTable), all wired into a
runnable editor example. The `test/src/external` suite is **migrated** to the new
model (old `DbCatalogConnection` API removed), not kept in parallel.

Decisions:
- External tests: **migrate** to the new model; drop the old API.
- End goal: **runnable editor example(s)**, not just projections+tests.
- `SqlSelectStatement` stays DB-agnostic; the execution projection takes the
  **pool + a `DatabaseInstance`** as parameters.
- Pool: hand-rolled in-repo (no new dependency); wraps the existing
  `OdbcDatabaseAdapter` so all `db_catalog_*` / `db_execute_raw` query code is
  reused unchanged.

The render target for results is the existing `TableTable`
(`program/src/document/Table.jl`, with its existing `TableToGraphics` path) —
**not** a new `WidgetTable` widget.

---

## Stage 1 — Catalog model consistency + DatabaseInstance + connection pool

Makes the tree build and the catalog projections work against the new model
end-to-end.

1. **Fix `program/src/document/DbCatalog.jl`.** Rewrite constructors and
   `Base.show` to match the new child-collection structs
   (`DbCatalogRdbms{host,port,databases}`, `DbCatalogDatabase{name,schemas}`,
   `DbCatalogSchema{name,tables}`, `DbCatalogTable{name,columns}`,
   `DbCatalogColumn{name,data_type}`). New constructors take name + a `CellVector`
   of children (no adapter), e.g. `DbCatalogRdbms(host, port, databases)`. Follow
   the `@document` reactive-field idiom in the file and in
   `program/src/document/Collection.jl`.

2. **New `program/src/document/DatabaseInstance.jl`** (module
   `DatabaseInstanceModule`), included after `document/DbCatalog.jl` in
   `program/src/Projectured.jl`. `@document` structs
   `DatabaseCredentials{user,password,selection}` and
   `DatabaseInstance{database,host,port,credentials,selection}` with **keyword
   constructors** matching `example/src/document/DatabaseInstance.jl`.

3. **New connection pool `program/src/external/ConnectionPool.jl`** (module
   `ConnectionPoolModule`), included after `external/Database.jl`.
   - `OdbcConnectionPool`: driver template (e.g. `"{PostgreSQL Unicode}"`),
     `max_size`, a `ReentrantLock`, idle `OdbcDatabaseAdapter`s keyed by DSN.
   - `dsn_for(pool, inst::DatabaseInstance) -> String` builds the ODBC DSN from
     instance fields + credentials + pool driver.
   - `with_connection(f, pool, inst)` checks out a connected
     `OdbcDatabaseAdapter` (reuse idle or create + `db_connect!`), runs
     `f(adapter)`, returns it to the pool (closes on error).
   - `close_pool!(pool)`. Reuses `OdbcDatabaseAdapter`, `db_connect!`,
     `db_alive`, `db_close!` from `program/src/external/Database.jl`.

4. **New projection `program/src/projection/primitive/DatabaseInstanceToDbCatalog.jl`.**
   `DatabaseInstanceToDbCatalog(pool)` (struct holds the pool). `projection_print`
   builds a `DbCatalogRdbms` whose `databases` is a lazy `CellVector(() -> …)`
   running `with_connection(pool, inst) do a; db_catalog_databases(a) end`; each
   nested level (`schemas`, `tables`, `columns`) is likewise a lazy `CellVector`
   thunk querying through the pool. **Replaces the role of**
   `program/src/projection/primitive/DbCatalogToChildren.jl` — **delete that file**
   and its include. Read-only.

5. **Update tree consumers to the new structs (pure-tree reads, no DB):**
   - `program/src/projection/primitive/DbCatalogToSyntax.jl`: rename
     `*Connection* → *Rdbms*`; read children from the document's own
     `CellVector`s (`rdbms.databases`, `db.schemas`, …) instead of calling
     `*ToChildren`. Keep node shapes/indentation/marker logic.
   - `program/src/projection/primitive/DbCatalogToJson.jl`: rename Connection→Rdbms;
     same data-only `JsonObject`s.

6. **Migrate external catalog tests** to the new model (rebuild the tree via
   `DatabaseInstanceToDbCatalog(pool)`; add `_make_test_instance` /
   `_make_test_pool` helpers next to `_make_test_adapter` in
   `test/src/external/DatabaseTest.jl`):
   `test/src/external/DbCatalogTest.jl`,
   `test/src/external/DbCatalogSyntaxTest.jl`,
   `test/src/external/DbCatalogJsonTest.jl`.

**Verify:** package loads/precompiles; `test_db_catalog()`,
`test_db_catalog_syntax()`, `test_db_catalog_json()` pass against the live
Postgres (`projectured_test`).

---

## Stage 2 — SQL statement document + SQL → Syntax projection

1. **New `program/src/document/Sql.jl`** (module `SqlDocumentModule`), included
   after `document/DatabaseInstance.jl`. Minimal v1 AST sufficient for
   `SELECT * FROM T`, shaped to extend: `SqlStatement <: Document`;
   `SqlSelectStatement{select_list, from, selection}` with leaf pieces
   `SqlAllColumns` (the `*`) and `SqlTableReference{name}`. `where`/`limit`
   reserved (default `nothing`) for later stages.

2. **New projection `program/src/projection/primitive/SqlToSyntax.jl`.**
   `SqlSelectStatement → SyntaxNode` with keyword leaves (`SELECT`, `*`, `FROM`,
   table name) as `TextString`s with fonts/colors, following the leaf/node idiom
   in `DbCatalogToSyntax.jl` and the `SyntaxNode`/`SyntaxLeaf` constructors in
   `program/src/document/Syntax.jl`. `SqlToSyntax()` TypeDispatching constructor.
   Read-only v1.

3. **Example wiring:** `make_sql_document_example()` (new
   `example/src/document/Sql.jl`) → `SqlSelectStatement` for
   `SELECT * FROM persons`; `make_sql_syntax_projection_example()` (new
   `example/src/projection/Sql.jl`) = `SqlToSyntax()` → `SyntaxToText()` →
   `TextToGraphics()`. Register `sql_syntax_example` in
   `example/src/ProjecturedExample.jl` and `example/src/Examples.jl`.

**Verify:** `test_printer(sql_syntax_example)` renders `SELECT * FROM persons`;
add a focused SqlToSyntax printer test.

---

## Stage 3 — SQL execution → CellTable → TableTable + runnable example

1. **New projection `program/src/projection/primitive/SqlToCellTable.jl`.**
   `SqlToCellTable(pool, instance)`. The projection pipeline
   (`SqlToSyntax → SyntaxToText → TextToString`) produces the SQL
   string. `projection_print` runs the query inside a
   reactive `Cell` thunk via `with_connection(pool, inst) do a;
   db_execute_raw(a, sql, RawDatabaseResult) end` and builds a `CellTable`
   (`program/src/document/Collection.jl`) — row 1 = column names, rows 2..n =
   data. Reuses `RawDatabaseResult` from `program/src/external/Database.jl`.
   Read-only v1.

2. **New projection `program/src/projection/primitive/CellTableToTable.jl`.**
   `CellTableToTable()`: `CellTable → TableTable` — derive `rows`/`columns`
   header `CellVector`s from the table shape and a flat row-major `cells`
   `CellVector` of `TableCell`s wrapping each value (`JsonString`/`JsonNumber` or
   `PrimitiveString`), mirroring `make_table_document_example` in
   `example/src/document/Table.jl`. Renders through the existing `TableToGraphics`
   path.

3. **Example wiring (runnable in editor):**
   - `make_sql_table_projection_example()` = `SqlToCellTable(pool, instance)` →
     `CellTableToTable()` → `TableToGraphics()` (via `NestingProjection`, like
     `example/src/projection/Table.jl`).
   - Repoint `make_dbcatalog_document_example()` /
     `make_dbcatalog_projection_example()` (`example/src/.../DbCatalog.jl`) to a
     `DatabaseInstance` document + `DatabaseInstanceToDbCatalog(pool)` → existing
     syntax/text/graphics chain. A shared example `OdbcConnectionPool` is created
     in the example module. Construction stays DB-free (lazy thunks), preserving
     current precompile-safe behavior.
   - Register `database_instance_example` / `sql_table_example` in
     `example/src/ProjecturedExample.jl` and `example/src/Examples.jl`.

4. **Migrate `test/src/external/DbCatalogTabularTest.jl`** to exercise the new
   result path (`SqlSelectStatement` → `SqlToCellTable(pool, instance)` →
   `CellTableToTable`) instead of the deleted parent-chain
   `program/src/projection/primitive/DbCatalogTableToTabularGrid.jl`. That
   projection + `DbCatalogUpdateOperation` (ctid-based **editable** grid) depended
   on parent pointers that no longer exist; **defer** ctid round-trip editing to a
   later stage (note it in the test). The non-catalog `DatabaseTable → TabularGrid`
   path (`test/src/external/DatabaseTest.jl`,
   `test/src/external/DatabaseTabularTest.jl`) is **unaffected** (uses
   `OdbcDatabaseAdapter` directly) and stays as-is.

**Verify:** open the example in the editor (`run_example(sql_table_example)` /
`dbcatalog_example`) and confirm the catalog tree and the `SELECT * FROM persons`
result table render; `test_example(sql_table_example)` and the migrated
`test_db_catalog_tabular()` pass against the live DB.

---

## Module/registration touch-points (all stages)

- `program/src/Projectured.jl`: add includes (`document/DatabaseInstance.jl`,
  `document/Sql.jl`, `external/ConnectionPool.jl`, the 4 new primitive
  projections); **remove** `DbCatalogToChildren.jl` (and, in Stage 3,
  `DbCatalogTableToTabularGrid.jl`); export new public symbols following the
  existing DbCatalog export pattern.
- `test/src/ProjecturedTest.jl`: keep the external includes; `test_all()` already
  aggregates them.

## Notes / risks

- All new query work runs inside lazy reactive `Cell`/`CellVector` thunks, so
  document **construction never touches the DB** (keeps precompile + example
  loading DB-free, matching today's `make_dbcatalog_document_example`).
- Live-DB tests stay gated by the existing `skip_if_no_db` / try-`db_connect!`
  pattern so CI without Postgres still passes.
- Each stage is self-contained: it compiles and its targeted tests pass before
  the next begins.
