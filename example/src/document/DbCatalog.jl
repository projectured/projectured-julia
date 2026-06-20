function make_dbcatalog_document_example(;
        dbname=get(ENV, "PGDATABASE", "projectured_test"),
        user=get(ENV, "PGUSER", "projectured"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")))
    # The catalog document is just a connection spec. No connection is opened
    # here — the DatabaseInstanceToDbCatalog projection queries the database
    # lazily (through its connection pool) when the tree is first forced, so
    # this maker stays safe to run at module-load / precompile time.
    DatabaseInstance(
        database=dbname,
        host=host,
        port=port,
        credentials=DatabaseCredentials(user=user, password=password),
    )
end

function make_dvdrental_catalog_document_example(;
        dbname=get(ENV, "PGDATABASE", "dvdrental"),
        user=get(ENV, "PGUSER", "projectured"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")))
    # Pure connection spec — safe at module-load time. The
    # DatabaseInstanceToDbCatalog projection in the matching projection
    # example handles the lazy DB connection.
    DatabaseInstance(
        database=dbname,
        host=host,
        port=port,
        credentials=DatabaseCredentials(user=user, password=password),
    )
end

"""
    explore_dbcatalog!(rdbms::DbCatalogRdbms) -> DbCatalogRdbms

Materialize only the **first** table of the catalog (first database → first
schema → first table's columns), leaving every other table's `columns`
`CellVector` lazy. Enumerating each schema's table *list* is forced (so the
table names are known), but the per-table column queries — the expensive part —
are deferred until something forces them (e.g. expanding that table's card in
the widget pipeline). This makes the catalog a good fixture for **testing
laziness**: only one table is opened up front; the rest load on demand.
Returns `rdbms` for chaining.
"""
function explore_dbcatalog!(rdbms::DbCatalogRdbms)
    length(rdbms.databases) >= 1 || return rdbms
    db = rdbms.databases[1]
    length(db.schemas) >= 1 || return rdbms
    schema = db.schemas[1]
    length(schema.tables) >= 1 || return rdbms   # force the table list, not its columns
    table = schema.tables[1]
    length(table.columns)                        # open only the first table's columns
    rdbms
end

"""
    make_dvdrental_dbcatalog_document_example(; ...) -> DbCatalogRdbms

Connect to the dvdrental PostgreSQL sample database and return a fully
explored `DbCatalogRdbms` tree with all schemas, tables, and columns
materialized. Unlike `make_dbcatalog_document_example`, this returns the
catalog tree directly (not a `DatabaseInstance`), so its projection should
start at `DbCatalogToSyntax` rather than `DatabaseInstanceToDbCatalog`.
"""
function make_dvdrental_dbcatalog_document_example(;
        dbname=get(ENV, "PGDATABASE", "dvdrental"),
        user=get(ENV, "PGUSER", "projectured"),
        password=get(ENV, "PGPASSWORD", "projectured"),
        host=get(ENV, "PGHOST", "localhost"),
        port=parse(Int, get(ENV, "PGPORT", "5432")),
        pool=OdbcConnectionPool())
    inst = DatabaseInstance(
        database=dbname, host=host, port=port,
        credentials=DatabaseCredentials(user=user, password=password))
    proj = DatabaseInstanceToDbCatalog(pool)
    iomap = projection_print(proj, nothing, inst, PrinterContext())
    explore_dbcatalog!(iomap.output)
end
