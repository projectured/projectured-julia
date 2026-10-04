# Database and catalog

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [sql.md](../sql/sql.md)

Two packages carry a database into the editor without a connection. `ProjecturedDatabase` defines the adapter interface and the connection documents, and `ProjecturedDBCatalog` models the catalog of a database as a tree of documents. This document says what each package holds and how the two depend on other packages. `ProjecturedODBC` is the one concrete adapter, and [odbc.md](../../adapter/odbc/odbc.md) describes it and the live queries.

<img width="396" alt="Database catalog example" src="../../../asset/image/example/dbcatalog.png">

## How it works

The two packages have no third-party dependency and do not depend on each other. So you can build and print a catalog, or define an adapter, without a database library. Only a program that loads `ProjecturedODBC` can reach a database; see [odbc.md](../../adapter/odbc/odbc.md).

### database: the adapter seam

`DatabaseAdapter` is an abstract type. Each verb is a function whose default method raises an error that names the adapter type:

- `connect_db!`, `close_db!`, `is_db_alive` and `get_db_rowid_column`;
- `query_db(adapter, table, T; columns, where, limit)` and `execute_db_raw(adapter, sql, T; params)`;
- `insert_into_db!`, `update_db!` and `delete_from_db!`;
- `get_db_catalog_databases`, `_schemas`, `_tables`, `_columns` and `_foreign_keys`.

`query_db` and `execute_db_raw` take the target type `T` of the result, so an adapter can fill each target without an intermediate copy. `RawDatabaseResult(columns, rows)` is the one target that exists: an explicit copy of the rows, for a caller that must keep or show them outside a projection.

`make_database_adapter(kind; kwargs...)` builds an adapter from a symbol. It calls `make_database_adapter(Val(kind); kwargs...)`, and a package that implements an adapter adds a method for its own `Val`. No table of adapters exists. A caller can then build an `:odbc` adapter without a dependency on `ProjecturedODBC`. When no method exists for the kind, the call raises the error "No database adapter registered for :odbc. Is the package/extension that provides it loaded?".

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

The package makes no connection. A caller builds the tree from ordinary vectors, or `ProjecturedODBC` builds it from a live database with vectors that query when a projection reads them. The package has two projections of the tree:

- **`DbCatalogToSql()`** builds SQL documents directly, not text that is parsed again. A column becomes a `SqlColumnDefinition`, a table a `SqlCreateTableStatement`, a schema a `CREATE SCHEMA` and one `CREATE TABLE` for each table in a `SqlStatementList`, and a database or a server the flat list of all these statements. The schema name travels down in the printer context as the property `:sql_schema_name`, so a table writes `schema.table`. `SqlToSyntax` then prints the statements, so the SQL domain is the one place that writes SQL text. The projection maps no reference and reads nothing: it gives a language model the shape of a database as DDL.
- **`DbCatalogToSyntax()`** makes a tree to browse. Each entity prints its name, and holds one keyword group, `Databases`, `Schemas`, `Tables` or `Columns`, that holds the items. A column prints as one leaf, `name::type`. The reference maps are hand-written for each level, and the reader maps a selection.

A keyword group starts collapsed unless its child collection is already computed. `_children_realized` reads the `valid` flag of the backing cell and does not compute it. So the first print of a live catalog runs no query, and a click that opens a group runs the query of that group only. `is_dbcatalog_marker_eligible` gives `SyntaxToText` the nodes that get an open or a closed marker: a node with a label. It does not read the children, because a read of the children of a live group runs its query.

#### The theme

`DbCatalogTheme` holds the look of the catalog tree: the text of a column, a table, a schema, a database and an RDBMS, and the keyword that opens a group of children. Each value has the default that the domain draws with no appearance. A projection holds its styles as fields, and no theme; nothing in it scales or asks whether a theme is scaled. `DbCatalogToSyntax(; theme)` gives each projection the style of its role with `get_db_catalog_style`, from `theme`, a `DbCatalogTheme` scaled or not, or the default styles for `nothing`; the database node and the RDBMS node take the same style, built once.

## How it fits

`ProjecturedDatabase` depends only on `ProjecturedKernel`. `ProjecturedDBCatalog` depends on `ProjecturedSQL`, the kernel and the platform, and it takes the DDL document types from the SQL domain; see [sql.md](../sql/sql.md). `ProjecturedODBC` depends on both of them; see [odbc.md](../../adapter/odbc/odbc.md).

Neither package has an `__init__`. They register no natural row and no file type, so the general renderer has no row for them, and a caller composes their projections into a chain.

## Design decisions

- **The adapter is an interface in a package with no dependency.** A caller that only builds SQL or a catalog loads no database library. See [plan/done/database-backend.md](../../../../plan/done/database-backend.md).
- **A missing verb fails at its first call.** Each default method raises an error, so an adapter that implements a part of the interface loads and fails only when a caller uses the missing part.
- **The catalog is a pure tree.** Each level is a vector of children with no parent pointer and no adapter in it, so each level can be built and queried alone. See [plan/done/database-instance-catalog-sql.md](../../../../plan/done/database-instance-catalog-sql.md).
- **The catalog becomes DDL through SQL documents.** DDL is a form of a database that a language model reads easily, and `SqlToSyntax` stays the one printer of SQL. See [plan/done/dbcatalog-sql-document-support.md](../../../../plan/done/dbcatalog-sql-document-support.md).

## Usage

```julia
table = DbCatalogTable("film", [DbCatalogColumn("title", "text"),
                                DbCatalogColumn("length", "integer")])
ddl = ChainingProjection(RecursiveProjection(DbCatalogToSql()),
                         RecursiveProjection(SqlToSyntax()),
                         RecursiveProjection(SyntaxToText()),
                         RecursiveProjection(TextToString()))
print_document(ddl, table).output    # "CREATE TABLE film (\n  title text,\n  length integer\n);"
```

- Examples: the atomic catalog has one document for each catalog type and one `DatabaseInstance`. [odbc.md](../../adapter/odbc/odbc.md) describes the live examples.
- Tests: `test_database()` and `test_dbcatalog()` need no database. `test_database()` checks the documents and that each verb of an empty adapter raises an error. `test_dbcatalog()` checks the DDL of each level and the marker predicate.

## Limits

- **`DatabaseTable` and its two operations have no projection.** No projection prints a `DatabaseTable`, and no code evaluates `UpdateDatabaseCellOperation` or `InsertDatabaseRowOperation`. Only a unit test builds a `DatabaseTable`. A live table view goes through `SqlToCellTable` of `ProjecturedODBC` instead.
- **The catalog has no indexes, keys or constraints.** [plan/pending/dbcatalog-index-support.md](../../../../plan/pending/dbcatalog-index-support.md) plans the indexes. [plan/pending/bound-sql-statement.md](../../../../plan/pending/bound-sql-statement.md) plans a SQL statement bound to the live catalog, for completion and checks.
