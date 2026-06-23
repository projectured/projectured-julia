# SQL statement document model

**✅ DONE (verified):** The entire document model described below is implemented in `package/domain/src/document/Sql.jl` (module `SqlDocumentModule`). All described types, fields, abstract hierarchy, and the worked example constructor are present, and the implementation goes beyond the plan (parser, CREATE/INSERT/UPDATE bodies, `SqlStatementList`, `DbCatalogToSql`). Per-section verification notes inline.

Document model for SQL statements following ANSI/PostgreSQL conventions.
Every semantic element is a dedicated document type.
Covers `SELECT`, `INSERT`, and `UPDATE` at the statement layer and details
the `SELECT` tree through its `SELECT`, `FROM`, and `WHERE` clauses.

All document names start with `Sql`; the remainder follows PostgreSQL naming.

Reference: [PostgreSQL SELECT](https://www.postgresql.org/docs/current/sql-select.html).

---

## Example

**✅ DONE (verified):** Every constructor used in the example below exists in `Sql.jl` — `SqlSelectStatement` (L282), `SqlSelectClause` (L138/L145), `SqlSelectItem` (L128/L133), `SqlColumnReference(qualifier, col)` (L116/L125), `SqlTableAlias` (L86/L90), `SqlColumnName` (L92/L96), `SqlFromClause`/`SqlFromItem` (L273/L265), `SqlTableExpression(tname, alias)` (L242/L249), `SqlTableName` (L76), `SqlWhereClause`/`SqlWhereFilterCondition` (L157/L150), `SqlComparison(left, op, right)` (L171/L177), `SqlScalarValue` (L165). A closely matching example is also constructed in `package/example/src/document/Sql.jl`.

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

**✅ DONE (verified):** The full hierarchy is realized in `Sql.jl`. Abstract types `SqlDocument`, `SqlStatement`, `SqlSelectExpression`, `SqlFromBaseItem`, `SqlJoinType`, `SqlJoinCondition`, `SqlWhereCondition`, `SqlBooleanExpression` are declared at L64-72. Concrete documents with the exact fields shown: `SqlSelectClause`(distinct, items) L138; `SqlSelectItem`(expression, column_alias) L128; `SqlAllColumns`(qualifier) L110; `SqlColumnReference`(qualifier, column_name) L116; `SqlFromClause`/`SqlFromItem`(base_item, joins) L273/L265; `SqlTableExpression`(table_name, alias) L242; `SqlTableName`(schema_name, name) L76; `SqlSubqueryFromItem`(subquery, alias) L301; `SqlJoinedFromItem`(join_type, from_item, condition) L254; the five join leaves `SqlInnerJoin`/`SqlLeftOuterJoin`/`SqlRightOuterJoin`/`SqlFullOuterJoin`/`SqlCrossJoin` L204-222; `SqlJoinOnCondition`(expression) L226 and `SqlJoinUsingCondition`(column_names) L233; `SqlWhereClause`(condition) L157; `SqlWhereFilterCondition`(expression) L150; boolean expressions `SqlComparison`(left, operator, right) L171, `SqlAnd`/`SqlOr`(left, right) L180/L188, `SqlNot`(expression) L196; `SqlScalarValue`(value) L165. The `SqlInsertStatement` (L314) and `SqlUpdateStatement` (L338) "stubs" are present as full single-row statements (exceeding the stub scope).

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

**✅ DONE (verified):** All four identifier leaf documents exist in `Sql.jl`: `SqlTableName` (L76, with optional `schema_name`), `SqlTableAlias` (L86), `SqlColumnName` (L92), `SqlColumnAlias` (L98). The type separation between `SqlColumnName` (reference side) and `SqlColumnAlias` (definition side) holds as described.

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

**✅ DONE (verified):** Abstract types and their concrete subtypes match `Sql.jl` exactly. `SqlSelectExpression` (L66) ⊇ `SqlAllColumns`/`SqlColumnReference` (L110/L116). `SqlBooleanExpression` (L72) ⊇ `SqlComparison`/`SqlAnd`/`SqlOr`/`SqlNot` (L171/L180/L188/L196). `SqlWhereCondition` (L71) ⊇ `SqlWhereFilterCondition` (L150). `SqlJoinCondition` (L69) ⊇ `SqlJoinOnCondition`/`SqlJoinUsingCondition` (L226/L233). `SqlJoinConditionExpression` is declared abstract (L70) and has no concrete subtypes, and `SqlJoinOnCondition.expression` is typed `::SqlBooleanExpression` (L227) — exactly as the prose states. `SqlScalarValue` (L165) holds `value::Any` (Number/String/Bool); the `SqlScalarValueToSyntaxLeaf` projection in `package/domain/src/projection/primitive/SqlToSyntax.jl` (L890-896) renders `42`, `'text'`, `TRUE`/`FALSE` through the pipeline as specified.

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

**✅ DONE (verified — boundary still holds):** None of these features exist as document types in `Sql.jl`. The only mentions of GROUP BY / ORDER BY / HAVING / LIMIT / OFFSET / UNION / NATURAL are in `package/domain/src/parser/SqlParser.jl`, where they are merely *skipped as trailing clauses* (see comments at L22 and L362) or listed as delimiter keywords — not modeled as documents. The exclusion boundary described here is intact.

- Arithmetic and function-call expressions as comparison operands.
- `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`, `OFFSET`, `WINDOW`, `UNION`.
- `DISTINCT ON (expression)` — only bare `DISTINCT` is in scope.
- CTEs (`WITH`), locking clauses (`FOR UPDATE`), `NATURAL JOIN`, `TABLESAMPLE`.
- Function-valued or `ROWS FROM` FROM items.
- `INSERT` and `UPDATE` fields beyond the empty stubs.
