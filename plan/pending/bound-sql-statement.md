# Bound SQL statement document model

Combines a database-agnostic `SqlStatement` document tree with a `DbCatalog`
schema to produce a `BoundSqlStatement` document tree. The bound tree mirrors
the structure of `SqlStatement` exactly; enrichment slots (`DbCatalogTable?`,
`DbCatalogColumn?`) appear at the nodes where catalog identity is meaningful.
Slots start as `nothing`; the binding projection populates them.

---

## Motivation

`SqlStatement` carries only string identifiers (`SqlTableName`, `SqlColumnName`).
`DbCatalog` holds live schema objects with type information. Features such as
column-type display, hover documentation, and validation need both trees together.
`BoundSqlStatement` is the document that holds this combined view.

Separation of concerns:

- `SqlStatement` — syntactic form; DB-agnostic; used by `SqlToSyntax` and `render_sql`.
- `DbCatalog` — live schema metadata; built by `DatabaseInstanceToDbCatalog`.
- `BoundSqlStatement` — combined view; built by the binding projection; consumed
  by type-aware display, validation, and completion.

---

## Projection name

`SqlToBoundSql` — follows the `XToY` / `SqlToSyntax` precedent. The
`DbCatalogSchema` is passed as a constructor parameter so the projection is
reusable across statements.

---

## 1. Document hierarchy

### Abstract types

```
BoundSqlDocument (abstract)
├── BoundSqlStatement (abstract)
├── BoundSqlSelectExpression (abstract)
└── BoundSqlFromBaseItem (abstract)
```

### Enrichment leaf nodes

These are the only nodes that carry new catalog fields. The original `Sql*`
document is kept as `sql` for rendering fallback and provenance.

```
BoundSqlTableExpression <: BoundSqlFromBaseItem
    sql           : SqlTableExpression
    catalog_table : DbCatalogTable | nothing

BoundSqlSubqueryFromItem <: BoundSqlFromBaseItem
    sql      : SqlSubqueryFromItem    -- carries alias for rendering
    subquery : BoundSqlSelectStatement

BoundSqlColumnReference <: BoundSqlSelectExpression
    sql            : SqlColumnReference
    catalog_column : DbCatalogColumn | nothing

BoundSqlAllColumns <: BoundSqlSelectExpression
    sql           : SqlAllColumns
    catalog_table : DbCatalogTable | nothing   -- table resolved from qualifier
```

### Structural wrapper nodes

Structural nodes carry only the fields that differ from the `SqlStatement`
side. Fields that carry no catalog-bindable content are included directly.

```
BoundSqlJoinSegment
    join_type : SqlJoinType          -- unchanged; no catalog binding
    from_item : BoundSqlFromBaseItem -- enriched
    condition : SqlJoinCondition | nothing  -- unchanged

BoundSqlFromItem
    base_item : BoundSqlFromBaseItem
    joins     : [BoundSqlJoinSegment]

BoundSqlFromClause
    items : [BoundSqlFromItem]

BoundSqlSelectItem
    expression   : BoundSqlSelectExpression
    column_alias : SqlColumnAlias | nothing   -- unchanged

BoundSqlSelectClause
    distinct : SqlDistinct | nothing  -- unchanged
    items    : [BoundSqlSelectItem]

BoundSqlSelectStatement <: BoundSqlStatement
    sql           : SqlSelectStatement    -- original; full provenance
    select_clause : BoundSqlSelectClause
    from_clause   : BoundSqlFromClause
    where_clause  : SqlWhereClause        -- unchanged; no binding in WHERE yet
```

`SqlWhereClause`, `SqlJoinCondition`, `SqlJoinType`, `SqlColumnAlias`, and
`SqlTableAlias` are reused unchanged — they carry no catalog-bindable identifiers
in the current scope.

---

## 2. Full tree example

Starting from the example in `sql-statement.md`:

```
SELECT sub.person_name FROM (SELECT name AS person_name FROM "persons") AS sub
```

the bound tree looks like:

```julia
BoundSqlSelectStatement(
    sql = <original SqlSelectStatement>,
    select_clause = BoundSqlSelectClause(
        distinct = nothing,
        items = [BoundSqlSelectItem(
            expression   = BoundSqlColumnReference(
                sql            = SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name")),
                catalog_column = nothing),   # <── populated by SqlToBoundSql
            column_alias = nothing)]),
    from_clause = BoundSqlFromClause(items = [BoundSqlFromItem(
        base_item = BoundSqlSubqueryFromItem(
            sql = SqlSubqueryFromItem(<subquery>, SqlTableAlias("sub")),
            subquery = BoundSqlSelectStatement(
                sql = <inner SqlSelectStatement>,
                select_clause = BoundSqlSelectClause(items = [BoundSqlSelectItem(
                    expression   = BoundSqlColumnReference(
                        sql            = SqlColumnReference(SqlColumnName("name")),
                        catalog_column = nothing),   # <── populated
                    column_alias = SqlColumnAlias("person_name"))]),
                from_clause = BoundSqlFromClause(items = [BoundSqlFromItem(
                    base_item = BoundSqlTableExpression(
                        sql           = SqlTableExpression(SqlTableName("persons")),
                        catalog_table = nothing),    # <── populated
                    joins = [])]),
                where_clause = SqlWhereClause())),
        joins = [])]),
    where_clause = SqlWhereClause())
```

---

## 3. Module: `BoundSql.jl`

**File:** `program/src/document/BoundSql.jl`
**Module:** `BoundSqlDocumentModule`

Included after `Sql.jl` and `DbCatalog.jl` in `program/src/Projectured.jl`.

Imports: `SqlDocumentModule` (all wrapped `Sql*` types), `DbCatalogDocumentModule`
(`DbCatalogTable`, `DbCatalogColumn`).

Exports: all `BoundSql*` types and their `IBoundSql*` interface wrappers,
plus convenience constructors.

---

## 4. Projection: `SqlToBoundSql`

**File:** `program/src/projection/primitive/SqlToBoundSql.jl`
**Module:** `SqlToBoundSqlModule`

### Constructor

```julia
struct SqlToBoundSql <: Projection
    catalog_schema :: DbCatalogSchema
end
```

The schema is the lookup scope. Cross-schema resolution is out of scope.

### `projection_print` walk

Bottom-up (subqueries before enclosing query):

1. Build a `String → DbCatalogTable` map from `catalog_schema.tables`.
2. Build a `(table_name, column_name) → DbCatalogColumn` map from each table's `columns`.
3. For each `SqlFromItem` in `from_clause`:
   - `SqlTableExpression` → `BoundSqlTableExpression(sql, lookup(table_name))`
   - `SqlSubqueryFromItem` → recurse first; `BoundSqlSubqueryFromItem(sql, bound_subquery)`
   - Each join: `BoundSqlJoinSegment(join_type, bound_from_item, condition)`
4. For each `SqlSelectItem` in `select_clause`:
   - `SqlColumnReference` → `BoundSqlColumnReference(sql, lookup(qualifier, column_name))`
   - `SqlAllColumns` → `BoundSqlAllColumns(sql, lookup(qualifier))`
5. Return `BoundSqlSelectStatement(sql, bound_select_clause, bound_from_clause, where_clause)`.

Read-only v1: no `projection_read`, no reference mapping.

---

## 5. Out of scope

- `BoundSqlInsertStatement`, `BoundSqlUpdateStatement` (parallel to `SqlStatement` stubs).
- Binding for WHERE / JOIN condition expressions (no concrete expression types yet).
- Cross-schema table resolution.
- Validation or error reporting for unresolved names (diagnostic layer, later).
- Rendering `BoundSqlStatement` to syntax — a separate `BoundSqlToSyntax` projection.

---

## 6. Implementation steps

1. **Create `program/src/document/BoundSql.jl`** — all `BoundSql*` structs and
   convenience constructors with default `nothing` catalog slots.
2. **Wire into `program/src/Projectured.jl`** — include after `Sql.jl` / `DbCatalog.jl`;
   add exports.
3. **Write document tests** in `test/src/document/BoundSqlDocumentTest.jl` —
   constructor round-trips; confirm catalog slots default to `nothing`.
4. **Create `program/src/projection/primitive/SqlToBoundSql.jl`** —
   `projection_print` for `SqlSelectStatement`.
5. **Wire projection into `program/src/Projectured.jl`** — include and export `SqlToBoundSql`.
6. **Write projection tests** in `test/src/projection/SqlToBoundSqlTest.jl` —
   bind `SELECT name, age FROM persons` against a `DbCatalogSchema` containing
   `persons(name TEXT, age INT)`; assert `catalog_table` and `catalog_column` are
   the expected `DbCatalogTable` / `DbCatalogColumn` instances; verify unresolved
   names leave the slot as `nothing`.

---

## 7. Dependencies

- `SqlDocumentModule` (`Sql.jl`) — must be loaded first.
- `DbCatalogDocumentModule` (`DbCatalog.jl`) — must be loaded first.
- `resolve_sql_names!` should be called on the `SqlSelectStatement` before
  passing it to `SqlToBoundSql` so qualifier back-references are canonical.
