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

## 2. Reusable name documents

Four leaf types carry identifiers.

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
(rendered through the projection pipeline).

---


---

## 5. Out of scope

- Arithmetic and function-call expressions as comparison operands.
- `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`, `OFFSET`, `WINDOW`, `UNION`.
- `DISTINCT ON (expression)` — only bare `DISTINCT` is in scope.
- CTEs (`WITH`), locking clauses (`FOR UPDATE`), `NATURAL JOIN`, `TABLESAMPLE`.
- Function-valued or `ROWS FROM` FROM items.
- `INSERT` and `UPDATE` fields beyond the empty stubs.
