# Single-line INSERT and UPDATE support

> **Status (2026-08-12): IN PROGRESS.** Document model, projection, examples, and
> tests are implemented and passing (re-confirmed today). The parser (§3) is
> still **not implemented** — `package/sql/main/SqlParser.jl` still dispatches
> only `SELECT`/`CREATE`; no INSERT/UPDATE parsing exists. That remains the one
> open item blocking this plan from DONE.

> **Status (as-built):** document model, projection, examples, and tests are
> **implemented and passing**. The parser (§3) was **deferred** — it remains the
> only open item. Sections below have been updated to match what actually shipped;
> places where the implementation diverged from the original design are called out
> with **As-built** notes.

> **✅ AUDIT (verified 2026-06-23):** §1 (model), §2 (projection), §4 (examples),
> §5 (tests) are all **DONE** against the current `package/` tree. §3 (parser) is
> **OPEN** — `parse_sql` in `package/sql/main/SqlParser.jl:325` still
> dispatches only `SELECT`/`CREATE`, no INSERT/UPDATE. Per-step evidence inline below.
> Note: old `program/src/...` and top-level `Projectured.jl` re-export paths in the
> text are pre-restructure; symbols now live/export under `package/<subpkg>/main/...`
> (source) and `package/<subpkg>/example/...` / `package/<subpkg>/test/...`
> (examples and tests), not `package/<subpkg>/src/...`.

Flesh out the two statement stubs `SqlInsertStatement` and `SqlUpdateStatement`
([program/src/document/Sql.jl:314-322](program/src/document/Sql.jl#L314-L322)) into
real document trees, give each a bidirectional `SqlToSyntax` projection
([program/src/projection/primitive/SqlToSyntax.jl](program/src/projection/primitive/SqlToSyntax.jl)),
and wire up examples plus tests.

Scope is **simple, single-row, single-line** statements only:

```sql
INSERT INTO persons (name, age) VALUES ('Ada', 36)
UPDATE persons SET age = 37 WHERE name = 'Ada'
```

This builds on the model designed in [sql-statement.md](../done/sql-statement.md) and reuses
its leaf types (`SqlTableName`, `SqlColumnName`, `SqlScalarValue`) and the existing
`SqlWhereClause` / boolean-expression subtree unchanged.

---

## 1. Document model (`package/sql/main/Sql.jl`)

**✅ DONE (verified):** all types/constructors exist in
`package/sql/main/Sql.jl` (not `package/sql/example/document/Sql.jl` — that file
holds only the `make_sql_*_document_example` builders, not the struct
definitions) — `SqlInsertStatement` (216-226), `SqlUpdateAssignment` (228-232),
`SqlUpdateStatement` (234-244), plus the zero-arg/ergonomic constructors
(331-336). Exported from `SqlDocumentModule`.
**⛔ OBSOLETE sub-point:** the "re-export from `Projectured.jl:255-269`/`:551+`"
wiring is pre-restructure path; exports now flow via the domain module export list.

### INSERT

```
SqlInsertStatement <: SqlStatement
├── table   : SqlTableName
├── columns : [SqlColumnName]        -- may be empty ⟹ omit the (col, …) list
├── values  : [SqlScalarValue]       -- single row; length should match columns
└── selection : Reference
```

Replace the stub at [Sql.jl:314-317](program/src/document/Sql.jl#L314-L317). Keep a
zero-arg `SqlInsertStatement()` constructor for backward compatibility (empty table /
columns / values) so existing `@test SqlInsertStatement() isa SqlInsertStatement`
keeps passing, plus an ergonomic constructor:

```julia
SqlInsertStatement(table::SqlTableName, columns::Vector{SqlColumnName}, values::Vector{SqlScalarValue})
```

### UPDATE

Introduce one new leaf document for an assignment, then the statement:

```
SqlUpdateAssignment <: SqlDocument
├── column_name : SqlColumnName
├── value       : SqlScalarValue
└── selection   : Reference

SqlUpdateStatement <: SqlStatement
├── table        : SqlTableName
├── assignments  : [SqlUpdateAssignment]   -- non-empty
├── where_clause : SqlWhereClause          -- reuse existing; empty ⟹ no WHERE rendered
└── selection    : Reference
```

Replace the stub at [Sql.jl:319-322](program/src/document/Sql.jl#L319-L322). Keep a
zero-arg `SqlUpdateStatement()` for compatibility.

Use `@document struct` and `CellVector` for the list fields, matching
`SqlSelectClause` / `SqlFromClause`. Add `Base.show` only if useful for debugging
(optional). Export the new `SqlUpdateAssignment` type (+ its `ISqlUpdateAssignment`
interface) and the updated constructors from `SqlDocumentModule`.

### Wiring

- Export `SqlUpdateAssignment` in [Sql.jl](program/src/document/Sql.jl) and re-export
  it from [Projectured.jl:255-269](program/src/Projectured.jl#L255-L269) and the
  top-level `export` list at [Projectured.jl:551+](program/src/Projectured.jl#L551).

---

## 2. Projection (`SqlToSyntax.jl`)

**✅ DONE (verified):** all projections exist in
`package/sql/main/SqlToSyntax.jl` —
`SqlInsertStatementToSyntaxNode` (1269, with forward/backward ref maps 1327/1362 and
`projection_read(::ReplaceSelectionOperation)` 1399), `SqlUpdateAssignmentToSyntaxNode`
(1413), `SqlUpdateStatementToSyntaxNode` (1506), plus the two bare-name leaves
`SqlColumnNameToSyntaxLeaf` (114) and `SqlTableNameToSyntaxLeaf` (124). All registered
in the `SqlToSyntax()` compound (1969-70, 1987-89) and exported from the module
(48, 57-58). **⛔ OBSOLETE sub-point:** §2.5 "re-export in `Projectured.jl`" — the
`package/projectured/src/Projectured.jl` file no longer references SQL; exports flow
through the domain module export list instead.

Add four projection types following the exact pattern already used by
`SqlSelectClauseToSyntaxNode` / `SqlSelectItemToSyntaxNode` (keyword leaves via
`_kw`, `ChildrenIoMap`, `iomap_cell` + `sel` cell, `map_reference_forward` /
`map_reference_backward`, and the `projection_read(::ReplaceSelectionOperation)`
flat-position fallback). Each needs a matching reader — projections are bidirectional
(see [CLAUDE.md](../../CLAUDE.md) conventions and [package/kernel/doc/projection-system.md](../../package/kernel/doc/projection-system.md)).

1. **`SqlInsertStatementToSyntaxNode`** — renders
   `INSERT INTO <table> (<col>, …) VALUES (<val>, …)`.
   - Child iomaps: the table leaf, each column leaf, each value leaf. Reference cases:
     `table`, `columns{i}`, `values{i}` forward; corresponding `children[…]` backward.
   - The column and value leaves live one level deeper, inside parenthesised
     comma lists rendered as `SyntaxNode("(", ")", ", ", …)`. So a column maps to
     `children[cols_idx].children[i]` and a value to `children[vals_idx].children[i]`.
   - **As-built:** the column list is omitted when `columns` is empty, which shifts
     the `VALUES`/values-paren positions — handle this with a `cols_present` /
     `vals_idx` computation in both reference maps (mirrors how
     `SqlSelectClauseToSyntaxNode` shifts indices for the optional `DISTINCT`).
   - Render single-line: a single `SyntaxNode` with a space separator and inline
     `_kw` keywords, **not** the indented `_comma_body` / `_newline_body` helpers the
     SELECT clauses use.

2. **`SqlUpdateAssignmentToSyntaxNode`** — renders `<col> = <value>`.
   - Two child iomaps (column leaf, value leaf); column at `children[1]`, value at
     `children[3]`, with `=` at `children[2]`.
   - **As-built:** `=` is rendered via `_kw("=", …)` (bold/blue keyword style), matching
     how `SqlComparisonToSyntaxNode` renders its operator — not a plain leaf.

3. **`SqlUpdateStatementToSyntaxNode`** — renders
   `UPDATE <table> SET <assignment>, … [WHERE <condition>]`.
   - Child iomaps: table leaf, each `SqlUpdateAssignment` node, and (when present) the
     WHERE condition. Positions: `[1]=UPDATE [2]=table [3]=SET [4]=assignments-body`
     `[5]=WHERE [6]=condition`; 5/6 present only when there is a condition.
   - **As-built — WHERE is rendered inline, NOT via `SqlWhereClauseToSyntaxNode`.**
     The original plan said to reuse the whole where-clause projection, but that
     projection is deliberately multi-line (`WHERE\n  <cond>\n` via `_newline_body`),
     which would break the single-line goal. Instead, project
     `stmt.where_clause.condition` directly and emit `_kw("WHERE")` + the condition's
     output inline. The condition is still included only when
     `where_clause.condition !== nothing`. The reference maps therefore route through
     the two-level path `where_clause.condition.<rest>` ⇄ `children[6]`.

4. Register all of them in the `SqlToSyntax()` compound constructor:
   `SqlInsertStatement => …`, `SqlUpdateStatement => …`, `SqlUpdateAssignment => …`.
   INSERT/UPDATE also need **two new bare-name leaves**, because their targets/columns
   are bare `SqlTableName` / `SqlColumnName` documents that no existing projection
   handles (`SqlColumnReference` and `SqlTableExpression` render those names inline
   rather than recursing into them):
   - `SqlColumnNameToSyntaxLeaf` (mirror `SqlColumnReferenceToSyntaxLeaf`), registered
     `SqlColumnName => SqlColumnNameToSyntaxLeaf()`.
   - **As-built:** also `SqlTableNameToSyntaxLeaf` (renders `schema.name` or `name`),
     registered `SqlTableName => SqlTableNameToSyntaxLeaf()`. Adding these global
     dispatch entries is harmless — they are only reached via INSERT/UPDATE recursion.

5. Add the new projection types to the module `export` list and the re-export in
   [Projectured.jl](program/src/Projectured.jl).

### Single-line rendering note

The existing SELECT projection deliberately renders multi-line (indented clause
bodies). INSERT/UPDATE here must stay on one line, so reuse only the inline
separator helpers and keep keywords (`INSERT`, `INTO`, `VALUES`, `UPDATE`, `SET`,
`WHERE`) as `_kw` leaves on a single `SyntaxNode` with a space separator.

---

## 3. Parser (`SqlParser.jl`) — DEFERRED (open follow-up)

**⏳ OPEN (verified still open):** `parse_sql` in
`package/sql/main/SqlParser.jl:325-341` dispatches only `SELECT` and
`CREATE`; there are no `parse_insert!`/`parse_update!` functions and no
`SqlInsertStatement`/`SqlUpdateStatement` construction in the parser. (INSERT/UPDATE
appear only in the keyword set at SqlParser.jl:100-102.) Remains the sole open item.

**Not implemented.** `sqlparse` still handles SELECT only. To finish: extend the entry
point to dispatch on the leading keyword (`INSERT` / `UPDATE` / `SELECT`) and add two
recursive-descent parse functions producing the new document trees. The shipped
projection + examples + tests do **not** depend on the parser, so this can land
separately without touching the rest of this work.

---

## 4. Examples

**✅ DONE (re-verified 2026-08-12):** `make_sql_insert_document_example` /
`make_sql_update_document_example` in `package/sql/example/document/Sql.jl:60,68`;
`make_sql_insert_syntax_projection_example` / `…_update_…` in
`package/sql/example/projection/Sql.jl:9,17`. Registered as `sql_insert_syntax_example`
/ `sql_update_syntax_example` in `package/projectured/example/DomainExamples.jl:97-98`
and the example list at 179-180; exported via `package/projectured/example/Examples.jl:42-43`
and `package/projectured/example/ProjecturedExample.jl`.

In [package/sql/example/document/Sql.jl](../../package/sql/example/document/Sql.jl) (already present):

```julia
make_sql_insert_document_example()  # INSERT INTO persons (name, age) VALUES ('Ada', 36)
make_sql_update_document_example()  # UPDATE persons SET age = 37 WHERE name = 'Ada'
```

In [package/sql/example/projection/Sql.jl](../../package/sql/example/projection/Sql.jl)
(already present): matching `make_sql_insert_syntax_projection_example` / `…_update_…`
(same three-stage `SqlToSyntax → SyntaxToText → TextToGraphics` pipeline as
`make_sql_syntax_projection_example`).

Registered as `sql_insert_syntax_example` and `sql_update_syntax_example` in
[package/projectured/example/DomainExamples.jl](../../package/projectured/example/DomainExamples.jl)
and the example list there.

---

## 5. Tests

**✅ DONE (re-verified 2026-08-12):** in `package/sql/test/projection/SqlToSyntaxTest.jl` the four
render checks exist (incl. empty-column and no-WHERE branches) and the
self-contained `test_sql_insert_update_selection()` covers INSERT
table/columns[i]/values[i] and UPDATE table/assignments[i].column_name/value plus a
`where_clause.condition.expression.left` sub-reference, asserting backward∘forward==path.
Exported and wired into `test_projections()` (`package/projectured/test/ProjecturedTest.jl`).

In [package/sql/test/projection/SqlToSyntaxTest.jl](../../package/sql/test/projection/SqlToSyntaxTest.jl):

- Replace the "Stubs compile" asserts with real round-trip rendering checks via the
  `sql_text` helper already defined there. Cover the index-shifting/optional branches,
  not just the happy path:
  - `INSERT INTO persons (name, age) VALUES ('Ada', 36)` (with column list)
  - `INSERT INTO persons VALUES ('Ada', 36)` (empty column list → list omitted)
  - `UPDATE persons SET age = 37 WHERE name = 'Ada'` (with WHERE)
  - `UPDATE persons SET name = 'Ada', age = 37` (no WHERE, multiple assignments)
- Add a **self-contained** selection round-trip test, `test_sql_insert_update_selection()`.
  **As-built / gotcha (historical):** at the time this was written, `test_sql_to_syntax_selection()`
  called a `test_selection` helper that was **defined nowhere in the repo**, so it could
  not be mirrored and the new test stood alone. **Since fixed:** the live
  `test_sql_to_syntax_selection()` now calls `test_position_navigation("SqlToSyntax nested",
  doc, proj)` — the current, working equivalent (see
  [sql-to-syntax-selection-support.md](sql-to-syntax-selection-support.md)). The
  standalone `test_sql_insert_update_selection()` still exists and still works the
  original way: `projection_print` the doc, take `iomap.projection` (RecursiveProjection
  unwraps to the concrete node projection), and assert
  `map_reference_backward(p, iomap, map_reference_forward(p, iomap, path)) == path`
  for `table`, `columns[i]`, `values[i]` (INSERT) and `table`, `assignments[i].column_name`,
  `assignments[i].value`, and a `where_clause.condition.expression.left` sub-reference
  (UPDATE). Build multi-step paths with `Reference(steps...)`.
- Needs `Reference`, `map_reference_forward`, `map_reference_backward` imported in
  [package/projectured/test/ProjecturedTest.jl](../../package/projectured/test/ProjecturedTest.jl),
  and the new test wired into `test_projections()` + the module `export` — already done.

### Verifying

Per [CLAUDE.md](../../CLAUDE.md) "Testing a change", use the narrowest scope:

```julia
test_sql_document()                  # document model still loads
test_sql_to_syntax()                 # rendering, incl. the new INSERT/UPDATE cases
test_sql_insert_update_selection()   # selection round-trip
```

**Do not rely on `test_example(sql_insert_syntax_example)` as a clean signal.**
`test_example` bundles a **typein** sub-test (`walk_typein`) that fails for SQL
scalar/column leaves — but this is a **pre-existing, SQL-wide limitation**: the
existing `sql_syntax_example` (SELECT) fails the same typein check, and the broad
`test_typeins()` sweep only covers `json/json_string/text/xml/book/syntax`, never SQL.
So the printer/reader/navigation portions of `test_example` pass for the new examples;
only the typein portion fails, and adding the examples to the registry does **not**
make the broad suite red. Editable string typein for SQL leaves is out of scope (see §6).

---

## 6. Out of scope

- Multi-row `INSERT ... VALUES (…), (…)` and `INSERT ... SELECT`.
- `RETURNING`, `ON CONFLICT`, `DEFAULT VALUES`, `FROM` in UPDATE.
- Expressions (arithmetic, function calls) as inserted/assigned values — values are
  `SqlScalarValue` only (`42`, `'text'`, `TRUE`/`FALSE`), as in SELECT.
- Qualified/multi-table UPDATE targets and joins.
- Multi-line / pretty-printed layout — these statements render on a single line.
- Parser support (see §3) — deferred, lands as a follow-up.
- Editable-string **typein** for SQL leaves (scalar values, column/table names). Not
  supported for any SQL document today (SELECT included); a separate effort.
