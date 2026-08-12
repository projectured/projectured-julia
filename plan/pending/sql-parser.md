# SqlParser — SQL parser module

> **Status (2026-08-12): DONE**, for the scope this plan states (SELECT parsing,
> later grown to include `CREATE TABLE`/`CREATE SCHEMA` DDL). INSERT/UPDATE
> parsing and `GROUP BY`/aggregate parsing are out of this plan's scope — see
> [sql-insert-update-support.md](sql-insert-update-support.md) and
> [sql-select-aggregation-support.md](sql-select-aggregation-support.md), both
> still open on the parser side. The one residual gap named below,
> `SqlJoinUsingCondition` having no `SqlToSyntax` projection, is still true.

> **✅ DONE (verified):** Module implemented at `package/sql/main/SqlParser.jl` (the plan's `program/src/parser/` path is the pre-restructure location). `SqlParserModule` exports `sqlparse`/`sqlparse_file` (line 42), is included from `package/sql/main/ProjecturedSql.jl:39`, and is exercised by `package/sql/test/document/SqlParserTest.jl` (`test_sql_parser`). Implementation now exceeds the SELECT-only scope described here — it also parses `CREATE TABLE`/`CREATE SCHEMA` DDL (SqlParser.jl:376-451). Per-step notes below.

`sqlparse(text) → SqlSelectStatement`. A standalone parser that turns SQL source
text into the `SqlDocument` hierarchy, mirroring the other parsers in
`program/src/parser/` (`jsonparse`, `xmlparse`, …). The result round-trips back to
text through the rendering pipeline (`SqlToSyntax → SyntaxToText → TextToString`).

**File:** `program/src/parser/SqlParser.jl`

**⛔ OBSOLETE (path):** File now lives at `package/sql/main/SqlParser.jl` after the repo restructure (`program/src/...` no longer exists). The file itself exists and matches the described purpose.

**Entry points:**
- `sqlparse(text)` — parse a SQL string into a `SqlSelectStatement`.
- `sqlparse_file(path)` — read and parse a `.sql` file from disk.

**✅ DONE (verified):** Both entry points exist — `sqlparse(text::AbstractString)` at `SqlParser.jl:55` and `sqlparse_file(path)` at `SqlParser.jl:66` (`= sqlparse(read(path, String))`), both exported at `SqlParser.jl:42`. Note: `sqlparse` now returns the broader `SqlStatement` (SELECT or CREATE DDL), not strictly `SqlSelectStatement`.

---

## Scope

**✅ DONE (verified):** All listed SELECT-related constructs are parsed and imported from `SqlDocumentModule` (`SqlParser.jl:31-40`): SELECT/FROM/WHERE clauses, joins (`parse_join_type!` SqlParser.jl:735 handles INNER/LEFT/RIGHT/FULL OUTER/CROSS), ON/USING conditions (`parse_join_condition!` SqlParser.jl:784), subqueries (`parse_from_base_item!` SqlParser.jl:656), boolean expressions (`parse_or!`/`parse_and!`/`parse_not!`/`parse_comparison!` SqlParser.jl:828-903), column references, aliases, DISTINCT (SqlParser.jl:486), and scalar values (numbers/strings/booleans, `parse_scalar_operand!` SqlParser.jl:905). The unsupported-fragment handling below is also all present. Scope has additionally grown to cover CREATE TABLE/SCHEMA DDL (not in original plan).

Parses exactly the SELECT-related types defined in `Sql.jl`: SELECT/FROM/WHERE
clauses, joins (INNER, LEFT/RIGHT/FULL OUTER, CROSS), ON and USING conditions,
subqueries, boolean expressions (AND/OR/NOT/comparison), column references,
aliases, DISTINCT, and scalar values (numbers, strings, booleans).

**✅ DONE (verified):** All four unsupported-fragment behaviors are implemented as described — comments stripped in `tokenize` (line/block, SqlParser.jl:124-146); `skip_trailing!` (SqlParser.jl:1020); fallback to `SqlScalarValue(raw)` in `parse_fallback_expression!` (SqlParser.jl:973-1016); `parse_sql` returns `nothing` (SqlParser.jl:340) and `sqlparse` converts to `error("SQL: not a parseable statement")` (SqlParser.jl:57). Verified by test `@test_throws Exception sqlparse("INSERT INTO t VALUES (1)")` (SqlParserTest.jl:215).

Unsupported fragments are silently handled:
- **Comments** (`--`, `/* */`) — stripped by tokeniser.
- **Unsupported clauses** (GROUP BY, ORDER BY, etc.) — consumed by `skip_trailing!`.
- **Unsupported expressions** (function calls, arithmetic, CASE) — collected
  into `SqlScalarValue(raw_text)` via greedy token fallback.
- **Non-SELECT / unparseable statements** — `sqlparse` raises an error (matching
  the `jsonparse`/`juliaparse` convention). Internally the private `parse_sql`
  helper returns `nothing`, which the public `sqlparse` converts to an error.

---

## Architecture

**✅ DONE (verified):** Tokeniser produces `Vector{SqlToken}` with exactly 13 `SqlTokenKind` values (`@enum` SqlParser.jl:72-86), uses `SubString` zero-copy values (struct SqlParser.jl:88-92), and matches keywords against `SQL_KEYWORDS::Set{String}` (SqlParser.jl:94, used at SqlParser.jl:224). Parser is recursive-descent single-pass with one-token lookahead (`peek`/`advance!` SqlParser.jl:251-259); boolean precedence OR<AND<NOT realized by `parse_or!`→`parse_and!`→`parse_not!` (SqlParser.jl:828-862); `!=` normalised to `<>` at SqlParser.jl:887-889. The simplified grammar matches the implemented `parse_*!` functions.

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

**✅ DONE (verified):** All four design decisions are reflected in code:
- Fallback expression — `parse_fallback_expression!` greedily collects to a delimiter respecting paren depth, wrapping raw text in `SqlScalarValue` (SqlParser.jl:973-1016; `FALLBACK_DELIMITERS` SqlParser.jl:968).
- `skip_trailing!` stops at `)` — `while !at_end(p) && peek(p).kind != TK_RPAREN` (SqlParser.jl:1021).
- Bypassing typed constructors — `SqlSelectItem(expr, alias, Cell(nothing))` built directly (SqlParser.jl:531, with explanatory comment SqlParser.jl:528-530).
- Error strategy — `try/catch` around `parse_select_statement!`/`parse_create_statement!` collapsing partial-parse exceptions to `nothing` (SqlParser.jl:328-338), surfaced as an error by `sqlparse` (SqlParser.jl:57).

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

- **Error strategy**: unparseable input → `sqlparse` raises; partial parse →
  best-effort with broken fragments wrapped in `SqlScalarValue`; a `try/catch`
  around the internal `parse_sql` prevents partial-parse exceptions from
  propagating (they collapse to the "not parseable" error).

---

## Round-trip characteristics

**✅ DONE (verified):** The round-trip pipeline is real and tested — `SequentialProjection(RecursiveProjection(SqlToSyntax()), RecursiveProjection(SyntaxToText()), RecursiveProjection(TextToString()))` in `SqlParserTest.jl:19-23`, asserting normalized round-trip equality (e.g. SqlParserTest.jl:34). The documented transformations hold: `JOIN → INNER JOIN` asserted at SqlParserTest.jl:90; join-type display strings at `SqlToSyntax.jl:223-224` (`SqlInnerJoin → "INNER JOIN"`, `SqlLeftOuterJoin → "LEFT OUTER JOIN"`). The final bullet — `SqlJoinUsingCondition` has no `SqlToSyntax` projection yet — **remains OPEN/accurate**: `SqlJoinUsingCondition` is not imported or registered in `SqlToSyntax.jl` (only `SqlJoinOnConditionToSyntaxNode` exists, SqlToSyntax.jl:506; USING round-trip is explicitly skipped at SqlParserTest.jl:134). This is the one residual gap.

The pipeline (`SqlToSyntax → SyntaxToText → TextToString`) does not reproduce
raw SQL verbatim. Known transformations:
- `JOIN` → `INNER JOIN`, `LEFT JOIN` → `LEFT OUTER JOIN`, etc.
- AND/OR/NOT wrapped in parentheses.
- Subquery body gets trailing space before `)`.
- Trailing clauses dropped; fallback expressions render string-quoted (lossy).
- `SqlJoinUsingCondition` has no `SqlToSyntax` projection yet.
