# Bound SQL statement document model

Combines a database-agnostic `SqlStatement` document tree with a `DbCatalog`
schema to produce a `BoundSqlStatement` document tree. The projection reuses
the existing `Sql*` structural containers (`SqlSelectClause`, `SqlFromClause`,
`SqlFromItem`, `SqlJoinSegment`, `SqlSelectItem`) and replaces only the
catalog-meaningful leaf nodes with `BoundSql*` enrichment nodes. Enrichment
slots (`DbCatalogTable?`, `DbCatalogColumn?`) start as `nothing`; the binding
projection populates them.

`@document` fields are `Cell`-wrapped `Any` at runtime — declared type
annotations are documentary, not enforced — so `BoundSql*` leaf nodes sit in
the same structural positions as their `Sql*` counterparts without type errors.

---

## Motivation

`SqlStatement` carries only string identifiers (`SqlTableName`, `SqlColumnName`).
`DbCatalog` holds live schema objects with type information. Features such as
column-type display, hover documentation, and validation need both trees together.
`BoundSqlStatement` is the document that holds this combined view.

Separation of concerns:

- `SqlStatement` — syntactic form; DB-agnostic; used by `SqlToSyntax` and the projection pipeline.
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

### New abstract types

```
BoundSqlStatement (abstract)
BoundSqlSelectExpression (abstract)
BoundSqlFromBaseItem (abstract)
```

### Enrichment leaf nodes

Four new concrete types — the only nodes that carry new catalog fields.
Each wraps its original `Sql*` document for rendering fallback and provenance.

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

### Top-level statement

```
BoundSqlSelectStatement <: BoundSqlStatement
    sql           : SqlSelectStatement   -- original; full provenance
    select_clause : SqlSelectClause      -- new instance; items hold BoundSql* expressions
    from_clause   : SqlFromClause        -- new instance; items hold SqlFromItem with BoundSql* base_items
    selection     : Reference
```

`where_clause` is accessed from `sql.where_clause` directly — no binding in
WHERE yet. All other `Sql*` structural containers (`SqlSelectClause`,
`SqlFromClause`, `SqlFromItem`, `SqlJoinSegment`, `SqlSelectItem`) and leaf
types (`SqlWhereClause`, `SqlJoinCondition`, `SqlJoinType`, `SqlColumnAlias`,
`SqlTableAlias`) are reused unchanged — only new instances are created by the
projection, replacing `Sql*` leaf nodes with `BoundSql*` where applicable.

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
    select_clause = SqlSelectClause(
        SqlSelectItem(
            BoundSqlColumnReference(
                sql            = SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name")),
                catalog_column = nothing))),   # <── populated by SqlToBoundSql
    from_clause = SqlFromClause(
        SqlFromItem(
            BoundSqlSubqueryFromItem(
                sql = SqlSubqueryFromItem(<subquery>, SqlTableAlias("sub")),
                subquery = BoundSqlSelectStatement(
                    sql = <inner SqlSelectStatement>,
                    select_clause = SqlSelectClause(
                        SqlSelectItem(
                            BoundSqlColumnReference(
                                sql            = SqlColumnReference(SqlColumnName("name")),
                                catalog_column = nothing),   # <── populated
                            SqlColumnAlias("person_name"))),
                    from_clause = SqlFromClause(
                        SqlFromItem(
                            BoundSqlTableExpression(
                                sql           = SqlTableExpression(SqlTableName("persons")),
                                catalog_table = nothing)))))))  # <── populated
```

---

## 3. Module: `BoundSql.jl`

**File:** `program/src/document/BoundSql.jl`
**Module:** `BoundSqlDocumentModule`

Included after `Sql.jl` and `DbCatalog.jl` in `program/src/Projectured.jl`.

Imports: `SqlDocumentModule` (all wrapped `Sql*` types), `DbCatalogDocumentModule`
(`DbCatalogTable`, `DbCatalogColumn`).

Exports: abstract types `BoundSqlStatement`, `BoundSqlSelectExpression`,
`BoundSqlFromBaseItem`; concrete types `BoundSqlTableExpression`,
`BoundSqlSubqueryFromItem`, `BoundSqlColumnReference`, `BoundSqlAllColumns`,
`BoundSqlSelectStatement`; their `IBoundSql*` interface wrappers; and
convenience constructors.

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
3. For each `SqlFromItem` in `from_clause.items`, build a new `SqlFromItem`:
   - `SqlTableExpression` base_item → `BoundSqlTableExpression(sql, lookup(table_name))`
   - `SqlSubqueryFromItem` base_item → recurse first; `BoundSqlSubqueryFromItem(sql, bound_subquery)`
   - Each join: new `SqlJoinSegment` with the same join_type/condition and a
     bound `from_item` using the same rules above.
4. For each `SqlSelectItem` in `select_clause.items`, build a new `SqlSelectItem`:
   - `SqlColumnReference` expression → `BoundSqlColumnReference(sql, lookup(qualifier, column_name))`
   - `SqlAllColumns` expression → `BoundSqlAllColumns(sql, lookup(qualifier))`
5. Return `BoundSqlSelectStatement(sql, new SqlSelectClause(...), new SqlFromClause(...))`.

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

1. **Create `program/src/document/BoundSql.jl`** — 3 abstract types, 4 enrichment
   leaf structs, `BoundSqlSelectStatement`; convenience constructors with default
   `nothing` catalog slots.
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
