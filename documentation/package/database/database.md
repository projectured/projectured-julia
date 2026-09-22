# Database, catalog and ODBC

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../design/domain-anatomy.md), [sql.md](../sql/sql.md)

Three packages carry a live database into the editor. `ProjecturedDatabase` defines the adapter interface and the connection documents, `ProjecturedDbCatalog` models the catalog of a database as a tree of documents, and `ProjecturedOdbc` is the one concrete adapter, built on `ODBC.jl`. This document says what each package holds, how the three depend on each other, and what a live query does.

<img width="396" alt="Database catalog example" src="../../../asset/image/example/dbcatalog.png">

## How it works

The first two packages have no third-party dependency and do not depend on each other. The third depends on both, on `ProjecturedSql`, and on `ODBC`, `DBInterface` and `Tables`:

```
ProjecturedDatabase        ProjecturedDbCatalog ──▶ ProjecturedSql
        ▲                          ▲                      ▲
        └──────── ProjecturedOdbc ─┴──────────────────────┘
```

So you can build and print a catalog, or define an adapter, without a database library. Only a program that loads `ProjecturedOdbc` can reach a database.

### database: the adapter seam

`DatabaseAdapter` is an abstract type. Each verb is a function whose default method raises an error that names the adapter type:

- `connect_db!`, `close_db!`, `is_db_alive` and `get_db_rowid_column`;
- `query_db(adapter, table, T; columns, where, limit)` and `execute_db_raw(adapter, sql, T; params)`;
- `insert_into_db!`, `update_db!` and `delete_from_db!`;
- `get_db_catalog_databases`, `_schemas`, `_tables`, `_columns` and `_foreign_keys`.

`query_db` and `execute_db_raw` take the target type `T` of the result, so an adapter can fill each target without an intermediate copy. `RawDatabaseResult(columns, rows)` is the one target that exists: an explicit copy of the rows, for a caller that must keep or show them outside a projection.

`make_database_adapter(kind; kwargs...)` builds an adapter from a symbol. It calls `make_database_adapter(Val(kind); kwargs...)`, and a package that implements an adapter adds a method for its own `Val`. No table of adapters exists. A caller can then build an `:odbc` adapter without a dependency on `ProjecturedOdbc`. When no method exists for the kind, the call raises the error "No database adapter registered for :odbc. Is the package/extension that provides it loaded?".

The package holds two groups of documents:

- `DatabaseCredentials(; user, password)` and `DatabaseInstance(; database, credentials, host = "localhost", port = 5432)` are a connection specification as a document, not a connection. The catalog examples start from a `DatabaseInstance`.
- `DatabaseTable` is a query specification: an adapter, a table name, and optional columns, a `WHERE` fragment and a row limit. `UpdateDatabaseCellOperation` and `InsertDatabaseRowOperation` are two operations on a table.

### dbcatalog: the catalog tree

The catalog is a tree of five document types, and each level holds its children in a `CellVector`:

```
DbCatalogRdbms(host, port, databases)
  DbCatalogDatabase(name, schemas)
    DbCatalogSchema(name, tables)
      DbCatalogTable(name, columns)
        DbCatalogColumn(name, data_type)
```

The package makes no connection. A caller builds the tree from ordinary vectors, or `ProjecturedOdbc` builds it from a live database with vectors that query when a projection reads them. The package has two projections of the tree:

- **`DbCatalogToSql()`** builds SQL documents directly, not text that is parsed again. A column becomes a `SqlColumnDefinition`, a table a `SqlCreateTableStatement`, a schema a `CREATE SCHEMA` and one `CREATE TABLE` for each table in a `SqlStatementList`, and a database or a server the flat list of all these statements. The schema name travels down in the printer context as the property `:sql_schema_name`, so a table writes `schema.table`. `SqlToSyntax` then prints the statements, so the SQL domain is the one place that writes SQL text. The projection maps no reference and reads nothing: it gives a language model the shape of a database as DDL.
- **`DbCatalogToSyntax()`** makes a tree to browse. Each entity prints its name, and holds one keyword group, `Databases`, `Schemas`, `Tables` or `Columns`, that holds the items. A column prints as one leaf, `name::type`. The reference maps are hand-written for each level, and the reader maps a selection.

A keyword group starts collapsed unless its child collection is already computed. `_children_realized` reads the `valid` flag of the backing cell and does not compute it. So the first print of a live catalog runs no query, and a click that opens a group runs the query of that group only. `is_dbcatalog_marker_eligible` gives `SyntaxToText` the nodes that get an open or a closed marker: a node with a label. It does not read the children, because a read of the children of a live group runs its query.

### odbc: the live adapter

`OdbcDatabaseAdapter(; dsn, rowid_column = "rowid")` implements every verb of `DatabaseAdapter` over `ODBC.jl`. `dsn` is a full ODBC connection string. `rowid_column` names the column that identifies a row, for example `"ctid"` for PostgreSQL and `"rowid"` for SQLite. The package adds `make_database_adapter(::Val{:odbc}; kwargs...)`. An `ODBC.Cursor` is a Tables.jl source and not a row iterator, so the adapter copies each result through `Tables.columntable`.

`OdbcConnectionPool(; driver, rowid_column, max_size)` keeps idle adapters in buckets by connection string. Its defaults are the driver `{PostgreSQL Unicode}` and the row column `ctid`. `get_dsn(pool, instance)` builds the connection string from a `DatabaseInstance`. `with_connection(f, pool, instance)` takes an adapter from the bucket, checks it with `is_db_alive`, runs `f(adapter)`, and puts the adapter back. When `f` raises an error, or the bucket is full, it closes the adapter instead, so a broken connection is not used again. `close_pool!` closes every idle adapter.

Two projections bring a live database into a chain:

- **`DatabaseInstanceToDbCatalog(pool)`** projects a `DatabaseInstance` to a `DbCatalogRdbms`. Each level is a `ComputedCellVector` that queries through `with_connection` when a projection reads it. The selection is opaque: the tree comes from queries and has no counterpart in the instance, so the backward map stores the catalog path as `proj(p, path)` on the instance, and the forward map takes it out again.
- **`SqlToCellTable(pool, instance)`** projects a `SqlSelectStatement` to a `CellTable`. It prints the statement to text with `SqlToSyntax`, `SyntaxToText` and `TextToString`, runs it with `execute_db_raw` in a computed cell, and makes a header row of the column names and one row for each result row. It maps no reference and reads nothing.

## How it fits

`ProjecturedDatabase` depends only on `ProjecturedKernel`. `ProjecturedDbCatalog` depends on `ProjecturedSql`, `ProjecturedSyntax`, `ProjecturedText` and the kernel packages, and it takes the DDL document types from the SQL domain; see [sql.md](../sql/sql.md). `ProjecturedOdbc` depends on both of them. It owns a third-party dependency, so the umbrella package `Projectured` does not load it, and a program that needs it names it; see [package-rules.md](../../rule/package-rules.md).

None of the three has an `__init__`. They register no natural row, no file type and no `.pred` type, so the general renderer has no row for them, and a caller composes their projections into a chain. The one registration is the method `make_database_adapter(::Val{:odbc})`.

## Design decisions

- **The adapter is an interface in a package with no dependency.** A caller that only builds SQL or a catalog loads no database library. See `plan/done/database-backend.md`.
- **The driver is ODBC.** One adapter reaches PostgreSQL, SQL Server, MySQL, Oracle and SQLite through the connection string. A PostgreSQL client library binds one database only. See `plan/done/libpq-go-to-hell.md`.
- **A missing verb fails at its first call.** Each default method raises an error, so an adapter that implements a part of the interface loads and fails only when a caller uses the missing part.
- **The catalog is a pure tree.** Each level is a vector of children with no parent pointer and no adapter in it, so each level can be built and queried alone. See `plan/done/database-instance-catalog-sql.md`.
- **The catalog becomes DDL through SQL documents.** DDL is a form of a database that a language model reads easily, and `SqlToSyntax` stays the one printer of SQL. See `plan/done/dbcatalog-sql-document-support.md`.
- **The pool is written in this repository.** It needs no new dependency and reuses the adapter unchanged. A query result is a `CellTable`, the table document that exists, and not a new widget. See `plan/done/database-instance-catalog-sql.md`.

## Usage

```julia
table = DbCatalogTable("film", [DbCatalogColumn("title", "text"),
                                DbCatalogColumn("length", "integer")])
ddl = ChainingProjection(RecursiveProjection(DbCatalogToSql()),
                         RecursiveProjection(SqlToSyntax()),
                         RecursiveProjection(SyntaxToText()),
                         RecursiveProjection(TextToString()))
print_document(ddl, table).output    # "CREATE TABLE film (\n  title text,\n  length integer\n);"

instance = DatabaseInstance(database = "shop",
                            credentials = DatabaseCredentials(user = "u", password = "p"))
pool     = OdbcConnectionPool()
catalog  = ChainingProjection(DatabaseInstanceToDbCatalog(pool),
                              RecursiveProjection(DbCatalogToSyntax()),
                              RecursiveProjection(SyntaxToText(marker_eligible = is_dbcatalog_marker_eligible)),
                              TextToGraphics(measure = measure_truetype_text))
```

- Examples: the atomic catalog has one document for each catalog type and one `DatabaseInstance`. The live examples are in `example/odbc/`: `dbcatalog_example` and `dvdrental_catalog_example` browse a catalog, and `sql_table_example` shows the result of a query. They read the connection from the `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGHOST` and `PGPORT` environment variables.
- Tests: `test_database()` and `test_dbcatalog()` need no database. `test_database()` checks the documents and that each verb of an empty adapter raises an error. `test_dbcatalog()` checks the DDL of each level and the marker predicate. `test_odbc()` needs a reachable database for its live part.

## Limits

- **`DatabaseTable` and its two operations have no projection.** No projection prints a `DatabaseTable`, and no code evaluates `UpdateDatabaseCellOperation` or `InsertDatabaseRowOperation`. Only a unit test builds a `DatabaseTable`. A live table view goes through `SqlToCellTable` instead.
- **The catalog queries are PostgreSQL SQL.** The `get_db_catalog_*` methods of `OdbcDatabaseAdapter` read `information_schema` with PostgreSQL filters such as `pg_%`, and the foreign key query reads `pg_catalog`, because the constraint views of `information_schema` show a constraint only to the owner of the table. The query, execute and change verbs write plain SQL with quoted identifiers, but `query_db` with a `limit` writes a `LIMIT` clause, which the SQL standard does not have.
- **The catalog shows the connected database only.** `get_db_catalog_databases` lists the catalogs that `information_schema.tables` of the connection shows, and `get_db_catalog_schemas` does not use its `database` argument.
- **Identifiers and `WHERE` fragments go into the SQL text as they are.** Only the row values of an insert or an update are parameters. A caller must not pass an untrusted table name, schema name or `WHERE` fragment.
- **A green `test_odbc()` does not prove a live query.** When the connection fails, the live tests of `DatabaseResultTest.jl` and `DbCatalogQueryTest.jl` are skipped with a log message. Each of the three files in `test/odbc/external/` puts its live group in one `try`, and an error there becomes one `@test_broken`, so the tests after the error do not run.
- **The catalog has no indexes, keys or constraints.** `plan/pending/dbcatalog-index-support.md` plans the indexes. `plan/pending/bound-sql-statement.md` plans a SQL statement bound to the live catalog, for completion and checks.
