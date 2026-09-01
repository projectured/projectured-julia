# Bound SQL statement document model

> **Status (2026-08-12): NOT STARTED.** No `BoundSql` code exists anywhere
> under `package/` — `grep "BoundSql"` returns zero source hits, and there is
> no `BoundSql.jl` document nor `SqlToBoundSql.jl` projection. All dependencies
> are present and current, so the plan is still applicable: `Sql.jl` is at
> [package/sql/main/Sql.jl](../../source/sql/Sql.jl), `DbCatalog.jl` at
> [package/dbcatalog/main/DbCatalog.jl](../../source/dbcatalog/DbCatalog.jl),
> `DatabaseInstance.jl` at
> [package/database/main/DatabaseInstance.jl](../../source/database/DatabaseInstance.jl).
> `DatabaseInstanceToDbCatalog`, `DbCatalogRdbms`, and `DbCatalogSchema` all
> exist with the shapes this plan assumes. Each domain is its own package now
> (`sql`, `dbcatalog`, `database`) — see
> [documentation/domains.md](../../documentation/design/domain-inventory.md). Every
> `program/src/...` path below needs translating to the package layout when
> this plan is picked up: `program/src/document/*.jl` maps to
> `package/<domain>/main/*.jl`; `program/src/projection/primitive/*.jl` also
> maps to `package/<domain>/main/*.jl`; `program/src/Projectured.jl` no longer
> exists — there is no umbrella file, each package exports its own symbols.

Combines a database-agnostic `SqlStatement` document tree with live `DbCatalog`
metadata to produce a `BoundSqlStatement` document tree. The projection rebuilds
the `Sql*` tree with `BoundSql*` enrichment nodes substituted at leaf positions
(table expressions, column references) and wraps the result in a
`BoundSqlStatement` that stamps database provenance onto the whole thing.

`@document` fields are `Cell`-wrapped `Any` at runtime — declared type
annotations are documentary, not enforced — so `BoundSql*` nodes sit in
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
constructor takes the full database context chain (`DatabaseInstance`,
`DbCatalogRdbms`, `DbCatalogSchema`) so the bound output carries the
complete provenance of the schema metadata. A `DbCatalogSchema` can exist
without any instance or RDBMS (it is a pure data document), so a
schema-only convenience constructor exists for testing; the full constructor
is the primary API.

---

## 1. Document hierarchy

### Abstract type

Single abstract top type — avoids type dispatch collisions with `SqlDocument`:

```
BoundSqlDocument <: Document
```

No further abstract subtypes. `BoundSqlStatement` is concrete.

### Concrete types (4 total)

Every bound document refers to its original Sql document via an `sql` slot.

**Statement level** — pure database context wrapper around any `SqlStatement`:

```julia
@document struct BoundSqlStatement <: BoundSqlDocument
    sql::SqlStatement                 # rebuilt SqlStatement with BoundSql* leaves inside
    database_instance::Any            # DatabaseInstance | nothing
    catalog_rdbms::Any                # DbCatalogRdbms | nothing
    catalog_schema::Any               # DbCatalogSchema | nothing
    selection::Reference
end
```

`BoundSqlStatement` is statement-kind-agnostic. The `sql` slot holds a rebuilt
`SqlSelectStatement` (or future `SqlInsertStatement`, `SqlUpdateStatement`)
whose clauses already contain `BoundSql*` leaves. The statement kind is
determined by the type of `sql`, not by `BoundSqlStatement` subtypes.

**Table-connected:**

```julia
@document struct BoundSqlTableExpression <: BoundSqlDocument
    sql::SqlTableExpression           # original
    catalog_table::Any                # DbCatalogTable | nothing
    selection::Reference
end
```

**Column-connected:**

```julia
@document struct BoundSqlColumnReference <: BoundSqlDocument
    sql::SqlColumnReference           # original
    catalog_column::Any               # DbCatalogColumn | nothing
    selection::Reference
end

@document struct BoundSqlAllColumns <: BoundSqlDocument
    sql::SqlAllColumns                # original
    catalog_table::Any                # DbCatalogTable | nothing (resolved from qualifier)
    selection::Reference
end
```

### Subquery handling

No `BoundSqlSubqueryFromItem` type. A subquery in the FROM clause is a
`SqlSubqueryFromItem` whose `subquery` slot holds a `BoundSqlStatement`
(not a raw `SqlSelectStatement`). The `@document` `Any`-typed cells allow
this substitution without type errors.

### Preserved as Sql (no bound wrappers)

All other `Sql*` types are reused unchanged — the projection creates new
instances of structural containers (e.g., new `SqlFromItem`) but fills them
with `BoundSql*` leaves where appropriate:

`SqlSelectStatement`, `SqlSelectClause`, `SqlFromClause`, `SqlFromItem`,
`SqlJoinedFromItem`, `SqlSelectItem`, `SqlWhereClause`,
`SqlWhereFilterCondition`, `SqlSubqueryFromItem`, all join types, all boolean
expressions, `SqlTableName`, `SqlTableAlias`, `SqlColumnName`,
`SqlColumnAlias`, `SqlDistinct`, `SqlScalarValue`, `SqlComparison`, `SqlAnd`,
`SqlOr`, `SqlNot`.

---

## 2. Full tree example

```
SELECT sub.person_name FROM (SELECT name AS person_name FROM "persons") AS sub
```

Bound tree:

```julia
BoundSqlStatement(
    sql = SqlSelectStatement(                         # rebuilt
        select_clause = SqlSelectClause(
            SqlSelectItem(
                BoundSqlColumnReference(
                    sql            = SqlColumnReference(SqlTableAlias("sub"), SqlColumnName("person_name")),
                    catalog_column = nothing))),
        from_clause = SqlFromClause(
            SqlFromItem(
                SqlSubqueryFromItem(                  # preserved as Sql
                    subquery = BoundSqlStatement(     # nested bound statement
                        sql = SqlSelectStatement(     # rebuilt inner
                            select_clause = SqlSelectClause(
                                SqlSelectItem(
                                    BoundSqlColumnReference(
                                        sql            = SqlColumnReference(SqlColumnName("name")),
                                        catalog_column = nothing),
                                    SqlColumnAlias("person_name"))),
                            from_clause = SqlFromClause(
                                SqlFromItem(
                                    BoundSqlTableExpression(
                                        sql           = SqlTableExpression(SqlTableName("persons")),
                                        catalog_table = nothing)))),
                        database_instance = <same>,
                        catalog_rdbms = <same>,
                        catalog_schema = <same>),
                    alias = SqlTableAlias("sub")))),
        where_clause = <reused from original>),
    database_instance = <DatabaseInstance | nothing>,
    catalog_rdbms = <DbCatalogRdbms | nothing>,
    catalog_schema = <DbCatalogSchema>)
```

---

## 3. Module: `BoundSql.jl`

**File:** `package/dbcatalog/main/BoundSql.jl` (proposed — `dbcatalog` already
depends on `sql`; confirm the package placement against
[documentation/domains.md](../../documentation/design/domain-inventory.md) before creating it,
since `BoundSql` also needs `DatabaseInstanceDocumentModule` from
`package/database/main/`, which `dbcatalog` does not depend on today).
**Module:** `BoundSqlDocumentModule`

There is no umbrella `Projectured.jl` file any more; each package exports its
own symbols directly from its module.

Imports: `SqlDocumentModule`, `DbCatalogDocumentModule`, `DatabaseInstanceDocumentModule`.

Exports: abstract type `BoundSqlDocument`; concrete types `BoundSqlStatement`,
`BoundSqlTableExpression`, `BoundSqlColumnReference`, `BoundSqlAllColumns`;
their `IBoundSql*` snapshot wrappers; and convenience constructors.

---

## 4. Projection: `SqlToBoundSql`

**File:** `package/dbcatalog/main/SqlToBoundSql.jl` (proposed — same package as
`BoundSql.jl`, see §3).
**Module:** `SqlToBoundSqlModule`

### Constructor

```julia
struct SqlToBoundSql <: Projection
    database_instance::Any        # DatabaseInstance | nothing
    catalog_rdbms::Any            # DbCatalogRdbms | nothing
    catalog_schema::DbCatalogSchema
end

# Primary API — full database context chain
SqlToBoundSql(instance::DatabaseInstance, rdbms::DbCatalogRdbms, schema::DbCatalogSchema) =
    SqlToBoundSql(instance, rdbms, schema)

# Testing convenience — schema can exist without instance/rdbms
SqlToBoundSql(schema::DbCatalogSchema) = SqlToBoundSql(nothing, nothing, schema)
```

The caller typically obtains all three from the `DatabaseInstanceToDbCatalog`
projection output — that projection lives in
[package/odbc/main/ProjecturedOdbc.jl](../../package/ProjecturedOdbc/src/ProjecturedOdbc.jl),
so a caller that needs live database context depends on `odbc`; the
schema-only constructor keeps `SqlToBoundSql` itself independent of that
package. The `DatabaseInstance` provides connection context (host,
port, database name); the `DbCatalogRdbms` anchors the schema in the catalog
tree; the `DbCatalogSchema` supplies the table/column metadata for name
resolution. All three are stamped onto the `BoundSqlStatement` output so
downstream consumers (hover docs, validation) know *where* the metadata
came from.

The projection is a single struct with internal helper functions for the walk
(like `DatabaseInstanceToDbCatalog`), NOT a `TypeDispatchingProjection`.

### `projection_print` walk

Single method: `projection_print(p::SqlToBoundSql, recursion, stmt::SqlSelectStatement, ctx)`.

Bottom-up (subqueries before enclosing query):

1. Build lookup maps from `p.catalog_schema`:
   - `table_map = Dict(t.name => t for t in catalog_schema.tables)`
   - `column_map = Dict((t.name, c.name) => c for t in ..., c in t.columns)`

2. Walk `stmt.from_clause.items` — for each `SqlFromItem`:
   - `SqlTableExpression` base_item → `BoundSqlTableExpression(sql=it, catalog_table=get(table_map, name, nothing))`
   - `SqlSubqueryFromItem` base_item → recurse on inner `subquery` to produce a `BoundSqlStatement`, then build new `SqlSubqueryFromItem(bound_stmt, original_alias)`
   - Each join: new `SqlJoinedFromItem` with same join_type/condition and a bound `from_item`
   - Build new `SqlFromItem(bound_base, new_joins)`, new `SqlFromClause(new_items)`

3. Build alias-to-table map from FROM clause for qualifying column references.

4. Walk `stmt.select_clause.items` — for each `SqlSelectItem`:
   - `SqlColumnReference` expression → `BoundSqlColumnReference(sql=it, catalog_column=lookup(qualifier, col))`
   - `SqlAllColumns` expression → `BoundSqlAllColumns(sql=it, catalog_table=lookup(qualifier))`
   - Build new `SqlSelectItem(bound_expr, original_alias)`
   - Build new `SqlSelectClause(original_distinct, new_items)`

5. Build rebuilt `SqlSelectStatement(new_sc, new_fc, stmt.where_clause)`.

6. Return `SimpleIoMap(p, stmt, BoundSqlStatement(sql=rebuilt_stmt, database_instance=p.database_instance, catalog_rdbms=p.catalog_rdbms, catalog_schema=p.catalog_schema))`.

### v1: read-only

- `map_reference_forward` / `map_reference_backward` → `nothing`
- `projection_read` → `nothing`

---

## 5. Out of scope

- Binding for INSERT / UPDATE statements (future `projection_print` methods).
- Binding for WHERE / JOIN condition expressions.
- Cross-schema table resolution.
- Validation or error reporting for unresolved names (diagnostic layer, later).
- Rendering `BoundSqlStatement` to syntax — a separate `BoundSqlToSyntax` projection.

---

## 6. Implementation steps

1. **⏳ OPEN — Create `package/dbcatalog/main/BoundSql.jl`** — 1 abstract type, 4 concrete
   `@document` structs; convenience constructors with default `nothing` catalog
   slots; `Base.show` methods.
   _Evidence (2026-08-12): no `BoundSql.jl` under `package/`; `grep BoundSql package/` → 0 hits._
2. **⏳ OPEN — Export `BoundSqlDocumentModule`'s symbols** from its own module (no
   umbrella file to wire into any more).
   _Evidence (2026-08-12): no `BoundSqlDocumentModule` referenced in any source file._
3. **⏳ OPEN — Create `package/dbcatalog/main/SqlToBoundSql.jl`** —
   `projection_print` for `SqlSelectStatement` with internal walk helpers.
   _Evidence (2026-08-12): no `SqlToBoundSql.jl`; `SqlToSyntax.jl` exists at
   [package/sql/main/SqlToSyntax.jl](../../source/sql/SqlToSyntax.jl)._
4. **⏳ OPEN — Export `SqlToBoundSqlModule`'s symbols** from its own module.
   _Evidence (2026-08-12): `grep SqlToBoundSql package/` → 0 hits._
5. **⏳ OPEN — Write projection tests** — bind `SELECT name, age FROM persons` against a
   `DbCatalogSchema` containing `persons(name TEXT, age INT)`; assert
   `catalog_table` and `catalog_column` are the expected instances; verify
   unresolved names leave the slot as `nothing`; verify database context
   metadata on statement.
   _Evidence (2026-08-12): no `BoundSql`/`SqlToBoundSql` references under `package/*/test/`._

---

## 7. Verification

```julia
# REPL smoke test
schema = DbCatalogSchema("public", CellVector([
    DbCatalogTable("persons", CellVector([
        DbCatalogColumn("name", "TEXT"),
        DbCatalogColumn("age", "INT")
    ]))
]))
stmt = SqlSelectStatement(
    SqlSelectClause(
        SqlSelectItem(SqlColumnReference("name")),
        SqlSelectItem(SqlColumnReference("age"))
    ),
    SqlFromClause(SqlFromItem(SqlTableExpression("persons")))
)
proj = SqlToBoundSql(schema)
iomap = projection_print(proj, proj, stmt, PrinterContext())
bound = iomap.output

# Check structure
bound isa BoundSqlStatement
bound.sql isa SqlSelectStatement                        # rebuilt, not original
bound.catalog_schema === schema
bound.sql.from_clause.items[1].base_item isa BoundSqlTableExpression
bound.sql.from_clause.items[1].base_item.catalog_table.name == "persons"
bound.sql.select_clause.items[1].expression isa BoundSqlColumnReference
bound.sql.select_clause.items[1].expression.catalog_column.name == "name"
```

---

## 8. Dependencies

- `SqlDocumentModule` ([package/sql/main/Sql.jl](../../source/sql/Sql.jl)) — must be loaded first.
- `DbCatalogDocumentModule` ([package/dbcatalog/main/DbCatalog.jl](../../source/dbcatalog/DbCatalog.jl)) — must be loaded first.
- `DatabaseInstanceDocumentModule` ([package/database/main/DatabaseInstance.jl](../../source/database/DatabaseInstance.jl)) — must be loaded first; `dbcatalog`'s `Project.toml` does not list `database` as a dependency today and needs it added if `BoundSql.jl` lives in `dbcatalog`.
