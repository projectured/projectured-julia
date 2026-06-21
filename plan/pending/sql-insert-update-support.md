# Single-line INSERT and UPDATE support

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

This builds on the model designed in [sql-statement.md](sql-statement.md) and reuses
its leaf types (`SqlTableName`, `SqlColumnName`, `SqlScalarValue`) and the existing
`SqlWhereClause` / boolean-expression subtree unchanged.

---

## 1. Document model (`program/src/document/Sql.jl`)

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

Add four projection types following the exact pattern already used by
`SqlSelectClauseToSyntaxNode` / `SqlSelectItemToSyntaxNode` (keyword leaves via
`_kw`, `ChildrenIoMap`, `iomap_cell` + `sel` cell, `map_reference_forward` /
`map_reference_backward`, and the `projection_read(::ReplaceSelectionOperation)`
flat-position fallback). Each needs a matching reader — projections are bidirectional
(see [CLAUDE.md](CLAUDE.md) conventions and [guide/projection-system.md](guide/projection-system.md)).

1. **`SqlInsertStatementToSyntaxNode`** — renders
   `INSERT INTO <table> (<col>, …) VALUES (<val>, …)`.
   - `table` is a `SqlTableExpressionToSyntaxLeaf`-style leaf, or reuse the table-name
     rendering. Columns and values render as comma-separated parenthesised lists.
   - Child iomaps: the table leaf, each column leaf, each value leaf. Reference cases:
     `table`, `columns{i}`, `values{i}` forward; corresponding `children[…]` backward.
   - Render single-line: use space separators (`_space_node` / inline `_kw`), **not**
     the indented `_comma_body` / `_newline_body` helpers the SELECT clauses use.

2. **`SqlUpdateAssignmentToSyntaxNode`** — renders `<col> = <value>`.
   - Two child iomaps (column leaf, value leaf), `=` as a plain (non-keyword) leaf.

3. **`SqlUpdateStatementToSyntaxNode`** — renders
   `UPDATE <table> SET <assignment>, … [WHERE …]`.
   - Child iomaps: table leaf, each `SqlUpdateAssignment` node, optional where clause
     (reuse `SqlWhereClauseToSyntaxNode`, included only when
     `where_clause.condition !== nothing`, exactly like
     `SqlSelectStatementToSyntaxNode` does at
     [SqlToSyntax.jl:1310-1319](program/src/projection/primitive/SqlToSyntax.jl#L1310-L1319)).

4. Register all of them in the `SqlToSyntax()` compound constructor
   ([SqlToSyntax.jl:1409-1436](program/src/projection/primitive/SqlToSyntax.jl#L1409-L1436)):
   `SqlInsertStatement => …`, `SqlUpdateStatement => …`,
   `SqlUpdateAssignment => …`. `SqlColumnName` is currently rendered only inside
   `SqlColumnReference`; INSERT/UPDATE need a bare-column-name leaf, so add a small
   `SqlColumnNameToSyntaxLeaf` (mirror `SqlColumnReferenceToSyntaxLeaf`) and register
   `SqlColumnName => SqlColumnNameToSyntaxLeaf()`.

5. Add the new projection types to the module `export` list
   ([SqlToSyntax.jl:40-48](program/src/projection/primitive/SqlToSyntax.jl#L40-L48)) and
   the re-export in [Projectured.jl:437-443](program/src/Projectured.jl#L437-L443).

### Single-line rendering note

The existing SELECT projection deliberately renders multi-line (indented clause
bodies). INSERT/UPDATE here must stay on one line, so reuse only the inline
separator helpers and keep keywords (`INSERT`, `INTO`, `VALUES`, `UPDATE`, `SET`,
`WHERE`) as `_kw` leaves on a single `SyntaxNode` with a space separator.

---

## 3. Parser (`SqlParser.jl`) — optional, can be deferred

`sqlparse` currently handles SELECT only. Extend the entry point to dispatch on the
leading keyword (`INSERT` / `UPDATE` / `SELECT`) and add two recursive-descent
parse functions producing the new document trees. If deferred, note it explicitly as
follow-up; the projection + examples + tests below do **not** depend on the parser.

---

## 4. Examples

In [example/src/document/Sql.jl](example/src/document/Sql.jl) add:

```julia
make_sql_insert_document_example()  # INSERT INTO persons (name, age) VALUES ('Ada', 36)
make_sql_update_document_example()  # UPDATE persons SET age = 37 WHERE name = 'Ada'
```

In [example/src/projection/Sql.jl](example/src/projection/Sql.jl) add matching
`make_sql_insert_syntax_projection_example` / `…_update_…` (same three-stage
`SqlToSyntax → SyntaxToText → TextToGraphics` pipeline as
`make_sql_syntax_projection_example`).

Register `sql_insert_syntax_example` and `sql_update_syntax_example` in
[example/src/Examples.jl:112-114](example/src/Examples.jl#L112-L114) and the example
list at [Examples.jl:160-162](example/src/Examples.jl#L160-L162).

---

## 5. Tests

In [test/src/projection/SqlToSyntaxTest.jl](test/src/projection/SqlToSyntaxTest.jl):

- Replace the "Stubs compile" asserts
  ([SqlToSyntaxTest.jl:42-44](test/src/projection/SqlToSyntaxTest.jl#L42-L44)) with
  real round-trip rendering checks via the `sql_text` helper already defined there,
  e.g.:
  - `sql_text(insert_doc)` ⟹ `"INSERT INTO persons (name, age) VALUES ('Ada', 36)"`
  - `sql_text(update_doc)` ⟹ `"UPDATE persons SET age = 37 WHERE name = 'Ada'"`
- Add selection round-trip coverage mirroring `test_sql_to_syntax_selection`: drive
  the printer/reader and assert `map_reference_forward`/`backward` invert for a
  selection on a column, a value, and (UPDATE) a WHERE sub-reference.

Verify with the narrowest scope (per [CLAUDE.md](CLAUDE.md) "Testing a change"):

```julia
test_sql_to_syntax()          # the targeted projection test
test_example(sql_insert_syntax_example)
test_example(sql_update_syntax_example)
```

Use `test_example(...)` to cover printer + reader + navigation per example. Only run
broader sweeps (`test_syntax()`, `test_all()`) if the targeted tests pass and a wide
check is wanted.

---

## 6. Out of scope

- Multi-row `INSERT ... VALUES (…), (…)` and `INSERT ... SELECT`.
- `RETURNING`, `ON CONFLICT`, `DEFAULT VALUES`, `FROM` in UPDATE.
- Expressions (arithmetic, function calls) as inserted/assigned values — values are
  `SqlScalarValue` only (`42`, `'text'`, `TRUE`/`FALSE`), as in SELECT.
- Qualified/multi-table UPDATE targets and joins.
- Multi-line / pretty-printed layout — these statements render on a single line.
- Parser support is optional (see §3) and may land as a follow-up.
