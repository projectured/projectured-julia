# SqlRawToSql projection — SQL parser

Projection that reads a `SqlRawStatement` document (a raw SQL string) and
parses its `content` field into the corresponding `SqlDocument` hierarchy.
Printer-only (no readers, no reference mapping) in this initial scope.

The projection direction is: `SqlRawStatement` → `SqlStatement` (e.g.
`SqlSelectStatement`). It is the *inverse* of the projection pipeline
(`SqlToSyntax → SyntaxToText → TextToString`) which serialises the AST to a
string; `SqlRawToSql` parses a string back into the AST.

**Status: implemented.** All tests passing.

---

## 1. Supported SQL constructs

The parser recognises exactly the concrete types already defined in `Sql.jl`:

### Statement
- `SqlSelectStatement` — `SELECT … FROM … [WHERE …]`

### SELECT clause
- `SqlSelectClause` — `SELECT [DISTINCT] <items>`
- `SqlSelectItem` — `<expression> [AS <alias>]`
- `SqlAllColumns` — `*` or `qualifier.*`
- `SqlColumnReference` — `[qualifier.]column_name`
- `SqlDistinct` — bare `DISTINCT` keyword
- `SqlColumnAlias` — the `AS alias` name

### FROM clause
- `SqlFromClause` — `FROM <items>`
- `SqlFromItem` — `<base_item> [<joins>…]`
- `SqlTableExpression` — `[schema.]table_name [AS alias]`
- `SqlSubqueryFromItem` — `(<subquery>) [AS alias]`
- `SqlJoinedFromItem` — `<join_type> <from_item> [<condition>]`
- Join types: `SqlInnerJoin`, `SqlLeftOuterJoin`, `SqlRightOuterJoin`,
  `SqlFullOuterJoin`, `SqlCrossJoin`
- `SqlJoinOnCondition` — `ON <boolean_expression>`
- `SqlJoinUsingCondition` — `USING (<column_names>)`

### WHERE clause
- `SqlWhereClause` — `WHERE <condition>`
- `SqlWhereFilterCondition` — wraps a `SqlBooleanExpression`

### Boolean / scalar expressions
- `SqlComparison` — `<left> <op> <right>` where op ∈ {`=`, `<>`, `!=`, `<`, `>`, `<=`, `>=`}
- `SqlAnd` — `<left> AND <right>`
- `SqlOr` — `<left> OR <right>`
- `SqlNot` — `NOT <expression>`
- `SqlScalarValue` — numeric literals, single-quoted strings, `TRUE`/`FALSE`
- `SqlColumnReference` (reused in boolean expressions as comparison operands)

---

## 2. Ignored / skipped fragments

The parser silently skips fragments it cannot map to a supported AST node:

- **Line comments** — `-- …` through end of line
- **Block comments** — `/* … */` (may be nested per SQL standard)
- **Unsupported statement types** — `INSERT`, `UPDATE`, `DELETE`, `CREATE`, etc.
  If the raw content does not begin with `SELECT` (after stripping comments and
  whitespace), `projection_print` returns `nothing`.
- **Unsupported clauses** — `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT`, `OFFSET`,
  `WINDOW`, `UNION`, CTEs (`WITH`), locking (`FOR UPDATE`).
  These are consumed by `skip_trailing!` and discarded. The skip stops at `)` to
  preserve subquery boundaries.
- **Unsupported expressions** — function calls (`COUNT(*)`, `COALESCE(…)`),
  arithmetic (`a + b`), `CASE WHEN`, `BETWEEN`, `IN`, `LIKE`, `IS NULL`, casts.
  When encountered inside a SELECT item or WHERE condition, the parser
  falls back: it collects the unparseable token run into a `SqlScalarValue`
  whose `.value` is the raw text fragment (string). This preserves the
  surrounding structure while making the opaque part render-safe.

---

## 3. Parser architecture

### 3.1 Tokeniser (lexer)

A lightweight scanner that operates on the raw `String`, producing
`Vector{SqlToken}`. Uses `SubString` for zero-copy token values.

**Token kinds** (`@enum SqlTokenKind`):

| Token | Examples |
|-------|----------|
| `TK_KEYWORD` | `SELECT`, `FROM`, `WHERE`, `AS`, `JOIN`, `ON`, `USING`, `AND`, `OR`, `NOT`, `DISTINCT`, `LEFT`, `RIGHT`, `FULL`, `OUTER`, `INNER`, `CROSS`, `TRUE`, `FALSE` |
| `TK_IDENT` | unquoted identifier: `persons`, `p`, `name` |
| `TK_QUOTED_IDENT` | `"persons"`, `"schema"."name"` (double-quoted) |
| `TK_STRING_LIT` | `'hello'` (single-quoted, with `''` escape) |
| `TK_NUMBER_LIT` | `42`, `3.14` |
| `TK_OP` | `=`, `<>`, `!=`, `<`, `>`, `<=`, `>=` |
| `TK_STAR` | `*` |
| `TK_DOT` | `.` |
| `TK_COMMA` | `,` |
| `TK_LPAREN` | `(` |
| `TK_RPAREN` | `)` |
| `TK_SEMICOLON` | `;` |
| `TK_EOF` | end of input |

Each token carries: `kind::SqlTokenKind`, `value::SubString{String}`,
`pos::Int` (1-based byte offset).

Comments are stripped during tokenisation — the token stream never contains
them. Whitespace is consumed between tokens — not emitted.

**Keyword recognition**: after scanning an identifier, check against
`SQL_KEYWORDS::Set{String}` (upper-cased). If matched, reclassify as
`TK_KEYWORD`. The keyword set includes structural SQL words plus common
clauses for accurate delimiter detection.

### 3.2 Recursive-descent parser

A top-down, single-pass parser with one token of lookahead (`peek`/`advance!`).
Each grammar production maps to a Julia function returning the corresponding
`Sql*` document node or `nothing` on failure.

**Grammar sketch** (simplified; precedence handled by nesting):

```
statement       := select_statement
select_statement := select_clause [from_clause] [where_clause]
                    [ignored_trailing_clauses]

select_clause   := SELECT [DISTINCT] select_item { COMMA select_item }
select_item     := select_expression [AS ident]
select_expression := STAR
                   | [qualifier DOT] STAR
                   | [qualifier DOT] column_name
                   | fallback_expression

from_clause     := FROM from_item { COMMA from_item }
from_item       := from_base_item { join_segment }
from_base_item  := LPAREN select_statement RPAREN [AS ident]
                 | [schema DOT] table_name [AS ident]
join_segment    := join_type from_base_item [join_condition]
join_type       := [INNER] JOIN
                 | LEFT [OUTER] JOIN
                 | RIGHT [OUTER] JOIN
                 | FULL [OUTER] JOIN
                 | CROSS JOIN
join_condition  := ON boolean_expression
                 | USING LPAREN column_name { COMMA column_name } RPAREN

where_clause    := WHERE boolean_expression

boolean_expression := boolean_or
boolean_or     := boolean_and { OR boolean_and }
boolean_and    := boolean_not { AND boolean_not }
boolean_not    := NOT boolean_not | boolean_primary
boolean_primary := LPAREN boolean_expression RPAREN
                 | comparison
comparison     := scalar_operand comp_op scalar_operand

scalar_operand := [qualifier DOT] column_name
                | scalar_value
scalar_value   := NUMBER_LIT | STRING_LIT | TRUE | FALSE

comp_op        := '=' | '<>' | '!=' | '<' | '>' | '<=' | '>='

ignored_trailing_clauses := { any_token_until_EOF_or_SEMICOLON_or_RPAREN }
```

`!=` is normalised to `<>` when constructing `SqlComparison`.

FROM clause is optional — `SELECT 1` is valid (produces empty `SqlFromClause`).

### 3.3 Fallback strategy for unsupported expressions

When the parser encounters an expression it cannot reduce (e.g. a function
call starting with `ident LPAREN`), it performs **greedy token collection**:
it consumes tokens until it hits a structural delimiter (`,`, `)`, `AS`,
`AND`, `OR`, `FROM`, `WHERE`, `GROUP`, `ORDER`, `HAVING`, `LIMIT`, `UNION`,
`EOF`, `;`), tracking parenthesis depth so balanced `(…)` within the
expression are consumed. The collected token text is extracted from the
original source string and wrapped in `SqlScalarValue(raw_text::String)`.

This keeps the surrounding clause structure intact while preserving the
opaque fragment for rendering.

**Implementation detail**: `SqlSelectItem` convenience constructors require
`SqlSelectExpression`, but `SqlScalarValue <: SqlDocument`. The parser
bypasses the typed constructors and builds `SqlSelectItem(expr, alias,
Cell(nothing))` directly, since `@document` makes all fields `::Cell` at
the struct level.

### 3.4 Trailing clause skip

`skip_trailing!` consumes tokens until `EOF`, `;`, **or `)`**. The `)`
boundary is critical for subquery support — without it, `skip_trailing!`
inside a subquery's `parse_select_statement!` would eat the closing paren
and any alias that follows.

---

## 4. Projection interface

### Module

**File:** `program/src/projection/primitive/SqlRawToSql.jl`
**Module:** `SqlRawToSqlModule`

### Struct

```julia
struct SqlRawToSql <: Projection end
```

No parameters — the parser is self-contained.

### `projection_print`

```julia
function projection_print(p::SqlRawToSql, recursion, doc::SqlRawStatement, ctx)
    parsed = parse_sql(doc.content)        # returns SqlStatement or nothing
    parsed === nothing && return nothing
    SimpleIoMap(p, doc, parsed)
end
```

Uses `SimpleIoMap` — the output is a `SqlStatement` (typically
`SqlSelectStatement`). No child iomaps needed because there is no reference
mapping.

### `projection_read` / reference mappers

```julia
projection_read(::SqlRawToSql, ::SimpleIoMap, op) = nothing
map_reference_forward(::SqlRawToSql, ::SimpleIoMap, ref) = nothing
map_reference_backward(::SqlRawToSql, ::SimpleIoMap, ref) = nothing
```

All stubs — printer-only, no selection forwarding.

---

## 5. Error strategy

- **Unparseable input** (not a SELECT statement, or gross syntax error before
  any clause is complete): `parse_sql` returns `nothing`;
  `projection_print` returns `nothing`. The downstream projection pipeline
  sees no output — the raw statement remains the terminal document.
- **Partial parse** (SELECT clause parsed, FROM clause has a syntax error):
  best-effort — return what was parsed so far with the broken fragment
  wrapped in `SqlScalarValue` or omitted.  The goal is robustness, not
  strict SQL validation; this is a projectional display aid, not a database
  front-end.
- **Exception safety**: `parse_sql` wraps the parse in `try/catch` —
  unexpected errors return `nothing` rather than propagating.

---

## 6. Module wiring

Included in `program/src/Projectured.jl` after `SqlToSyntax.jl`:

```julia
include("projection/primitive/SqlRawToSql.jl")
using .SqlRawToSqlModule: SqlRawToSql
```

`SqlRawToSql` and `SqlRawStatement` are exported at the public API level.

---

## 7. Implementation files

| File | Role |
|------|------|
| `program/src/projection/primitive/SqlRawToSql.jl` | Module: tokeniser, parser, projection |
| `program/src/Projectured.jl` | Wiring: include, using, export |
| `test/src/projection/SqlRawToSqlTest.jl` | Tests: 21 test cases |
| `test/src/ProjecturedTest.jl` | Test wiring: include |

---

## 8. Test cases

| Input SQL | Expected AST root | Notes |
|-----------|-------------------|-------|
| `SELECT * FROM persons` | `SqlSelectStatement` with `SqlAllColumns()`, one `SqlFromItem` | simplest case |
| `SELECT name, age FROM persons` | two `SqlSelectItem`s, each `SqlColumnReference` | multi-column |
| `SELECT p.name AS n FROM persons AS p` | qualifier + column alias + table alias | alias support |
| `SELECT DISTINCT name FROM persons` | `SqlDistinct` present | DISTINCT flag |
| `SELECT * FROM persons WHERE age >= 18` | `SqlWhereClause` with `SqlComparison` | WHERE + comparison |
| `SELECT * FROM a JOIN b ON a.id = b.id` | `SqlJoinedFromItem` with `SqlInnerJoin` + `SqlJoinOnCondition` | join |
| `SELECT * FROM a LEFT JOIN b ON a.id = b.id` | `SqlLeftOuterJoin` | outer join |
| `SELECT * FROM a RIGHT JOIN b ON a.id = b.id` | `SqlRightOuterJoin` | right join |
| `SELECT * FROM a FULL OUTER JOIN b ON a.id = b.id` | `SqlFullOuterJoin` | full outer join |
| `SELECT * FROM a CROSS JOIN b` | `SqlCrossJoin`, no condition | cross join |
| `SELECT * FROM a JOIN b USING (id, name)` | `SqlJoinUsingCondition` with 2 columns | USING condition |
| `SELECT * FROM (SELECT * FROM t) AS sub` | `SqlSubqueryFromItem` with alias `sub` | subquery in FROM |
| `SELECT * FROM t WHERE a = 1 AND b = 2` | `SqlAnd` with two `SqlComparison`s | boolean AND |
| `SELECT * FROM t WHERE NOT a = 1` | `SqlNot` wrapping `SqlComparison` | boolean NOT |
| `SELECT * FROM t WHERE a = 1 OR b = 2 AND c = 3` | `SqlOr(comp, SqlAnd(comp, comp))` | precedence: AND binds tighter |
| `-- comment\nSELECT * FROM t` | parses as `SELECT * FROM t` | line comment stripped |
| `SELECT /* inline */ * FROM t` | parses as `SELECT * FROM t` | block comment stripped |
| `SELECT * FROM t ORDER BY name` | parses; `ORDER BY` ignored | trailing clause skipped |
| `SELECT COUNT(*) FROM t` | `SqlScalarValue("COUNT(*)")` as select expression | fallback for unsupported expr |
| `INSERT INTO t VALUES (1)` | `nothing` | non-SELECT → no output |
| `SELECT * FROM public.persons` | `SqlTableName("public", "persons")` | schema-qualified table |
| `SELECT * FROM t WHERE name = 'hello'` | `SqlScalarValue("hello")` | string literal in WHERE |
| `SELECT * FROM t WHERE a != b` | `SqlComparison` with `"<>"` | `!=` normalised to `<>` |
| `SELECT p.* FROM persons AS p` | `SqlAllColumns(SqlTableAlias("p"))` | qualifier.* |

---

## 9. Implementation lessons

- **`@document` field types**: The `@document` macro rewrites all field types
  to `::Cell`. Convenience constructors retain the original type annotations
  as dispatch guards. When a parser-produced value doesn't match (e.g.
  `SqlScalarValue` where `SqlSelectExpression` is expected), bypass the
  convenience constructor and use the Cell-level constructor directly:
  `SqlSelectItem(expr, alias, Cell(nothing))`.

- **`skip_trailing!` must respect `)`**: The initial implementation consumed
  all tokens to EOF, which broke subquery parsing — the closing `)` and
  trailing `AS alias` were swallowed. Fix: stop at `TK_RPAREN`.

---

## 10. Out of scope

- Reader / reference mapping (future: editing the parsed AST reflects back
  to `SqlRawStatement.content`).
- `INSERT`, `UPDATE`, `DELETE`, `CREATE` parsing.
- Expression types beyond comparisons and boolean connectives.
- Multi-statement parsing (only the first statement is parsed; `;` terminates).
- Error recovery with source-position diagnostics.
- Schema-qualified column names (`schema.table.column` three-part references).
