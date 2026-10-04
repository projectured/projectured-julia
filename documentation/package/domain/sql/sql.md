# SQL domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [syntax.md](../../platform/syntax/syntax.md)

The SQL domain, `ProjecturedSQL`, holds a SQL statement as a tree of clause and expression documents, with a hand-written parser and a projection that prints the statement as syntax. It has no connection to a database; [database.md](../database/database.md) describes the adapter interface, and [odbc.md](../../adapter/odbc/odbc.md) the adapter that runs a statement. This document says where the domain differs from the [shape of every domain](../../../design/domain-anatomy.md): a statement is read and printed but not edited in place, the parser reads only two kinds of statement, and the printer is mostly hand-written.

<img width="396" alt="SQL example" src="../../../asset/image/example/sql-nested-syntax.png">

## How it works

`SqlDocument` is the abstract root, and `SqlStatement` is the abstract root of the statements:

| Statement | Built from | Parser |
| --- | --- | --- |
| `SqlSelectStatement` | `SqlSelectClause`, `SqlFromClause`, `SqlWhereClause` | yes |
| `SqlCreateTableStatement` | a `SqlTableName` and `SqlColumnDefinition`s | yes |
| `SqlCreateSchemaStatement` | a schema name | yes |
| `SqlInsertStatement` | a table, `columns`, `values` | no |
| `SqlUpdateStatement` | a table, `SqlUpdateAssignment`s, a `SqlWhereClause` | no |

A `SELECT` goes down through select items, from items, joins with `ON` or `USING`, subqueries, and a `WHERE` tree of `SqlComparison`, `SqlAnd`, `SqlOr` and `SqlNot` to `SqlColumnName`, `SqlTableName` and `SqlScalarValue`. A select expression that the model does not have, such as a function call, is a `SqlRawExpression` that holds its source text, and a condition that the model does not have, such as a `LIKE` or an `IN`, is a `SqlRawCondition` that holds its source text. A `SqlColumnDefinition` has a `column_name` and a `data_type` that is a plain string. `SqlStatementList` holds a sequence of statements and prints them with a blank line between two statements. Each statement in the list ends with `;`: a DDL statement prints its own, and the list adds one after any other statement, so the printed list parses back as the same list. `ProjecturedDBCatalog` uses the list to print a whole DDL script as one document.

`SqlStatement` must exist before `SqlInsertion` can subtype it, so both roots and the insertion are hand-written. `@domain Sql root = SqlDocument insertion = SqlInsertion` then makes only `SqlNothing`, the traits, the `"sql"` alias and the Insert gesture.

### A statement is a view with a selection

`SqlToSyntax()` has one rule for each document type. The nine leaf rules, such as the column, table and scalar leaves, are `@projection_template` rules with no `bound` field: each prints a text computed from several fields. The `USING` condition is a `@projection_template` rule too, with the column names in a `collection`. The rules of the other clauses and statements are hand-written `print_document` methods. Each builds a `SyntaxNode` and maps the selection clause by clause through a `ChildrenIoMap`. A `SELECT` prints no `FROM` clause when it has no from item and no `WHERE` clause when it has no condition, so `SELECT 1` prints as `SELECT 1` and reads back.

Every reader of the domain maps a `ReplaceSelectionOperation` and returns `nothing` for every other operation. So you can select and navigate every part of a statement, but no key edits a statement in place, and no `@gestures` table exists. A caret on the computed text of a leaf, or on a keyword that a node prints, is named by the introduced step of the projection that printed it, which holds the path of the part in that projection's output; the forward map gives that path back. See `PAR-CROSS-DOMAIN-LATE` in [architecture-invariants.md](../../../rule/architecture-invariants.md).

### The insertion parses source text

The Insert key replaces a `SqlNothing` with a `SqlInsertion`, whose `value` is SQL source. `SqlInsertionToSyntaxLeaf` shows the buffer green when `parse_sql_text` reads it as a whole statement, and red when it does not. Enter commits the parsed statement, and a buffer that does not parse does not commit. So the way to write a new statement is to type its text.

### The parser

`parse_sql_text` runs a tokenizer and a recursive-descent parser with one token of lookahead. `parse_sql` reads the statements that `;` separates, and skips an empty one, so a trailing `;` is allowed. One statement comes back as it is, and more than one as a `SqlStatementList`. For each statement, `parse_sql` looks at the first keyword and reads only two families:

- **`SELECT`**: the select list with `DISTINCT`, `*` and aliases, the `FROM` list with joins and subqueries, `ON` and `USING` conditions, and a `WHERE` tree.
- **`CREATE TABLE` and `CREATE SCHEMA`**: a column type is kept as its raw text up to the next comma at the top level, so `numeric(10, 2) NOT NULL` becomes one `data_type` string.

A statement that starts with any other keyword, such as `INSERT` or `UPDATE`, is not a statement for the parser, and `parse_sql_text` raises the error "SQL: not a parseable statement" for the whole text. A statement must end at a `;` or at the end of the text. `parse_sql` catches every error inside a statement and returns `nothing`, so each failure gives that same message.

The parser does not raise an error for a part that it does not model, and it drops no text of one. The tokenizer drops comments. It steps over the text by string index, so a string, an identifier or a comment can hold text that is not ASCII, and a letter of any script can start an identifier. The clauses after `WHERE`, such as `GROUP BY` and `ORDER BY`, are skipped to the end of the statement, and a parenthesis in one does not end the skip. A select expression that starts with a function call, a parenthesis or an operator becomes a `SqlRawExpression` whose `text` is the source text of the tokens. So does an expression that goes on after a column or a literal, such as `a + 1`: the parser reads it again from its first token, so no part of it is lost. It prints as that text, without quotes, so `COUNT(*)` reads and prints back as `COUNT(*)`.

A condition of a `WHERE` or an `ON` is read the same way. The parser reads a comparison, or a condition in parentheses, and keeps it only where the condition ends after it; otherwise it reads the condition again from its first token as a `SqlRawCondition` whose `text` is the source text. So `a - 1 = 0`, `a = -b`, `name LIKE 'x%'` and `a IN (1, 2)` keep their text, and each condition around them stays what it is: `a = 1 AND name LIKE 'x%'` is a `SqlAnd` of a comparison and a raw condition. A condition ends at `AND`, at `OR`, at a comma, at a `)` that it did not open, at a clause or a join that follows it, or at the end of the statement; the `AND` of a `BETWEEN` belongs to the condition. A `LEFT (` and a `RIGHT (` are function calls, not joins. A `WHERE` or an `AND` with no condition after it is an error for the whole statement, because no text is dropped.

A join has no raw form, because a from item is one table or one subquery. The joins of the model are `JOIN`, `INNER`, `LEFT`, `RIGHT`, `FULL` and `CROSS`, and a join of any other form is an error for the whole statement. So `SELECT * FROM a NATURAL JOIN b`, a join of a list of tables, and an `ON` or a `USING` with no condition after it each raise the error, and no join and no clause after one is lost. A join that names no condition at all, such as `a JOIN b` or `a CROSS JOIN b`, is a join of the model with no condition.

A `+` or a `-` in front of a number is the sign of that number where the grammar reads a value, so `WHERE a = -1` compares with -1 and `SELECT -1` selects -1. Between two operands it is an operator, so `a - 1` is a `SqlRawExpression`. A number with an exponent, such as `1e5` or `2.5E-3`, is one number, and its value is a `Float64`; an `e` that no digit follows is not part of the number. A string literal reads `''` as one quote, and the printer writes each quote of a string value as `''`. So `'it''s'` holds `it's` and prints back as `'it''s'`.

### The file

`SqlFile` is the file type for `.sql`. A reference to a node in another file is a `SqlScalarValue` whose value is a string that holds only the marker, as in JSON and YAML. A number or a boolean value is never a marker. A `.sql` path that does not exist opens as a `SqlInsertion`.

### The theme

`SqlTheme` holds the look of the SQL projections: the text of a keyword, the plain text of columns, values, expressions and types, and the text of a table name; the plain text also styles the commas and the parentheses that the printers build. Each value has
the default that the domain draws with no appearance. A projection holds its
styles as fields, and no theme; nothing in it scales or asks whether a theme is
scaled. `SqlToSyntax(; theme, syntax_theme)` gives each projection the style of
its role with `get_sql_style`, from `theme`, a `SqlTheme` scaled or not, or the
default styles for `nothing`; the insertion and the empty placeholder take
`syntax_theme`. The natural registration gives the scaled theme of the
`Appearance` of the editor, so the view follows its scales, and the appearance
tab shows a section for `SqlTheme`.

## How it fits

`ProjecturedSQL` depends on the kernel and the platform. It does not depend on `ProjecturedDatabase` or `ProjecturedODBC`. Two packages depend on it: `ProjecturedDBCatalog` makes `CREATE` statements from a catalog, and `ProjecturedODBC` prints a `SqlSelectStatement` to text and runs it on a connection.

Its `__init__` registers the natural row with the rung `:syntax`, the format `:sql`, the extension `.sql` and the parser `parse_sql_text`, and it registers `SqlFile` for `.sql`.

## Design decisions

- **Every clause is a document type.** A selection can then name a clause, a join or one comparison, and the catalog package can build a statement from parts. See [plan/done/sql-statement.md](../../../../plan/done/sql-statement.md).
- **The parser is hand-written.** A domain has no third-party dependency, and the parser reads only the grammar that the documents model. See [plan/done/sql-parser.md](../../../../plan/done/sql-parser.md).
- **A part that the model does not have degrades.** A skipped clause, or an expression or a condition that holds raw text, lets a real query load, at the cost of that part. A part that holds raw text keeps every character of it, so the statement prints back as the text that it was read from. [plan/pending/sql-select-aggregation-support.md](../../../../plan/pending/sql-select-aggregation-support.md) plans a model for the aggregate functions.
- **The composite rules are hand-written.** Some rules need an indent for each child between separators, which only the combined `SyntaxNode` can print. The reason is in the comment above `_comma_body` in `source/domain/sql/SqlToSyntax.jl`. The selection mapping is [plan/done/sql-to-syntax-selection-support.md](../../../../plan/done/sql-to-syntax-selection-support.md).
- **A column type is a string.** The catalog stores the type as a string too. A model of types, nullability and defaults is left for later.
- **INSERT and UPDATE are single-row statements.** No multi-row `VALUES` and no update of more than one table. See [plan/pending/sql-insert-update-support.md](../../../../plan/pending/sql-insert-update-support.md).

## Usage

```julia
statement = parse_sql_text("SELECT id, name FROM users WHERE age > 18")
statement = parse_sql_file("query.sql")
insert    = SqlInsertStatement(SqlTableName("persons"),
                               [SqlColumnName("name"), SqlColumnName("age")],
                               [SqlScalarValue("Ada"), SqlScalarValue(36)])
print_natural_text(insert)       # INSERT prints, although it does not parse
projection = SqlToSyntax()
```

- Examples: `sql_syntax_example`, `sql_insert_syntax_example`, `sql_update_syntax_example` and `sql_nested_syntax_example`, from `make_sql_*_document_example` and `make_sql_*_syntax_projection_example`. The atomic catalog has one document for each type.
- Test: `test_sql()` runs the layering guard, the parser, the printer, the selection through a `SELECT`, an `INSERT`, an `UPDATE` and a statement list, and the DDL printer and selection.

## Limits

- **The parser does not read `INSERT` or `UPDATE`.** The documents, the printer, the examples and the tests exist, but a typed `INSERT INTO …` stays red in the insertion and does not commit. This is the open step of [plan/pending/sql-insert-update-support.md](../../../../plan/pending/sql-insert-update-support.md).
- **A condition that the model does not have is one text.** A `SqlRawCondition` holds the whole condition as it is written, so a selection names the condition and no part of it. A comparison of a column or a value with a column or a value is the one condition that has a document for each side.
- **A join that the parser does not read is an error.** The joins are `JOIN`, `INNER`, `LEFT`, `RIGHT`, `FULL` and `CROSS`, so `SELECT * FROM a NATURAL JOIN b` is not a statement for the parser. A from item has no raw form to keep the text of such a join in, so the whole statement raises the error instead.
- **A skipped clause is lost.** `GROUP BY`, `HAVING`, `ORDER BY` and `LIMIT` do not survive a round trip. [plan/pending/sql-select-aggregation-support.md](../../../../plan/pending/sql-select-aggregation-support.md) plans `GROUP BY` and the aggregate functions.
- **A table constraint reads as a column.** A `PRIMARY KEY (id)` entry in the column list becomes a column named `PRIMARY` with the type `KEY (id)`. It prints back as the same text.
- **No `CREATE INDEX`.** [plan/pending/dbcatalog-index-support.md](../../../../plan/pending/dbcatalog-index-support.md) plans the index statements.
