# SQL `GROUP BY` + SELECT aggregation support

> **Status (2026-08-12): NOT STARTED.** No part of this plan is built. A search
> of `package/sql/` finds no `SqlGroupByClause`, `SqlAggregateExpression`,
> `SqlAggregateFunction`, or `SqlCountFunction`/`SqlSumFunction`/etc. The parser
> (`package/sql/main/SqlParser.jl`) still only dispatches `SELECT` and `CREATE`.
> All three phases remain to do.

Add support for the `GROUP BY` clause (basic column list) and basic column
aggregation functions in the `SELECT` list (`COUNT`, `SUM`, `AVG`, `MIN`,
`MAX`, plus `COUNT(*)`).

This is the first feature to lift two items out of the **Out of scope** list in
[sql-statement.md](../done/sql-statement.md) (§5): `GROUP BY` and function-call
expressions as SELECT operands. `HAVING`, `ORDER BY`, `LIMIT`, arithmetic, and
function-call *comparison operands* stay out of scope.

Target example:

```sql
SELECT p.department, COUNT(*), AVG(p.salary) AS avg_salary
FROM persons AS p
WHERE p.age >= 18
GROUP BY p.department
```

---

## Affected files

| Layer | File | Phase |
|-------|------|-------|
| Document model | [package/sql/main/Sql.jl](../../source/sql/Sql.jl) | 1 |
| Doc model guide | [plan/done/sql-statement.md](../done/sql-statement.md) | 1 (maintain after) |
| Parser | [package/sql/main/SqlParser.jl](../../source/sql/SqlParser.jl) | 2 |
| Sql→Syntax projection | [package/sql/main/SqlToSyntax.jl](../../source/sql/SqlToSyntax.jl) | 3 |
| Examples | [package/sql/example/document/Sql.jl](../../example/sql/document/Sql.jl) | 1 / 3 |
| Tests | [package/sql/test/projection/SqlToSyntaxTest.jl](../../test/sql/projection/SqlToSyntaxTest.jl) and parser/printer tests | each phase |

---

## Implementation rules (apply to every phase)

1. **Test after each phase.** After completing a phase, write test cases that
   validate the newly introduced features:
   - **Atomic tests** covering *only* the new construct in isolation.
   - **Combined tests** that exercise the new construct *together with*
     previously implemented features (e.g. aggregation + WHERE + joins +
     subqueries) so existing behaviour is not regressed.
   Run the narrowest test that covers the change (see
   [CLAUDE.md](../../CLAUDE.md) "Testing a change"). **Do not advance to the
   next phase until these tests pass.**
2. **Maintain this plan after each phase.** Record what was actually
   implemented, any deviations from the design below, and lessons learned, so a
   later phase starts from ground truth rather than the original guess.
3. **After Phase 1, maintain [sql-statement.md](../done/sql-statement.md)** with the new
   document structs (hierarchy diagram §1, abstract-type tables §3, and remove
   the now-supported items from the Out-of-scope list §5).

---

## Phase 1 — Document structure

Add to [package/sql/main/Sql.jl](../../source/sql/Sql.jl) and
export from `SqlDocumentModule`.

### New abstract type

```julia
abstract type SqlAggregateFunction <: SqlDocument end
```

### Aggregate-function kind leaves

Model each function name as a dedicated leaf document, mirroring the existing
`SqlJoinType` family (`SqlInnerJoin`, `SqlLeftOuterJoin`, …) — leaf structs with
only a `selection::Reference`, no payload. This keeps the function name
statically distinguishable and gives the projection a `_aggregate_display`
helper analogous to `_join_type_display`.

```julia
@document struct SqlCountFunction <: SqlAggregateFunction; selection::Reference end
@document struct SqlSumFunction   <: SqlAggregateFunction; selection::Reference end
@document struct SqlAvgFunction   <: SqlAggregateFunction; selection::Reference end
@document struct SqlMinFunction   <: SqlAggregateFunction; selection::Reference end
@document struct SqlMaxFunction   <: SqlAggregateFunction; selection::Reference end
# + zero-arg convenience constructors, e.g. SqlCountFunction() = SqlCountFunction(Cell(nothing))
```

### Aggregate expression (SELECT operand)

A new concrete `SqlSelectExpression` so it slots into `SqlSelectItem.expression`
alongside `SqlAllColumns` and `SqlColumnReference`:

```julia
@document struct SqlAggregateExpression <: SqlSelectExpression
    func::SqlAggregateFunction
    argument::Any            # SqlColumnReference | SqlAllColumns (for COUNT(*))
    selection::Reference
end
```

- `argument` is `SqlColumnReference` for `SUM(p.salary)`, `AVG(col)`, etc.
- `argument` is `SqlAllColumns` (no qualifier) to represent `COUNT(*)`.
  Restrict `*` to `COUNT` at the parser/validation layer; the document model
  permits it structurally for any function.
- Add convenience constructors:
  `SqlAggregateExpression(func, arg)` defaulting `selection` to `Cell(nothing)`.

### GROUP BY clause (basic column list)

```julia
@document struct SqlGroupByClause <: SqlDocument
    items::CellVector        # [SqlColumnReference]   -- basic columns only
    selection::Reference
end
SqlGroupByClause() = SqlGroupByClause(CellVector(), Cell(nothing))
SqlGroupByClause(items::SqlColumnReference...) =
    SqlGroupByClause(CellVector([items...]), Cell(nothing))
```

"Basic column support" = a flat list of `SqlColumnReference`. Grouping by
expressions, ordinals, or aliases is out of scope.

### Wire GROUP BY into the statement

Add a `group_by_clause::SqlGroupByClause` field to `SqlSelectStatement`
(positioned after `where_clause`, before `selection`). An empty
`SqlGroupByClause` (no items) means "no GROUP BY" and renders nothing — the same
convention `SqlWhereClause` uses with a `nothing` condition.

**Backward compatibility is critical:** keep the existing
`SqlSelectStatement(sc, fc)` and `(sc, fc, wc)` convenience constructors working
by defaulting `group_by_clause` to `SqlGroupByClause()`. Add a new
`(sc, fc, wc, gbc)` constructor. The `SqlSelectStatement(table_name::String)`
convenience constructor also needs the new default. Audit every existing call
site / positional constructor (including the `@document`-generated all-fields
constructor used by the parser and projections).

### Base.show

Add `Base.show` for the new leaves and `SqlAggregateExpression` /
`SqlGroupByClause` for REPL debugging, matching the style at the bottom of
`Sql.jl`.

### Example document

Add an aggregation example to
[package/sql/example/document/Sql.jl](../../example/sql/document/Sql.jl) (e.g.
`make_sql_aggregation_document_example`) built from the target query above, for
use by later phases' tests.

### Phase 1 tests

- Atomic: construct each new document type directly; assert field access and
  `selection` defaults.
- Combined: construct a full `SqlSelectStatement` with aggregation in SELECT and
  a GROUP BY clause *plus* an existing WHERE clause; assert it builds and the
  old constructors (`SqlSelectStatement(sc, fc)` etc.) still work unchanged.

### Phase 1 maintenance

Update [sql-statement.md](../done/sql-statement.md): hierarchy diagram (add
`group_by_clause`, `SqlAggregateExpression`, the function leaves), the
abstract-type table (`SqlSelectExpression` now also has
`SqlAggregateExpression`; add `SqlAggregateFunction` row), and prune §5.

---

## Phase 2 — Parser support

Edit [package/sql/main/SqlParser.jl](../../source/sql/SqlParser.jl).

### Aggregate function in SELECT

Currently aggregate calls fall into `parse_fallback_expression!` (collected as a
raw `SqlScalarValue`). Replace that for the supported five functions:

- In `parse_select_expression!` (line ~536), before the fallback, detect an
  aggregate: an identifier/keyword whose upper-cased text is one of
  `COUNT`/`SUM`/`AVG`/`MIN`/`MAX` immediately followed by `(`.
- Parse `FUNC ( arg )` where `arg` is either `*` (only valid for `COUNT`,
  producing `SqlAllColumns()`) or a column reference via the existing
  `try_parse_column_or_star!`. Build `SqlAggregateExpression(func_leaf, arg)`.
- Add the function names to `SQL_KEYWORDS` only if needed; they currently parse
  as idents, which is fine — match case-insensitively on the ident text. Do
  **not** treat them as reserved elsewhere (a column named `count` must still
  parse as a column when not followed by `(`).
- `parse_select_item!` already handles the trailing `AS alias`; aggregate
  expressions get aliases for free (`COUNT(*) AS n`).

### GROUP BY clause

- In `parse_select_statement!` (line ~345), after the WHERE branch and **before**
  `skip_trailing!`, add a `GROUP` branch:

  ```julia
  gbc = if match_keyword(p, "GROUP") # then expect BY
      parse_group_by_clause!(p)
  else
      SqlGroupByClause()
  end
  ```
  then `SqlSelectStatement(sc, fc, wc, gbc)`.
- `parse_group_by_clause!`: expect `GROUP` then `BY`, then a comma-separated
  list of column references (reuse `try_parse_column_or_star!` / the column-ref
  parser, rejecting `*`). Build `SqlGroupByClause(items...)`.
- `GROUP`/`ORDER` are already in the keyword sets and the `skip_trailing!` stop
  lists (lines ~99, ~308, ~717, ~970). Removing `GROUP` from the *trailing-skip*
  set is required so GROUP BY is parsed instead of skipped — but keep `ORDER`,
  `HAVING`, `LIMIT`, etc. there so trailing clauses after GROUP BY are still
  consumed. Verify the column-list parser stops at `ORDER`/`HAVING`/`LIMIT`/`)`.

### Phase 2 tests

- Atomic: `sqlparse("SELECT COUNT(*) FROM t")`,
  `sqlparse("SELECT SUM(t.x) FROM t")`,
  `sqlparse("SELECT a FROM t GROUP BY a")` → assert the resulting document
  types (`SqlAggregateExpression` with the right func leaf;
  `SqlGroupByClause` with the right column items). Confirm `count` as a bare
  column still parses as a column.
- Combined: parse the full target query (aggregation + alias + WHERE +
  GROUP BY); assert structure. Re-run a representative existing parser test
  (e.g. the join/subquery example) to confirm no regression. Confirm a trailing
  `ORDER BY` after `GROUP BY` is still skipped cleanly.

---

## Phase 3 — Sql→Syntax projection (full bidirectional)

Edit
[package/sql/main/SqlToSyntax.jl](../../source/sql/SqlToSyntax.jl).
Follow the patterns documented in
[sql-to-syntax-selection-support.md](../done/sql-to-syntax-selection-support.md) — every
new node projection needs `projection_print`, `map_reference_forward`,
`map_reference_backward`, and `projection_read`, and must be registered in the
projection map (line ~2229).

### New projections

1. **`SqlAggregateFunctionToSyntaxLeaf`** — leaf, like
   `SqlJoinTypeToSyntaxLeaf`. The five function structs have a `selection`
   field (unlike join types), so use the **shared-cell trick**
   (`doc.selection` straight into the leaf). Display text via an
   `_aggregate_display` helper (`COUNT`, `SUM`, `AVG`, `MIN`, `MAX`). Register
   each leaf type → this projection.

2. **`SqlAggregateExpressionToSyntaxNode`** — node. Output shape:
   `FUNC ( argument )`. Children with input pre-images: the func leaf and the
   argument; the parens are proj-introduced. Forward arms: `func.rest…` →
   `children[1]`, `argument.rest…` → the argument's child position. Use the
   standard node template; `COUNT(*)` projects the argument through
   `SqlAllColumnsToSyntaxLeaf`.

3. **`SqlGroupByClauseToSyntaxNode`** — node, modeled on
   `SqlWhereClauseToSyntaxNode` (keyword + body) crossed with
   `SqlFromClauseToSyntaxNode` (comma-separated items list through a body node).
   Output: `GROUP BY` keyword + newline/indent body whose children are the
   column-reference leaves. Use the **items-list-through-body-node** forward/
   backward pattern. Renders **nothing when `items` is empty** (the
   "no GROUP BY" case) — mirror how the statement node omits an absent WHERE.

### Wire into `SqlSelectStatementToSyntaxNode`

Edit `projection_print` (line ~1378) and its mappers (lines ~1423/1452):

- In `projected`, add a `gbc` entry: `nothing` when
  `stmt.group_by_clause.items` is empty, else the projected clause (analogous to
  the existing `wc` handling).
- Append `gbc` to `child_iomaps_cell` and `children` after `wc` when present.
  Because both WHERE and GROUP BY are optional, the child index of GROUP BY is
  **dynamic** (3 if no WHERE, 4 with WHERE). Handle this the way
  `SqlSelectClauseToSyntaxNode` handles its dynamic `body_idx` (compute from
  `iomap.input`): compute the GROUP BY child position from whether
  `where_clause.condition === nothing`.
- Add `group_by_clause.rest…` forward arm and the matching backward arm
  (extend the `children{s:_}` dispatch to map the computed index back to
  `group_by_clause`).

### Examples / selection test

- Register the new projections so the `make_sql_aggregation_document_example`
  from Phase 1 renders end-to-end (`Sql→Syntax→Text→String`).
- Per the **Rule: new SQL projection → must add to selection test** in
  [sql-to-syntax-selection-support.md](../done/sql-to-syntax-selection-support.md):
  ensure the nested/aggregation example in `test_sql_to_syntax_selection()`
  exercises every new node and leaf, or add a targeted call using the live
  test helper `test_position_navigation(label, document, projection)` (there is
  no `test_selection` and no `test/src/editor/SelectionTest.jl` — that API does
  not exist in the current tree; see
  [sql-to-syntax-selection-support.md](../done/sql-to-syntax-selection-support.md)).

### Phase 3 tests

- Atomic: `test_printer` / `test_reader` on a minimal aggregation example
  (`SELECT COUNT(*) FROM t`) and a minimal GROUP BY example;
  `test_position_navigation` on each new projection.
- Combined: `test_example(sql_aggregation_example)` (printer + reader +
  navigation) on the full target query; `test_sql_to_syntax_selection()` over
  the extended nested document; re-run the existing nested SQL example to
  confirm no regression.
- Round-trip: `sqlparse(target) → Sql→Syntax→Text→String` reproduces the query
  (modulo the known transformations listed in
  [sql-parser.md](../done/sql-parser.md) "Round-trip characteristics").

---

## Out of scope (still)

- `HAVING`, `ORDER BY`, `LIMIT`, `OFFSET`.
- Aggregates with `DISTINCT` argument (`COUNT(DISTINCT x)`), `FILTER`, or
  `OVER` (window) clauses.
- Aggregate or arbitrary expressions as GROUP BY keys (basic columns only).
- Aggregates as comparison operands in WHERE/HAVING.
- Arithmetic and general function-call expressions (unchanged from
  [sql-statement.md](../done/sql-statement.md) §5).
```
