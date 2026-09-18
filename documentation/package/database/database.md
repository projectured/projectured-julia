# Database, catalog and ODBC

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md), [sql.md](../sql/sql.md)

Three slices carry a live database from a connection to a browsable tree and
back to SQL text: `database` defines the adapter interface with no live
dependency, `dbcatalog` models the catalog a database exposes, and `odbc`
is the one concrete adapter, built on the `ODBC.jl` package. A caller who
wants to see or query a real database needs all three; a caller who only
builds or prints SQL text needs neither.

## Which slice does what

| Slice | Package | What it holds |
| --- | --- | --- |
| `database` | `ProjecturedDatabase` | the `DatabaseAdapter` interface, `DatabaseTable`, `DatabaseInstance` and its credentials — no live dependency |
| `dbcatalog` | `ProjecturedDbCatalog` | the catalog tree document (`DbCatalogRdbms` → `Database` → `Schema` → `Table` → `Column`) and its projections to SQL and to syntax |
| `odbc` | `ProjecturedOdbc` | `OdbcDatabaseAdapter`, the concrete `DatabaseAdapter` over `ODBC.jl`, a connection pool, and the projections that query a live database |

## What is in each slice

| File | What it holds |
| --- | --- |
| `source/database/DatabaseModule.jl` | the module, and what it exports |
| `source/database/DatabaseAdapters.jl` | the abstract `DatabaseAdapter`, `make_database_adapter`, and `RawDatabaseResult` |
| `source/database/DatabaseInstance.jl` | `DatabaseCredentials` and `DatabaseInstance`, a connection spec as a document |
| `source/database/DatabaseDocument.jl` | `DatabaseTable`, `UpdateDatabaseCellOperation`, `InsertDatabaseRowOperation` |
| `source/dbcatalog/DbCatalogModule.jl` | the module, and what it exports |
| `source/dbcatalog/DbCatalogDocument.jl` | the catalog document types |
| `source/dbcatalog/DbCatalogToSql.jl` | the catalog rendered as `CREATE …` DDL, through the SQL pipeline |
| `source/dbcatalog/DbCatalogToSyntax.jl` | the catalog rendered as a collapsible syntax tree, for browsing |
| `source/odbc/OdbcModule.jl` | the module, and what it exports |
| `source/odbc/OdbcAdapter.jl` | `OdbcDatabaseAdapter`, the `DatabaseAdapter` methods over `ODBC.jl` |
| `source/odbc/ConnectionPool.jl` | `OdbcConnectionPool`, connections kept and reused per DSN |
| `source/odbc/DatabaseInstanceToDbCatalog.jl` | a `DatabaseInstance` projected to a lazy `DbCatalogRdbms`, querying on demand |
| `source/odbc/SqlToCellTable.jl` | a `SqlSelectStatement` projected to a `CellTable` of live query results |

## The adapter seam

`DatabaseAdapter` is an abstract type with no method implemented; every
operation — `connect_db!`, `close_db!`, `is_db_alive`,
`get_db_rowid_column`, `query_db`, `execute_db_raw`, `insert_into_db!`,
`update_db!`, `delete_from_db!`, and the five `get_db_catalog_*` catalog
readers — raises until a concrete adapter defines it.
`make_database_adapter(:odbc; kwargs...)` builds one by a symbolic `kind`
without naming its concrete type, so a caller can ask for an adapter without
depending on the package that provides it; `OdbcModule` registers `:odbc`.
`RawDatabaseResult(columns, rows)` is the explicit materialized result a
caller asks `query_db` for when it needs to inspect, cache or serialize data
outside the projection pipeline.

`OdbcDatabaseAdapter(; dsn, rowid_column="rowid")` is the one implementation:
any ODBC-reachable database — PostgreSQL, SQL Server, MySQL, Oracle, SQLite —
by varying only the connection string. `rowid_column` is the technical
row-identity column a table update keys on, `"ctid"` for PostgreSQL,
`"rowid"` for SQLite. `OdbcConnectionPool` checks an adapter out per DSN,
returns it after `with_connection(f, pool, instance)` runs, and discards
rather than returns a connection that errored, so a broken connection is
never reused; `get_dsn` builds the ODBC connection string from a
`DatabaseInstance`, and `close_pool!` closes every idle adapter.

## The catalog tree

`DbCatalogRdbms(host, port, databases)` down to `DbCatalogColumn(name,
data_type)` mirrors a PostgreSQL server's catalog, each level's children held
in a `CellVector`. `DatabaseInstanceToDbCatalog` builds this tree lazily from
a live `DatabaseInstance`: each level's `CellVector` queries the adapter only
when read, so opening a server node does not query every table underneath
it. `DbCatalogToSql` renders the tree as SQL DDL — a `DbCatalogColumn`
becomes a `SqlColumnDefinition`, a `DbCatalogTable` a `CREATE TABLE`
statement, up to a whole `CREATE SCHEMA` script — by constructing SQL
documents directly and printing them through [sql.md](../sql/sql.md)'s
`SqlToSyntax`, not by printing and reparsing text. `DbCatalogToSyntax`
renders the same tree as a collapsible syntax tree for browsing;
`is_dbcatalog_marker_eligible` keys the expand/collapse marker off a node
carrying a label, so a lazy child `CellVector` is not forced just to decide
whether to draw the marker.

`SqlToCellTable` is the other direction: it projects a `SqlSelectStatement`
to a `CellTable` of the rows it returns when run against a `DatabaseInstance`
through the pool, so editing SQL text produces a live query result.

## How it fits

`database` depends only on `ProjecturedKernel` and touches neither `ODBC`
nor `DBInterface`; a session that only prints or edits SQL text never loads
them. `dbcatalog` depends on `database` and on [sql.md](../sql/sql.md), but
not on `odbc`, so the catalog document and its SQL/syntax projections work
with no live adapter. `odbc` depends on all three and is the only slice of
the group that a database engine's client library reaches — it is an opt-in
package, loaded only when a caller wants a real connection.

## What a reader must know before changing this

Every method of `DatabaseAdapter` raises `error(...)` by default rather than
being declared abstract, so a new adapter that misses a method fails at the
first call, not at load time. `test_odbc()` tries to connect and skips its
live-query assertions when the connection fails, logging why; the surrounding
document and result-shape assertions still run with no database. A green
`test_odbc()` on a machine with no ODBC server running is therefore not proof
that a query against a real database succeeds. `test_database()` and
`test_dbcatalog()` need no live database: `test/database/DatabaseSuite.jl`
and `test/dbcatalog/DbCatalogSuite.jl` cover the document types and the SQL
rendering with no connection.
