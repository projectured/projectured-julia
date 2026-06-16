# SqlRawToSql projection — SQL parser

`SqlRawStatement` → `SqlSelectStatement` parser projection. The *inverse*
of the rendering pipeline (`SqlToSyntax → SyntaxToText → TextToString`).
Printer-only (no readers, no reference mapping).

**File:** `program/src/projection/primitive/SqlRawToSql.jl`

---

## Scope

Parses exactly the SELECT-related types defined in `Sql.jl`: SELECT/FROM/WHERE
clauses, joins (INNER, LEFT/RIGHT/FULL OUTER, CROSS), ON and USING conditions,
subqueries, boolean expressions (AND/OR/NOT/comparison), column references,
aliases, DISTINCT, and scalar values (numbers, strings, booleans).

Unsupported fragments are silently handled:
- **Comments** (`--`, `/* */`) — stripped by tokeniser.
- **Unsupported clauses** (GROUP BY, ORDER BY, etc.) — consumed by `skip_trailing!`.
- **Unsupported expressions** (function calls, arithmetic, CASE) — collected
  into `SqlScalarValue(raw_text)` via greedy token fallback.
- **Non-SELECT statements** — `parse_sql` returns `nothing`.

---

## Architecture

**Tokeniser**: scans raw string into `Vector{SqlToken}` with 13 token kinds
(`TK_KEYWORD`, `TK_IDENT`, `TK_OP`, etc.). Zero-copy `SubString` values.
Keywords recognised by checking against `SQL_KEYWORDS::Set{String}`.

**Parser**: recursive-descent, single-pass, one-token lookahead. Boolean
precedence: OR < AND < NOT. `!=` normalised to `<>`.

**Grammar** (simplified):
```
select_statement := select_clause [from_clause] [where_clause] [trailing…]
select_clause    := SELECT [DISTINCT] select_item {, select_item}
from_clause      := FROM from_item {, from_item}
from_item        := base_item {join_segment}
base_item        := (select_statement) [AS alias] | [schema.]table [AS alias]
where_clause     := WHERE boolean_expression
boolean_expr     := or { OR or }  →  and { AND and }  →  [NOT] primary
primary          := (boolean_expr) | scalar_operand comp_op scalar_operand
```

---

## Design decisions

- **Fallback expression**: when the parser hits an unrecognised expression
  (e.g. `COUNT(*)`), it greedily collects tokens until a structural delimiter
  (`,`, `)`, `AS`, clause keywords), respecting paren depth, and wraps the
  raw text in `SqlScalarValue`. This preserves surrounding structure.

- **`skip_trailing!` stops at `)`**: trailing-clause consumption must not
  cross subquery boundaries — stopping at `TK_RPAREN` preserves the closing
  paren and any alias that follows.

- **Bypassing typed constructors**: `@document` rewrites fields to `::Cell`
  but convenience constructors keep original type guards. When the parser
  produces `SqlScalarValue` where `SqlSelectExpression` is expected, it
  builds `SqlSelectItem(expr, alias, Cell(nothing))` directly.

- **Error strategy**: unparseable input → `nothing`; partial parse → best-effort
  with broken fragments wrapped in `SqlScalarValue`; `try/catch` around the
  full parse prevents propagation.

---

## Round-trip characteristics

The pipeline (`SqlToSyntax → SyntaxToText → TextToString`) does not reproduce
raw SQL verbatim. Known transformations:
- `JOIN` → `INNER JOIN`, `LEFT JOIN` → `LEFT OUTER JOIN`, etc.
- AND/OR/NOT wrapped in parentheses.
- Subquery body gets trailing space before `)`.
- Trailing clauses dropped; fallback expressions render string-quoted (lossy).
- `SqlJoinUsingCondition` has no `SqlToSyntax` projection yet.
