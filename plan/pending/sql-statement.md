# SQL statement document model

Document model for SQL statements following ANSI/PostgreSQL conventions.
Every semantic element is a dedicated document type.
Covers `SELECT`, `INSERT`, and `UPDATE` at the statement layer and details
the `SELECT` tree through its `SELECT`, `FROM`, and `WHERE` clauses.

All document names start with `Sql`; the remainder follows PostgreSQL naming.

Reference: [PostgreSQL SELECT](https://www.postgresql.org/docs/current/sql-select.html).

---

## Example

```sql
SELECT p.name, p.age FROM persons AS p WHERE p.age >= 18
```

Built as one constructor expression:

```julia
SqlSelectStatement(
    SqlSelectClause(
        SqlSelectItem(SqlColumnReference(SqlTableAlias("p"), SqlColumnName("name"))),
        SqlSelectItem(SqlColumnReference(SqlTableAlias("p"), SqlColumnName("age")))),
    SqlFromClause(SqlFromItem(
        SqlTableExpression(SqlTableName("persons"), SqlTableAlias("p")))),
    SqlWhereClause(
        SqlWhereFilterCondition(SqlComparison(
            SqlColumnReference(SqlTableAlias("p"), SqlColumnName("age")),
            ">=",
            SqlScalarValue(18)))))
```

Call `resolve_sql_names!` after construction to bind qualifier references to
the canonical definition objects (see §4).

---

## 1. Document hierarchy

```
SqlDocument (abstract)
└── SqlStatement (abstract)
    ├── SqlSelectStatement
    │   ├── select_clause : SqlSelectClause
    │   │   ├── distinct : SqlDistinct?            -- leaf, no fields; present ⟹ DISTINCT
    │   │   └── items    : [SqlSelectItem]
    │   │       ├── expression   : SqlSelectExpression (abstract)
    │   │       │   ├── SqlAllColumns
    │   │       │   │   └── qualifier : SqlTableName | SqlTableAlias | nothing
    │   │       │   └── SqlColumnReference
    │   │       │       ├── qualifier   : SqlTableName | SqlTableAlias | nothing
    │   │       │       └── column_name : SqlColumnName
    │   │       └── column_alias : SqlColumnAlias?  -- AS alias; nothing when omitted
    │   ├── from_clause : SqlFromClause
    │   │   └── items : [SqlFromItem]
    │   │       ├── base_item : SqlFromBaseItem (abstract)
    │   │       │   ├── SqlTableExpression
    │   │       │   │   ├── table_name : SqlTableName
    │   │       │   │   │   ├── schema_name : String?
    │   │       │   │   │   └── name        : String
    │   │       │   │   └── alias : SqlTableAlias?
    │   │       │   └── SqlSubqueryFromItem
    │   │       │       ├── subquery : SqlSelectStatement
    │   │       │       └── alias    : SqlTableAlias?
    │   │       └── joins : [SqlJoinedFromItem]
    │   │           ├── join_type  : SqlJoinType (abstract)
    │   │           │   ├── SqlInnerJoin       (leaf)
    │   │           │   ├── SqlLeftOuterJoin   (leaf)
    │   │           │   ├── SqlRightOuterJoin  (leaf)
    │   │           │   ├── SqlFullOuterJoin   (leaf)
    │   │           │   └── SqlCrossJoin       (leaf)
    │   │           ├── from_item  : SqlFromBaseItem
    │   │           └── condition  : SqlJoinCondition (abstract)?
    │   │               ├── SqlJoinOnCondition
    │   │               │   └── expression : SqlBooleanExpression (abstract)
    │   │               └── SqlJoinUsingCondition
    │   │                   └── column_names : [SqlColumnName]
    │   └── where_clause : SqlWhereClause
    │       └── condition : SqlWhereCondition (abstract)?
    │           └── SqlWhereFilterCondition
    │               └── expression : SqlBooleanExpression (abstract)
    │                   ├── SqlComparison
    │                   │   ├── left     : SqlColumnReference | SqlScalarValue
    │                   │   │                  └── value : Any
    │                   │   ├── operator : String  -- "=", "<>", "<", ">", "<=", ">="
    │                   │   └── right    : SqlColumnReference | SqlScalarValue
    │                   ├── SqlAnd
    │                   │   ├── left  : SqlBooleanExpression
    │                   │   └── right : SqlBooleanExpression
    │                   ├── SqlOr
    │                   │   ├── left  : SqlBooleanExpression
    │                   │   └── right : SqlBooleanExpression
    │                   └── SqlNot
    │                       └── expression : SqlBooleanExpression
    ├── SqlInsertStatement   (stub)
    └── SqlUpdateStatement   (stub)
```

---

## 2. Design decision — when to call `resolve_sql_names!`

**Resolution is explicit, not automatic.**

### Why not automatic / reactive

- **Construction catch-22**: the `@document` Cell system fires on individual field
  mutations; midway through assembling the tree the FROM clause may not exist yet,
  so an auto-triggered pass would resolve against an incomplete scope and produce
  wrong bindings.
- **Walk-order dependency**: the pass must visit subqueries before their enclosing
  query (bottom-up). Expressing this ordering as reactive Cell dependencies would
  require inter-node wiring that does not currently exist in the model.
- **Granularity mismatch**: Cells track single-field changes; name resolution is a
  whole-tree traversal. Auto-triggering on every field write (e.g., each character
  typed in an alias name) would re-walk the entire tree for no useful intermediate result.
- **Unresolved state is observable and useful**: the test suite deliberately checks
  that all qualifier objects are distinct before resolution. Automatic resolution
  would erase this observable pre-state.

### Why explicit call is the right fit

- Callers build the complete tree first, then call `resolve_sql_names!` once —
  no partial-tree hazard.
- Resolution is cheap to call selectively: before projection (`SqlToSyntax`),
  before catalog binding (`SqlToBoundSql`), or before execution (`SqlToCellTable`).
- After an interactive edit in the editor the projection pipeline re-runs anyway;
  `resolve_sql_names!` is called as part of that re-render cycle, not as a
  side-effect of setting an individual Cell.
- The "forgot to call" risk is best addressed by a thin pipeline wrapper
  (e.g., a `prepare!` step that resolves + validates) rather than by fighting
  the construction-order problem in a reactive setting.

---

## 3. Reusable name documents

Four leaf types carry identifiers. Each is its own document so that `===`
identity testing reliably detects co-reference after `resolve_sql_names!`.

| Type | Role | Renders as |
|------|------|------------|
| `SqlTableName` | real table name in the schema; optional `schema_name` | `"schema"."name"` or `"name"` |
| `SqlTableAlias` | alias introduced in FROM | `name` (unquoted) |
| `SqlColumnName` | **reference side** — identifier inside `SqlColumnReference` | `name` |
| `SqlColumnAlias` | **definition side** — `AS` output alias in `SqlSelectItem` | `name` |

A subquery's `SqlColumnAlias` values are the names outer queries address via
`SqlColumnName` in `SqlColumnReference`. The type separation makes definitions
and references statically distinguishable.

---

## 3. Expression and condition abstract types

| Abstract type | Used in | Concrete subtypes in scope |
|---------------|---------|---------------------------|
| `SqlSelectExpression` | `SqlSelectItem.expression` | `SqlAllColumns`, `SqlColumnReference` |
| `SqlBooleanExpression` | `SqlWhereFilterCondition.expression`, `SqlJoinOnCondition.expression`, future `HAVING` | `SqlComparison`, `SqlAnd`, `SqlOr`, `SqlNot` |
| `SqlWhereCondition` | `SqlWhereClause.condition` | `SqlWhereFilterCondition` |
| `SqlJoinCondition` | `SqlJoinedFromItem.condition` | `SqlJoinOnCondition`, `SqlJoinUsingCondition` |

`SqlWhereFilterCondition` is the sole concrete `SqlWhereCondition`; it wraps a
`SqlBooleanExpression` and exists as an explicit container so the hierarchy is
uniform top-to-bottom: clause → condition → boolean expression.

`SqlJoinConditionExpression` remains as an exported abstract type but has no
concrete subtypes; `SqlJoinOnCondition.expression` is typed
`::SqlBooleanExpression` directly.

`SqlBooleanExpression` is the **context-independent** boolean root.
`SqlScalarValue` is a leaf document holding a Julia `Number`, `String`, or `Bool`;
the syntax projection renders it as `42`, `'text'`, `TRUE`/`FALSE` respectively
(no `render_sql` call at the projection level).

---

## 4. `resolve_sql_names!`

```julia
resolve_sql_names!(stmt::SqlSelectStatement) -> SqlSelectStatement
```

Bottom-up pass that rebinds qualifier and column-name reference fields so every
reference holds the **same object instance** as the canonical definition document.
After the pass, `===` reliably indicates co-reference.

**Walk order**: subqueries inside `SqlSubqueryFromItem` are resolved before
the enclosing query (bottom-up), so subquery column aliases are already bound
when the outer scope is processed.

**Two local maps per scope:**

- *Table/alias scope* — built from `from_clause`: registers each
  `SqlTableExpression.table_name` (`SqlTableName`) and `.alias` (`SqlTableAlias`),
  and each `SqlSubqueryFromItem.alias`. JOIN `from_item`s are registered the same way.
- *Column alias scope* — built from `select_clause`: registers each
  `SqlSelectItem.column_alias` (`SqlColumnAlias`).

**Rebinding rules:**

| Field | Rebound to |
|-------|------------|
| `SqlColumnReference.qualifier` | canonical `SqlTableName` or `SqlTableAlias` from table/alias scope |
| `SqlAllColumns.qualifier` | same |
| `SqlColumnReference.column_name` | canonical `SqlColumnAlias` when name matches; otherwise unchanged |

Unresolved references are left as-is — resolution failure is a diagnostic
concern for a later validation layer, not a structural error.

---

## 5. Out of scope

- Arithmetic and function-call expressions as comparison operands.
- `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`, `OFFSET`, `WINDOW`, `UNION`.
- `DISTINCT ON (expression)` — only bare `DISTINCT` is in scope.
- CTEs (`WITH`), locking clauses (`FOR UPDATE`), `NATURAL JOIN`, `TABLESAMPLE`.
- Function-valued or `ROWS FROM` FROM items.
- `INSERT` and `UPDATE` fields beyond the empty stubs.
