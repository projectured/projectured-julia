# SQL Domain

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md)

The SQL domain: a database-agnostic document model for a `SELECT`, `INSERT`,
`UPDATE`, `CREATE TABLE` or `CREATE SCHEMA` statement, a hand-written parser
that reads SQL text into it, and a projection that prints it back out as
syntax. `source/sql/` holds the model; `source/dbcatalog/` and
`source/odbc/` run a statement against a live connection (see the
`database` slice's guide).

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/sql/SqlModule.jl` | the module, and what it exports |
| `source/sql/SqlDocument.jl` | the document types: `SqlInsertion` and every clause and expression of a statement |
| `source/sql/SqlParser.jl` | `parse_sql_text` / `parse_sql_file`, a recursive-descent parser over a hand-written tokenizer |
| `source/sql/SqlToSyntax.jl` | the projection from a statement to a syntax tree, one method per document type |

## The document

`SqlDocument` is the abstract root; `SqlStatement` is the abstract root of the
five statements a caller builds or the parser returns: `SqlSelectStatement`,
`SqlInsertStatement`, `SqlUpdateStatement`, `SqlCreateTableStatement` and
`SqlCreateSchemaStatement`. Each prints through its own `*ToSyntaxNode` method
in `SqlToSyntax.jl`. A `SELECT` is built from `SqlSelectClause`,
`SqlFromClause` and `SqlWhereClause`, each a tree of smaller documents down to
`SqlColumnName`, `SqlTableName` and the scalar and comparison expressions of a
`WHERE` filter.

`SqlInsertion` is the domain's insertion placeholder: an empty statement being
typed. Pressing Enter on it calls `parse_sql_text` on the text so far and
replaces the insertion with the statement the parser returns, the same
commit path every domain's insertion takes. `@domain Sql root = SqlDocument
insertion = SqlInsertion` registers the domain under the `"sql"` alias and
generates `SqlNothing` and the domain traits; the root and the insertion are
hand-written because `SqlStatement` must exist before the generated code can
name it.

## The parser

```julia
statement = parse_sql_text("SELECT id, name FROM users WHERE age > 18")
statement = parse_sql_file("query.sql")
```

`parse_sql_text` tokenizes and parses one statement; a text that is not a
complete, parseable statement raises an error rather than returning a partial
tree. `parse_sql_file` reads the file and calls `parse_sql_text` on its
content. The grammar covers `SELECT` with joins, a `WHERE` filter of
comparisons and boolean connectives, `INSERT`, `UPDATE`, `CREATE TABLE` and
`CREATE SCHEMA` — the subset the other slices of the domain-inventory table
exercise, not the whole of ANSI SQL.

## How it fits

`SqlToSyntax` is what [text.md](../text/text.md) and
[syntax.md](../syntax/syntax.md) print through to turn a statement into
readable, editable text; a caller chains `SqlToSyntax()` into
`SyntaxToText()` the way every syntax-backed domain does. `ProjecturedDbCatalog`
builds a `SqlSelectStatement` from a catalog node
(`DbCatalogRdbmsToSql`, …) and `ProjecturedOdbc`'s `SqlToCellTable` executes
one against a `DatabaseInstance`; the `database` slice's guide covers that
seam. The domain itself has no notion of a connection: nothing under
`source/sql/` imports `ProjecturedDatabase` or `ProjecturedOdbc`.

## What to check when a change touches this slice

`test/sql/SqlSuite.jl` runs `test_sql()`: the document tests
(`test/sql/document/SqlDocumentTest.jl`, `SqlParserTest.jl`) and the
projection tests (`test/sql/projection/SqlToSyntaxTest.jl`), including
selection through an `INSERT`/`UPDATE` statement and through a `CREATE`
statement. `example/sql/` holds `SqlDocumentExample.jl` and
`SqlProjectionExample.jl`, the examples the printer and reader sweeps drive.
A grammar change that the parser accepts but `SqlToSyntax` cannot print back
out breaks the round trip the printer/reader tests check, not the parser
tests alone.
