# DbCatalog → SQL DDL document support

Give the database catalog an **executable-SQL (DDL)** representation, built the
projectional way: a new `DbCatalogToSql` projection maps the catalog tree into
**SQL DDL document nodes**, which the existing SQL rendering pipeline
(`SqlToSyntax → SyntaxToText → TextToString`) turns into `CREATE …` text.

This plan covers three layers that ship together:

1. New SQL **DDL document types** in `Sql.jl`.
2. **`SqlToSyntax`** rendering for those types (+ optional **`SqlParser`** support).
3. **`DbCatalogToSql`** projection: catalog → DDL document tree, built directly.

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

## Layer 1 — SQL DDL document types

**File:** `program/src/document/Sql.jl`

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

## Layer 2 — `SqlToSyntax` rendering (+ optional parser)

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

**Parser (optional, can land later in this plan or be deferred):**
**File:** `program/src/parser/SqlParser.jl`

`sqlparse` currently parses **SELECT only**
([SqlParser.jl:4](../../program/src/parser/SqlParser.jl#L4)). Extend the
recursive-descent parser to recognise `CREATE TABLE` / `CREATE SCHEMA` so
external DDL text round-trips into the new document types. This is **only needed
for ingesting external SQL** — it is *not* on the `DbCatalogToSql` path. If time
is short, ship Layers 1–3 and rendering first; add DDL parsing as a follow-up.
See [plan/pending/sql-parser.md](sql-parser.md) for the parser's architecture and
error/round-trip conventions to match.

---

## Layer 3 — `DbCatalogToSql` projection

**File (new):** `program/src/projection/primitive/DbCatalogToSql.jl`

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
  names are wanted.

---

## Testing

Per repo convention, run the **smallest** covering test, never `test_all`:

- `test_sql()` / `test_printer(sql_example)` after Layer 2 for DDL rendering.
- A new DDL example document exercising `SqlCreateTableStatement` round-trips
  (`test_example(...)`), and a parser example (`test_reader(...)`) if Layer-2
  parser support lands.
- A `DbCatalogToSql` example feeding the full
  `DbCatalog → Sql → Syntax → Text → String` pipeline; assert the emitted SQL is
  the expected `CREATE TABLE …`.

See [guide/testing.md](../../guide/testing.md) and
[CLAUDE.md](../../CLAUDE.md) "Testing a change".

---

## Out of scope

- Renaming the existing `DbCatalogToSyntax` browser projection (separate change).
- Generic `ObjectToJson` — see
  [plan/pending/object-to-json-projection.md](object-to-json-projection.md).
- Catalog model enrichment (keys, FKs, nullability, indexes) — prerequisite for
  richer DDL, tracked separately.
