# DbCatalog → SQL DDL document support

Give the database catalog an **executable-SQL (DDL)** representation, built the
projectional way: a new `DbCatalogToSql` projection maps the catalog tree into
**SQL DDL document nodes**, which the existing SQL rendering pipeline
(`SqlToSyntax → SyntaxToText → TextToString`) turns into `CREATE …` text.

This plan covers three layers that ship together:

1. New SQL **DDL document types** in `Sql.jl`.
2. **`SqlToSyntax`** rendering for those types (+ optional **`SqlParser`** support).
3. **`DbCatalogToSql`** projection: catalog → DDL document tree, built directly.

## Status (2026-06-21)

- **Layer 1 — DONE.** `SqlColumnDefinition`, `SqlCreateTableStatement`,
  `SqlCreateSchemaStatement` added to `Sql.jl`, exported through `Projectured.jl`.
- **Layer 2 — DONE, including the optional parser.** `SqlToSyntax` renders all
  three types; `SqlParser` now parses `CREATE TABLE` / `CREATE SCHEMA` too. Both
  the offline `SqlToSyntax`/`SqlParser` suites and a live-DB round-trip test pass.
- **Layer 3 — DONE.** `DbCatalogToSql` projects the catalog tree directly into
  SQL DDL documents (a new `SqlStatementList` container holds the CREATE-script
  sequence). Schema qualification is threaded through the printer context. Pure
  and live-DB tests pass — the generated script executes on real PostgreSQL.

The goal that motivates this: a representation of a database that is *easy for an
LLM to understand*. DDL (`CREATE TABLE …`) is the most idiomatic, highest-prior
form an LLM has for "how a database looks", far more than a bespoke syntax tree.

---

## Why this shape (decisions already made)

- **Compound, not direct.** The DDL view is assembled as
  `SequentialProjection(DbCatalogToSql(), SqlToSyntax())` (each stage wrapped in
  `RecursiveProjection`, the way `print_object` chains its stages in
  [ObjectToSyntax.jl](../../program/src/projection/primitive/ObjectToSyntax.jl)).
  There is **no direct `DbCatalog → Syntax` DDL projection** — `SqlToSyntax` is
  the single source of truth for SQL text, so we reuse it rather than duplicate
  SQL-rendering knowledge.
- **`DbCatalogToSql` builds the SQL document tree directly — NOT print-and-parse.**
  A projection's `projection_print` must return an IO map linking input nodes to
  the output nodes they produced; that correspondence is what makes selection
  mapping / bidirectionality possible. Serialising the catalog to text and
  re-parsing it with `SqlParser` would throw the IO map away, force two grammars
  (emitter + parser) to stay byte-compatible, and is backwards (the catalog is
  already a structured tree). The parser exists for the opposite direction:
  ingesting *external* SQL text. See the reference projections that all build
  their output directly:
  [DbCatalogToJson.jl](../../program/src/projection/primitive/DbCatalogToJson.jl),
  [JsonToSyntax.jl](../../program/src/projection/primitive/JsonToSyntax.jl).
- **The existing `DbCatalogToSyntax` browser is left as-is.** It is a *direct*
  `DbCatalog → Syntax` projection producing an interactive, collapsible, lazy,
  bidirectional database-browser tree
  ([DbCatalogToSyntax.jl](../../program/src/projection/primitive/DbCatalogToSyntax.jl)).
  Its output shape (entity → keyword → body UI) is not SQL, so it cannot route
  through the Sql domain — it stays a separate, direct projection. A later,
  separate rename (e.g. `DbCatalogToBrowserSyntax`) can free the canonical
  `…ToSyntax`-means-canonical-text naming slot; **out of scope here.**

So the two catalog views coexist deliberately:

| View | Output | Path |
|---|---|---|
| Browser (existing `DbCatalogToSyntax`) | interactive collapsible tree | **direct** `DbCatalog → Syntax` |
| DDL (this plan) | executable `CREATE …` text | **compound** `DbCatalog → Sql → Syntax` |

---

## Layer 1 — SQL DDL document types ✅ DONE

**File:** `program/src/document/Sql.jl`

**As implemented:** `SqlColumnDefinition` (`column_name::SqlColumnName`,
`data_type::String`), `SqlCreateTableStatement` (`table_name::SqlTableName`,
`columns::CellVector`), `SqlCreateSchemaStatement` (`schema_name::String`) — each
with the `selection::Reference` field, convenience constructors that default the
selection to `Cell(nothing)` and accept plain vectors / bare strings, and terse
`Base.show` methods. Names are wired into the `using .SqlDocumentModule` import
list and `export` list in `Projectured.jl`. Scope kept to name + type only (no
nullable/default/constraints), matching what the catalog holds.

The Sql domain currently models only `SqlSelectStatement` plus stub
`SqlInsertStatement` / `SqlUpdateStatement` (selection-only). Add DDL statement
and supporting types, following the existing `@document struct … selection::Reference`
convention with convenience constructors that default `selection = Cell(nothing)`
and auto-wrap values in Cells.

Reuse what already exists: `SqlTableName` already carries an optional
`schema_name` ([Sql.jl:71](../../program/src/document/Sql.jl#L71)); `SqlColumnName`
exists ([Sql.jl:87](../../program/src/document/Sql.jl#L87)).

New types (initial scope — keep minimal, extend later):

- `SqlColumnDefinition <: SqlDocument` — `column_name::SqlColumnName`,
  `data_type::String` (the catalog stores the type as a plain string), plus room
  to grow (`nullable`, `default`, `constraints`) later. Start with name + type.
- `SqlCreateTableStatement <: SqlStatement` — `table_name::SqlTableName`,
  `columns::CellVector` ( `[SqlColumnDefinition]` ).
- `SqlCreateSchemaStatement <: SqlStatement` — `schema_name::String`.
- (later, flagged but not required now) `SqlCreateDatabaseStatement`,
  `SqlCreateIndexStatement`.

Notes:
- The catalog has **no keys / FKs / nullability / indexes**
  ([DbCatalog.jl](../../program/src/document/DbCatalog.jl)), so the first DDL cut
  carries only what the catalog actually holds (table name, column name+type). Do
  not invent constraint fields the source can't populate — that is a *catalog
  model* gap to fill separately before richer DDL is meaningful.
- Add `Base.show` methods matching the existing terse style at
  [Sql.jl:324](../../program/src/document/Sql.jl#L324).

---

## Layer 2 — `SqlToSyntax` rendering (+ optional parser) ✅ DONE

**As implemented (rendering):** three projections in
`program/src/projection/primitive/SqlToSyntax.jl`, registered in the
`SqlToSyntax()` dispatcher and exported via `Projectured.jl`:

- `SqlColumnDefinitionToSyntaxNode` — `<column-name> <data-type>`; the column name
  recurses through the existing `SqlColumnName` leaf, the type is a plain leaf
  (it's a `String` on the document, so no projected child).
- `SqlCreateTableStatementToSyntaxNode` — multi-line, schema-qualified, with the
  column list in an indented `(` … `)` body node (`indentation=1`) and a trailing
  `;` carried as the node's **close** delimiter. Child positions: `[1]`=CREATE,
  `[2]`=TABLE, `[3]`=table_name, `[4]`=columns body.
- `SqlCreateSchemaStatementToSyntaxNode` — single line `CREATE SCHEMA name;`. The
  schema name is a plain `String` (no projected child), so the statement has
  **no child iomaps** and maps only the whole-statement (`∅`) selection.

Selection mapping is fully wired (forward/backward + `projection_read`) and
round-trips (verified: `columns[2].column_name ↔ children[4].children[2].children[1]`,
`table_name ↔ children[3]`). Rendered indentation is the project standard **2
spaces**, e.g. `CREATE TABLE public.film (\n  title text,\n  len integer\n);`.

**File:** `program/src/projection/primitive/SqlToSyntax.jl`

Add `projection_print` (and the bidirectional `map_reference_forward/backward`,
`projection_read` where editing is wanted) for each new DDL type, registered in
the `SqlToSyntax()` `TypeDispatchingProjection`
([SqlToSyntax.jl:48](../../program/src/projection/primitive/SqlToSyntax.jl)). Render:

```
CREATE TABLE schema.table (
    col_a integer,
    col_b text
);

CREATE SCHEMA name;
```

- Keywords (`CREATE`, `TABLE`, `SCHEMA`) as bold colored leaves via the existing
  `_kw` helper; identifiers as regular leaves.
- Column list as a comma/newline body node (`_comma_body` / `_newline_body`
  helpers already in the file).
- Selection/IO-map wiring can start minimal (read-only is acceptable for the
  LLM-teaching use case) and follow the `ChildrenIoMap` clause-delegation pattern
  used by `SqlSelectStatementToSyntaxNode` when round-trip editing is wanted.

**Parser ✅ DONE (was optional; INSERT/UPDATE parsing explicitly excluded).**
**File:** `program/src/parser/SqlParser.jl`

`sqlparse` now dispatches on the leading keyword: `SELECT` → existing query path,
`CREATE` → new DDL path (`CREATE TABLE` / `CREATE SCHEMA`); anything else still
returns `nothing` → raises. This is **only for ingesting external SQL** — *not*
on the `DbCatalogToSql` path.

Learnings worth keeping:

- **`TABLE` and `SCHEMA` were not in `SQL_KEYWORDS`** and tokenised as plain
  identifiers, so `match_keyword(p, "TABLE")` failed silently — the parser just
  returned `nothing`. Fix: add both to the keyword set. (`consume_ident!`'s
  structural-keyword exclusion list does not include them, so they can still be
  used as identifiers elsewhere.)
- **Data type is captured as greedy raw source text** (`parse_data_type!`),
  paren-aware so `numeric(10, 2)` / `varchar(255)` stay whole, stopping at the
  top-level `,` or `)`. The model has only `data_type::String`, so any trailing
  per-column constraints (`NOT NULL`, `PRIMARY KEY`, …) would fold into that
  string — acceptable for the minimal cut; richer DDL needs catalog enrichment
  first (out of scope, tracked separately).
- Round-trip through the render pipeline is **not byte-identical** to the input:
  the renderer adds the indented multi-line layout, spaces inside the parens, and
  a trailing `;`. Tests compare against the rendered+normalised form, not the raw
  input (same convention as the SELECT round-trip tests).

See [plan/pending/sql-parser.md](sql-parser.md) for the parser's architecture and
error/round-trip conventions.

---

## Layer 3 — `DbCatalogToSql` projection ✅ DONE

**File (new):** `program/src/projection/primitive/DbCatalogToSql.jl`

**As implemented:** a `TypeDispatchingProjection` over the five catalog types,
mirroring `DbCatalogToJson` — each `projection_print` builds the SQL DDL document
directly and recurses children through `projection_printer_recurse` (so wrapping
in `RecursiveProjection` fully walks the lazy catalog):

- `DbCatalogColumn` → `SqlColumnDefinition`
- `DbCatalogTable`  → `SqlCreateTableStatement`, schema-qualified when the
  enclosing schema name is present in context
- `DbCatalogSchema` → `SqlStatementList` of `CREATE SCHEMA` + one `CREATE TABLE`
  per table
- `DbCatalogDatabase` / `DbCatalogRdbms` → the contained statements **flattened**
  into one `SqlStatementList` (a clean single script, not nested lists)

Decisions made against the open questions:

- **Statement granularity / container.** Added a new `SqlStatementList`
  (`<: SqlDocument`, holds `statements::CellVector`) to the Sql domain, plus
  `SqlStatementListToSyntaxNode` in `SqlToSyntax` that renders statements
  blank-line separated (each already ends with `;`). This keeps everything routing
  through `SqlToSyntax` — no bespoke catalog→syntax SQL rendering. A schema
  projects to one list; database/rdbms flatten their descendants' lists.
- **Schema qualification source.** The enclosing schema name is threaded down via
  the printer-context property `:sql_schema_name` (`with_property` /
  `get_property`); a table reads it to emit `schema.table`, or an unqualified name
  when absent (standalone table projection).
- **Lazy children.** Read-only serialiser, so it forces the whole subtree by
  nature (iterating each lazy child `CellVector` and recursing). `map_reference_*`
  and `projection_read` return `nothing`, exactly like `DbCatalogToJson`.

A `TypeDispatchingProjection` over the catalog types, mirroring the structure of
[DbCatalogToJson.jl](../../program/src/projection/primitive/DbCatalogToJson.jl).
Each `projection_print` **constructs the SQL DDL document directly**:

- `DbCatalogColumn` → `SqlColumnDefinition(SqlColumnName(col.name), col.data_type)`
- `DbCatalogTable`  → `SqlCreateTableStatement(SqlTableName(table.name),
   CellVector([... SqlColumnDefinition per column ...]))`
   (schema-qualify via `SqlTableName(schema, name)` when the enclosing schema is
   known through the printer context).
- `DbCatalogSchema` → `SqlCreateSchemaStatement(schema.name)` and/or a sequence of
  its tables' `CREATE TABLE`s — decide whether a schema projects to one statement
  or a statement list (see open question).
- `DbCatalogDatabase` / `DbCatalogRdbms` → a list/sequence of the contained
  schema/table statements.

Read-only to start (`map_reference_*` and `projection_read` return `nothing`,
exactly like `DbCatalogToJson`); it is a serialiser for LLM consumption, not an
editor view. A reader can be added later if "edit the DDL → mutate the catalog"
is ever wanted (which is the moment the Layer-2 parser support pays off).

Register the new module in `program/src/Projectured.jl` alongside the other
projection includes/imports.

---

## Assembling the view

```julia
SequentialProjection(
    RecursiveProjection(DbCatalogToSql()),
    RecursiveProjection(SqlToSyntax()),
    RecursiveProjection(SyntaxToText()),   # when a string is wanted (e.g. LLM input)
    RecursiveProjection(TextToString()),
)
```

For display inside the editor, stop at `SqlToSyntax` (Syntax domain) and let the
normal widget/graphics pipeline render it.

---

## Open questions

- **Statement granularity above table level.** Does a `DbCatalogSchema` project to
  a single `CREATE SCHEMA` + N `CREATE TABLE`s (a statement list), or just the
  tables? Likely a list document / sequence node; confirm the container shape
  (does the Sql domain need a `SqlStatementList`, or do we lean on a
  collection/`CellVector` projection?).
- **Lazy children.** Catalog child collections are lazy `CellVector`s populated by
  `DatabaseInstanceToDbCatalog`. The browser handles this with collapse-on-unrealized
  ([DbCatalogToSyntax.jl:186](../../program/src/projection/primitive/DbCatalogToSyntax.jl#L186)).
  DDL serialisation forces the whole subtree by nature — decide whether
  `DbCatalogToSql` should force eagerly or only project already-materialised nodes.
- **Schema qualification source.** `SqlTableName` supports `schema.name`; the
  catalog table doesn't know its parent schema name. Thread the enclosing schema
  through the printer context (`child_context` / `with_property`) if qualified
  names are wanted. *(Output side confirmed working in Layer 2: a
  `SqlTableName("test", "ddl_roundtrip")` renders and executes as
  `CREATE TABLE test.ddl_roundtrip …`; only the catalog-side threading remains.)*

---

## Testing

Per repo convention, run the **smallest** covering test, never `test_all`:

**Landed (Layers 1–3):**

- `test_sql_ddl()` / `test_sql_ddl_selection()` in `SqlToSyntaxTest.jl` — DDL
  rendering (`CREATE TABLE` / `CREATE SCHEMA` / column definition) and
  forward/backward selection round-trips. Wired into `test_projections()`.
- The DDL `CREATE` cases in `test_sql_parser()` (`SqlParserTest.jl`) round-trip
  parsed DDL back through the render pipeline.
- `test_create_ddl_in_test_schema(adapter)` in `external/DatabaseTest.jl` — a
  **live-DB** lifecycle against `projectured_test`, run **inside a dedicated
  `test` schema** (never `public`): create order `CREATE SCHEMA test` →
  `CREATE TABLE test.ddl_roundtrip (…)`, verified via `information_schema`, then
  teardown in reverse `DROP TABLE` → `DROP SCHEMA` (with a reverse-order `finally`
  safety net). Gated by `skip_if_no_db`, so it's a no-op without a database.

- `test_db_catalog_sql()` in `external/DbCatalogSqlTest.jl` — pure construction
  (no DB): per-type projection, schema qualification, schema/database flattening,
  and full-pipeline `DbCatalog → Sql → Syntax → Text → String` rendering asserts.
  Wired into `test_projections()`.
- `test_db_catalog_to_sql_live(adapter)` (T9 in `external/DatabaseTest.jl`) —
  builds a catalog rooted at a `test` schema, projects it to a DDL script, and
  **executes the generated script** against `projectured_test` (split per
  statement for the ODBC path), verifying via `information_schema` and tearing
  down in reverse order.

See [guide/testing.md](../../guide/testing.md) and
[CLAUDE.md](../../CLAUDE.md) "Testing a change".

---

## Out of scope

- Renaming the existing `DbCatalogToSyntax` browser projection (separate change).
- Generic `ObjectToJson` — see
  [plan/pending/object-to-json-projection.md](object-to-json-projection.md).
- Catalog model enrichment (keys, FKs, nullability, indexes) — prerequisite for
  richer DDL, tracked separately.
