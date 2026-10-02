# The ODBC database adapter

> **Kind:** design · **Status:** current · **Stands on:** [database.md](../../domain/database/database.md), [sql.md](../../domain/sql/sql.md)

`ProjecturedODBC` is the one concrete database adapter, built on `ODBC.jl`. It implements the adapter interface of `ProjecturedDatabase`, keeps a pool of connections, and brings a live database into a chain of projections: a catalog that queries when a projection reads it, and the result of a query as a table. This document says how the adapter reaches a database, what a live query does, and what the package does not do. The adapter seam and the catalog tree are in [database.md](../../domain/database/database.md).

## How it works

`OdbcDatabaseAdapter(; dsn, rowid_column = "rowid")` implements every verb of `DatabaseAdapter` over `ODBC.jl`. `dsn` is a full ODBC connection string. `rowid_column` names the column that identifies a row, for example `"ctid"` for PostgreSQL and `"rowid"` for SQLite. The package adds `make_database_adapter(::Val{:odbc}; kwargs...)`. An `ODBC.Cursor` is a Tables.jl source and not a row iterator, so the adapter copies each result through `Tables.columntable`.

`OdbcConnectionPool(; driver, rowid_column, max_size)` keeps idle adapters in buckets by connection string. Its defaults are the driver `{PostgreSQL Unicode}` and the row column `ctid`. `get_dsn(pool, instance)` builds the connection string from a `DatabaseInstance`: the server, the database, the user and the password go into it escaped, so a value with a `;`, a `{`, a `}`, an `=` or a space at an end goes between braces, with each `}` of it written twice. The driver carries its own braces and goes in as it is. `with_connection(f, pool, instance)` takes an adapter from the bucket, checks it with `is_db_alive`, runs `f(adapter)`, and puts the adapter back. When `f` raises an error, or the bucket is full, it closes the adapter instead, so a broken connection is not used again. `close_pool!` closes every idle adapter.

Two projections bring a live database into a chain:

- **`DatabaseInstanceToDbCatalog(pool)`** projects a `DatabaseInstance` to a `DbCatalogRdbms`. Each level is a computed `CellVector` that queries through `with_connection` when a projection reads it. The list of databases comes through the connection of the instance. Each database of the list reads its schemas, tables and columns through a connection to that database, with the host, the port and the credentials of the instance, so the pool opens that connection when a person opens the `Schemas` group of that database. The selection is opaque: the tree comes from queries and has no counterpart in the instance, so the backward map stores the catalog path as `proj(p, path)` on the instance, and the forward map takes it out again.
- **`SqlToCellTable(pool, instance)`** projects a `SqlSelectStatement` to a `CellTable`. It prints the statement to text with `SqlToSyntax`, `SyntaxToText` and `TextToString`, runs it with `execute_db_raw` in a computed cell, and makes a header row of the column names and one row for each result row. It maps no reference and reads nothing.

## How it fits

The package depends on `ProjecturedDatabase`, `ProjecturedDBCatalog` and `ProjecturedSQL`, and on `ODBC`, `DBInterface` and `Tables`. The first two packages have no third-party dependency and do not depend on each other:

```
ProjecturedDatabase        ProjecturedDBCatalog ──▶ ProjecturedSQL
        ▲                          ▲                      ▲
        └──────── ProjecturedODBC ─┴──────────────────────┘
```

So only a program that loads `ProjecturedODBC` can reach a database. The package owns a third-party dependency, so the umbrella package `Projectured` does not depend on it; see [package-rules.md](../../../rule/package-rules.md). When the environment has the package, the umbrella loads it as soon as `ODBC` is loaded; see [system-anatomy.md](../../../design/system-anatomy.md).

The package has no `__init__`. It registers no natural row and no file type, so the general renderer has no row for it, and a caller composes its projections into a chain. Its one registration is the method `make_database_adapter(::Val{:odbc})`.

## Design decisions

- **The driver is ODBC.** One adapter reaches PostgreSQL, SQL Server, MySQL, Oracle and SQLite through the connection string. A PostgreSQL client library binds one database only. See [plan/done/libpq-go-to-hell.md](../../../../plan/done/libpq-go-to-hell.md).
- **The pool is written in this repository.** It needs no new dependency and reuses the adapter unchanged. A query result is a `CellTable`, the table document that exists, and not a new widget. See [plan/done/database-instance-catalog-sql.md](../../../../plan/done/database-instance-catalog-sql.md).

## Usage

```julia
instance = DatabaseInstance(database = "shop",
                            credentials = DatabaseCredentials(user = "u", password = "p"))
pool     = OdbcConnectionPool()
catalog  = ChainingProjection(DatabaseInstanceToDbCatalog(pool),
                              RecursiveProjection(DbCatalogToSyntax()),
                              RecursiveProjection(SyntaxToText(marker_eligible = is_dbcatalog_marker_eligible)),
                              TextToGraphics(measure = FontFileMeasure()))
```

- Examples: the live examples are in `example/adapter/odbc/`. `dbcatalog_example` and `dvdrental_catalog_example` browse a catalog, and `sql_table_example` shows the result of a query. They read the connection from the `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGHOST` and `PGPORT` environment variables.
- Tests: `test_odbc()` needs a reachable database for its live part. `test_odbc_adapter()`, its first part, needs none: it checks the text of the catalog queries, a name with a quote in each of them, the text of the select, insert, update and delete statements with a name that holds a double quote, the connection string of a database of the catalog, and a value of the connection string with a `;` or a `}` in it.

## Limits

- **The catalog queries are PostgreSQL SQL.** The `get_db_catalog_*` methods of `OdbcDatabaseAdapter` read `information_schema` with PostgreSQL filters such as `pg_%`, the list of databases reads `pg_database`, and the foreign key query reads `pg_catalog`, because the constraint views of `information_schema` show a constraint only to the owner of the table. The query, execute and change verbs write plain SQL with quoted identifiers, but `query_db` with a `limit` writes a `LIMIT` clause, which the SQL standard does not have.
- **A connection reads the schemas of its own database only.** `get_db_catalog_databases` lists every database of the server from `pg_database`, and `get_db_catalog_schemas` lists the schemas whose `catalog_name` is its `database` argument. PostgreSQL shows a connection the `information_schema` of its own database, so the schemas of another database are an empty list. `DatabaseInstanceToDbCatalog` connects to each database for that reason. A database that the credentials of the instance can not connect to raises the error of the connection when its schemas are read.
- **A `WHERE` fragment goes into the SQL text as it is.** Only the row values of an insert or an update are parameters, and the `WHERE` fragment of `query_db`, `update_db!` and `delete_from_db!` goes into the text as it is. A caller must not pass an untrusted one. A table name and a column name are not a limit: each goes into the text as a quoted identifier, with each double quote of the name written twice, so a name with a double quote in it stays one identifier. The catalog queries write the name of a database, a schema or a table as a string literal, with each quote of the name written twice, for the same reason.
- **A green `test_odbc()` does not prove a live query.** When the connection fails, the live tests of `DatabaseResultTest.jl` and `DbCatalogQueryTest.jl` are skipped with a log message. Each of the three files in `test/adapter/odbc/external/` puts its live group in one `try`, and an error there becomes one `@test_broken`, so the tests after the error do not run.
