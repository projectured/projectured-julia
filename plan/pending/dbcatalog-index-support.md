# DbCatalog + SQL: CREATE / DROP INDEX support

> **Status (2026-08-12): NOT STARTED.** No `DbCatalogIndex`, `SqlCreateIndexStatement`,
> or `SqlDropIndexStatement` symbol exists anywhere in `package/`. All six phases
> are still ⬜. The file paths below are corrected from the plan's original
> `program/src/...` layout to the current `package/<name>/main/...` one; most line
> numbers still line up closely because the SQL/DbCatalog files moved directory
> without much internal reshuffling, but a few drifted (noted inline) — re-check
> line numbers again before acting, since this plan has not been touched since the
> package split.

Add **indexes** to the database story, end to end: model them in the catalog, in
the SQL DDL document, in the parser, and in the three printers that turn a catalog
into something readable (`DbCatalogToSyntax` browser, `DbCatalogToSql` DDL, and the
live `DatabaseInstanceToDbCatalog` catalog builder).

Scope of the SQL surface, kept deliberately minimal (mirrors the existing
`CREATE TABLE` / `CREATE SCHEMA` cut — name + columns only, no extras):

```sql
CREATE INDEX <index-name> ON [schema.]<table> (<col> [, <col> …]);
DROP INDEX [schema.]<index-name>;
```

**Out of scope (flag, don't build):** `UNIQUE`, `CONCURRENTLY`, `USING <method>`,
`IF [NOT] EXISTS`, partial indexes (`WHERE …`), expression / functional indexes,
`ASC`/`DESC`/`NULLS` ordering, opclasses, `CASCADE`/`RESTRICT` on drop. These are
real but each needs a model field the catalog can't populate yet — same reasoning
as the table-DDL cut in
[plan/done/dbcatalog-sql-document-support.md](../done/dbcatalog-sql-document-support.md).
A later catalog-enrichment pass adds them; tracked there, not here.

This plan builds on the already-shipped DDL work in
[plan/done/dbcatalog-sql-document-support.md](../done/dbcatalog-sql-document-support.md)
and reuses its conventions (direct construction, not print-and-parse; `SqlToSyntax`
as the single source of truth for SQL text; read-only catalog projections).

---

## Implementation rules (apply to every phase)

These are **hard gates**, not suggestions:

1. **Test after each phase before moving on.** After implementing a phase, write:
   - **Atomic tests** covering *only* the newly introduced feature in isolation.
   - **Combined tests** that exercise the new feature *together with* the
     previously implemented features (e.g. a table that has both columns and
     indexes; a schema whose DDL script contains `CREATE TABLE` *and*
     `CREATE INDEX`; a parser round-trip over a mixed statement list).
   - Run the **smallest covering test** per [CLAUDE.md](../../CLAUDE.md) "Testing a
     change" — never `test_all`. Only proceed to the next phase once both the
     atomic and combined tests pass.
2. **Maintain this plan after each phase.** Record what was actually implemented,
   any deviations from the plan, and learnings (the way the done-plan captured the
   `TABLE`/`SCHEMA`-not-in-keywords gotcha). Update the per-phase **Status** line.
3. **After Phase 2, update
   [plan/done/dbcatalog-sql-document-support.md](../done/dbcatalog-sql-document-support.md)**
   (the SQL/DbCatalog document-structure reference) with the new supported document
   structs (`SqlCreateIndexStatement`, `SqlDropIndexStatement`, and the
   `DbCatalogIndex` catalog node from Phase 1), so that doc stays the canonical
   inventory of the SQL + catalog document model.

---

## Phase 1 — DbCatalog document structure for index

**Status:** ⬜ not started.

**File:** [package/dbcatalog/main/DbCatalog.jl](../../package/dbcatalog/main/DbCatalog.jl)

The catalog currently models
`DbCatalogRdbms → DbCatalogDatabase → DbCatalogSchema → DbCatalogTable → DbCatalogColumn`
and holds **no indexes** ([DbCatalog.jl:21-45](../../package/dbcatalog/main/DbCatalog.jl#L21)) —
confirmed still true: `DbCatalogTable` has only `name` and `columns` today.

Add:

- `DbCatalogIndex <: DbCatalogDocument` with:
  - `name::String` — the index name.
  - `column_names::CellVector` — the indexed column names, in order. Store them as
    a `CellVector` (lazy-friendly, uniform with the other child collections). The
    elements are plain `String`s (an index references existing table columns *by
    name*; it does not own `DbCatalogColumn` nodes — same modelling choice as a
    column carrying its `data_type` as a bare `String`).
  - `selection::Reference`.
- A field on `DbCatalogTable` to hold its indexes:
  - `indexes::CellVector` (of `DbCatalogIndex`), added **after** `columns`.
  - This shifts `DbCatalogTable`'s positional layout — update its `@document`
    struct, its convenience constructor, and **every existing construction site**
    (tests build `DbCatalogTable(name, columns)`). Keep a back-compat constructor
    `DbCatalogTable(name, columns) = DbCatalogTable(name, columns, CellVector(), Cell(nothing))`
    so existing call sites that pass no indexes keep working, plus a
    `DbCatalogTable(name, columns, indexes)` arity.

Conventions to follow (match the file):
- `@document struct … selection::Reference`, convenience constructor defaulting
  `selection = Cell(nothing)` and auto-wrapping (the `@document` inner constructor
  wraps raw values in Cells).
- A terse `Base.show`, e.g.
  `DbCatalogIndex(name on col_a, col_b)`.
- Export `DbCatalogIndex` from `DbCatalogDocumentModule`, in
  [package/dbcatalog/main/DbCatalog.jl](../../package/dbcatalog/main/DbCatalog.jl),
  next to the other `DbCatalog*` names. There is no separate umbrella file to
  wire into: `package/dbcatalog/main/ProjecturedDbCatalog.jl` already
  `include`s `DbCatalog.jl` and re-binds every exported name automatically.

**Tests (Phase 1):** a small `DbCatalogTest` (document-construction) check:
- *Atomic:* construct a `DbCatalogIndex`, assert `name` and `column_names`.
- *Combined:* construct a `DbCatalogTable` with both columns **and** indexes;
  assert both collections read back; assert the no-index back-compat constructor
  still yields an empty `indexes`.

---

## Phase 2 — SQL document structure for CREATE / DROP INDEX

**Status:** ⬜ not started.

**File:** [package/sql/main/Sql.jl](../../package/sql/main/Sql.jl)

Add two statement types next to the existing DDL block
([Sql.jl:257-275](../../package/sql/main/Sql.jl#L257)):

- `SqlCreateIndexStatement <: SqlStatement`:
  - `index_name::String`.
  - `table_name::SqlTableName` (reuse the existing schema-qualifiable name —
    [Sql.jl:50](../../package/sql/main/Sql.jl#L50)).
  - `columns::CellVector` — `[SqlColumnName]` (reuse `SqlColumnName`,
    [Sql.jl:61](../../package/sql/main/Sql.jl#L61)).
  - `selection::Reference`.
  - Convenience constructors mirroring `SqlCreateTableStatement`'s
    ([Sql.jl:258-263](../../package/sql/main/Sql.jl#L258)): accept a
    `CellVector` or an `AbstractVector{SqlColumnName}`, and a bare-string index
    name.
- `SqlDropIndexStatement <: SqlStatement`:
  - `index_name::String`.
  - `schema_name::Any` — `String` or `nothing` (PostgreSQL `DROP INDEX` takes a
    schema-qualified *index* name, e.g. `DROP INDEX public.idx_film_title;`, not a
    table). Keep it optional so an unqualified drop works.
  - `selection::Reference`.
  - Constructors: `SqlDropIndexStatement(name)` (unqualified) and
    `SqlDropIndexStatement(schema, name)`.

Also:
- No manual export step: `@document` auto-exports the schema name and its
  spelling aliases (`DocumentMacro.jl` line 220 area), so `SqlCreateIndexStatement`
  and `SqlDropIndexStatement` export themselves. The `export` list at
  [Sql.jl:16-17](../../package/sql/main/Sql.jl#L16) today holds only the abstract
  categories (`SqlStatement`, `SqlSelectExpression`, …), not each concrete
  statement type — re-check this convention when implementing, since it differs
  from what this phase originally assumed.
- No separate umbrella wiring: `package/sql/main/ProjecturedSql.jl` already
  `include`s `Sql.jl` and re-binds every exported name automatically.
- Terse `Base.show`, matching the style of the other statement types in
  [Sql.jl](../../package/sql/main/Sql.jl) (e.g. `SqlCreateTableStatement` around
  line 258): `CREATE INDEX <name> ON <table>` and `DROP INDEX <name>`.

**Tests (Phase 2):** in `SqlDocumentTest.jl`:
- *Atomic:* construct each new statement; assert fields (`index_name`,
  `table_name`, `columns`, `schema_name`).
- *Combined:* build a `SqlStatementList` mixing a `SqlCreateTableStatement` and a
  `SqlCreateIndexStatement`; assert length and element types.

**➡ After Phase 2: update
[plan/done/dbcatalog-sql-document-support.md](../done/dbcatalog-sql-document-support.md)**
with the new structs (`DbCatalogIndex`, `SqlCreateIndexStatement`,
`SqlDropIndexStatement`).

---

## Phase 3 — Parser support

**Status:** ⬜ not started.

**File:** [package/sql/main/SqlParser.jl](../../package/sql/main/SqlParser.jl)

This is **only for ingesting external SQL text** — *not* on the `DbCatalogToSql`
path (which builds documents directly). Add:

1. **`INDEX` to `SQL_KEYWORDS`** ([SqlParser.jl:94-106](../../package/sql/main/SqlParser.jl#L94)).
   `CREATE`, `DROP`, `ON` are already keywords; `TABLE`/`SCHEMA` were added by the
   table-DDL work, and the same "not in keywords ⇒ silently tokenised as ident ⇒
   parser returns `nothing`" trap applies — so `INDEX` **must** be added.
   (`consume_ident!`'s structural-keyword exclusion list at
   [SqlParser.jl:305-309](../../package/sql/main/SqlParser.jl#L305) does not list
   `INDEX`/`TABLE`/`SCHEMA`, so they remain usable as identifiers elsewhere —
   leave it that way.)
2. **`CREATE INDEX` branch** in `parse_create_statement!`
   ([SqlParser.jl:376-384](../../package/sql/main/SqlParser.jl#L376)): on
   `match_keyword(p, "INDEX")`, dispatch to a new `parse_create_index!`:
   - `CREATE INDEX <index-name> ON [schema.]<table> ( <col> {, <col>} )`.
   - Index name via `consume_ident!`; expect `ON`; parse `[schema.]table` exactly
     like `parse_create_table!` does
     ([SqlParser.jl:404-410](../../package/sql/main/SqlParser.jl#L404)); parse a
     parenthesised comma-separated column-name list (reuse the `(` … `)` loop shape
     from `parse_create_table!` / the `USING (…)` list at
     [SqlParser.jl:792-805](../../package/sql/main/SqlParser.jl#L792)); build
     `SqlCreateIndexStatement`. `skip_trailing!` at the end.
3. **`DROP` dispatch.** `parse_sql` currently handles only `SELECT` and `CREATE`
   ([SqlParser.jl:325-341](../../package/sql/main/SqlParser.jl#L325)). Add a
   `match_keyword(p, "DROP")` branch → `parse_drop_statement!`:
   - `DROP INDEX [schema.]<index-name>` → `SqlDropIndexStatement`. Parse the
     optional `schema.` qualifier the same dotted-ident way. Anything other than
     `DROP INDEX` returns `nothing` (out of scope), matching how non-TABLE/SCHEMA
     `CREATE` returns `nothing`.
   - Update the `sqlparse` / `parse_sql` docstrings to mention DROP.
4. Import the two new statement types into the parser module's `import` list
   ([SqlParser.jl:31-40](../../package/sql/main/SqlParser.jl#L31)).

**Round-trip note** (same convention as the table-DDL round-trip tests): the
rendered form is *not* byte-identical to the input — the printer (Phase 5 of the
done-plan / `SqlToSyntax`) decides layout, spacing and the trailing `;`. Tests
compare against the rendered+normalised form, not the raw input.

**Tests (Phase 3):** in `SqlParserTest.jl`:
- *Atomic:* parse `CREATE INDEX idx ON public.film (title)` and
  `CREATE INDEX idx2 ON film (a, b)`; assert statement type, index name, table
  name (qualified + unqualified), column list. Parse
  `DROP INDEX public.idx` and `DROP INDEX idx`; assert type, name, schema.
- *Combined:* parse a `CREATE INDEX` and round-trip it back through the render
  pipeline (needs Phase 5's `SqlToSyntax` index printer — so the **round-trip**
  combined test is added/enabled in Phase 5; here, assert the parsed tree only).
  Also assert the parser still parses `CREATE TABLE` / `CREATE SCHEMA` / `SELECT`
  unchanged (regression).

> Sequencing note: pure-parse atomic tests can land in Phase 3. The parse→render
> round-trip combined test depends on Phase 5; add it there and reference it back.

---

## Phase 4 — DbCatalog → Syntax (browser) projection — **printer only**

**Status:** ⬜ not started.

**File:** [package/dbcatalog/main/DbCatalogToSyntax.jl](../../package/dbcatalog/main/DbCatalogToSyntax.jl)

This is the **interactive collapsible browser** view (direct `DbCatalog → Syntax`,
*not* SQL). Surface indexes under their table:

- Add a `DbCatalogIndexToSyntaxLeaf` (or small node) rendering an index as e.g.
  `index_name (col_a, col_b)` — follow `DbCatalogColumnToSyntaxLeaf`
  ([DbCatalogToSyntax.jl:54-60](../../package/dbcatalog/main/DbCatalogToSyntax.jl#L54)).
- Extend `DbCatalogTableToSyntaxNode`
  ([DbCatalogToSyntax.jl:253-263](../../package/dbcatalog/main/DbCatalogToSyntax.jl#L253))
  to show the index collection alongside the existing `Columns` body — likely a
  second keyword/body group (`Indexes`), through the shared helper
  `_catalog_syntax_node`
  ([DbCatalogToSyntax.jl:216](../../package/dbcatalog/main/DbCatalogToSyntax.jl#L216)),
  the same helper `DbCatalogTableToSyntaxNode` already calls for `columns` (the
  plan's original `projection_printer_recurse` name does not exist in the current
  file — the recursion happens inside `_catalog_syntax_node` via `print_child`).
  Reuse the lazy collapse-on-unrealized handling already in the file.
- Register `DbCatalogIndex => DbCatalogIndexToSyntaxLeaf()` in the
  `DbCatalogToSyntax()` `TypeDispatchingProjection`
  ([DbCatalogToSyntax.jl:362-369](../../package/dbcatalog/main/DbCatalogToSyntax.jl#L362)).

**Printer only:** selection/reference mapping can start minimal (read-only is fine,
matching the LLM-teaching use case and the done-plan's read-only stance). If the
node already delegates reference mapping for columns, extend it for indexes the
same way; otherwise return `nothing` like the other read-only catalog projections.

**Tests (Phase 4):** projection-level (no live DB; build catalogs by hand like
[DbCatalogSqlTest.jl:32-34](../../package/dbcatalog/test/external/DbCatalogSqlTest.jl#L32)):
- *Atomic:* project a `DbCatalogIndex` and assert its rendered leaf text.
- *Combined:* project a `DbCatalogTable` carrying columns **and** indexes through
  `DbCatalogToSyntax → SyntaxToText → TextToString`; assert the rendered browser
  text shows both groups. Assert a table with no indexes renders unchanged
  (regression vs. the existing browser output).

---

## Phase 5 — DbCatalog → SQL (DDL) projection — **printer only**

**Status:** ⬜ not started.

**Files:**
- [package/dbcatalog/main/DbCatalogToSql.jl](../../package/dbcatalog/main/DbCatalogToSql.jl)
- [package/sql/main/SqlToSyntax.jl](../../package/sql/main/SqlToSyntax.jl)
  (the rendering of the new SQL statements)

Two halves, both printer-only:

**5a — `SqlToSyntax` rendering** for the new statements (so they have SQL text).
Add, next to the existing DDL printers
([SqlToSyntax.jl:1955-2222](../../package/sql/main/SqlToSyntax.jl#L1955)):
- `SqlCreateIndexStatementToSyntaxNode` →
  `CREATE INDEX <name> ON <table> (col_a, col_b);` — keywords via `_kw`, the
  table name recursing through the existing `SqlTableName` printer, the column list
  as a `(` … `)` comma body, trailing `;` as the node's close delimiter (copy the
  shape of `SqlCreateTableStatementToSyntaxNode`). Decide single-line vs. the
  indented multi-line table style — single line reads better for an index; keep it
  single line unless the column list is long. **Document the chosen exact output**
  in the code comment and in this plan's Status after implementing.
- `SqlDropIndexStatementToSyntaxNode` → `DROP INDEX [schema.]<name>;` — single
  line; the name is a plain `String`/qualified string, so (like
  `SqlCreateSchemaStatementToSyntaxNode`) it has no projected child and maps only
  the `∅` selection.
- Register both in the `SqlToSyntax()` dispatcher
  ([SqlToSyntax.jl:2226](../../package/sql/main/SqlToSyntax.jl#L2226))
  and import/export them.
- Selection wiring: minimal/read-first is acceptable (done-plan precedent), but the
  `CREATE INDEX` table_name + column children should map forward/backward like
  `SqlCreateTableStatement` does if round-trip editing is wanted.

**5b — `DbCatalogToSql`** maps the catalog index into the SQL DDL document
([DbCatalogToSql.jl](../../package/dbcatalog/main/DbCatalogToSql.jl)):
- `DbCatalogIndexToSql`: `DbCatalogIndex` →
  `SqlCreateIndexStatement(index.name, SqlTableName([schema.]table), [SqlColumnName…])`.
  The **enclosing table name** (and schema) must be threaded down the printer
  context, the way the schema name is threaded via `:sql_schema_name`
  ([DbCatalogToSql.jl:49,83-91,101-108](../../package/dbcatalog/main/DbCatalogToSql.jl#L49)).
  Add a `:sql_table_name` property set by `DbCatalogTableToSql` before recursing
  its indexes, so each index can name its target table.
- `DbCatalogTableToSql`
  ([DbCatalogToSql.jl:81-91](../../package/dbcatalog/main/DbCatalogToSql.jl#L81))
  now emits **a `CREATE TABLE` plus one `CREATE INDEX` per index** — so a table no
  longer projects to a single statement but to a `SqlStatementList` (or its indexes
  are appended at the schema/database flatten level). Decide and record:
  - Option A: `DbCatalogTableToSql` returns a `SqlStatementList`
    `[CREATE TABLE, CREATE INDEX…]`; update `_flatten_statements`
    ([DbCatalogToSql.jl:58-65](../../package/dbcatalog/main/DbCatalogToSql.jl#L58))
    callers, and `DbCatalogSchemaToSql`
    ([DbCatalogToSql.jl:101-108](../../package/dbcatalog/main/DbCatalogToSql.jl#L101))
    which currently `push!`es a single table statement — switch it to flatten the
    table's list. **(Recommended — keeps "a table's full DDL" cohesive.)**
  - Option B: keep `CREATE TABLE` single and collect index statements separately.
  Option A is cleaner; confirm during implementation.
- Register `DbCatalogIndex => DbCatalogIndexToSql()` in the `DbCatalogToSql()`
  dispatcher
  ([DbCatalogToSql.jl:143-151](../../package/dbcatalog/main/DbCatalogToSql.jl#L143)).
- Read-only (`map_reference_*` / `projection_read` return `nothing`), matching the
  rest of `DbCatalogToSql`.

**Tests (Phase 5):**
- *Atomic (5a):* render `SqlCreateIndexStatement` and `SqlDropIndexStatement` to
  text through `SqlToSyntax → SyntaxToText → TextToString` (the `sql_text` helper at
  [SqlToSyntaxTest.jl:157-161](../../package/sql/test/projection/SqlToSyntaxTest.jl#L157));
  assert exact strings. Add the `CREATE INDEX` **parse→render round-trip** in
  `SqlParserTest.jl` deferred from Phase 3.
- *Atomic (5b):* project a `DbCatalogIndex` (with table/schema threaded) to a
  `SqlCreateIndexStatement`; assert fields.
- *Combined:* project a `DbCatalogTable` with columns **and** an index, and a
  `DbCatalogSchema` containing it, through the full
  `DbCatalog → Sql → Syntax → Text → String` pipeline (extend
  [DbCatalogSqlTest.jl](../../package/dbcatalog/test/external/DbCatalogSqlTest.jl)); assert the
  script contains `CREATE TABLE …`, `CREATE INDEX …` (in the right order), and that
  a table with no indexes renders exactly as before (regression).

---

## Phase 6 — DatabaseInstance → DbCatalog projection — **printer only**

**Status:** ⬜ not started.

**Files:**
- [package/odbc/main/ProjecturedOdbc.jl](../../package/odbc/main/ProjecturedOdbc.jl)
- [package/database/main/DatabaseAdapters.jl](../../package/database/main/DatabaseAdapters.jl) (adapter query)

Populate the catalog's index collection from a live database, lazily:

- Add a `db_catalog_indexes(adapter, schema, table) -> Vector{NamedTuple}` to the
  adapter layer, next to `db_catalog_columns`
  ([Database.jl:369-379](../../package/database/main/DatabaseAdapters.jl#L369)): a generic
  `error("… not implemented")` fallback plus the `OdbcDatabaseAdapter` method.
  Suggested PostgreSQL query (returns each index with its ordered column list):

  ```sql
  SELECT i.relname AS index_name,
         a.attname AS column_name,
         array_position(ix.indkey, a.attnum) AS ord
  FROM pg_class t
  JOIN pg_namespace n  ON n.oid = t.relnamespace
  JOIN pg_index ix     ON ix.indrelid = t.oid
  JOIN pg_class i      ON i.oid = ix.indexrelid
  JOIN pg_attribute a  ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
  WHERE n.nspname = '<schema>' AND t.relname = '<table>'
  ORDER BY i.relname, ord;
  ```

  Group rows by `index_name` into `(name=…, column_names=[…])` (ordered).
  Confirm/iterate the exact catalog columns at implementation time (the existing
  queries use `information_schema`; indexes are easier via `pg_catalog`). Keep the
  `array_position` ordering so multi-column indexes preserve column order.
- Add a `_build_indexes(pool, inst, schema_name, table_name)` lazy `CellVector`
  builder mirroring `_build_columns`
  ([DatabaseInstanceToDbCatalog.jl:39-46](../../package/odbc/main/ProjecturedOdbc.jl#L39))
  and pass it into the `DbCatalogTable` constructor in `_build_tables`
  ([DatabaseInstanceToDbCatalog.jl:48-56](../../package/odbc/main/ProjecturedOdbc.jl#L48)).
- Import `db_catalog_indexes` into the projection module
  ([ProjecturedOdbc.jl:26-27](../../package/odbc/main/ProjecturedOdbc.jl#L26))
  and export the new adapter fn from `package/odbc/main/ProjecturedOdbc.jl`, the
  package's own module file — there is no separate umbrella file.
- Still read-only — no reference mapping/read support (unchanged).

**Tests (Phase 6):** live-DB, gated by `skip_if_no_db`, in
[package/odbc/test/external/DatabaseTest.jl](../../package/odbc/test/external/DatabaseTest.jl)
(follow `test_db_catalog_to_sql_live` /
[`test_create_ddl_in_test_schema`](../../package/odbc/test/external/DatabaseTest.jl#L166),
all inside a dedicated `test` schema, torn down in reverse):
- *Atomic:* create a table + index in the `test` schema, call
  `db_catalog_indexes(adapter, "test", <table>)`, assert the index name and ordered
  column list. (A pure no-DB unit test can cover the grouping/ordering logic by
  feeding synthetic rows, if the grouping is factored into a testable helper.)
- *Combined:* build the catalog via `DatabaseInstanceToDbCatalog`, force the table
  subtree, and assert the `DbCatalogTable` exposes both its columns and its
  indexes; then project that catalog through `DbCatalogToSql` (Phase 5) and assert
  the generated script includes the `CREATE INDEX`. Tear down in reverse
  (`DROP INDEX` → `DROP TABLE` → `DROP SCHEMA`) with a `finally` safety net.

---

## Cross-cutting checklist

- Every new document type exported through its own module. There is no
  umbrella `Projectured.jl` any more — each package's own
  `Projectured<Name>.jl` (e.g. `package/dbcatalog/main/ProjecturedDbCatalog.jl`,
  `package/sql/main/ProjecturedSql.jl`) already `include`s the domain file and
  re-binds every exported name automatically.
- Bidirectional rule (CLAUDE.md): printers added here are read-first, but where a
  printer maps children (CREATE INDEX table/columns), wire the matching
  forward/backward reference mapping so selection can round-trip — or explicitly
  record "read-only, deferred" in the phase Status.
- Run the **smallest** covering test each phase; reach for `test_projections()` /
  broader sweeps only after the targeted atomic+combined tests pass.

## Reference reading

- [plan/done/dbcatalog-sql-document-support.md](../done/dbcatalog-sql-document-support.md)
  — the table/schema DDL precedent this extends (conventions, decisions, gotchas).
- [plan/pending/sql-parser.md](../done/sql-parser.md) — parser architecture and
  error/round-trip conventions.
- [package/kernel/doc/projection-system.md](../../package/kernel/doc/projection-system.md) and
  [package/json/doc/json.md](../../package/json/doc/json.md) — printer/IO-map pattern.
